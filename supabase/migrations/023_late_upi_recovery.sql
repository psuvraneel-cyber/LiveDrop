-- LiveDrop Migration: 023_late_upi_recovery.sql
-- Description: BLOCKER 1E — Late UPI Payment Recovery & Manual Boutique Review.
-- Security: SECURITY DEFINER with pinned search_path = public, pg_temp

-- ============================================================================
-- 1. UPDATE CHECK CONSTRAINT ON payment_attempts.status
-- ============================================================================

ALTER TABLE payment_attempts DROP CONSTRAINT IF EXISTS payment_attempts_status_check;
ALTER TABLE payment_attempts ADD CONSTRAINT payment_attempts_status_check
CHECK (status IN (
    'created',
    'awaiting_payment',
    'buyer_claimed',
    'awaiting_seller_verification',
    'late_claim_pending_review',
    'verified',
    'rejected',
    'expired'
));

-- Index for late claims review queue
CREATE INDEX IF NOT EXISTS idx_payment_attempts_late_claims
ON payment_attempts(status, buyer_claimed_at)
WHERE status = 'late_claim_pending_review';

-- ============================================================================
-- 2. UPDATED RPC: submit_buyer_payment_claim() WITH LATE CLAIM CAPTURE
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

    -- 2. Validate UTR Syntax (alphanumeric 6–35 chars)
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
    -- Instead of discarding buyer money with an error, record claim in late_claim_pending_review
    -- Do NOT auto-reclaim inventory; manual review is required.
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

    -- 6. Normal Flow: Calculate Authoritative 24-Hour Verification Deadline
    v_verification_expires_at := NOW() + INTERVAL '24 hours';

    -- 7. Atomically Record Buyer Claim on Payment Attempt
    UPDATE payment_attempts
    SET buyer_submitted_utr = v_clean_utr,
        buyer_claimed_at = NOW(),
        status = 'awaiting_seller_verification',
        verification_expires_at = v_verification_expires_at,
        expires_at = v_verification_expires_at,
        updated_at = NOW()
    WHERE id = v_attempt.id;

    -- 8. Atomically Extend Order Reservation Hold to Match Verification Deadline
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

-- 3-parameter overload
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

REVOKE ALL ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, TEXT) TO anon, authenticated, service_role;

-- ============================================================================
-- 3. UPDATED RPC: verify_manual_upi_payment() WITH LATE CLAIM & NOT_READY SUPPORT
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
    v_is_late_claim BOOLEAN := FALSE;
    v_all_available BOOLEAN := TRUE;
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

    -- 4. Idempotency on Attempt
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

    -- 5. Determine if this is a late claim
    v_is_late_claim := (v_attempt.status = 'late_claim_pending_review');

    -- 6. Terminal Order Guard & Expiry Check (for non-late claims)
    IF NOT v_is_late_claim THEN
        IF v_order.status IN ('cancelled', 'expired') THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', format('Order is in terminal state "%s" and cannot be verified.', v_order.status)
            );
        END IF;

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
    END IF;

    -- 7. Resolve Authoritative Reference / UTR
    v_clean_utr := trim(COALESCE(p_utr, v_attempt.buyer_submitted_utr, ''));
    v_verified_ref := COALESCE(NULLIF(v_clean_utr, ''), v_attempt.transaction_reference);

    -- 8. Cross-Order Idempotency / Reference Reuse Protection
    IF v_verified_ref IS NOT NULL THEN
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
    END IF;

    SELECT profiles.* INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 9. Handle Late Claims vs Standard Payment Types
    IF v_is_late_claim THEN
        -- Check if all items in order are still available
        SELECT COALESCE(bool_and(p.status = 'available'), true) INTO v_all_available
        FROM order_items oi
        JOIN products p ON p.id = oi.product_id
        WHERE oi.order_id = v_order.id;

        IF v_all_available THEN
            -- Re-reserve and transition products to sold
            PERFORM id FROM products
            WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id)
            ORDER BY id ASC
            FOR UPDATE;

            UPDATE products
            SET status = 'sold',
                reserved_at = NULL,
                reserved_by_order_id = NULL,
                version = version + 1,
                updated_at = NOW()
            WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id);

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
                v_attempt.payment_type,
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
                    'verified_at', NOW(),
                    'is_late_claim', true,
                    'inventory_reinstated', true
                )
            )
            RETURNING id INTO v_payment_id;

            -- Restore order to paid & not_ready (awaiting packaging)
            UPDATE orders
            SET status = 'paid',
                payment_status = 'paid',
                total_paid_paisa = total_paisa,
                balance_due_paisa = 0,
                fulfilment_status = 'not_ready',
                paid_at = NOW(),
                updated_at = NOW()
            WHERE id = v_order.id;

            UPDATE payment_attempts
            SET status = 'verified',
                seller_verified_at = NOW(),
                verified_by = auth.uid(),
                buyer_submitted_utr = COALESCE(NULLIF(v_clean_utr, ''), buyer_submitted_utr),
                updated_at = NOW()
            WHERE id = v_attempt.id;

            RETURN jsonb_build_object(
                'success', true,
                'is_late_claim', true,
                'inventory_available', true,
                'payment_attempt_id', v_attempt.id,
                'attempt_id', v_attempt.id,
                'payment_id', v_payment_id,
                'order_id', v_order.id,
                'payment_type', v_attempt.payment_type,
                'amount_paisa', v_attempt.expected_amount_paisa,
                'status', 'paid',
                'payment_status', 'paid',
                'fulfilment_status', 'not_ready',
                'total_paid_paisa', v_order.total_paisa,
                'balance_due_paisa', 0,
                'message', 'Late payment verified and inventory successfully secured for order.'
            );
        ELSE
            -- Items are no longer available. Record verified payment but keep order cancelled/expired with note
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
                v_attempt.payment_type,
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
                    'verified_at', NOW(),
                    'is_late_claim', true,
                    'inventory_reinstated', false,
                    'refund_required', true
                )
            )
            RETURNING id INTO v_payment_id;

            UPDATE payment_attempts
            SET status = 'verified',
                seller_verified_at = NOW(),
                verified_by = auth.uid(),
                buyer_submitted_utr = COALESCE(NULLIF(v_clean_utr, ''), buyer_submitted_utr),
                updated_at = NOW()
            WHERE id = v_attempt.id;

            UPDATE orders
            SET payment_status = 'paid',
                total_paid_paisa = v_attempt.expected_amount_paisa,
                balance_due_paisa = 0,
                notes = COALESCE(notes || E'\n', '') || 'LATE_CLAIM_PAYMENT_VERIFIED: Inventory was already reallocated. Refund or boutique resolution required.',
                updated_at = NOW()
            WHERE id = v_order.id;

            RETURN jsonb_build_object(
                'success', true,
                'is_late_claim', true,
                'inventory_available', false,
                'refund_required', true,
                'payment_attempt_id', v_attempt.id,
                'attempt_id', v_attempt.id,
                'payment_id', v_payment_id,
                'order_id', v_order.id,
                'payment_type', v_attempt.payment_type,
                'amount_paisa', v_attempt.expected_amount_paisa,
                'status', v_order.status,
                'payment_status', 'paid',
                'fulfilment_status', v_order.fulfilment_status,
                'total_paid_paisa', v_attempt.expected_amount_paisa,
                'balance_due_paisa', 0,
                'message', 'Late payment verified, but items are no longer available. Seller refund or resolution required.'
            );
        END IF;

    ELSIF v_attempt.payment_type = 'advance' THEN
        IF v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', 'Order is not in pending unpaid state for advance verification.'
            );
        END IF;

        v_hold_days := COALESCE(v_drop.hold_duration_days, v_seller.hold_duration_days, 30);
        IF v_hold_days < 1 OR v_hold_days > 30 THEN
            v_hold_days := 30;
        END IF;
        v_hold_expires_at := NOW() + (v_hold_days || ' days')::interval;

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

        UPDATE orders
        SET status = 'confirmed',
            payment_status = 'advance_paid',
            advance_paid_paisa = v_attempt.expected_amount_paisa,
            total_paid_paisa = v_attempt.expected_amount_paisa,
            balance_due_paisa = total_paisa - v_attempt.expected_amount_paisa,
            fulfilment_status = 'not_ready',
            advance_paid_at = NOW(),
            hold_expires_at = v_hold_expires_at,
            updated_at = NOW()
        WHERE id = v_order.id;

        UPDATE payment_attempts
        SET status = 'verified',
            seller_verified_at = NOW(),
            verified_by = auth.uid(),
            buyer_submitted_utr = COALESCE(NULLIF(v_clean_utr, ''), buyer_submitted_utr),
            updated_at = NOW()
        WHERE id = v_attempt.id;

    ELSIF v_attempt.payment_type = 'balance' THEN
        IF v_order.status <> 'confirmed' OR v_order.payment_status <> 'advance_paid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', 'Balance payment requires an order in confirmed advance_paid state.'
            );
        END IF;

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

        -- Authoritative transition: fulfilment_status is not_ready, awaiting packing
        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'not_ready',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = v_order.id;

        UPDATE products
        SET status = 'sold',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id);

        UPDATE payment_attempts
        SET status = 'verified',
            seller_verified_at = NOW(),
            verified_by = auth.uid(),
            buyer_submitted_utr = COALESCE(NULLIF(v_clean_utr, ''), buyer_submitted_utr),
            updated_at = NOW()
        WHERE id = v_attempt.id;

    ELSIF v_attempt.payment_type = 'full' THEN
        IF v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', 'Full payment requires an order in pending unpaid state.'
            );
        END IF;

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

        -- Authoritative transition: fulfilment_status is not_ready, awaiting packing
        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'not_ready',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = v_order.id;

        UPDATE products
        SET status = 'sold',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id);

        UPDATE payment_attempts
        SET status = 'verified',
            seller_verified_at = NOW(),
            verified_by = auth.uid(),
            buyer_submitted_utr = COALESCE(NULLIF(v_clean_utr, ''), buyer_submitted_utr),
            updated_at = NOW()
        WHERE id = v_attempt.id;
    END IF;

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

REVOKE ALL ON FUNCTION verify_manual_upi_payment(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION verify_manual_upi_payment(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION verify_manual_upi_payment(UUID, TEXT) TO authenticated, service_role;

