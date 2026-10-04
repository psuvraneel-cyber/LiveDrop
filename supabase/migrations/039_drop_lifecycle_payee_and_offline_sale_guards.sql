-- LiveDrop Migration: 039_drop_lifecycle_payee_and_offline_sale_guards.sql
-- Description: P1 fixes from the seller-app audit (audit/seller-app/), round 4.
--
--   SA-DROP-001  Closed drops could be reopened (closed -> draft -> live) although docs/09 §2.2 forbids
--                it. The database now enforces the drop state machine exactly as specified:
--                draft -> live, live -> closed (only through close_drop / close_drop_safely). Every
--                other status change is refused (DROP_TRANSITION_FORBIDDEN).
--   SA-DROP-002  The public slug could be changed while the drop was live, breaking links already
--                shared. The slug is now editable only while the drop is a draft (DROP_SLUG_LOCKED).
--   SA-PAY-012   With UPI turned off (or no payee UPI ID), checkout still reserved pieces that the buyer
--                could not pay for. create_order_with_reservation now refuses with UPI_DISABLED /
--                UPI_NOT_CONFIGURED before anything is reserved.
--   SA-INV-001   An accidental "Mark Sold" could not be undone. Owner decision (ADR-014): a piece marked
--                sold offline can be returned to sale by its seller within 30 minutes, if no live order
--                references it and its drop is not closed. mark_product_sold_offline records
--                sold_offline_at; undo_mark_product_sold_offline is the only way back.
--   SA-AUTH-004  The payee UPI ID (where every buyer sends money) and the seller's phone could be
--                changed with any active session, without a record. Now:
--                  * a seller (authenticated role) can change upi_id, upi_vpa or phone_number only
--                    within 10 minutes of signing in with their password (JWT `amr` claim), otherwise
--                    the update is refused (REAUTH_REQUIRED);
--                  * every change of upi_id, upi_vpa, upi_display_name or phone_number is written to
--                    payee_change_log (seller can read their own rows; nobody can edit them).
--
-- Machine-readable error codes raised by triggers are in the HINT field of the error.
-- Rules kept: SECURITY DEFINER functions pin search_path = public, pg_temp; money in integer paisa;
-- RLS stays enabled; signatures and grants of redefined RPCs are unchanged. Idempotent.
--
-- Regression suites: audit/seller-app/tests/sql/12_lifecycle_guards.sql (12.4b/12.4c/12.5),
-- 13_payments.sql (13.13), 21_p1_round4.sql.

-- ============================================================================
-- 1. Drop state machine and slug lock (SA-DROP-001, SA-DROP-002)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.enforce_drop_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status IS DISTINCT FROM OLD.status
       AND NOT (OLD.status = 'draft' AND NEW.status = 'live')
       AND NOT (OLD.status = 'live' AND NEW.status = 'closed') THEN
        RAISE EXCEPTION 'A drop cannot move from % to %. Closed drops cannot be reopened; start a new drop instead.',
            OLD.status, NEW.status
            USING ERRCODE = '42501', HINT = 'DROP_TRANSITION_FORBIDDEN';
    END IF;

    IF NEW.slug IS DISTINCT FROM OLD.slug AND OLD.status <> 'draft' THEN
        RAISE EXCEPTION 'The drop link cannot be changed once the drop has gone live.'
            USING ERRCODE = '42501', HINT = 'DROP_SLUG_LOCKED';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_drop_lifecycle ON public.drops;
CREATE TRIGGER trg_enforce_drop_lifecycle
    BEFORE UPDATE ON public.drops
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_drop_lifecycle();

-- ============================================================================
-- 2. Offline sale and its 30-minute undo (SA-INV-001, ADR-014)
-- ============================================================================
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sold_offline_at TIMESTAMPTZ;
GRANT SELECT (sold_offline_at) ON public.products TO authenticated;

-- Same as migration 009 except: records sold_offline_at, and refuses pieces of a closed drop.
CREATE OR REPLACE FUNCTION public.mark_product_sold_offline(
    p_product_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_prod products%ROWTYPE;
    v_drop_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    SELECT p.* INTO v_prod
    FROM products p
    JOIN drops d ON d.id = p.drop_id
    WHERE p.id = p_product_id AND d.seller_id = auth.uid()
    FOR UPDATE OF p;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'PRODUCT_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    IF v_prod.status = 'sold' THEN
        RETURN jsonb_build_object('success', false, 'error', 'ALREADY_SOLD');
    END IF;

    IF v_prod.status = 'reserved' THEN
        RETURN jsonb_build_object('success', false, 'error', 'PRODUCT_RESERVED');
    END IF;

    SELECT status INTO v_drop_status FROM drops WHERE id = v_prod.drop_id;
    IF v_drop_status = 'closed' THEN
        RETURN jsonb_build_object('success', false, 'error', 'DROP_CLOSED');
    END IF;

    UPDATE products
    SET status = 'sold',
        sold_offline_at = NOW(),
        version = version + 1,
        updated_at = NOW()
    WHERE id = p_product_id;

    RETURN jsonb_build_object(
        'success', true,
        'sold_offline_at', NOW(),
        'undo_until', NOW() + INTERVAL '30 minutes'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Returns a piece that its seller marked sold offline back to sale, within 30 minutes.
CREATE OR REPLACE FUNCTION public.undo_mark_product_sold_offline(
    p_product_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_prod products%ROWTYPE;
    v_drop_status TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    SELECT p.* INTO v_prod
    FROM products p
    JOIN drops d ON d.id = p.drop_id
    WHERE p.id = p_product_id AND d.seller_id = auth.uid()
    FOR UPDATE OF p;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'PRODUCT_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    IF v_prod.status = 'available' THEN
        RETURN jsonb_build_object('success', true, 'idempotent', true, 'status', 'available');
    END IF;

    IF v_prod.status <> 'sold' OR v_prod.sold_offline_at IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'NOT_SOLD_OFFLINE',
            'message', 'Only a piece you marked as sold yourself can be put back on sale.');
    END IF;

    IF v_prod.sold_offline_at < NOW() - INTERVAL '30 minutes' THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNDO_WINDOW_EXPIRED',
            'message', 'A sale can only be undone within 30 minutes.');
    END IF;

    IF EXISTS (
        SELECT 1 FROM order_items oi JOIN orders o ON o.id = oi.order_id
         WHERE oi.product_id = v_prod.id AND o.status NOT IN ('cancelled', 'expired')
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'PRODUCT_HAS_ORDER',
            'message', 'This piece belongs to an order and cannot be put back on sale.');
    END IF;

    SELECT status INTO v_drop_status FROM drops WHERE id = v_prod.drop_id;
    IF v_drop_status = 'closed' THEN
        RETURN jsonb_build_object('success', false, 'error', 'DROP_CLOSED',
            'message', 'This drop is closed.');
    END IF;

    UPDATE products
    SET status = 'available',
        sold_offline_at = NULL,
        version = version + 1,
        updated_at = NOW()
    WHERE id = v_prod.id;

    RETURN jsonb_build_object('success', true, 'idempotent', false, 'status', 'available');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 3. Payee details: recent password sign-in and change log (SA-AUTH-004)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payee_change_log (
    id BIGSERIAL PRIMARY KEY,
    seller_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    field TEXT NOT NULL CHECK (field IN ('upi_id', 'upi_vpa', 'upi_display_name', 'phone_number')),
    old_value TEXT,
    new_value TEXT,
    changed_by UUID,
    changed_by_role TEXT NOT NULL,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_payee_change_log_seller ON public.payee_change_log (seller_id, changed_at DESC);

ALTER TABLE public.payee_change_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.payee_change_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.payee_change_log TO authenticated;
REVOKE ALL ON SEQUENCE public.payee_change_log_id_seq FROM PUBLIC, anon, authenticated;
DROP POLICY IF EXISTS payee_change_log_owner_read ON public.payee_change_log;
CREATE POLICY payee_change_log_owner_read ON public.payee_change_log
    FOR SELECT TO authenticated
    USING (seller_id = auth.uid());

-- Seconds since the caller last signed in with a password, from the JWT `amr` claim; NULL if the
-- token carries no password sign-in.
CREATE OR REPLACE FUNCTION public.seconds_since_password_sign_in()
RETURNS BIGINT
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT extract(epoch FROM clock_timestamp())::bigint - max((e ->> 'timestamp')::bigint)
      FROM jsonb_array_elements(
               CASE WHEN jsonb_typeof(auth.jwt() -> 'amr') = 'array' THEN auth.jwt() -> 'amr' ELSE '[]'::jsonb END
           ) AS e
     WHERE e ->> 'method' = 'password'
       AND (e ->> 'timestamp') ~ '^[0-9]+$';
$$;

CREATE OR REPLACE FUNCTION public.guard_and_log_payee_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_role TEXT := COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', current_user);
    v_age BIGINT;
BEGIN
    IF v_role = 'authenticated'
       AND (NEW.upi_id IS DISTINCT FROM OLD.upi_id
            OR NEW.upi_vpa IS DISTINCT FROM OLD.upi_vpa
            OR NEW.phone_number IS DISTINCT FROM OLD.phone_number) THEN
        v_age := public.seconds_since_password_sign_in();
        IF v_age IS NULL OR v_age > 600 THEN
            RAISE EXCEPTION 'Enter your password again to change where buyers pay you.'
                USING ERRCODE = '42501', HINT = 'REAUTH_REQUIRED';
        END IF;
    END IF;

    INSERT INTO payee_change_log (seller_id, field, old_value, new_value, changed_by, changed_by_role)
    SELECT NEW.id, f.field, f.old_value, f.new_value, auth.uid(), v_role
      FROM (VALUES ('upi_id', OLD.upi_id, NEW.upi_id),
                   ('upi_vpa', OLD.upi_vpa, NEW.upi_vpa),
                   ('upi_display_name', OLD.upi_display_name, NEW.upi_display_name),
                   ('phone_number', OLD.phone_number, NEW.phone_number)) AS f(field, old_value, new_value)
     WHERE f.old_value IS DISTINCT FROM f.new_value;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_and_log_payee_change ON public.profiles;
CREATE TRIGGER trg_guard_and_log_payee_change
    BEFORE UPDATE OF upi_id, upi_vpa, upi_display_name, phone_number ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_and_log_payee_change();

-- ============================================================================
-- 4. RPC: create_order_with_reservation (signature, grants and response keys unchanged)
-- ============================================================================
-- Identical to migration 038 except step 2.2: a seller who cannot be paid (UPI turned off, or no
-- payee UPI ID) cannot take orders (SA-PAY-012). The codes match initiate_payment_attempt.
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

    -- 2.2 A seller who cannot be paid cannot take orders (SA-PAY-012); nothing is reserved.
    IF v_seller.upi_enabled IS FALSE THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UPI_DISABLED',
            'message', 'This boutique has paused payments, so orders cannot be placed right now.'
        );
    END IF;
    IF COALESCE(NULLIF(trim(v_seller.upi_vpa), ''), NULLIF(trim(v_seller.upi_id), '')) IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UPI_NOT_CONFIGURED',
            'message', 'This boutique has not set up payments yet, so orders cannot be placed right now.'
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
-- 5. Privileges
-- ============================================================================
REVOKE ALL ON FUNCTION public.mark_product_sold_offline(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_product_sold_offline(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.undo_mark_product_sold_offline(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.undo_mark_product_sold_offline(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

-- Trigger functions and the claim helper are not part of the client API.
REVOKE ALL ON FUNCTION public.enforce_drop_lifecycle() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_and_log_payee_change() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.seconds_since_password_sign_in() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seconds_since_password_sign_in() TO authenticated, service_role;
