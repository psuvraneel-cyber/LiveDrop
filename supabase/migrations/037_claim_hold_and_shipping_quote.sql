-- LiveDrop Migration: 037_claim_hold_and_shipping_quote.sql
-- Description: Launch-blocker fixes from the seller-app audit (audit/seller-app/).
--
--   SA-PAY-007  Any syntactically valid (possibly fake) UTR extended the 15-minute hold to 24 hours,
--               locking a unique piece for a day. New rule (owner decision):
--                 * A normal claim on a PENDING order opens a verification window, and holds the
--                   pieces, for 30 minutes when the drop is live at claim time, else 24 hours.
--                 * Re-submitting a different UTR on an attempt that is already claimed keeps the
--                   original window (a buyer cannot extend the hold by re-claiming).
--                 * When the hold AND the claim's verification window have both passed, the reaper
--                   (release_expired_holds) and checkout's lazy expiry (release_stale_hold) release
--                   the order: order cancelled, pieces back on sale, and the claimed attempt moves to
--                   'late_claim_pending_review' with its UTR and buyer_claimed_at kept. It stays in
--                   the seller's payment queue; verifying it uses the late path from migration 035,
--                   which re-secures the pieces if they are still free or records a refund obligation.
--                 * Unclaimed attempts still expire. A claimed attempt is never set to 'expired'.
--                 * CONFIRMED (advance-paid) orders with a pending balance claim are not released by
--                   this rule (migration 035 behaviour kept).
--   SA-PAY-008  The free-shipping threshold was computed four different ways and checkout ignored the
--               drop's own threshold. One rule now, used by checkout and exposed to clients:
--                 drop.free_shipping_threshold_paisa, else profiles.free_shipping_threshold_paisa,
--                 else no free shipping. The hidden Rs 2,000 column defaults are removed (existing
--                 values stay as they are).
--
-- Rules kept from migration 035:
--   * Lock order: orders -> payment_attempts -> products (products always ORDER BY id).
--   * The reaper and the lazy-expiry helper never wait for a lock (FOR UPDATE SKIP LOCKED).
--   * Money is integer paisa. SECURITY DEFINER functions pin search_path = public, pg_temp.
--   * Signatures, grants and response keys of the redefined RPCs are unchanged.
--
-- Regression suites: audit/seller-app/tests/sql/13_payments.sql, 19_p0_remediation.sql,
-- 14_concurrency.sh.

-- ============================================================================
-- 1. Free-shipping threshold: no hidden defaults (SA-PAY-008)
-- ============================================================================
ALTER TABLE public.drops    ALTER COLUMN free_shipping_threshold_paisa DROP DEFAULT;
ALTER TABLE public.profiles ALTER COLUMN free_shipping_threshold_paisa DROP DEFAULT;

-- ============================================================================
-- 2. resolve_free_shipping_threshold(p_drop_id) -> paisa, or NULL = no free shipping
-- ============================================================================
-- The single authoritative rule. Clients may call it to show the same promise checkout applies;
-- the threshold is public storefront information (also served by public_seller_storefronts).
CREATE OR REPLACE FUNCTION public.resolve_free_shipping_threshold(p_drop_id UUID)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(d.free_shipping_threshold_paisa, p.free_shipping_threshold_paisa)
      FROM drops d
      LEFT JOIN profiles p ON p.id = d.seller_id
     WHERE d.id = p_drop_id;
$$;

-- ============================================================================
-- 3. Internal: does an order have a payment claim whose verification window is still open?
-- ============================================================================
-- A claim (buyer_claimed / awaiting_seller_verification) keeps a PENDING order's hold until its
-- verification_expires_at; a claim without a window is treated as open (never auto-released).
-- Late claims (late_claim_pending_review) do not keep a pending hold: they are already outside the
-- window and stay in the seller's queue whatever happens to the order.
CREATE OR REPLACE FUNCTION public.order_has_open_payment_claim(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM payment_attempts pa
         WHERE pa.order_id = p_order_id
           AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification')
           AND (pa.verification_expires_at IS NULL OR pa.verification_expires_at >= clock_timestamp())
    );
$$;

-- ============================================================================
-- 4. RPC: submit_buyer_payment_claim (4-arg; signature, grants and response keys unchanged)
-- ============================================================================
-- Same as migration 023 except step 6: the window is 30 minutes during a live and 24 hours
-- otherwise for a pending order, and a re-claim never extends an existing window.
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

    -- 2. Validate UTR Syntax (alphanumeric 6-35 chars)
    v_clean_utr := trim(COALESCE(p_utr, ''));
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
-- 5. Internal: release one stale hold without ever waiting for a lock
-- ============================================================================
-- Returns true when the order was cancelled and its pieces returned to sale; false (and changes
-- nothing) when the order is not a pending unpaid hold past hold_expires_at, has a claim whose
-- verification window is still open, or any of its rows is locked by another transaction.
-- Unclaimed attempts expire; claimed attempts past their window move to late review (money in
-- flight is never expired).
CREATE OR REPLACE FUNCTION public.release_stale_hold(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_locked INT;
    v_total INT;
BEGIN
    SELECT * INTO v_order
      FROM orders
     WHERE id = p_order_id
       AND status = 'pending'
       AND payment_status = 'unpaid'
       AND hold_expires_at < clock_timestamp()
     FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Payment attempts: never wait.
    SELECT count(*) INTO v_locked
      FROM (SELECT 1 FROM payment_attempts WHERE order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
    SELECT count(*) INTO v_total FROM payment_attempts WHERE order_id = v_order.id;
    IF v_locked < v_total THEN
        RETURN false;
    END IF;

    -- A claim inside its verification window keeps the hold (re-checked under the locks).
    IF public.order_has_open_payment_claim(v_order.id) THEN
        RETURN false;
    END IF;

    -- Pieces: never wait (the caller may already hold some of them; own locks are re-acquired).
    SELECT count(*) INTO v_locked
      FROM (SELECT 1 FROM products WHERE reserved_by_order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
    SELECT count(*) INTO v_total FROM products WHERE reserved_by_order_id = v_order.id;
    IF v_locked < v_total THEN
        RETURN false;
    END IF;

    UPDATE products
       SET status = 'available',
           reserved_at = NULL,
           reserved_by_order_id = NULL,
           version = version + 1,
           updated_at = NOW()
     WHERE reserved_by_order_id = v_order.id
       AND status = 'reserved';

    -- Unclaimed attempts expire.
    UPDATE payment_attempts
       SET status = 'expired',
           updated_at = NOW()
     WHERE order_id = v_order.id
       AND status IN ('created', 'awaiting_payment');

    -- Claimed attempts past their window stay in the seller's queue as late claims
    -- (UTR, buyer_claimed_at and verification_expires_at are kept).
    UPDATE payment_attempts
       SET status = 'late_claim_pending_review',
           updated_at = NOW()
     WHERE order_id = v_order.id
       AND status IN ('buyer_claimed', 'awaiting_seller_verification');

    UPDATE orders
       SET status = 'cancelled',
           fulfilment_status = 'not_ready',
           updated_at = NOW()
     WHERE id = v_order.id;

    RETURN true;
END;
$$;

-- ============================================================================
-- 6. Reaper: release_expired_holds() (signature unchanged; pg_cron job from 036 and run-reaper.mjs)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.release_expired_holds()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_candidate RECORD;
    v_order orders%ROWTYPE;
    v_locked INT;
    v_total INT;
BEGIN
    FOR v_candidate IN
        SELECT o.id, o.status
          FROM orders o
         WHERE o.status IN ('pending', 'confirmed')
           AND o.hold_expires_at < clock_timestamp()
           AND CASE
                   -- Pending hold: released unless a claim is still inside its window (SA-PAY-007).
                   WHEN o.status = 'pending' THEN NOT public.order_has_open_payment_claim(o.id)
                   -- Advance-paid hold: any claim in flight keeps it (migration 035 rule).
                   ELSE NOT EXISTS (
                       SELECT 1 FROM payment_attempts pa
                        WHERE pa.order_id = o.id
                          AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
                   )
               END
         ORDER BY o.id
         FOR UPDATE OF o SKIP LOCKED
    LOOP
        IF v_candidate.status = 'pending' THEN
            -- Cancel, release pieces, expire unclaimed attempts, move lapsed claims to late review
            -- (shared with lazy expiry).
            PERFORM public.release_stale_hold(v_candidate.id);
            CONTINUE;
        END IF;

        -- Advance-paid hold that lapsed: order expires, the advance is retained (existing rule).
        SELECT * INTO v_order FROM orders WHERE id = v_candidate.id;
        IF v_order.status <> 'confirmed' OR v_order.hold_expires_at >= clock_timestamp() THEN
            CONTINUE;
        END IF;

        SELECT count(*) INTO v_locked
          FROM (SELECT 1 FROM payment_attempts WHERE order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
        SELECT count(*) INTO v_total FROM payment_attempts WHERE order_id = v_order.id;
        IF v_locked < v_total THEN
            CONTINUE;
        END IF;

        IF EXISTS (
            SELECT 1 FROM payment_attempts
             WHERE order_id = v_order.id
               AND status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
        ) THEN
            CONTINUE;
        END IF;

        SELECT count(*) INTO v_locked
          FROM (SELECT 1 FROM products WHERE reserved_by_order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
        SELECT count(*) INTO v_total FROM products WHERE reserved_by_order_id = v_order.id;
        IF v_locked < v_total THEN
            CONTINUE;
        END IF;

        UPDATE products
           SET status = 'available',
               reserved_at = NULL,
               reserved_by_order_id = NULL,
               version = version + 1,
               updated_at = NOW()
         WHERE reserved_by_order_id = v_order.id
           AND status = 'reserved';

        UPDATE payment_attempts
           SET status = 'expired',
               updated_at = NOW()
         WHERE order_id = v_order.id
           AND status IN ('created', 'awaiting_payment');

        UPDATE orders
           SET status = 'expired',
               fulfilment_status = 'not_ready',
               updated_at = NOW()
         WHERE id = v_order.id;
    END LOOP;
END;
$$;

-- ============================================================================
-- 7. RPC: create_order_with_reservation (signature, grants and response keys unchanged)
-- ============================================================================
-- Identical to migration 035 except:
--   * step 9.1 lazy expiry uses the claim-window rule above (order_has_open_payment_claim);
--   * step 10 uses resolve_free_shipping_threshold (SA-PAY-008).
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
-- 8. Privileges
-- ============================================================================
-- Public read of the shipping rule (same audience as checkout).
REVOKE ALL ON FUNCTION public.resolve_free_shipping_threshold(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_free_shipping_threshold(UUID) TO anon, authenticated, service_role;

-- Internal helpers: callable only from the SECURITY DEFINER functions above (function owner).
REVOKE ALL ON FUNCTION public.order_has_open_payment_claim(UUID) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.release_stale_hold(UUID) FROM PUBLIC, anon, authenticated, service_role;

-- Redefined RPCs: same grants as before.
REVOKE ALL ON FUNCTION public.submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.release_expired_holds() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_expired_holds() TO service_role;

REVOKE ALL ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
