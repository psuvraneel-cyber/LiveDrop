-- LiveDrop Migration: 015_fulfillment_idempotency_and_rejection_release.sql
-- Description: SPRINT 1 (P0) — Fulfillment RPC (mark_order_shipped), Order Request Idempotency, and Immediate Rejection Inventory Release.
-- Standards: ADR-009 (Strict Integer Paisa), Migration 012 Defense-in-Depth (Triggers Intact)
-- Security: SECURITY DEFINER with pinned search_path = public, pg_temp

-- ============================================================================
-- 1. SCHEMA ENHANCEMENTS (TABLE: orders)
-- ============================================================================

-- 1.1 Add idempotency_key for safe mobile network retries
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

-- 1.2 Add notes for shipping and operational context
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS notes TEXT;

-- 1.3 Unique partial index to enforce per-drop idempotency key uniqueness
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_drop_idempotency 
ON orders(drop_id, idempotency_key) 
WHERE idempotency_key IS NOT NULL;


-- ============================================================================
-- 2. UPDATED RPC: create_order_with_reservation() WITH IDEMPOTENCY KEY SUPPORT
-- ============================================================================

DROP FUNCTION IF EXISTS create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION create_order_with_reservation(
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
BEGIN
    -- 0. Check Idempotency Token
    v_clean_idempotency := trim(COALESCE(p_idempotency_key, ''));
    IF v_clean_idempotency <> '' THEN
        SELECT * INTO v_existing_order 
        FROM orders 
        WHERE drop_id = p_drop_id AND idempotency_key = v_clean_idempotency;

        IF FOUND THEN
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

REVOKE ALL ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;


-- ============================================================================
-- 3. NEW RPC: mark_order_shipped()
-- ============================================================================

CREATE OR REPLACE FUNCTION mark_order_shipped(
    p_order_id UUID,
    p_tracking_number TEXT,
    p_courier_partner TEXT,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_clean_tracking TEXT;
    v_clean_courier TEXT;
    v_clean_notes TEXT;
BEGIN
    -- 1. Authentication Check
    IF current_user <> 'service_role' AND auth.uid() IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to mark an order as shipped.'
        );
    END IF;

    -- 2. Fetch and Lock Order
    SELECT * INTO v_order
    FROM orders
    WHERE id = p_order_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'Order not found.'
        );
    END IF;

    -- 3. Verify Seller Ownership via Drop
    SELECT * INTO v_drop
    FROM drops
    WHERE id = v_order.drop_id;

    IF NOT FOUND OR (current_user <> 'service_role' AND v_drop.seller_id <> auth.uid()) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'FORBIDDEN',
            'message', 'You are not authorized to fulfill orders for this drop.'
        );
    END IF;

    -- 4. Check Order State & Financial Prerequisites
    IF v_order.payment_status <> 'paid' OR v_order.balance_due_paisa > 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_PAID',
            'message', 'Order cannot be shipped until payment is fully settled.'
        );
    END IF;

    IF v_order.status = 'shipped' OR v_order.fulfilment_status = 'shipped' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ALREADY_SHIPPED',
            'message', 'Order has already been marked as shipped.'
        );
    END IF;

    IF v_order.status NOT IN ('paid', 'confirmed') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order status "%s" cannot transition to shipped.', v_order.status)
        );
    END IF;

    -- 5. Validate Tracking Number and Courier Partner
    v_clean_tracking := trim(COALESCE(p_tracking_number, ''));
    v_clean_courier := trim(COALESCE(p_courier_partner, ''));
    v_clean_notes := trim(COALESCE(p_notes, ''));

    IF v_clean_tracking = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_TRACKING_NUMBER',
            'message', 'Tracking number is required to mark an order as shipped.'
        );
    END IF;

    IF v_clean_courier = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_COURIER_PARTNER',
            'message', 'Courier partner name is required.'
        );
    END IF;

    -- 6. Mutate Order State to Shipped
    UPDATE orders
    SET status = 'shipped',
        fulfilment_status = 'shipped',
        shipped_at = NOW(),
        tracking_number = v_clean_tracking,
        courier_partner = v_clean_courier,
        notes = CASE WHEN v_clean_notes <> '' THEN v_clean_notes ELSE notes END,
        updated_at = NOW()
    WHERE id = v_order.id
    RETURNING * INTO v_order;

    -- 7. Return Receipt
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'status', v_order.status,
        'fulfilment_status', v_order.fulfilment_status,
        'shipped_at', v_order.shipped_at,
        'tracking_number', v_order.tracking_number,
        'courier_partner', v_order.courier_partner,
        'notes', v_order.notes
    );
END;
$$;

REVOKE ALL ON FUNCTION mark_order_shipped(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_order_shipped(UUID, TEXT, TEXT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION mark_order_shipped(UUID, TEXT, TEXT, TEXT) TO authenticated, service_role;


-- ============================================================================
-- 4. UPDATED RPC: reject_manual_upi_payment() WITH INSTANT INVENTORY RELEASE
-- ============================================================================

DROP FUNCTION IF EXISTS reject_manual_upi_payment(UUID, TEXT);
DROP FUNCTION IF EXISTS reject_manual_upi_payment(UUID, TEXT, BOOLEAN);

CREATE OR REPLACE FUNCTION reject_manual_upi_payment(
    p_payment_attempt_id UUID,
    p_rejection_reason TEXT DEFAULT 'payment_not_found',
    p_release_hold BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_attempt RECORD;
    v_order RECORD;
    v_drop RECORD;
    v_reason TEXT;
BEGIN
    -- 1. Fetch Payment Attempt
    SELECT * INTO v_attempt 
    FROM payment_attempts 
    WHERE id = p_payment_attempt_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt does not exist.'
        );
    END IF;

    -- 2. Fetch Order & Drop for Ownership Verification
    SELECT * INTO v_order FROM orders WHERE id = v_attempt.order_id FOR UPDATE;
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;

    IF current_user <> 'service_role' AND (auth.uid() IS NULL OR auth.uid() <> v_drop.seller_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Only the drop-owning seller can reject this payment claim.'
        );
    END IF;

    IF v_attempt.status = 'verified' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'CANNOT_REJECT_VERIFIED',
            'message', 'A verified payment attempt cannot be rejected.'
        );
    END IF;

    v_reason := trim(COALESCE(p_rejection_reason, 'payment_not_found'));

    -- 3. Mark Attempt as Rejected
    UPDATE payment_attempts
    SET status = 'rejected',
        rejection_reason = v_reason,
        updated_at = NOW()
    WHERE id = v_attempt.id;

    -- 4. Immediate Inventory Release (Fix for 24-hour orphaned hold bug)
    IF p_release_hold AND v_order.status = 'pending' AND v_order.payment_status = 'unpaid' THEN
        -- Lock and unlock reserved products
        PERFORM id FROM products
        WHERE reserved_by_order_id = v_order.id AND status = 'reserved'
        ORDER BY id ASC
        FOR UPDATE;

        UPDATE products
        SET status = 'available',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE reserved_by_order_id = v_order.id AND status = 'reserved';

        -- Cancel order and expire hold immediately
        UPDATE orders
        SET status = 'cancelled',
            hold_expires_at = NOW(),
            updated_at = NOW()
        WHERE id = v_order.id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'payment_attempt_id', v_attempt.id,
        'status', 'rejected',
        'rejection_reason', v_reason,
        'hold_released', (p_release_hold AND v_order.status = 'pending' AND v_order.payment_status = 'unpaid')
    );
END;
$$;

REVOKE ALL ON FUNCTION reject_manual_upi_payment(UUID, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION reject_manual_upi_payment(UUID, TEXT, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION reject_manual_upi_payment(UUID, TEXT, BOOLEAN) TO authenticated, service_role;


-- ============================================================================
-- 5. UPDATED RPC: get_order_by_token() WITH DISPATCH & TRACKING METADATA
-- ============================================================================

CREATE OR REPLACE FUNCTION get_order_by_token(
    p_order_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_drop RECORD;
    v_seller RECORD;
    v_items JSONB;
    v_active_attempt RECORD;
    v_upi_uri TEXT;
    v_attempt_json JSONB;
BEGIN
    -- 1. Locate order by order_token
    SELECT * INTO v_order FROM orders WHERE order_token::text = p_order_token;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'No active order found for the provided token.'
        );
    END IF;

    -- 2. Fetch drop and seller profiles
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 3. Fetch aggregated line items
    SELECT jsonb_agg(
        jsonb_build_object(
            'product_id', oi.product_id,
            'code', p.code,
            'title', p.title,
            'image_url', p.image_url,
            'price_at_purchase_paisa', oi.price_at_purchase_paisa
        ) ORDER BY p.code ASC
    ) INTO v_items
    FROM order_items oi
    JOIN products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id;

    -- 4. Fetch latest active payment attempt
    SELECT * INTO v_active_attempt
    FROM payment_attempts
    WHERE order_id = v_order.id
    ORDER BY created_at DESC
    LIMIT 1;

    IF FOUND THEN
        v_upi_uri := generate_upi_payment_uri(
            v_active_attempt.payee_vpa_snapshot,
            v_active_attempt.payee_display_name_snapshot,
            v_active_attempt.expected_amount_paisa,
            v_active_attempt.transaction_reference,
            'LiveDrop ' || v_order.order_code
        );

        v_attempt_json := jsonb_build_object(
            'id', v_active_attempt.id,
            'payment_type', v_active_attempt.payment_type,
            'payment_method', v_active_attempt.payment_method,
            'expected_amount_paisa', v_active_attempt.expected_amount_paisa,
            'payee_vpa', v_active_attempt.payee_vpa_snapshot,
            'payee_display_name', v_active_attempt.payee_display_name_snapshot,
            'payee_vpa_snapshot', v_active_attempt.payee_vpa_snapshot,
            'payee_display_name_snapshot', v_active_attempt.payee_display_name_snapshot,
            'transaction_reference', v_active_attempt.transaction_reference,
            'status', v_active_attempt.status,
            'buyer_submitted_utr', v_active_attempt.buyer_submitted_utr,
            'buyer_claimed_at', v_active_attempt.buyer_claimed_at,
            'seller_verified_at', v_active_attempt.seller_verified_at,
            'rejection_reason', v_active_attempt.rejection_reason,
            'verification_expires_at', v_active_attempt.verification_expires_at,
            'expires_at', v_active_attempt.expires_at,
            'created_at', v_active_attempt.created_at,
            'updated_at', v_active_attempt.updated_at,
            'upi_uri', v_upi_uri
        );
    ELSE
        v_attempt_json := NULL;
        IF COALESCE(v_seller.upi_vpa, v_seller.upi_id) IS NOT NULL THEN
            v_upi_uri := generate_upi_payment_uri(
                COALESCE(v_seller.upi_vpa, v_seller.upi_id),
                COALESCE(v_seller.upi_display_name, v_seller.store_name, 'LiveDrop Seller'),
                CASE WHEN v_order.confirmation_mode = 'advance' THEN v_order.advance_required_paisa ELSE v_order.total_paisa END,
                v_order.order_code,
                'LiveDrop ' || v_order.order_code
            );
        END IF;
    END IF;

    -- 5. Construct Authoritative Receipt Payload with fulfillment & tracking metadata
    RETURN jsonb_build_object(
        'success', true,
        'order', jsonb_build_object(
            'id', v_order.id,
            'order_code', v_order.order_code,
            'buyer_name', v_order.buyer_name,
            'subtotal_paisa', v_order.subtotal_paisa,
            'shipping_paisa', v_order.shipping_paisa,
            'total_paisa', v_order.total_paisa,
            'confirmation_mode', v_order.confirmation_mode,
            'advance_required_paisa', v_order.advance_required_paisa,
            'advance_paid_paisa', v_order.advance_paid_paisa,
            'total_paid_paisa', v_order.total_paid_paisa,
            'balance_due_paisa', v_order.balance_due_paisa,
            'payment_status', v_order.payment_status,
            'fulfilment_status', v_order.fulfilment_status,
            'status', v_order.status,
            'hold_expires_at', v_order.hold_expires_at,
            'shipped_at', v_order.shipped_at,
            'tracking_number', v_order.tracking_number,
            'courier_partner', v_order.courier_partner,
            'notes', v_order.notes,
            'store_name', v_seller.store_name,
            'store_slug', v_seller.store_slug,
            'upi_id', COALESCE(v_seller.upi_vpa, v_seller.upi_id),
            'upi_enabled', v_seller.upi_enabled,
            'upi_qr_url', v_seller.upi_qr_url,
            'upi_uri', v_upi_uri,
            'items', COALESCE(v_items, '[]'::jsonb),
            'payment_attempt', v_attempt_json,
            'active_payment_attempt', v_attempt_json
        )
    );
END;
$$;

-- 2-parameter overload: get_order_by_token(UUID, UUID)
CREATE OR REPLACE FUNCTION get_order_by_token(
    p_order_id UUID,
    p_order_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_res JSONB;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND order_token = p_order_token) THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    v_res := get_order_by_token(p_order_token::text);
    RETURN v_res;
END;
$$;

-- 2-parameter overload: get_order_by_token(UUID, TEXT)
CREATE OR REPLACE FUNCTION get_order_by_token(
    p_order_id UUID,
    p_order_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_res JSONB;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND order_token::text = p_order_token) THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    v_res := get_order_by_token(p_order_token);
    RETURN v_res;
END;
$$;

REVOKE ALL ON FUNCTION get_order_by_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_order_by_token(TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION get_order_by_token(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_order_by_token(UUID, UUID) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION get_order_by_token(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_order_by_token(UUID, TEXT) TO anon, authenticated, service_role;
