-- ============================================================================
-- LiveDrop — Migration 011: Domain Consistency & Payment Authority Hardening
-- TASK-2.4A.1: Hardening Pass on Domain Model, Payment Authority & Idempotency
-- ============================================================================
-- 
-- KEY ARCHITECTURAL PRINCIPLES:
-- 1. Advance Feature Default: profiles.advance_confirmation_enabled defaults to false.
--    Opt-in only for sellers; default advance amount remains 25000 paisa (₹250), 30-day hold max.
-- 2. Payment Authority Boundary: Payment confirmation belongs to the trusted backend / payment
--    verification service. Drop confirm_order_advance (seller self-assertion).
--    Establish record_verified_payment() executable ONLY by service_role.
-- 3. Payment Ledger & Idempotency: Unique partial index on order_payments(reference_id)
--    where status = 'verified'. Direct write operations on order_payments revoked from authenticated.
-- 4. State Machine & Lifecycle Hardening: Block illegal transitions (e.g. cancelled/expired -> paid).
--    Enforce strict fulfillment prerequisites (ready_to_ship and shipped strictly require paid & balance = 0).
-- 5. Checkout Reservation Hold: Initial unpaid reservation hold is 15 minutes.
--    Hold is extended up to configured hold days (max 30 days) ONLY upon verified advance payment.
-- ============================================================================

-- ============================================================================
-- 1. SELLER ADVANCE FEATURE DEFAULT SEMANTICS
-- ============================================================================

-- Newly created sellers must have advance confirmation DISABLED by default (opt-in).
ALTER TABLE profiles 
ALTER COLUMN advance_confirmation_enabled SET DEFAULT false;

-- ============================================================================
-- 2. PAYMENT LEDGER HARDENING & IDEMPOTENCY (TABLE: order_payments)
-- ============================================================================

-- 2.1 Enforce partial uniqueness on verified payment references to prevent double-crediting
CREATE UNIQUE INDEX IF NOT EXISTS uq_order_payments_reference_verified 
ON order_payments(reference_id) 
WHERE reference_id IS NOT NULL AND status = 'verified';

-- 2.2 Strict Table Permissions: Revoke direct writes from ordinary clients
REVOKE ALL ON order_payments FROM PUBLIC;
REVOKE INSERT, UPDATE, DELETE ON order_payments FROM authenticated;
GRANT SELECT ON order_payments TO anon, authenticated;
GRANT ALL ON order_payments TO service_role;

-- ============================================================================
-- 3. STATE INVARIANTS & CONSTRAINTS HARDENING (TABLE: orders)
-- ============================================================================

-- 3.1 Fulfilment strictly requires payment_status = 'paid' and balance_due_paisa = 0
ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_shipment_requires_full_payment;
ALTER TABLE orders ADD CONSTRAINT chk_orders_shipment_requires_full_payment
    CHECK (fulfilment_status = 'not_ready' OR (payment_status = 'paid' AND balance_due_paisa = 0));

-- 3.2 Confirmed state strictly represents verified advance payment
ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_confirmed_lifecycle;
ALTER TABLE orders ADD CONSTRAINT chk_orders_confirmed_lifecycle
    CHECK (
        status != 'confirmed' OR (
            confirmation_mode = 'advance' 
            AND payment_status = 'advance_paid' 
            AND advance_paid_paisa = advance_required_paisa 
            AND total_paid_paisa = advance_required_paisa 
            AND fulfilment_status = 'not_ready'
        )
    );

-- 3.3 Paid lifecycle constraint: status = 'paid' requires payment_status = 'paid', total_paid = total, balance = 0
ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_paid_lifecycle;
ALTER TABLE orders ADD CONSTRAINT chk_orders_paid_lifecycle
    CHECK (
        status != 'paid' OR (
            payment_status = 'paid' 
            AND balance_due_paisa = 0 
            AND total_paid_paisa = total_paisa
        )
    );

-- 3.4 Invariant: advance mode with positive total requires advance_required_paisa > 0
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_adv_req_positive') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_adv_req_positive
            CHECK (confirmation_mode != 'advance' OR total_paisa = 0 OR advance_required_paisa > 0);
    END IF;
END $$;

-- ============================================================================
-- 4. RPC HARDENING & REFACTORING
-- ============================================================================

-- 4.1 Remove obsolete confirm_order_advance RPC (seller cannot self-assert customer payment)
DROP FUNCTION IF EXISTS confirm_order_advance(UUID, TEXT);

-- 4.2 Create Trusted Backend Payment Transition RPC: record_verified_payment()
-- Granted EXCLUSIVELY to service_role (backend webhook / verification worker).
CREATE OR REPLACE FUNCTION record_verified_payment(
    p_order_id UUID,
    p_payment_type TEXT,
    p_amount_paisa INT,
    p_reference_id TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_seller profiles%ROWTYPE;
    v_hold_days INT;
    v_expected_balance INT;
    v_contested_count INT;
BEGIN
    -- 1. Input parameter validation
    IF p_order_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_PARAMETER', 'message', 'Order ID cannot be null.');
    END IF;

    IF p_payment_type NOT IN ('advance', 'balance', 'full') THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_PAYMENT_TYPE', 'message', 'Payment type must be advance, balance, or full.');
    END IF;

    IF p_amount_paisa IS NULL OR p_amount_paisa <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT', 'message', 'Payment amount must be greater than zero.');
    END IF;

    -- 2. Lock target order row FOR UPDATE
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND', 'message', 'Order does not exist.');
    END IF;

    -- 3. Reference Idempotency Check
    IF p_reference_id IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM order_payments 
            WHERE reference_id = p_reference_id AND status = 'verified'
        ) THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'message', 'Payment reference has already been verified and recorded.'
            );
        END IF;
    END IF;

    -- 4. Order Terminal State Guard: Expired or Cancelled orders CANNOT receive payments
    IF v_order.status IN ('cancelled', 'expired') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in terminal state "%s" and cannot receive payments.', v_order.status)
        );
    END IF;

    -- 5. Branch by Payment Type
    IF p_payment_type = 'advance' THEN
        IF v_order.confirmation_mode != 'advance' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_OPERATION',
                'message', 'Advance payments are only valid for orders with confirmation_mode = advance.'
            );
        END IF;

        -- Idempotency check: already confirmed with advance paid
        IF v_order.status IN ('confirmed', 'paid', 'shipped') AND v_order.advance_paid_paisa >= v_order.advance_required_paisa THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'message', 'Advance payment has already been credited to this order.'
            );
        END IF;

        IF v_order.status != 'pending' OR v_order.payment_status != 'unpaid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', format('Order is in status "%s" with payment_status "%s" and cannot accept advance payment.', v_order.status, v_order.payment_status)
            );
        END IF;

        -- Strict amount check against snapshotted advance requirement
        IF p_amount_paisa != v_order.advance_required_paisa THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'AMOUNT_MISMATCH',
                'message', format('Provided amount %s does not match required advance %s.', p_amount_paisa, v_order.advance_required_paisa)
            );
        END IF;

        -- Resolve hold duration (Drop override > Seller profile default, platform cap 30 days)
        SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;
        SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;
        v_hold_days := COALESCE(v_drop.hold_duration_days, v_seller.hold_duration_days, 30);
        IF v_hold_days < 1 OR v_hold_days > 30 THEN
            v_hold_days := 30;
        END IF;

        -- Atomically update order to confirmed state and extend hold duration
        UPDATE orders
        SET status = 'confirmed',
            payment_status = 'advance_paid',
            advance_paid_paisa = v_order.advance_required_paisa,
            total_paid_paisa = v_order.advance_required_paisa,
            balance_due_paisa = v_order.total_paisa - v_order.advance_required_paisa,
            advance_paid_at = NOW(),
            hold_expires_at = NOW() + (v_hold_days || ' days')::interval,
            updated_at = NOW()
        WHERE id = p_order_id;

        -- Record immutable payment ledger entry
        INSERT INTO order_payments (
            order_id, payment_type, amount_paisa, status, reference_id, metadata, verified_at
        ) VALUES (
            p_order_id, 'advance', v_order.advance_required_paisa, 'verified', p_reference_id, p_metadata, NOW()
        );

        RETURN jsonb_build_object(
            'success', true,
            'order_id', p_order_id,
            'payment_type', 'advance',
            'amount_paisa', v_order.advance_required_paisa,
            'status', 'confirmed',
            'payment_status', 'advance_paid'
        );

    ELSIF p_payment_type = 'balance' THEN
        IF v_order.confirmation_mode != 'advance' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_OPERATION',
                'message', 'Balance payments are only valid for orders with confirmation_mode = advance.'
            );
        END IF;

        -- Idempotency check: already fully paid
        IF v_order.status IN ('paid', 'shipped') AND v_order.balance_due_paisa = 0 THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'message', 'Order balance has already been settled.'
            );
        END IF;

        IF v_order.status != 'confirmed' OR v_order.payment_status != 'advance_paid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', format('Order is in status "%s" with payment_status "%s" and cannot accept balance payment.', v_order.status, v_order.payment_status)
            );
        END IF;

        v_expected_balance := v_order.total_paisa - v_order.advance_paid_paisa;
        IF p_amount_paisa != v_expected_balance THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'AMOUNT_MISMATCH',
                'message', format('Provided amount %s does not match balance due %s.', p_amount_paisa, v_expected_balance)
            );
        END IF;

        -- Deterministic product locking in ascending UUID order
        PERFORM id FROM products
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
        ORDER BY id ASC
        FOR UPDATE;

        -- Assert products were not reclaimed
        SELECT COUNT(*) INTO v_contested_count
        FROM products p
        JOIN order_items oi ON oi.product_id = p.id
        WHERE oi.order_id = p_order_id
          AND (p.status = 'sold' OR (p.status = 'reserved' AND p.reserved_by_order_id != p_order_id));

        IF v_contested_count > 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'PRODUCT_ALREADY_RECLAIMED',
                'message', 'One or more items in this order were claimed by another buyer after hold expired.'
            );
        END IF;

        -- Transition products to sold
        UPDATE products
        SET status = 'sold',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);

        -- Transition order to paid (zero balance, ready_to_ship)
        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = v_order.total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'ready_to_ship',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = p_order_id;

        -- Record immutable payment ledger entry
        INSERT INTO order_payments (
            order_id, payment_type, amount_paisa, status, reference_id, metadata, verified_at
        ) VALUES (
            p_order_id, 'balance', v_expected_balance, 'verified', p_reference_id, p_metadata, NOW()
        );

        RETURN jsonb_build_object(
            'success', true,
            'order_id', p_order_id,
            'payment_type', 'balance',
            'amount_paisa', v_expected_balance,
            'status', 'paid',
            'payment_status', 'paid',
            'fulfilment_status', 'ready_to_ship'
        );

    ELSIF p_payment_type = 'full' THEN
        IF v_order.confirmation_mode != 'full_payment' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_OPERATION',
                'message', 'Full payments are only valid for orders with confirmation_mode = full_payment.'
            );
        END IF;

        -- Idempotency check: already paid
        IF v_order.status IN ('paid', 'shipped') AND v_order.payment_status = 'paid' THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'message', 'Order is already fully paid.'
            );
        END IF;

        IF v_order.status != 'pending' OR v_order.payment_status != 'unpaid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', format('Order is in status "%s" with payment_status "%s" and cannot accept full payment.', v_order.status, v_order.payment_status)
            );
        END IF;

        IF p_amount_paisa != v_order.total_paisa THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'AMOUNT_MISMATCH',
                'message', format('Provided amount %s does not match order total %s.', p_amount_paisa, v_order.total_paisa)
            );
        END IF;

        -- Deterministic product locking in ascending UUID order
        PERFORM id FROM products
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
        ORDER BY id ASC
        FOR UPDATE;

        -- Assert products were not reclaimed
        SELECT COUNT(*) INTO v_contested_count
        FROM products p
        JOIN order_items oi ON oi.product_id = p.id
        WHERE oi.order_id = p_order_id
          AND (p.status = 'sold' OR (p.status = 'reserved' AND p.reserved_by_order_id != p_order_id));

        IF v_contested_count > 0 THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'PRODUCT_ALREADY_RECLAIMED',
                'message', 'One or more items in this order were claimed by another buyer after hold expired.'
            );
        END IF;

        -- Transition products to sold
        UPDATE products
        SET status = 'sold',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);

        -- Transition order to paid (zero balance, ready_to_ship)
        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = v_order.total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'ready_to_ship',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = p_order_id;

        -- Record immutable payment ledger entry
        INSERT INTO order_payments (
            order_id, payment_type, amount_paisa, status, reference_id, metadata, verified_at
        ) VALUES (
            p_order_id, 'full', v_order.total_paisa, 'verified', p_reference_id, p_metadata, NOW()
        );

        RETURN jsonb_build_object(
            'success', true,
            'order_id', p_order_id,
            'payment_type', 'full',
            'amount_paisa', v_order.total_paisa,
            'status', 'paid',
            'payment_status', 'paid',
            'fulfilment_status', 'ready_to_ship'
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 4.3 Permissions on record_verified_payment
REVOKE ALL ON FUNCTION record_verified_payment(UUID, TEXT, INT, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION record_verified_payment(UUID, TEXT, INT, TEXT, JSONB) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION record_verified_payment(UUID, TEXT, INT, TEXT, JSONB) TO service_role;

-- 4.4 Hardened mark_order_paid() — service_role ONLY (F-01 Audit Remediation)
-- TRUST BOUNDARY: This RPC is restricted to service_role only, consistent with
-- record_verified_payment. Sellers cannot self-assert payment without gateway verification.
-- The backend payment verification service calls this after confirming payment with the provider.
DROP FUNCTION IF EXISTS mark_order_paid(UUID);
CREATE OR REPLACE FUNCTION mark_order_paid(
    p_order_id UUID,
    p_reference_id TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb
) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_contested_count INT;
    v_pay_amount INT;
    v_pay_type TEXT;
BEGIN
    -- 1. Input validation
    IF p_order_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_PARAMETER', 'message', 'Order ID cannot be null.');
    END IF;

    -- 2. Lock target order row FOR UPDATE
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
    END IF;

    -- 3. Reference Idempotency Check
    IF p_reference_id IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM order_payments
            WHERE reference_id = p_reference_id AND status = 'verified'
        ) THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'message', 'Payment reference has already been verified and recorded.'
            );
        END IF;
    END IF;

    -- 4. Idempotency check: already fully paid
    IF v_order.status IN ('paid', 'shipped') THEN
        RETURN jsonb_build_object('success', true, 'idempotent', true);
    END IF;

    -- 5. SECURITY HARDENING: Strictly reject cancelled or expired orders
    IF v_order.status NOT IN ('pending', 'confirmed') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in state "%s" and cannot be marked paid.', v_order.status)
        );
    END IF;

    -- 6. Lock target products in deterministic ascending UUID order
    PERFORM id FROM products
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
    ORDER BY id ASC
    FOR UPDATE;

    -- 7. Check for contested items
    SELECT COUNT(*) INTO v_contested_count
    FROM products p
    JOIN order_items oi ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id
      AND (p.status = 'sold' OR (p.status = 'reserved' AND p.reserved_by_order_id != p_order_id));

    IF v_contested_count > 0 THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'PRODUCT_ALREADY_RECLAIMED',
            'message', 'One or more items in this order were claimed by another buyer after the hold expired.'
        );
    END IF;

    -- 8. Determine payment type and amount to record in payments table
    IF v_order.confirmation_mode = 'advance' AND v_order.advance_paid_paisa > 0 THEN
        v_pay_type := 'balance';
        v_pay_amount := v_order.total_paisa - v_order.advance_paid_paisa;
    ELSE
        v_pay_type := 'full';
        v_pay_amount := v_order.total_paisa;
    END IF;

    -- 9. Transition products to sold
    UPDATE products
    SET status = 'sold',
        reserved_at = NULL,
        reserved_by_order_id = NULL,
        version = version + 1,
        updated_at = NOW()
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);

    -- 10. Transition order to paid (balance = 0, ready_to_ship)
    UPDATE orders
    SET status = 'paid',
        payment_status = 'paid',
        total_paid_paisa = v_order.total_paisa,
        balance_due_paisa = 0,
        fulfilment_status = 'ready_to_ship',
        paid_at = NOW(),
        updated_at = NOW()
    WHERE id = p_order_id;

    -- 11. Log payment record with reference for audit trail
    IF v_pay_amount > 0 THEN
        INSERT INTO order_payments (
            order_id, payment_type, amount_paisa, status, reference_id, metadata, verified_at
        ) VALUES (
            p_order_id, v_pay_type, v_pay_amount, 'verified', p_reference_id, p_metadata, NOW()
        );
    END IF;

    RETURN jsonb_build_object('success', true, 'order_id', p_order_id, 'payment_type', v_pay_type, 'amount_paisa', v_pay_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- TRUST BOUNDARY: mark_order_paid is service_role ONLY (F-01 Audit Remediation)
REVOKE ALL ON FUNCTION mark_order_paid(UUID, TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_order_paid(UUID, TEXT, JSONB) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_order_paid(UUID, TEXT, JSONB) TO service_role;

-- 4.5 Hardened create_order_with_reservation()
-- Fallback advance_enabled = false; initial checkout reservation hold = 15 minutes.
CREATE OR REPLACE FUNCTION create_order_with_reservation(
    p_drop_id UUID,
    p_product_ids UUID[],
    p_buyer_name TEXT,
    p_buyer_phone TEXT,
    p_shipping_address TEXT,
    p_pincode TEXT,
    p_confirmation_mode TEXT DEFAULT 'advance'
) RETURNS JSONB AS $$
DECLARE
    v_clean_name TEXT;
    v_clean_phone TEXT;
    v_clean_address TEXT;
    v_clean_pincode TEXT;
    v_confirmation_mode TEXT;
    v_clean_product_ids UUID[];
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
    v_random_suffix TEXT;
BEGIN
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
    SELECT coalesce(array_agg(DISTINCT pid), '{}') INTO v_clean_product_ids
    FROM unnest(p_product_ids) AS pid
    WHERE pid IS NOT NULL;

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

    IF v_seller.free_shipping_threshold_paisa IS NOT NULL 
       AND v_subtotal_paisa >= v_seller.free_shipping_threshold_paisa THEN
        v_shipping_paisa := 0;
    ELSE
        v_shipping_paisa := COALESCE(v_drop.shipping_fee_paisa, v_seller.default_shipping_fee_paisa, 8000);
    END IF;

    v_total_paisa := v_subtotal_paisa + v_shipping_paisa;

    -- 11. Resolve Seller Advance & Hold Policy (Drop override > Seller profile default)
    -- DOMAIN HARDENING: Defaults to false if neither drop nor seller explicitly enabled it.
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

        -- Initial checkout reservation hold: 15 minutes to pay advance.
        -- Hold extends up to 30 days only upon verified advance payment.
        v_hold_expires_at := NOW() + INTERVAL '15 minutes';
    ELSE
        -- Full payment mode: 15 minutes checkout reservation
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

    -- 13. Insert Order Record with Snapshotted Financial Model
    INSERT INTO orders (
        drop_id, order_code, order_token, buyer_name, buyer_phone,
        shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa,
        confirmation_mode, advance_required_paisa, advance_paid_paisa,
        total_paid_paisa, balance_due_paisa, payment_status, fulfilment_status,
        status, hold_expires_at
    ) VALUES (
        p_drop_id, v_order_code, v_order_token, v_clean_name, v_clean_phone,
        v_clean_address, v_clean_pincode, v_subtotal_paisa, v_shipping_paisa, v_total_paisa,
        v_confirmation_mode, v_advance_required_paisa, 0,
        0, v_total_paisa, 'unpaid', 'not_ready',
        'pending', v_hold_expires_at
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

REVOKE ALL ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
