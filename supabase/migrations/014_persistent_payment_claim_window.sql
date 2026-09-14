-- LiveDrop Migration: 014_persistent_payment_claim_window.sql
-- Description: TASK-2.4C Persistent Payment Claims, Independent Verification Window & Resume-Safe Buyer UX
-- Standards: ADR-009 (Strict Integer Paisa), Migration 012 Defense-in-Depth (Triggers Intact)
-- Security: SECURITY DEFINER with pinned search_path = public, pg_temp

-- ============================================================================
-- 1. SCHEMA ENHANCEMENTS (TABLE: payment_attempts)
-- ============================================================================

-- Add verification_expires_at column to payment_attempts
ALTER TABLE payment_attempts
ADD COLUMN IF NOT EXISTS verification_expires_at TIMESTAMPTZ;

-- Index for efficient expiration queries
CREATE INDEX IF NOT EXISTS idx_payment_attempts_verification_expires
ON payment_attempts(verification_expires_at)
WHERE status = 'awaiting_seller_verification';

-- ============================================================================
-- 2. UPDATE: submit_buyer_payment_claim() WITH 24-HOUR VERIFICATION WINDOW & ATOMIC HOLD EXTENSION
-- ============================================================================

CREATE OR REPLACE FUNCTION submit_buyer_payment_claim(
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

    -- 2. Reject Terminal Orders
    IF v_order.status IN ('cancelled', 'expired') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in terminal state "%s" and cannot accept payment claims.', v_order.status)
        );
    END IF;

    -- 3. Validate UTR Syntax (alphanumeric 6–35 chars)
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

    -- 4. Fetch and Lock Payment Attempt
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

    -- Idempotency Check: Same attempt + same UTR returns idempotent success without resetting deadline
    IF v_attempt.status = 'awaiting_seller_verification' AND v_attempt.buyer_submitted_utr = v_clean_utr THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'payment_attempt_id', v_attempt.id,
            'attempt_id', v_attempt.id,
            'order_id', v_order.id,
            'status', 'awaiting_seller_verification',
            'buyer_submitted_utr', v_clean_utr,
            'buyer_claimed_at', v_attempt.buyer_claimed_at,
            'verification_expires_at', v_attempt.verification_expires_at,
            'expires_at', v_attempt.expires_at,
            'message', 'Payment claim already submitted with this UTR.'
        );
    END IF;

    -- Check if attempt expired before claim submission
    IF v_attempt.status = 'expired' OR v_attempt.expires_at <= NOW() THEN
        UPDATE payment_attempts SET status = 'expired', updated_at = NOW() WHERE id = v_attempt.id;
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_EXPIRED',
            'message', 'Payment attempt has expired.'
        );
    END IF;

    -- 5. Calculate Authoritative 24-Hour Verification Deadline
    -- The verification deadline is strictly server-authoritative (attempt_claimed_at + 24 hours)
    v_verification_expires_at := NOW() + INTERVAL '24 hours';

    -- 6. Atomically Record Buyer Claim on Payment Attempt
    UPDATE payment_attempts
    SET buyer_submitted_utr = v_clean_utr,
        buyer_claimed_at = NOW(),
        status = 'awaiting_seller_verification',
        verification_expires_at = v_verification_expires_at,
        expires_at = v_verification_expires_at,
        updated_at = NOW()
    WHERE id = v_attempt.id;

    -- 7. Atomically Extend Order Reservation Hold to Match Verification Deadline
    -- This guarantees the product is not reclaimed by the reaper at the initial 15-minute mark
    UPDATE orders
    SET hold_expires_at = v_verification_expires_at,
        updated_at = NOW()
    WHERE id = v_order.id;

    -- Financial invariants strictly preserved:
    -- orders.payment_status remains 'unpaid'
    -- orders.total_paid_paisa remains 0
    -- orders.advance_paid_paisa remains 0
    -- orders.balance_due_paisa remains total_paisa
    -- No insert into order_payments
    -- Product status remains 'reserved'

    RETURN jsonb_build_object(
        'success', true,
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

-- 3-parameter overload: submit_buyer_payment_claim(payment_attempt_id, order_token, utr)
CREATE OR REPLACE FUNCTION submit_buyer_payment_claim(
    p_payment_attempt_id UUID,
    p_order_token TEXT,
    p_utr TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id UUID;
BEGIN
    SELECT order_id INTO v_order_id FROM payment_attempts WHERE id = p_payment_attempt_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt not found.'
        );
    END IF;
    RETURN submit_buyer_payment_claim(v_order_id, p_order_token, p_payment_attempt_id, p_utr);
END;
$$;

-- ============================================================================
-- 3. UPDATE: verify_manual_upi_payment() WITH EXPLICIT DEADLINE CHECK
-- ============================================================================

CREATE OR REPLACE FUNCTION verify_manual_upi_payment(
    p_payment_attempt_id UUID,
    p_utr TEXT DEFAULT NULL
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
    v_seller RECORD;
    v_clean_utr TEXT;
    v_verified_ref TEXT;
    v_existing_order_id UUID;
    v_hold_days INT;
    v_hold_expires_at TIMESTAMPTZ;
    v_payment_id UUID;
BEGIN
    -- 1. Fetch & Lock Payment Attempt
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

    -- 2. Fetch Order & Drop to Verify Seller Ownership
    SELECT orders.* INTO v_order 
    FROM orders 
    WHERE id = v_attempt.order_id 
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'Associated order not found.'
        );
    END IF;

    SELECT drops.* INTO v_drop FROM drops WHERE id = v_order.drop_id;

    -- 3. Authorization Check: Drop-owning seller or service_role
    IF current_user <> 'service_role' AND (auth.uid() IS NULL OR auth.uid() <> v_drop.seller_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Only the drop-owning seller or trusted backend service can verify this payment.'
        );
    END IF;

    -- 4. Terminal Order Guard
    IF v_order.status IN ('cancelled', 'expired') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in terminal state "%s" and cannot be verified.', v_order.status)
        );
    END IF;

    -- 5. Expiry Check on Payment Attempt / Verification Window
    IF v_attempt.status = 'expired' 
       OR (v_attempt.verification_expires_at IS NOT NULL AND v_attempt.verification_expires_at <= NOW())
       OR (v_attempt.expires_at <= NOW()) THEN
        UPDATE payment_attempts SET status = 'expired', updated_at = NOW() WHERE id = v_attempt.id;
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_EXPIRED',
            'message', 'Payment verification window has expired.'
        );
    END IF;

    -- 6. Idempotency on Attempt
    IF v_attempt.status = 'verified' THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'message', 'Payment attempt has already been verified.',
            'order_id', v_order.id,
            'order_status', v_order.status,
            'payment_status', v_order.payment_status
        );
    END IF;

    -- 7. Resolve Authoritative Reference / UTR
    v_clean_utr := trim(COALESCE(p_utr, v_attempt.buyer_submitted_utr, ''));
    v_verified_ref := COALESCE(NULLIF(v_clean_utr, ''), v_attempt.transaction_reference);

    -- 8. Cross-Order Idempotency / Reference Reuse Protection
    SELECT order_id INTO v_existing_order_id
    FROM order_payments
    WHERE reference_id = v_verified_ref AND status = 'verified';

    IF FOUND THEN
        IF v_existing_order_id = v_order.id THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'message', 'Payment reference already verified for this order.'
            );
        ELSE
            RETURN jsonb_build_object(
                'success', false,
                'error', 'REFERENCE_USED_ON_ANOTHER_ORDER',
                'message', 'This payment reference or UTR has already been verified on another order.'
            );
        END IF;
    END IF;

    -- 9. Atomic Transition by Payment Type
    SELECT profiles.* INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    IF v_attempt.payment_type = 'advance' THEN
        IF v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', 'Order is not in pending unpaid state for advance verification.'
            );
        END IF;

        -- Resolve Hold Extension for Advance (seller configured post-advance hold, capped at 30 days)
        v_hold_days := COALESCE(v_drop.hold_duration_days, v_seller.hold_duration_days, 30);
        IF v_hold_days < 1 OR v_hold_days > 30 THEN
            v_hold_days := 30; -- Hard platform cap <= 30 days
        END IF;
        v_hold_expires_at := NOW() + (v_hold_days || ' days')::interval;

        -- Insert Verified Payment Ledger Row
        INSERT INTO order_payments (
            order_id,
            payment_type,
            payment_method,
            verification_method,
            amount_paisa,
            status,
            reference_id,
            verified_at,
            verified_by,
            metadata
        ) VALUES (
            v_order.id,
            'advance',
            'upi',
            'seller_manual',
            v_attempt.expected_amount_paisa,
            'verified',
            v_verified_ref,
            NOW(),
            auth.uid(),
            jsonb_build_object(
                'payment_attempt_id', v_attempt.id,
                'verified_by', auth.uid(),
                'verified_at', NOW()
            )
        )
        RETURNING id INTO v_payment_id;

        -- Mutate Order State
        UPDATE orders
        SET status = 'confirmed',
            payment_status = 'advance_paid',
            advance_paid_paisa = v_attempt.expected_amount_paisa,
            total_paid_paisa = v_attempt.expected_amount_paisa,
            balance_due_paisa = total_paisa - v_attempt.expected_amount_paisa,
            advance_paid_at = NOW(),
            hold_expires_at = v_hold_expires_at,
            updated_at = NOW()
        WHERE id = v_order.id;

    ELSIF v_attempt.payment_type = 'balance' THEN
        IF v_order.status <> 'confirmed' OR v_order.payment_status <> 'advance_paid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', 'Balance payment requires an order in confirmed advance_paid state.'
            );
        END IF;

        -- Insert Verified Payment Ledger Row
        INSERT INTO order_payments (
            order_id,
            payment_type,
            payment_method,
            verification_method,
            amount_paisa,
            status,
            reference_id,
            verified_at,
            verified_by,
            metadata
        ) VALUES (
            v_order.id,
            'balance',
            'upi',
            'seller_manual',
            v_attempt.expected_amount_paisa,
            'verified',
            v_verified_ref,
            NOW(),
            auth.uid(),
            jsonb_build_object(
                'payment_attempt_id', v_attempt.id,
                'verified_by', auth.uid(),
                'verified_at', NOW()
            )
        )
        RETURNING id INTO v_payment_id;

        -- Mutate Order State
        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'ready_to_ship',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = v_order.id;

        -- Transition Reserved Products to Sold
        UPDATE products
        SET status = 'sold',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id);

    ELSIF v_attempt.payment_type = 'full' THEN
        IF v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', 'Full payment requires an order in pending unpaid state.'
            );
        END IF;

        -- Insert Verified Payment Ledger Row
        INSERT INTO order_payments (
            order_id,
            payment_type,
            payment_method,
            verification_method,
            amount_paisa,
            status,
            reference_id,
            verified_at,
            verified_by,
            metadata
        ) VALUES (
            v_order.id,
            'full',
            'upi',
            'seller_manual',
            v_attempt.expected_amount_paisa,
            'verified',
            v_verified_ref,
            NOW(),
            auth.uid(),
            jsonb_build_object(
                'payment_attempt_id', v_attempt.id,
                'verified_by', auth.uid(),
                'verified_at', NOW()
            )
        )
        RETURNING id INTO v_payment_id;

        -- Mutate Order State
        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'ready_to_ship',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = v_order.id;

        -- Transition Reserved Products to Sold
        UPDATE products
        SET status = 'sold',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id);
    END IF;

    -- 10. Mark Payment Attempt as Verified
    UPDATE payment_attempts
    SET status = 'verified',
        seller_verified_at = NOW(),
        verified_by = auth.uid(),
        buyer_submitted_utr = COALESCE(NULLIF(v_clean_utr, ''), buyer_submitted_utr),
        updated_at = NOW()
    WHERE id = v_attempt.id;

    RETURN jsonb_build_object(
        'success', true,
        'payment_attempt_id', v_attempt.id,
        'attempt_id', v_attempt.id,
        'payment_id', v_payment_id,
        'order_id', v_order.id,
        'payment_type', v_attempt.payment_type,
        'amount_paisa', v_attempt.expected_amount_paisa,
        'status', (SELECT status FROM orders WHERE id = v_order.id),
        'payment_status', (SELECT payment_status FROM orders WHERE id = v_order.id),
        'fulfilment_status', (SELECT fulfilment_status FROM orders WHERE id = v_order.id),
        'total_paid_paisa', (SELECT total_paid_paisa FROM orders WHERE id = v_order.id),
        'balance_due_paisa', (SELECT balance_due_paisa FROM orders WHERE id = v_order.id),
        'advance_paid_paisa', (SELECT advance_paid_paisa FROM orders WHERE id = v_order.id)
    );
END;
$$;

-- ============================================================================
-- 4. UPDATE: release_expired_holds() REAPER HARDENING
-- ============================================================================

CREATE OR REPLACE FUNCTION release_expired_holds()
RETURNS VOID AS $$
DECLARE
    v_expired_order RECORD;
BEGIN
    FOR v_expired_order IN
        SELECT id, status, confirmation_mode, advance_paid_paisa FROM orders
        WHERE status IN ('pending', 'confirmed') AND hold_expires_at < clock_timestamp()
        ORDER BY id ASC
        FOR UPDATE SKIP LOCKED
    LOOP
        -- Lock products for this expired order deterministically
        PERFORM id FROM products
        WHERE reserved_by_order_id = v_expired_order.id
        ORDER BY id ASC
        FOR UPDATE;

        -- Release associated products back to 'available'
        UPDATE products
        SET status = 'available',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE reserved_by_order_id = v_expired_order.id
          AND status = 'reserved';

        -- Transition any active payment attempts to 'expired'
        UPDATE payment_attempts
        SET status = 'expired',
            updated_at = NOW()
        WHERE order_id = v_expired_order.id
          AND status IN ('created', 'awaiting_payment', 'awaiting_seller_verification');

        -- If order was advance-confirmed, advance is retained as non-refundable and order is marked 'expired'
        IF v_expired_order.status = 'confirmed' THEN
            UPDATE orders
            SET status = 'expired',
                fulfilment_status = 'not_ready',
                updated_at = NOW()
            WHERE id = v_expired_order.id;
        ELSE
            -- Initial pending order with unpaid hold simply cancels
            UPDATE orders
            SET status = 'cancelled',
                fulfilment_status = 'not_ready',
                updated_at = NOW()
            WHERE id = v_expired_order.id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 5. UPDATE: get_order_by_token() WITH VERIFICATION EXPIRES AT & ALIASING
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

    -- 5. Construct Authoritative Receipt Payload (both payment_attempt and active_payment_attempt returned)
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

-- 2-parameter overload: get_order_by_token(UUID, UUID) for legacy compatibility
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
    -- Verify both order_id and order_token match
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

-- ============================================================================
-- 6. ROUTINE PRIVILEGES & SECURITY HARDENING
-- ============================================================================

REVOKE ALL ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION verify_manual_upi_payment(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION verify_manual_upi_payment(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION verify_manual_upi_payment(UUID, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION release_expired_holds() FROM PUBLIC;
REVOKE ALL ON FUNCTION release_expired_holds() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION release_expired_holds() TO service_role;

REVOKE ALL ON FUNCTION get_order_by_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_order_by_token(TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION get_order_by_token(UUID, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_order_by_token(UUID, UUID) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION get_order_by_token(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_order_by_token(UUID, TEXT) TO anon, authenticated, service_role;
