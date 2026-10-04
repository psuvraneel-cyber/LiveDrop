-- LiveDrop Migration: 038_storage_suspension_and_utr_guards.sql
-- Description: P1 fixes from the seller-app audit (audit/seller-app/), round 2.
--
--   SA-SEC-003  Any signed-up account, approved or not, could upload to the public product-images
--               bucket. Upload and overwrite now also require an approved seller
--               (public.is_seller_approved(auth.uid())), still only inside the seller's own folder.
--   SA-SEC-008  The read policy on storage.objects covered every object for every role, so anyone
--               with the anon key could list all folders and files, including photos of draft drops.
--               Public object URLs of a public bucket do not need a policy; listing is now limited to
--               the owning seller (also needed by the app's upsert uploads).
--   SA-ONB-002  Suspending a seller (is_approved -> false) hid the catalogue but the live drop kept
--               selling. Now:
--                 * a trigger on profiles closes every live drop of a seller whose approval is revoked,
--                   through the same safe-closure path as close_drop (unclaimed holds released, buyer
--                   claims and paid orders kept). It covers admin_approve_seller and a direct SQL update;
--                 * create_order_with_reservation and initiate_payment_attempt refuse a seller who is
--                   not approved with SELLER_SUSPENDED (no new orders, no new payment requests).
--                 Buyers who already paid can still submit their UTR, and the seller can still verify
--                 it or record a refund: money already sent is never left without a record.
--   SA-PAY-011  The duplicate-UTR check was an exact, case-sensitive match at verification only.
--               UTRs are now normalised (spaces removed, upper case) when the buyer submits them and
--               when the seller verifies; a UTR already verified on another order is refused at claim
--               time and at verification (REFERENCE_USED_ON_ANOTHER_ORDER), and a unique index on the
--               normalised verified reference backs the check.
--
-- Rules kept from migrations 035/037:
--   * Lock order: orders -> payment_attempts -> products (products always ORDER BY id).
--   * Money is integer paisa. SECURITY DEFINER functions pin search_path = public, pg_temp.
--   * Signatures, grants and existing response keys of the redefined RPCs are unchanged.
--   * RLS stays enabled everywhere; no policy is widened.
--
-- Idempotent: the Database Deploy workflow re-applies it on every apply run.
--
-- Regression suites: audit/seller-app/tests/sql/11_seller_isolation.sql (11.5b),
-- 12_lifecycle_guards.sql (12.7), 13_payments.sql (13.3), 18_storage_enumeration.sql (18.1),
-- 20_p1_round2.sql.

-- ============================================================================
-- 1. Storage: product-images (SA-SEC-003, SA-SEC-008)
-- ============================================================================
-- Downloads of a public bucket go through the public object URL, which is not subject to RLS.
-- The SELECT policy only decides who can list/search objects through the Storage API; the owning
-- seller needs it to overwrite (upsert) their own photos.
-- On a hosted project the deploy role may not be allowed to change policies on storage.objects
-- (owned by supabase_storage_admin). A refusal must not roll back the rest of this migration: it
-- is reported as a WARNING and the post-deploy check (H21) fails until this section has been run
-- in the Supabase SQL editor.
DO $storage$
BEGIN
    DROP POLICY IF EXISTS product_images_public_read ON storage.objects;
    DROP POLICY IF EXISTS product_images_seller_read ON storage.objects;
    CREATE POLICY product_images_seller_read ON storage.objects
        FOR SELECT TO authenticated
        USING (
            bucket_id = 'product-images'
            AND (storage.foldername(name))[1] = auth.uid()::text
        );

    DROP POLICY IF EXISTS product_images_seller_insert ON storage.objects;
    CREATE POLICY product_images_seller_insert ON storage.objects
        FOR INSERT TO authenticated
        WITH CHECK (
            bucket_id = 'product-images'
            AND (storage.foldername(name))[1] = auth.uid()::text
            AND public.is_seller_approved(auth.uid())
        );

    DROP POLICY IF EXISTS product_images_seller_update ON storage.objects;
    CREATE POLICY product_images_seller_update ON storage.objects
        FOR UPDATE TO authenticated
        USING (
            bucket_id = 'product-images'
            AND (storage.foldername(name))[1] = auth.uid()::text
            AND public.is_seller_approved(auth.uid())
        )
        WITH CHECK (
            bucket_id = 'product-images'
            AND (storage.foldername(name))[1] = auth.uid()::text
            AND public.is_seller_approved(auth.uid())
        );
    RAISE NOTICE 'SA-SEC-003/SA-SEC-008: product-images policies updated';
EXCEPTION WHEN insufficient_privilege THEN
    RAISE WARNING 'SA-SEC-003/SA-SEC-008 NOT APPLIED: % (run section 1 of 038 in the Supabase SQL editor)', SQLERRM;
END $storage$;

-- product_images_seller_delete (027) is unchanged: a seller, approved or not, may delete their own files.

-- ============================================================================
-- 2. Payment reference normalisation (SA-PAY-011)
-- ============================================================================
-- One canonical form for bank UTRs and internal references: whitespace removed, upper case.
CREATE OR REPLACE FUNCTION public.normalize_payment_reference(p_reference TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = public, pg_temp
AS $$
    SELECT NULLIF(upper(regexp_replace(COALESCE(p_reference, ''), '\s', '', 'g')), '');
$$;

-- A verified reference exists once, whatever its case or spacing. Existing ledgers that already
-- contain a case/spacing duplicate are reported instead of failing the deploy; the RPC checks
-- below enforce the rule either way, and the post-deploy check prints the count.
DO $$
DECLARE v_dupes INT;
BEGIN
    IF to_regclass('public.uq_order_payments_reference_verified_norm') IS NOT NULL THEN
        RETURN;
    END IF;
    SELECT count(*) INTO v_dupes
      FROM (SELECT public.normalize_payment_reference(reference_id)
              FROM public.order_payments
             WHERE status = 'verified' AND public.normalize_payment_reference(reference_id) IS NOT NULL
             GROUP BY 1 HAVING count(*) > 1) d;
    IF v_dupes > 0 THEN
        RAISE WARNING 'SA-PAY-011: % verified payment reference(s) appear more than once after normalisation; unique index uq_order_payments_reference_verified_norm NOT created. Review order_payments and re-run.', v_dupes;
        RETURN;
    END IF;
    CREATE UNIQUE INDEX uq_order_payments_reference_verified_norm
        ON public.order_payments (public.normalize_payment_reference(reference_id))
        WHERE status = 'verified' AND public.normalize_payment_reference(reference_id) IS NOT NULL;
END $$;

-- ============================================================================
-- 3. RPC: submit_buyer_payment_claim (4-arg; signature, grants and response keys unchanged)
-- ============================================================================
-- Same as migration 037 except: the UTR is normalised (step 2), and a UTR already verified on a
-- different order is refused (step 2b). The same UTR claimed but not verified on two orders is
-- still accepted; the seller sees both claims and verification refuses the second one.
-- Locks: orders -> payment_attempts (products are not touched).
CREATE OR REPLACE FUNCTION public.submit_buyer_payment_claim(
    p_order_id UUID,
    p_order_token TEXT,
    p_payment_attempt_id UUID,
    p_utr TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_attempt RECORD;
    v_clean_utr TEXT;
    v_verification_expires_at TIMESTAMPTZ;
    v_drop_status TEXT;
BEGIN
    -- 1. Validate Order & Capability Token
    SELECT * INTO v_order
    FROM orders
    WHERE id = p_order_id AND order_token::text = p_order_token
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Invalid order ID or security token.'
        );
    END IF;

    -- 2. Normalise (SA-PAY-011: spaces removed, upper case) and validate UTR syntax (6-35 chars)
    v_clean_utr := COALESCE(public.normalize_payment_reference(p_utr), '');
    IF v_clean_utr = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_UTR',
            'message', 'UPI Transaction ID / UTR is required.'
        );
    END IF;

    IF char_length(v_clean_utr) < 6 OR char_length(v_clean_utr) > 35 OR NOT (v_clean_utr ~ '^[a-zA-Z0-9_\-]+$') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_UTR_FORMAT',
            'message', 'UTR must be between 6 and 35 alphanumeric characters without special symbols.'
        );
    END IF;

    -- 2b. A UTR already verified on a different order cannot pay for this one (SA-PAY-011).
    IF EXISTS (
        SELECT 1 FROM order_payments
         WHERE status = 'verified'
           AND order_id <> v_order.id
           AND public.normalize_payment_reference(reference_id) = v_clean_utr
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'REFERENCE_USED_ON_ANOTHER_ORDER',
            'message', 'This UTR has already been used to pay for another order. Check the UTR in your UPI app and enter the one for this payment.'
        );
    END IF;

    -- 3. Fetch and Lock Payment Attempt
    SELECT * INTO v_attempt
    FROM payment_attempts
    WHERE id = p_payment_attempt_id AND order_id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt not found for this order.'
        );
    END IF;

    IF v_attempt.status = 'verified' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_PAYMENT_STATE',
            'message', 'This payment attempt has already been verified.'
        );
    END IF;

    -- 4. Idempotency Check: Same attempt + same UTR returns idempotent success
    IF v_attempt.status IN ('awaiting_seller_verification', 'late_claim_pending_review')
       AND v_attempt.buyer_submitted_utr = v_clean_utr THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'is_late_claim', (v_attempt.status = 'late_claim_pending_review'),
            'payment_attempt_id', v_attempt.id,
            'attempt_id', v_attempt.id,
            'order_id', v_order.id,
            'status', v_attempt.status,
            'buyer_submitted_utr', v_clean_utr,
            'buyer_claimed_at', v_attempt.buyer_claimed_at,
            'verification_expires_at', v_attempt.verification_expires_at,
            'expires_at', v_attempt.expires_at,
            'message', 'Payment claim already submitted with this UTR.'
        );
    END IF;

    -- 5. Late UPI Payment Detection (Order cancelled/expired or payment attempt expired)
    --    The claim is recorded for manual review; inventory is not reclaimed here.
    IF v_order.status IN ('cancelled', 'expired')
       OR v_attempt.status = 'expired'
       OR (v_attempt.expires_at <= NOW() AND v_attempt.status <> 'awaiting_seller_verification') THEN

        UPDATE payment_attempts
        SET buyer_submitted_utr = v_clean_utr,
            buyer_claimed_at = NOW(),
            status = 'late_claim_pending_review',
            updated_at = NOW()
        WHERE id = v_attempt.id;

        RETURN jsonb_build_object(
            'success', true,
            'is_late_claim', true,
            'payment_attempt_id', v_attempt.id,
            'attempt_id', v_attempt.id,
            'order_id', v_order.id,
            'status', 'late_claim_pending_review',
            'buyer_submitted_utr', v_clean_utr,
            'buyer_claimed_at', NOW(),
            'message', 'Your order reservation had expired, but your payment claim has been submitted for manual boutique review.'
        );
    END IF;

    -- 6. Normal flow: authoritative verification deadline (SA-PAY-007).
    --    * Re-claim (different UTR) on an attempt that is already claimed: keep its window.
    --    * Pending order: 30 minutes while the drop is live, else 24 hours.
    --    * Any other order state (e.g. a balance claim on a confirmed order): 24 hours (unchanged).
    IF v_attempt.status IN ('buyer_claimed', 'awaiting_seller_verification')
       AND v_attempt.verification_expires_at IS NOT NULL THEN
        v_verification_expires_at := v_attempt.verification_expires_at;
    ELSIF v_order.status = 'pending' THEN
        SELECT status INTO v_drop_status FROM drops WHERE id = v_order.drop_id;
        v_verification_expires_at := NOW() + CASE WHEN v_drop_status = 'live'
                                                  THEN INTERVAL '30 minutes'
                                                  ELSE INTERVAL '24 hours' END;
    ELSE
        v_verification_expires_at := NOW() + INTERVAL '24 hours';
    END IF;

    -- 7. Atomically Record Buyer Claim on Payment Attempt
    UPDATE payment_attempts
    SET buyer_submitted_utr = v_clean_utr,
        buyer_claimed_at = NOW(),
        status = 'awaiting_seller_verification',
        verification_expires_at = v_verification_expires_at,
        expires_at = v_verification_expires_at,
        updated_at = NOW()
    WHERE id = v_attempt.id;

    -- 8. Order reservation hold matches the verification deadline
    UPDATE orders
    SET hold_expires_at = v_verification_expires_at,
        updated_at = NOW()
    WHERE id = v_order.id;

    RETURN jsonb_build_object(
        'success', true,
        'is_late_claim', false,
        'payment_attempt_id', v_attempt.id,
        'attempt_id', v_attempt.id,
        'order_id', v_order.id,
        'status', 'awaiting_seller_verification',
        'buyer_submitted_utr', v_clean_utr,
        'buyer_claimed_at', NOW(),
        'verification_expires_at', v_verification_expires_at,
        'expires_at', v_verification_expires_at,
        'message', 'Payment claim submitted. Waiting for boutique to verify payment.'
    );
END;
$$;

-- ============================================================================
-- 4. RPC: verify_manual_upi_payment (signature unchanged)
-- ============================================================================
-- Same as migration 035 except steps 6–7: the reference is normalised and the cross-order reuse
-- check compares normalised references (SA-PAY-011).
CREATE OR REPLACE FUNCTION public.verify_manual_upi_payment(
    p_payment_attempt_id UUID,
    p_utr TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id UUID;
    v_order orders%ROWTYPE;
    v_attempt payment_attempts%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_is_service BOOLEAN;
    v_clean_utr TEXT;
    v_verified_ref TEXT;
    v_existing_order_id UUID;
BEGIN
    -- 1. Find the attempt's order WITHOUT locking the attempt (lock order: orders -> attempts -> products).
    SELECT order_id INTO v_order_id FROM payment_attempts WHERE id = p_payment_attempt_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt does not exist.'
        );
    END IF;

    -- 2. Lock the order, then lock and re-read the attempt.
    SELECT * INTO v_order FROM orders WHERE id = v_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'Associated order not found.'
        );
    END IF;

    SELECT * INTO v_attempt
      FROM payment_attempts
     WHERE id = p_payment_attempt_id AND order_id = v_order.id
     FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt does not exist.'
        );
    END IF;

    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;

    -- 3. Authorization: drop-owning seller or trusted backend (service_role request).
    v_is_service := COALESCE(current_setting('role', true), '') = 'service_role'
                 OR COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                             NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                             '') = 'service_role';
    IF NOT v_is_service AND (auth.uid() IS NULL OR auth.uid() <> v_drop.seller_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Only the drop-owning seller or trusted backend service can verify this payment.'
        );
    END IF;

    -- 4. Idempotency on the attempt.
    IF v_attempt.status = 'verified' THEN
        RETURN public.upi_verification_response(v_order.id, v_attempt.id, NULL, true, NULL, NULL,
                                                'Payment attempt has already been verified.');
    END IF;

    -- 5. On-time attempts: terminal orders cannot be verified; UNCLAIMED attempts past their window
    --    expire. A CLAIMED attempt (buyer_claimed / awaiting_seller_verification) stays verifiable
    --    after its window: money in flight never auto-expires (SA-PAY-003).
    IF v_attempt.status <> 'late_claim_pending_review' THEN
        IF v_order.status IN ('cancelled', 'expired') THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', format('Order is in terminal state "%s" and cannot be verified.', v_order.status)
            );
        END IF;

        IF v_attempt.status NOT IN ('buyer_claimed', 'awaiting_seller_verification')
           AND (v_attempt.status = 'expired'
                OR (v_attempt.verification_expires_at IS NOT NULL AND v_attempt.verification_expires_at <= NOW())
                OR (v_attempt.expires_at <= NOW())) THEN
            UPDATE payment_attempts SET status = 'expired', updated_at = NOW() WHERE id = v_attempt.id;
            RETURN jsonb_build_object(
                'success', false,
                'error', 'PAYMENT_ATTEMPT_EXPIRED',
                'message', 'Payment verification window has expired.'
            );
        END IF;
    END IF;

    -- 6. Authoritative reference / UTR.
    --    Normalised (SA-PAY-011): claims stored before 038 may be lower case or contain spaces.
    v_clean_utr := COALESCE(public.normalize_payment_reference(COALESCE(p_utr, v_attempt.buyer_submitted_utr)), '');
    v_verified_ref := COALESCE(NULLIF(v_clean_utr, ''), public.normalize_payment_reference(v_attempt.transaction_reference));

    -- 7. Cross-order reference reuse protection (normalised comparison).
    IF v_verified_ref IS NOT NULL THEN
        SELECT order_id INTO v_existing_order_id
          FROM order_payments
         WHERE public.normalize_payment_reference(reference_id) = v_verified_ref AND status = 'verified'
         ORDER BY (order_id = v_order.id) DESC
         LIMIT 1;

        IF FOUND THEN
            IF v_existing_order_id = v_order.id THEN
                RETURN public.upi_verification_response(v_order.id, v_attempt.id, NULL, true, NULL, NULL,
                                                        'Payment reference already verified for this order.');
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'error', 'REFERENCE_USED_ON_ANOTHER_ORDER',
                    'message', 'This payment reference or UTR has already been verified on another order.'
                );
            END IF;
        END IF;
    END IF;

    -- 8. Per-type transition (shared by on-time and late claims).
    RETURN public.apply_upi_payment_transition(v_order.id, v_attempt.id, v_verified_ref, v_clean_utr, auth.uid());
END;
$$;

-- ============================================================================
-- 5. Internal: safe closure of a drop (shared by close_drop and seller suspension)
-- ============================================================================
-- Steps 5–6 of close_drop from migration 035, unchanged, moved into a helper so that suspension
-- closes drops exactly the way a seller does:
--   * unpaid, unclaimed holds: pieces back to available, order cancelled, open attempts expired;
--   * claims awaiting verification, late claims, advance-paid and paid orders: untouched.
-- The caller must hold the drop row lock and must have checked authorization. Returns the number of
-- orders released. Not callable by clients.
CREATE OR REPLACE FUNCTION public.close_drop_safely(p_drop_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_drop drops%ROWTYPE;
    v_order RECORD;
    v_released_orders_count INT := 0;
BEGIN
    SELECT * INTO v_drop FROM drops WHERE id = p_drop_id FOR UPDATE;
    IF NOT FOUND OR v_drop.status = 'closed' THEN
        RETURN 0;
    END IF;

    -- Safe Closure Protocol (if drop is live):
    -- - Unpaid unclaimed reservations: released back to available & cancelled
    -- - Claims awaiting verification: preserved intact (buyer money in flight)
    -- - Advance-paid holds, fully paid and shipped orders: untouched
    IF v_drop.status = 'live' THEN
        FOR v_order IN
            SELECT o.id FROM orders o
            WHERE o.drop_id = p_drop_id
              AND o.status = 'pending'
              AND o.payment_status = 'unpaid'
              AND NOT EXISTS (
                  SELECT 1 FROM payment_attempts pa
                  WHERE pa.order_id = o.id
                    AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
              )
            ORDER BY o.id ASC
            FOR UPDATE OF o
        LOOP
            -- Lock order: orders -> payment_attempts -> products. Re-check with a fresh snapshot
            -- now that the order is locked: a claim committed while we waited keeps the hold.
            PERFORM 1 FROM payment_attempts WHERE order_id = v_order.id ORDER BY id FOR UPDATE;

            IF EXISTS (
                SELECT 1 FROM payment_attempts
                 WHERE order_id = v_order.id
                   AND status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
            ) OR NOT EXISTS (
                SELECT 1 FROM orders
                 WHERE id = v_order.id AND status = 'pending' AND payment_status = 'unpaid'
            ) THEN
                CONTINUE;
            END IF;

            PERFORM id FROM products
            WHERE reserved_by_order_id = v_order.id
            ORDER BY id ASC
            FOR UPDATE;

            UPDATE products
            SET status = 'available',
                reserved_at = NULL,
                reserved_by_order_id = NULL,
                version = version + 1,
                updated_at = NOW()
            WHERE reserved_by_order_id = v_order.id
              AND status = 'reserved';

            -- Cancel the unpaid unclaimed order
            UPDATE orders
            SET status = 'cancelled',
                hold_expires_at = NOW(),
                updated_at = NOW()
            WHERE id = v_order.id;

            -- Expire associated open payment attempts
            UPDATE payment_attempts
            SET status = 'expired',
                updated_at = NOW()
            WHERE order_id = v_order.id
              AND status IN ('created', 'awaiting_payment');

            v_released_orders_count := v_released_orders_count + 1;
        END LOOP;
    END IF;

    -- Transition Drop to Closed with Transaction-Local Exemption
    PERFORM set_config('livedrop.closing_drop', 'true', true);

    UPDATE drops
    SET status = 'closed',
        closed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_drop_id;

    RETURN v_released_orders_count;
END;
$$;

-- ============================================================================
-- 6. RPC: close_drop (signature, grants and response keys unchanged)
-- ============================================================================
-- Authorization and idempotency as in migration 035; the closure itself is close_drop_safely.
CREATE OR REPLACE FUNCTION public.close_drop(
    p_drop_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_drop drops%ROWTYPE;
    v_released_orders_count INT := 0;
    v_is_service BOOLEAN;
BEGIN
    v_is_service := COALESCE(current_setting('role', true), '') = 'service_role'
                 OR COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                             NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                             '') = 'service_role';

    -- 1. Authentication Check
    IF NOT v_is_service AND auth.uid() IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to close a drop.'
        );
    END IF;

    -- 2. Fetch and Lock Drop
    SELECT * INTO v_drop
    FROM drops
    WHERE id = p_drop_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'DROP_NOT_FOUND',
            'message', 'The specified drop does not exist.'
        );
    END IF;

    -- 3. Verify Seller Ownership
    IF NOT v_is_service AND v_drop.seller_id IS DISTINCT FROM auth.uid() THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'FORBIDDEN',
            'message', 'You are not authorized to close drops for this boutique.'
        );
    END IF;

    -- 4. Idempotency Check
    IF v_drop.status = 'closed' THEN
        RETURN jsonb_build_object(
            'success', true,
            'drop_id', v_drop.id,
            'status', 'closed',
            'closed_at', v_drop.closed_at,
            'idempotent', true,
            'message', 'Drop is already closed.'
        );
    END IF;

    -- 5–6. Safe closure (unclaimed holds released, claims and paid orders kept) and status change.
    v_released_orders_count := public.close_drop_safely(p_drop_id);

    RETURN jsonb_build_object(
        'success', true,
        'drop_id', p_drop_id,
        'status', 'closed',
        'closed_at', NOW(),
        'released_orders_count', v_released_orders_count,
        'message', 'Drop successfully closed. Unclaimed reservations released.'
    );
END;
$$;

-- ============================================================================
-- 7. Suspension closes live drops (SA-ONB-002)
-- ============================================================================
-- Fires on every path that revokes approval: admin_approve_seller(id, false) and a direct
-- UPDATE profiles SET is_approved = false by an operator.
CREATE OR REPLACE FUNCTION public.close_live_drops_on_suspension()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_drop_id UUID;
BEGIN
    FOR v_drop_id IN
        SELECT id FROM drops
         WHERE seller_id = NEW.id AND status = 'live'
         ORDER BY id
    LOOP
        PERFORM public.close_drop_safely(v_drop_id);
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_close_live_drops_on_suspension ON public.profiles;
CREATE TRIGGER trg_close_live_drops_on_suspension
    AFTER UPDATE OF is_approved ON public.profiles
    FOR EACH ROW
    WHEN (OLD.is_approved IS TRUE AND NEW.is_approved IS NOT TRUE)
    EXECUTE FUNCTION public.close_live_drops_on_suspension();

-- Data repair (idempotent): a seller suspended before this migration may still have a live drop.
DO $$
DECLARE v_drop_id UUID; v_n INT := 0;
BEGIN
    FOR v_drop_id IN
        SELECT d.id FROM public.drops d JOIN public.profiles p ON p.id = d.seller_id
         WHERE d.status = 'live' AND p.is_approved IS NOT TRUE
         ORDER BY d.id
    LOOP
        PERFORM public.close_drop_safely(v_drop_id);
        v_n := v_n + 1;
    END LOOP;
    IF v_n > 0 THEN
        RAISE NOTICE 'SA-ONB-002: closed % live drop(s) of sellers who are not approved', v_n;
    END IF;
END $$;

-- ============================================================================
-- 8. RPC: create_order_with_reservation (signature, grants and response keys unchanged)
-- ============================================================================
-- Identical to migration 037 except step 2.1: a seller who is not approved cannot take orders
-- (SA-ONB-002), even if a drop of theirs is still marked live.
CREATE OR REPLACE FUNCTION public.create_order_with_reservation(
    p_drop_id UUID,
    p_product_ids UUID[],
    p_buyer_name TEXT,
    p_buyer_phone TEXT,
    p_shipping_address TEXT,
    p_pincode TEXT,
    p_confirmation_mode TEXT DEFAULT 'advance',
    p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_clean_name TEXT;
    v_clean_phone TEXT;
    v_clean_address TEXT;
    v_clean_pincode TEXT;
    v_clean_idempotency TEXT;
    v_confirmation_mode TEXT;
    v_clean_product_ids UUID[];
    v_existing_product_ids UUID[];
    v_sorted_clean_pids UUID[];
    v_drop drops%ROWTYPE;
    v_seller profiles%ROWTYPE;
    v_subtotal_paisa INT := 0;
    v_shipping_paisa INT := 0;
    v_total_paisa INT := 0;
    v_advance_required_paisa INT := 0;
    v_advance_enabled BOOLEAN;
    v_hold_expires_at TIMESTAMPTZ;
    v_order_code TEXT;
    v_order_token UUID := gen_random_uuid();
    v_order orders%ROWTYPE;
    v_existing_order orders%ROWTYPE;
    v_random_suffix TEXT;
    v_stale_order_id UUID;
    v_free_shipping_threshold_paisa INT;
BEGIN
    -- 0. Clean and Deduplicate Product IDs Array early
    SELECT coalesce(array_agg(DISTINCT pid), '{}') INTO v_clean_product_ids
    FROM unnest(p_product_ids) AS pid
    WHERE pid IS NOT NULL;

    -- 0.1 Check Idempotency Token & Conflict Detection
    v_clean_idempotency := trim(COALESCE(p_idempotency_key, ''));
    IF v_clean_idempotency <> '' THEN
        SELECT * INTO v_existing_order
        FROM orders
        WHERE drop_id = p_drop_id AND idempotency_key = v_clean_idempotency;

        IF FOUND THEN
            -- Check if requested product items match existing order items
            SELECT coalesce(array_agg(product_id ORDER BY product_id ASC), '{}') INTO v_existing_product_ids
            FROM order_items
            WHERE order_id = v_existing_order.id;

            SELECT coalesce(array_agg(pid ORDER BY pid ASC), '{}') INTO v_sorted_clean_pids
            FROM unnest(v_clean_product_ids) AS pid;

            IF v_existing_product_ids IS DISTINCT FROM v_sorted_clean_pids THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'error', 'CHECKOUT_IDEMPOTENCY_CONFLICT',
                    'message', 'The provided idempotency key has already been used for an order with different cart items.'
                );
            END IF;

            -- Return existing committed order receipt idempotently
            RETURN jsonb_build_object(
                'success', true,
                'order_id', v_existing_order.id,
                'order_code', v_existing_order.order_code,
                'order_token', v_existing_order.order_token,
                'subtotal_paisa', v_existing_order.subtotal_paisa,
                'shipping_paisa', v_existing_order.shipping_paisa,
                'total_paisa', v_existing_order.total_paisa,
                'confirmation_mode', v_existing_order.confirmation_mode,
                'advance_required_paisa', v_existing_order.advance_required_paisa,
                'advance_paid_paisa', v_existing_order.advance_paid_paisa,
                'balance_due_paisa', v_existing_order.balance_due_paisa,
                'total_paid_paisa', v_existing_order.total_paid_paisa,
                'payment_status', v_existing_order.payment_status,
                'fulfilment_status', v_existing_order.fulfilment_status,
                'hold_expires_at', v_existing_order.hold_expires_at,
                'idempotent_replay', true
            );
        END IF;
    END IF;

    -- 1. Validate Drop Existence & Status
    SELECT * INTO v_drop FROM drops WHERE id = p_drop_id FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'DROP_NOT_FOUND',
            'message', 'The specified drop does not exist.'
        );
    END IF;

    IF v_drop.status != 'live' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'DROP_NOT_LIVE',
            'message', 'Orders can only be placed on drops that are currently live.'
        );
    END IF;

    -- 2. Fetch Seller Profile
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'SELLER_NOT_FOUND',
            'message', 'The seller for this drop could not be found.'
        );
    END IF;

    -- 2.1 Suspended (or never approved) seller: no new orders (SA-ONB-002).
    IF v_seller.is_approved IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'SELLER_SUSPENDED',
            'message', 'This boutique is not taking orders right now.'
        );
    END IF;

    -- 3. Sanitize and Validate Buyer Name
    v_clean_name := trim(p_buyer_name);
    IF char_length(v_clean_name) < 3 OR char_length(v_clean_name) > 100 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_BUYER_NAME',
            'message', 'Buyer name must be between 3 and 100 characters.'
        );
    END IF;

    -- 4. Sanitize and Validate Indian Phone Number
    v_clean_phone := trim(p_buyer_phone);
    IF v_clean_phone ~ '^91[6-9][0-9]{9}$' THEN
        v_clean_phone := substr(v_clean_phone, 3);
    END IF;
    IF v_clean_phone !~ '^[6-9][0-9]{9}$' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_BUYER_PHONE',
            'message', 'Buyer phone must be a valid 10-digit Indian mobile number starting with 6-9.'
        );
    END IF;

    -- 5. Sanitize and Validate Shipping Address
    v_clean_address := trim(p_shipping_address);
    IF char_length(v_clean_address) < 10 OR char_length(v_clean_address) > 500 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_SHIPPING_ADDRESS',
            'message', 'Shipping address must be between 10 and 500 characters.'
        );
    END IF;

    -- 6. Sanitize and Validate Indian Pincode
    v_clean_pincode := trim(p_pincode);
    IF v_clean_pincode !~ '^[1-9][0-9]{5}$' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_PINCODE',
            'message', 'Pincode must be a valid 6-digit Indian postal code not starting with 0.'
        );
    END IF;

    -- 7. Validate Confirmation Mode
    v_confirmation_mode := lower(trim(coalesce(p_confirmation_mode, 'advance')));
    IF v_confirmation_mode NOT IN ('advance', 'full_payment') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_CONFIRMATION_MODE',
            'message', 'Confirmation mode must be either "advance" or "full_payment".'
        );
    END IF;

    -- 8. Deduplicate and Validate Product IDs Array
    IF array_length(v_clean_product_ids, 1) IS NULL OR array_length(v_clean_product_ids, 1) = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'EMPTY_CART',
            'message', 'At least one product must be selected to checkout.'
        );
    END IF;

    IF array_length(v_clean_product_ids, 1) > 10 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'EXCEEDS_CART_LIMIT',
            'message', 'Cart cannot exceed 10 items.'
        );
    END IF;

    -- 9. Deterministic Product Locking & Availability Assertion
    PERFORM id FROM products
    WHERE id = ANY(v_clean_product_ids)
    ORDER BY id ASC
    FOR UPDATE;

    -- 9.1 Lazy expiry (SA-OPS-001, SA-PAY-007): a requested piece held by a pending order whose
    --     hold has expired and that has no payment claim inside its verification window is released
    --     now instead of waiting for the reaper (a claim past its window moves to late review inside
    --     release_stale_hold; it is never expired). release_stale_hold never waits for a lock; if it
    --     cannot lock everything it changes nothing and the piece simply counts as unavailable below.
    FOR v_stale_order_id IN
        SELECT DISTINCT p.reserved_by_order_id
          FROM products p
          JOIN orders o ON o.id = p.reserved_by_order_id
         WHERE p.id = ANY(v_clean_product_ids)
           AND p.drop_id = p_drop_id
           AND p.status = 'reserved'
           AND o.status = 'pending'
           AND o.hold_expires_at < clock_timestamp()
           AND NOT public.order_has_open_payment_claim(o.id)
    LOOP
        PERFORM public.release_stale_hold(v_stale_order_id);
    END LOOP;

    IF (
        SELECT COUNT(*) FROM products
        WHERE id = ANY(v_clean_product_ids)
          AND drop_id = p_drop_id
          AND status = 'available'
    ) != array_length(v_clean_product_ids, 1) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'STOCK_UNAVAILABLE',
            'message', 'One or more items in your cart are no longer available.'
        );
    END IF;

    -- 10. Compute Subtotal and Authoritative Shipping Fee
    SELECT SUM(price_paisa) INTO v_subtotal_paisa
    FROM products
    WHERE id = ANY(v_clean_product_ids);

    -- SA-PAY-008: one rule everywhere (drop threshold, else shop threshold, else none).
    v_free_shipping_threshold_paisa := public.resolve_free_shipping_threshold(p_drop_id);
    IF v_free_shipping_threshold_paisa IS NOT NULL
       AND v_subtotal_paisa >= v_free_shipping_threshold_paisa THEN
        v_shipping_paisa := 0;
    ELSE
        v_shipping_paisa := COALESCE(v_drop.shipping_fee_paisa, v_seller.default_shipping_fee_paisa, 8000);
    END IF;

    v_total_paisa := v_subtotal_paisa + v_shipping_paisa;

    -- 11. Resolve Seller Advance & Hold Policy
    IF v_confirmation_mode = 'advance' THEN
        v_advance_enabled := COALESCE(v_drop.advance_confirmation_enabled, v_seller.advance_confirmation_enabled, false);
        IF NOT v_advance_enabled THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'ADVANCE_CONFIRMATION_DISABLED',
                'message', 'This seller does not offer advance confirmation. Please choose Pay in Full.'
            );
        END IF;

        v_advance_required_paisa := COALESCE(v_drop.advance_amount_paisa, v_seller.advance_amount_paisa, 25000);
        IF v_advance_required_paisa > v_total_paisa THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'ADVANCE_EXCEEDS_TOTAL',
                'message', 'Configured advance amount exceeds total order amount.'
            );
        END IF;

        v_hold_expires_at := NOW() + INTERVAL '15 minutes';
    ELSE
        v_advance_required_paisa := 0;
        v_hold_expires_at := NOW() + INTERVAL '15 minutes';
    END IF;

    -- 12. Generate Collision-Resistant 6-Char Order Code
    <<code_gen>>
    FOR _attempt IN 1..100 LOOP
        v_random_suffix := '';
        FOR _i IN 1..6 LOOP
            v_random_suffix := v_random_suffix ||
                substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                       floor(random() * 36 + 1)::int, 1);
        END LOOP;
        v_order_code := 'LD-' || v_random_suffix;
        EXIT code_gen WHEN NOT EXISTS (SELECT 1 FROM orders WHERE order_code = v_order_code);
    END LOOP code_gen;

    IF EXISTS (SELECT 1 FROM orders WHERE order_code = v_order_code) THEN
        RAISE EXCEPTION 'Failed to generate unique order code after 100 attempts';
    END IF;

    -- 13. Insert Order Record with Snapshotted Financial Model & Idempotency Key
    INSERT INTO orders (
        drop_id, order_code, order_token, buyer_name, buyer_phone,
        shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa,
        confirmation_mode, advance_required_paisa, advance_paid_paisa,
        total_paid_paisa, balance_due_paisa, payment_status, fulfilment_status,
        status, hold_expires_at, idempotency_key
    ) VALUES (
        p_drop_id, v_order_code, v_order_token, v_clean_name, v_clean_phone,
        v_clean_address, v_clean_pincode, v_subtotal_paisa, v_shipping_paisa, v_total_paisa,
        v_confirmation_mode, v_advance_required_paisa, 0,
        0, v_total_paisa, 'unpaid', 'not_ready',
        'pending', v_hold_expires_at, NULLIF(v_clean_idempotency, '')
    ) RETURNING * INTO v_order;

    -- 14. Insert Order Line Items & Update Products to Reserved State
    INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
    SELECT v_order.id, p.id, p.price_paisa
    FROM products p
    WHERE p.id = ANY(v_clean_product_ids)
    ORDER BY p.id ASC;

    UPDATE products
    SET status = 'reserved',
        reserved_at = NOW(),
        reserved_by_order_id = v_order.id,
        version = version + 1,
        updated_at = NOW()
    WHERE id = ANY(v_clean_product_ids);

    -- 15. Return Authoritative Order Receipt
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'order_token', v_order.order_token,
        'subtotal_paisa', v_order.subtotal_paisa,
        'shipping_paisa', v_order.shipping_paisa,
        'total_paisa', v_order.total_paisa,
        'confirmation_mode', v_order.confirmation_mode,
        'advance_required_paisa', v_order.advance_required_paisa,
        'advance_paid_paisa', v_order.advance_paid_paisa,
        'balance_due_paisa', v_order.balance_due_paisa,
        'total_paid_paisa', v_order.total_paid_paisa,
        'payment_status', v_order.payment_status,
        'fulfilment_status', v_order.fulfilment_status,
        'hold_expires_at', v_order.hold_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 9. RPC: initiate_payment_attempt (signature, grants and response keys unchanged)
-- ============================================================================
-- Same as migration 013 except step 4.1: no new payment request (UPI payee details) is handed out
-- for a seller who is not approved (SA-ONB-002). Claims for money already sent are still accepted by
-- submit_buyer_payment_claim.
CREATE OR REPLACE FUNCTION public.initiate_payment_attempt(
    p_order_id UUID,
    p_order_token TEXT,
    p_payment_type TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_seller RECORD;
    v_drop RECORD;
    v_payment_type TEXT;
    v_expected_amount_paisa INT;
    v_vpa TEXT;
    v_display_name TEXT;
    v_reference TEXT;
    v_random_suffix TEXT;
    v_attempt RECORD;
    v_upi_uri TEXT;
    v_note TEXT;
BEGIN
    -- 1. Validate Order Existence & Token Access
    SELECT * INTO v_order 
    FROM orders 
    WHERE id = p_order_id AND order_token::text = p_order_token 
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Invalid order ID or security token.'
        );
    END IF;

    -- 2. Reject Terminal Orders
    IF v_order.status IN ('cancelled', 'expired') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in terminal state "%s" and cannot initiate payments.', v_order.status)
        );
    END IF;

    -- 3. Resolve Payment Type & Amount
    IF p_payment_type IS NOT NULL THEN
        v_payment_type := p_payment_type;
    ELSIF v_order.status = 'pending' THEN
        IF v_order.confirmation_mode = 'advance' THEN
            v_payment_type := 'advance';
        ELSE
            v_payment_type := 'full';
        END IF;
    ELSIF v_order.status = 'confirmed' AND v_order.payment_status = 'advance_paid' THEN
        v_payment_type := 'balance';
    ELSE
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Cannot initiate payment for order in status "%s" with payment status "%s".', v_order.status, v_order.payment_status)
        );
    END IF;

    IF v_payment_type = 'advance' THEN
        IF v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid' THEN
            RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE', 'message', 'Advance payment is only allowed on pending unpaid orders.');
        END IF;
        v_expected_amount_paisa := v_order.advance_required_paisa;
    ELSIF v_payment_type = 'balance' THEN
        IF v_order.status <> 'confirmed' OR v_order.payment_status <> 'advance_paid' THEN
            RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE', 'message', 'Balance payment is only allowed on confirmed advance-paid orders.');
        END IF;
        v_expected_amount_paisa := v_order.balance_due_paisa;
    ELSIF v_payment_type = 'full' THEN
        IF v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid' THEN
            RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE', 'message', 'Full payment is only allowed on pending unpaid orders.');
        END IF;
        v_expected_amount_paisa := v_order.total_paisa;
    ELSE
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_PAYMENT_TYPE', 'message', 'Invalid payment type requested.');
    END IF;

    IF v_expected_amount_paisa <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'ZERO_AMOUNT_DUE', 'message', 'No balance due on this order.');
    END IF;

    -- 4. Resolve Seller Configuration Snapshot
    SELECT drops.* INTO v_drop FROM drops WHERE id = v_order.drop_id;
    SELECT profiles.* INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 4.1 Suspended (or never approved) seller: do not hand out payee details (SA-ONB-002).
    IF v_seller.is_approved IS NOT TRUE THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'SELLER_SUSPENDED',
            'message', 'This boutique is not accepting payments right now. Please do not send any payment for this order.'
        );
    END IF;

    IF v_seller.upi_enabled IS FALSE THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UPI_DISABLED',
            'message', 'This seller has temporarily disabled UPI payments.'
        );
    END IF;

    v_vpa := COALESCE(v_seller.upi_vpa, v_seller.upi_id);
    IF v_vpa IS NULL OR v_vpa = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UPI_NOT_CONFIGURED',
            'message', 'Seller has not configured a valid UPI ID.'
        );
    END IF;

    v_display_name := COALESCE(v_seller.upi_display_name, v_seller.store_name, 'LiveDrop Seller');

    -- 5. Reuse Existing Active Attempt If Valid
    SELECT * INTO v_attempt 
    FROM payment_attempts 
    WHERE order_id = v_order.id 
      AND payment_type = v_payment_type 
      AND status IN ('created', 'awaiting_payment', 'awaiting_seller_verification')
      AND expires_at > NOW()
    ORDER BY created_at DESC 
    LIMIT 1;

    IF FOUND THEN
        v_note := 'LiveDrop ' || v_order.order_code || ' ' || v_payment_type;
        v_upi_uri := generate_upi_payment_uri(
            v_attempt.payee_vpa_snapshot,
            v_attempt.payee_display_name_snapshot,
            v_attempt.expected_amount_paisa,
            v_attempt.transaction_reference,
            v_note
        );

        RETURN jsonb_build_object(
            'success', true,
            'payment_attempt_id', v_attempt.id,
            'attempt_id', v_attempt.id,
            'order_id', v_order.id,
            'order_code', v_order.order_code,
            'payment_type', v_attempt.payment_type,
            'expected_amount_paisa', v_attempt.expected_amount_paisa,
            'payee_vpa', v_attempt.payee_vpa_snapshot,
            'payee_display_name', v_attempt.payee_display_name_snapshot,
            'payee_name', v_attempt.payee_display_name_snapshot,
            'transaction_reference', v_attempt.transaction_reference,
            'status', v_attempt.status,
            'buyer_submitted_utr', v_attempt.buyer_submitted_utr,
            'expires_at', v_attempt.expires_at,
            'upi_uri', v_upi_uri,
            'is_existing', true
        );
    END IF;

    -- 6. Generate Collision-Resistant Transaction Reference
    v_random_suffix := substr(md5(random()::text || clock_timestamp()::text), 1, 4);
    v_reference := v_order.order_code || '-' 
        || CASE 
             WHEN v_payment_type = 'advance' THEN 'ADV' 
             WHEN v_payment_type = 'balance' THEN 'BAL' 
             ELSE 'FUL' 
           END 
        || '-' || upper(v_random_suffix);

    -- 7. Snapshot Values and Insert Payment Attempt
    INSERT INTO payment_attempts (
        order_id,
        payment_type,
        payment_method,
        expected_amount_paisa,
        payee_vpa_snapshot,
        payee_display_name_snapshot,
        transaction_reference,
        status,
        expires_at
    ) VALUES (
        v_order.id,
        v_payment_type,
        'upi',
        v_expected_amount_paisa,
        v_vpa,
        v_display_name,
        v_reference,
        'awaiting_payment',
        COALESCE(v_order.hold_expires_at, NOW() + INTERVAL '15 minutes')
    )
    RETURNING * INTO v_attempt;

    v_note := 'LiveDrop ' || v_order.order_code || ' ' || v_payment_type;
    v_upi_uri := generate_upi_payment_uri(
        v_attempt.payee_vpa_snapshot,
        v_attempt.payee_display_name_snapshot,
        v_attempt.expected_amount_paisa,
        v_attempt.transaction_reference,
        v_note
    );

    RETURN jsonb_build_object(
        'success', true,
        'payment_attempt_id', v_attempt.id,
        'attempt_id', v_attempt.id,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'payment_type', v_attempt.payment_type,
        'expected_amount_paisa', v_attempt.expected_amount_paisa,
        'payee_vpa', v_attempt.payee_vpa_snapshot,
        'payee_display_name', v_attempt.payee_display_name_snapshot,
        'payee_name', v_attempt.payee_display_name_snapshot,
        'transaction_reference', v_attempt.transaction_reference,
        'status', v_attempt.status,
        'buyer_submitted_utr', v_attempt.buyer_submitted_utr,
        'expires_at', v_attempt.expires_at,
        'upi_uri', v_upi_uri,
        'is_existing', false
    );
END;
$$;


-- ============================================================================
-- 10. Privileges
-- ============================================================================
REVOKE ALL ON FUNCTION public.normalize_payment_reference(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_payment_reference(TEXT) TO anon, authenticated, service_role;

-- Internal helpers: callable only from the SECURITY DEFINER functions above (function owner).
REVOKE ALL ON FUNCTION public.close_drop_safely(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.close_live_drops_on_suspension() FROM PUBLIC, anon, authenticated, service_role;

-- Redefined RPCs: same grants as before.
REVOKE ALL ON FUNCTION public.submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.verify_manual_upi_payment(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_manual_upi_payment(UUID, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.close_drop(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_drop(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.initiate_payment_attempt(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.initiate_payment_attempt(UUID, TEXT, TEXT) TO anon, authenticated, service_role;
