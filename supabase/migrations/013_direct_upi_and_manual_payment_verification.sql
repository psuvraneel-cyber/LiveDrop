-- LiveDrop Migration: 013_direct_upi_and_manual_payment_verification.sql
-- Description: TASK-2.4B Direct Peer-to-Peer UPI Payment & Manual Seller Verification
-- Standards: ADR-009 (Strict Integer Paisa), Migration 012 Defense-in-Depth (Triggers Intact)
-- Security: SECURITY DEFINER with pinned search_path = public, pg_temp

-- ============================================================================
-- 1. SELLER PROFILES UPI CONFIGURATION (TABLE: profiles)
-- ============================================================================

-- 1.1 UPI Feature Flag & Configuration Fields
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS upi_enabled BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS upi_vpa TEXT;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS upi_display_name TEXT;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS payment_instructions TEXT;

-- 1.2 Backfill upi_vpa from existing upi_id
UPDATE profiles SET upi_vpa = upi_id WHERE upi_vpa IS NULL AND upi_id IS NOT NULL;

-- 1.3 Format Constraint on upi_vpa
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS chk_profiles_upi_vpa;
ALTER TABLE profiles ADD CONSTRAINT chk_profiles_upi_vpa
    CHECK (upi_vpa IS NULL OR upi_vpa ~ '^[a-zA-Z0-9.\-_]{2,255}@[a-zA-Z]{2,64}$');

-- 1.4 Synchronization Trigger: Keep upi_id and upi_vpa identical for zero regression
CREATE OR REPLACE FUNCTION sync_profiles_upi_fields()
RETURNS TRIGGER 
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.upi_vpa IS NOT NULL AND (OLD.upi_vpa IS NULL OR NEW.upi_vpa <> OLD.upi_vpa) THEN
        NEW.upi_id := NEW.upi_vpa;
    ELSIF NEW.upi_id IS NOT NULL AND (OLD.upi_id IS NULL OR NEW.upi_id <> OLD.upi_id) THEN
        NEW.upi_vpa := NEW.upi_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_profiles_upi_fields ON profiles;
CREATE TRIGGER trg_sync_profiles_upi_fields
    BEFORE INSERT OR UPDATE OF upi_id, upi_vpa ON profiles
    FOR EACH ROW EXECUTE FUNCTION sync_profiles_upi_fields();

-- ============================================================================
-- 1.5 PAYMENT LEDGER ENHANCEMENTS (TABLE: order_payments)
-- ============================================================================

ALTER TABLE order_payments 
ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'upi' 
CHECK (payment_method IN ('upi', 'card', 'netbanking', 'wallet'));

ALTER TABLE order_payments 
ADD COLUMN IF NOT EXISTS verification_method TEXT NOT NULL DEFAULT 'seller_manual' 
CHECK (verification_method IN ('seller_manual', 'provider_webhook', 'system'));

-- ============================================================================
-- 2. PAYMENT ATTEMPTS TABLE (TABLE: payment_attempts)
-- ============================================================================

CREATE TABLE IF NOT EXISTS payment_attempts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    payment_type TEXT NOT NULL CHECK (payment_type IN ('advance', 'balance', 'full')),
    payment_method TEXT NOT NULL DEFAULT 'upi' CHECK (payment_method = 'upi'),
    expected_amount_paisa INT NOT NULL CHECK (expected_amount_paisa > 0),
    payee_vpa_snapshot TEXT NOT NULL CHECK (payee_vpa_snapshot ~ '^[a-zA-Z0-9.\-_]{2,255}@[a-zA-Z]{2,64}$'),
    payee_display_name_snapshot TEXT,
    transaction_reference TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'awaiting_payment', 'buyer_claimed', 'awaiting_seller_verification', 'verified', 'rejected', 'expired')),
    buyer_claimed_at TIMESTAMPTZ,
    buyer_submitted_utr TEXT CHECK (buyer_submitted_utr IS NULL OR (char_length(buyer_submitted_utr) BETWEEN 6 AND 35 AND buyer_submitted_utr ~ '^[a-zA-Z0-9_\-]+$')),
    seller_verified_at TIMESTAMPTZ,
    verified_by UUID REFERENCES auth.users(id),
    rejection_reason TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for performance & idempotency
CREATE INDEX IF NOT EXISTS idx_payment_attempts_order_id ON payment_attempts(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_attempts_status ON payment_attempts(status);
CREATE INDEX IF NOT EXISTS idx_payment_attempts_reference ON payment_attempts(transaction_reference);
CREATE INDEX IF NOT EXISTS idx_payment_attempts_utr ON payment_attempts(buyer_submitted_utr) WHERE buyer_submitted_utr IS NOT NULL;

-- Automatic updated_at trigger
DROP TRIGGER IF EXISTS trg_payment_attempts_updated_at ON payment_attempts;
CREATE TRIGGER trg_payment_attempts_updated_at
    BEFORE UPDATE ON payment_attempts
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- 3. ROW-LEVEL SECURITY ON PAYMENT ATTEMPTS
-- ============================================================================

ALTER TABLE payment_attempts ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON payment_attempts FROM PUBLIC;
REVOKE ALL ON payment_attempts FROM anon;
REVOKE ALL ON payment_attempts FROM authenticated;

GRANT SELECT ON payment_attempts TO anon;
GRANT SELECT ON payment_attempts TO authenticated;
GRANT ALL ON payment_attempts TO service_role;

-- 3.1 Seller Select: Authenticated sellers can read payment attempts for orders in their drops
DROP POLICY IF EXISTS payment_attempts_seller_select ON payment_attempts;
CREATE POLICY payment_attempts_seller_select ON payment_attempts
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders
            JOIN drops ON drops.id = orders.drop_id
            WHERE orders.id = payment_attempts.order_id
              AND drops.seller_id = auth.uid()
        )
    );

-- 3.2 Buyer Select with Token: Anonymous buyers can read payment attempts matching their order token
DROP POLICY IF EXISTS payment_attempts_buyer_select_with_token ON payment_attempts;
CREATE POLICY payment_attempts_buyer_select_with_token ON payment_attempts
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = payment_attempts.order_id
              AND orders.order_token::text = COALESCE(
                  current_setting('request.headers', true)::jsonb ->> 'x-order-token',
                  ''
              )
        )
    );

-- Direct mutation (INSERT/UPDATE/DELETE) remains strictly blocked for anon and authenticated clients.
-- All state transitions must occur through controlled RPCs.

-- ============================================================================
-- 4. UPI URI GENERATION HELPER
-- ============================================================================

CREATE OR REPLACE FUNCTION generate_upi_payment_uri(
    p_vpa TEXT,
    p_name TEXT,
    p_amount_paisa INT,
    p_reference TEXT,
    p_note TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT 'upi://pay?pa=' || p_vpa
        || '&pn=' || replace(replace(replace(COALESCE(p_name, 'LiveDrop Seller'), ' ', '%20'), '&', '%26'), '=', '%3D')
        || '&am=' || trim(to_char(p_amount_paisa / 100.0, 'FM999999990.00'))
        || '&cu=INR'
        || '&tr=' || p_reference
        || '&tn=' || replace(replace(replace(COALESCE(p_note, 'LiveDrop Order'), ' ', '%20'), '&', '%26'), '=', '%3D');
$$;

-- ============================================================================
-- 5. RPC: initiate_payment_attempt()
-- ============================================================================

CREATE OR REPLACE FUNCTION initiate_payment_attempt(
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
-- 6. RPC: submit_buyer_payment_claim()
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
BEGIN
    -- 1. Validate Order & Token
    SELECT * INTO v_order 
    FROM orders 
    WHERE id = p_order_id AND order_token::text = p_order_token;

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

    -- 3. Validate UTR Syntax
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

    IF v_attempt.status = 'awaiting_seller_verification' AND v_attempt.buyer_submitted_utr = v_clean_utr THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'payment_attempt_id', v_attempt.id,
            'attempt_id', v_attempt.id,
            'status', 'awaiting_seller_verification',
            'buyer_submitted_utr', v_clean_utr,
            'message', 'Payment claim already submitted with this UTR.'
        );
    END IF;

    IF v_attempt.status = 'expired' OR v_attempt.expires_at <= NOW() THEN
        UPDATE payment_attempts SET status = 'expired', updated_at = NOW() WHERE id = v_attempt.id;
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_EXPIRED',
            'message', 'Payment attempt has expired.'
        );
    END IF;

    -- 5. Record Buyer Claim without Mutating Financial State
    UPDATE payment_attempts
    SET buyer_submitted_utr = v_clean_utr,
        buyer_claimed_at = NOW(),
        status = 'awaiting_seller_verification',
        updated_at = NOW()
    WHERE id = v_attempt.id;

    RETURN jsonb_build_object(
        'success', true,
        'payment_attempt_id', v_attempt.id,
        'attempt_id', v_attempt.id,
        'status', 'awaiting_seller_verification',
        'buyer_submitted_utr', v_clean_utr,
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
-- 7. RPC: verify_manual_upi_payment()
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

    -- 5. Idempotency on Attempt
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

    -- 6. Resolve Authoritative Reference / UTR
    v_clean_utr := trim(COALESCE(p_utr, v_attempt.buyer_submitted_utr, ''));
    v_verified_ref := COALESCE(NULLIF(v_clean_utr, ''), v_attempt.transaction_reference);

    -- 7. Cross-Order Idempotency / Reference Reuse Protection
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

    -- 8. Atomic Transition by Payment Type
    SELECT profiles.* INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    IF v_attempt.payment_type = 'advance' THEN
        IF v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', 'Order is not in pending unpaid state for advance verification.'
            );
        END IF;

        -- Resolve Hold Extension for Advance
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

    -- 9. Mark Payment Attempt as Verified
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
-- 8. RPC: reject_manual_upi_payment()
-- ============================================================================

CREATE OR REPLACE FUNCTION reject_manual_upi_payment(
    p_payment_attempt_id UUID,
    p_rejection_reason TEXT
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
    SELECT orders.* INTO v_order FROM orders WHERE id = v_attempt.order_id;
    SELECT drops.* INTO v_drop FROM drops WHERE id = v_order.drop_id;

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

    UPDATE payment_attempts
    SET status = 'rejected',
        rejection_reason = v_reason,
        updated_at = NOW()
    WHERE id = v_attempt.id;

    RETURN jsonb_build_object(
        'success', true,
        'payment_attempt_id', v_attempt.id,
        'status', 'rejected',
        'rejection_reason', v_reason
    );
END;
$$;

-- ============================================================================
-- 9. PATCH: record_verified_payment() CROSS-ORDER IDEMPOTENCY FIX
-- ============================================================================

DROP FUNCTION IF EXISTS record_verified_payment(UUID, TEXT, INT, TEXT);
DROP FUNCTION IF EXISTS record_verified_payment(UUID, TEXT, INT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION record_verified_payment(
    p_order_id UUID,
    p_payment_type TEXT,
    p_amount_paisa INT,
    p_reference_id TEXT DEFAULT NULL,
    p_metadata JSONB DEFAULT '{}'::jsonb,
    p_payment_method TEXT DEFAULT 'upi'
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
    v_payment_id UUID;
    v_existing_order_id UUID;
    v_hold_days INT;
    v_hold_expires_at TIMESTAMPTZ;
    v_expected_balance INT;
    v_contested_count INT;
BEGIN
    -- 1. Validate input parameters
    IF p_order_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_PARAMETER', 'message', 'Order ID cannot be null.');
    END IF;

    IF p_payment_type NOT IN ('advance', 'balance', 'full') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_PAYMENT_TYPE',
            'message', 'Payment type must be advance, balance, or full.'
        );
    END IF;

    IF p_amount_paisa IS NULL OR p_amount_paisa <= 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_AMOUNT', 'message', 'Payment amount must be greater than zero.');
    END IF;

    -- 2. Lock target order row FOR UPDATE
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND', 'message', 'Order does not exist.');
    END IF;

    -- 3. Cross-Order & Same-Order Reference Idempotency Check
    IF p_reference_id IS NOT NULL THEN
        SELECT order_id INTO v_existing_order_id
        FROM order_payments 
        WHERE reference_id = p_reference_id AND status = 'verified';

        IF FOUND THEN
            IF v_existing_order_id = p_order_id THEN
                RETURN jsonb_build_object(
                    'success', true,
                    'idempotent', true,
                    'message', 'Payment reference has already been verified and recorded.'
                );
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'error', 'REFERENCE_USED_ON_ANOTHER_ORDER',
                    'message', 'This payment reference has already been verified on another order.'
                );
            END IF;
        END IF;
    END IF;

    -- 4. Order Terminal State Guard
    IF v_order.status IN ('cancelled', 'expired') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in terminal state "%s" and cannot receive payments.', v_order.status)
        );
    END IF;

    -- 5. Fetch Drop & Seller Configuration
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 6. Branch: Advance Payment Verification
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
                'message', format('Cannot record advance for order in state "%s" with payment_status "%s".', v_order.status, v_order.payment_status)
            );
        END IF;

        IF p_amount_paisa != v_order.advance_required_paisa THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'AMOUNT_MISMATCH',
                'message', format('Provided amount %s does not match required advance %s.', p_amount_paisa, v_order.advance_required_paisa)
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
            amount_paisa,
            payment_method,
            status,
            reference_id,
            metadata
        ) VALUES (
            p_order_id,
            'advance',
            p_amount_paisa,
            COALESCE(p_payment_method, 'upi'),
            'verified',
            p_reference_id,
            COALESCE(p_metadata, '{}'::jsonb)
        ) RETURNING id INTO v_payment_id;

        UPDATE orders
        SET status = 'confirmed',
            payment_status = 'advance_paid',
            advance_paid_paisa = p_amount_paisa,
            total_paid_paisa = p_amount_paisa,
            balance_due_paisa = v_order.total_paisa - p_amount_paisa,
            advance_paid_at = NOW(),
            hold_expires_at = v_hold_expires_at,
            updated_at = NOW()
        WHERE id = p_order_id;

        RETURN jsonb_build_object(
            'success', true,
            'payment_id', v_payment_id,
            'order_id', p_order_id,
            'payment_type', 'advance',
            'amount_paisa', p_amount_paisa,
            'status', 'confirmed',
            'payment_status', 'advance_paid',
            'hold_expires_at', v_hold_expires_at
        );

    -- 7. Branch: Balance Payment Verification
    ELSIF p_payment_type = 'balance' THEN
        IF v_order.confirmation_mode != 'advance' THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_OPERATION',
                'message', 'Balance payments are only valid for orders with confirmation_mode = advance.'
            );
        END IF;

        -- Idempotency check: already fully settled
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
                'message', format('Cannot record balance for order in state "%s" with payment_status "%s".', v_order.status, v_order.payment_status)
            );
        END IF;

        v_expected_balance := v_order.total_paisa - v_order.advance_paid_paisa;
        IF p_amount_paisa != v_expected_balance THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'AMOUNT_MISMATCH',
                'message', format('Provided amount %s does not match outstanding balance %s.', p_amount_paisa, v_expected_balance)
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

        INSERT INTO order_payments (
            order_id,
            payment_type,
            amount_paisa,
            payment_method,
            status,
            reference_id,
            metadata
        ) VALUES (
            p_order_id,
            'balance',
            p_amount_paisa,
            COALESCE(p_payment_method, 'upi'),
            'verified',
            p_reference_id,
            COALESCE(p_metadata, '{}'::jsonb)
        ) RETURNING id INTO v_payment_id;

        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = v_order.total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'ready_to_ship',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = p_order_id;

        RETURN jsonb_build_object(
            'success', true,
            'payment_id', v_payment_id,
            'order_id', p_order_id,
            'payment_type', 'balance',
            'amount_paisa', p_amount_paisa,
            'status', 'paid',
            'payment_status', 'paid',
            'fulfilment_status', 'ready_to_ship'
        );

    -- 8. Branch: Full Payment Verification
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
                'message', format('Cannot record full payment for order in state "%s" with payment_status "%s".', v_order.status, v_order.payment_status)
            );
        END IF;

        IF p_amount_paisa != v_order.total_paisa THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'AMOUNT_MISMATCH',
                'message', format('Provided amount %s does not match total amount %s.', p_amount_paisa, v_order.total_paisa)
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

        INSERT INTO order_payments (
            order_id,
            payment_type,
            amount_paisa,
            payment_method,
            status,
            reference_id,
            metadata
        ) VALUES (
            p_order_id,
            'full',
            p_amount_paisa,
            COALESCE(p_payment_method, 'upi'),
            'verified',
            p_reference_id,
            COALESCE(p_metadata, '{}'::jsonb)
        ) RETURNING id INTO v_payment_id;

        UPDATE orders
        SET status = 'paid',
            payment_status = 'paid',
            total_paid_paisa = v_order.total_paisa,
            balance_due_paisa = 0,
            fulfilment_status = 'ready_to_ship',
            paid_at = NOW(),
            updated_at = NOW()
        WHERE id = p_order_id;

        RETURN jsonb_build_object(
            'success', true,
            'payment_id', v_payment_id,
            'order_id', p_order_id,
            'payment_type', 'full',
            'amount_paisa', p_amount_paisa,
            'status', 'paid',
            'payment_status', 'paid',
            'fulfilment_status', 'ready_to_ship'
        );
    END IF;
END;
$$;

-- ============================================================================
-- 10. UPDATE: get_order_by_token() WITH PAYMENT ATTEMPTS
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
        )
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
    ELSE
        -- Fallback: generate default UPI URI for active order before attempt is created
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

    -- 5. Construct Authoritative Receipt Payload
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
            'payment_attempt', CASE 
                WHEN v_active_attempt.id IS NOT NULL THEN jsonb_build_object(
                    'id', v_active_attempt.id,
                    'payment_type', v_active_attempt.payment_type,
                    'expected_amount_paisa', v_active_attempt.expected_amount_paisa,
                    'payee_vpa', v_active_attempt.payee_vpa_snapshot,
                    'payee_display_name', v_active_attempt.payee_display_name_snapshot,
                    'transaction_reference', v_active_attempt.transaction_reference,
                    'status', v_active_attempt.status,
                    'buyer_submitted_utr', v_active_attempt.buyer_submitted_utr,
                    'expires_at', v_active_attempt.expires_at,
                    'upi_uri', v_upi_uri
                )
                ELSE NULL
            END
        )
    );
END;
$$;

-- ============================================================================
-- 11. ROUTINE PRIVILEGES & SECURITY HARDENING
-- ============================================================================

-- initiate_payment_attempt: Public for zero-account buyers holding token
REVOKE ALL ON FUNCTION initiate_payment_attempt(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION initiate_payment_attempt(UUID, TEXT, TEXT) TO anon, authenticated, service_role;

-- submit_buyer_payment_claim: Public for buyers submitting UTR (both 4-param and 3-param overloads)
REVOKE ALL ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, UUID, TEXT) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION submit_buyer_payment_claim(UUID, TEXT, TEXT) TO anon, authenticated, service_role;

-- verify_manual_upi_payment: Authenticated sellers & service_role only (Revoked from anon & PUBLIC)
REVOKE ALL ON FUNCTION verify_manual_upi_payment(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION verify_manual_upi_payment(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION verify_manual_upi_payment(UUID, TEXT) TO authenticated, service_role;

-- reject_manual_upi_payment: Authenticated sellers & service_role only (Revoked from anon & PUBLIC)
REVOKE ALL ON FUNCTION reject_manual_upi_payment(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION reject_manual_upi_payment(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION reject_manual_upi_payment(UUID, TEXT) TO authenticated, service_role;

-- generate_upi_payment_uri: Helper
REVOKE ALL ON FUNCTION generate_upi_payment_uri(TEXT, TEXT, INT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION generate_upi_payment_uri(TEXT, TEXT, INT, TEXT, TEXT) TO anon, authenticated, service_role;

-- get_order_by_token: Public token-gated
REVOKE ALL ON FUNCTION get_order_by_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_order_by_token(TEXT) TO anon, authenticated, service_role;

-- record_verified_payment: service_role only (Maintained from 011)
REVOKE ALL ON FUNCTION record_verified_payment(UUID, TEXT, INT, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION record_verified_payment(UUID, TEXT, INT, TEXT, JSONB, TEXT) FROM anon;
REVOKE ALL ON FUNCTION record_verified_payment(UUID, TEXT, INT, TEXT, JSONB, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION record_verified_payment(UUID, TEXT, INT, TEXT, JSONB, TEXT) TO service_role;
