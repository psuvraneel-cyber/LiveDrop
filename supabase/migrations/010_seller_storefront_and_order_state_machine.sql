-- LiveDrop Migration: 010_seller_storefront_and_order_state_machine.sql
-- Description: Establishes multi-seller storefront identity, seller advance confirmation policies,
--              30-day maximum hold policy, multi-dimensional order state machine (lifecycle, payment,
--              fulfilment), dedicated order_payments recording table, and hardened business RPCs.
-- Parent Documentation: docs/SOURCE-OF-TRUTH.md, docs/04-technical-design.md, docs/12-database-design.md
-- Governing Rules: AGENTS.md, ADR-002, ADR-003, ADR-009, TASK-2.4A Specification

-- ============================================================================
-- 1. SELLER STOREFRONT IDENTITY & CONFIGURATION (TABLE: profiles)
-- ============================================================================

-- 1.1 Add store_slug with URL-safe format and length constraints
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS store_slug TEXT;

-- Backfill existing default seller profile with canonical storefront handle
UPDATE profiles 
SET store_slug = 'mothers-boutique' 
WHERE id = '8a329e71-4b10-4055-90d2-df8029d5b512' AND store_slug IS NULL;

-- Fallback backfill for any other profiles in development
UPDATE profiles 
SET store_slug = lower(regexp_replace(store_name, '[^a-zA-Z0-9]+', '-', 'g'))
WHERE store_slug IS NULL;

ALTER TABLE profiles ALTER COLUMN store_slug SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'uq_profiles_store_slug'
    ) THEN
        ALTER TABLE profiles ADD CONSTRAINT uq_profiles_store_slug UNIQUE (store_slug);
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'chk_profiles_store_slug'
    ) THEN
        ALTER TABLE profiles ADD CONSTRAINT chk_profiles_store_slug 
            CHECK (store_slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' AND char_length(store_slug) BETWEEN 3 AND 60);
    END IF;
END $$;

-- 1.2 Seller Advance Confirmation Configuration (Default: Enabled, ₹250.00 / 25000 Paisa, 30-Day Hold)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS advance_confirmation_enabled BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS advance_amount_paisa INT NOT NULL DEFAULT 25000 
CHECK (advance_amount_paisa > 0);

-- Hard platform cap: hold duration must be between 1 and 30 days (<= 30 days mandatory)
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS hold_duration_days INT NOT NULL DEFAULT 30 
CHECK (hold_duration_days BETWEEN 1 AND 30);

-- ============================================================================
-- 2. OPTIONAL DROP-LEVEL CONFIGURATION OVERRIDE (TABLE: drops)
-- ============================================================================

ALTER TABLE drops 
ADD COLUMN IF NOT EXISTS advance_confirmation_enabled BOOLEAN;

ALTER TABLE drops 
ADD COLUMN IF NOT EXISTS advance_amount_paisa INT 
CHECK (advance_amount_paisa IS NULL OR advance_amount_paisa > 0);

ALTER TABLE drops 
ADD COLUMN IF NOT EXISTS hold_duration_days INT 
CHECK (hold_duration_days IS NULL OR (hold_duration_days BETWEEN 1 AND 30));

-- ============================================================================
-- 3. ORDER STATE MACHINE & FINANCIAL SNAPSHOTS (TABLE: orders)
-- ============================================================================

-- 3.1 Confirmation mode: 'advance' or 'full_payment'
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS confirmation_mode TEXT NOT NULL DEFAULT 'advance' 
CHECK (confirmation_mode IN ('advance', 'full_payment'));

-- 3.2 Integer Paisa financial fields
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS advance_required_paisa INT NOT NULL DEFAULT 0 
CHECK (advance_required_paisa >= 0);

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS advance_paid_paisa INT NOT NULL DEFAULT 0 
CHECK (advance_paid_paisa >= 0);

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS total_paid_paisa INT NOT NULL DEFAULT 0 
CHECK (total_paid_paisa >= 0);

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS balance_due_paisa INT NOT NULL DEFAULT 0 
CHECK (balance_due_paisa >= 0);

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS advance_paid_at TIMESTAMPTZ;

-- 3.3 Orthogonal Payment and Fulfilment states
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS payment_status TEXT NOT NULL DEFAULT 'unpaid' 
CHECK (payment_status IN ('unpaid', 'advance_paid', 'paid'));

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS fulfilment_status TEXT NOT NULL DEFAULT 'not_ready' 
CHECK (fulfilment_status IN ('not_ready', 'ready_to_ship', 'shipped'));

-- 3.4 Backfill existing historical/seed orders safely
UPDATE orders 
SET confirmation_mode = 'full_payment',
    advance_required_paisa = 0,
    advance_paid_paisa = 0,
    total_paid_paisa = total_paisa,
    balance_due_paisa = 0,
    payment_status = 'paid',
    fulfilment_status = 'ready_to_ship'
WHERE status = 'paid';

UPDATE orders 
SET confirmation_mode = 'full_payment',
    advance_required_paisa = 0,
    advance_paid_paisa = 0,
    total_paid_paisa = total_paisa,
    balance_due_paisa = 0,
    payment_status = 'paid',
    fulfilment_status = 'shipped'
WHERE status = 'shipped';

UPDATE orders 
SET confirmation_mode = 'advance',
    advance_required_paisa = LEAST(25000, total_paisa),
    advance_paid_paisa = 0,
    total_paid_paisa = 0,
    balance_due_paisa = total_paisa,
    payment_status = 'unpaid',
    fulfilment_status = 'not_ready'
WHERE status IN ('pending', 'cancelled');

-- 3.5 Update status CHECK constraint to include 'confirmed' and 'expired'
DO $$
BEGIN
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
    ALTER TABLE orders DROP CONSTRAINT IF EXISTS chk_orders_status;
    ALTER TABLE orders ADD CONSTRAINT chk_orders_status 
        CHECK (status IN ('pending', 'confirmed', 'paid', 'shipped', 'cancelled', 'expired'));
END $$;

-- 3.6 Financial Invariants and Consistency Constraints
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_advance_lte_total') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_advance_lte_total
            CHECK (advance_required_paisa <= total_paisa);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_adv_paid_lte_req') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_adv_paid_lte_req
            CHECK (advance_paid_paisa <= advance_required_paisa);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_total_paid_lte_total') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_total_paid_lte_total
            CHECK (total_paid_paisa <= total_paisa);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_balance_formula') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_balance_formula
            CHECK (balance_due_paisa = total_paisa - total_paid_paisa);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_adv_paid_lte_total_paid') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_adv_paid_lte_total_paid
            CHECK (advance_paid_paisa <= total_paid_paisa);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_full_pay_zero_adv') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_full_pay_zero_adv
            CHECK (confirmation_mode != 'full_payment' OR advance_required_paisa = 0);
    END IF;

    -- CRITICAL SHIPMENT INVARIANT: Advance paid != Ready to ship.
    -- Order cannot be ready_to_ship or shipped if balance_due_paisa > 0.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_shipment_requires_full_payment') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_shipment_requires_full_payment
            CHECK (fulfilment_status = 'not_ready' OR balance_due_paisa = 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_shipped_lifecycle') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_shipped_lifecycle
            CHECK (status != 'shipped' OR (fulfilment_status = 'shipped' AND balance_due_paisa = 0));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_paid_lifecycle') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_paid_lifecycle
            CHECK (status != 'paid' OR (payment_status = 'paid' AND balance_due_paisa = 0));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_orders_confirmed_lifecycle') THEN
        ALTER TABLE orders ADD CONSTRAINT chk_orders_confirmed_lifecycle
            CHECK (status != 'confirmed' OR (confirmation_mode = 'advance' AND payment_status = 'advance_paid'));
    END IF;
END $$;

-- ============================================================================
-- 4. DEDICATED PAYMENT RECORDING TABLE (TABLE: order_payments)
-- ============================================================================

CREATE TABLE IF NOT EXISTS order_payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    payment_type TEXT NOT NULL CHECK (payment_type IN ('advance', 'balance', 'full')),
    amount_paisa INT NOT NULL CHECK (amount_paisa > 0),
    status TEXT NOT NULL CHECK (status IN ('pending', 'verified', 'failed', 'refunded')) DEFAULT 'pending',
    reference_id TEXT,
    verified_at TIMESTAMPTZ,
    verified_by UUID REFERENCES auth.users(id),
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_payments_order ON order_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_order_payments_status ON order_payments(status);

-- Enable RLS on order_payments
ALTER TABLE order_payments ENABLE ROW LEVEL SECURITY;

-- 4.1 Token-gated read: Anonymous buyers can view payment records ONLY for their token-verified order
DROP POLICY IF EXISTS order_payments_buyer_read_with_token ON order_payments;
CREATE POLICY order_payments_buyer_read_with_token ON order_payments
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_payments.order_id
              AND orders.order_token::text = (
                  CASE 
                      WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> ''
                      THEN current_setting('request.headers', true)::json->>'x-order-token'
                      ELSE NULL
                  END
              )
        )
    );

-- 4.2 Seller read: Authenticated sellers can view payment records for orders under drops they own
DROP POLICY IF EXISTS order_payments_seller_select ON order_payments;
CREATE POLICY order_payments_seller_select ON order_payments
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders
            JOIN drops ON drops.id = orders.drop_id
            WHERE orders.id = order_payments.order_id
              AND drops.seller_id = auth.uid()
        )
    );

-- Revoke all default public permissions on order_payments
REVOKE ALL ON order_payments FROM PUBLIC;
GRANT SELECT ON order_payments TO anon;
GRANT SELECT, INSERT, UPDATE ON order_payments TO authenticated;

-- Trigger: automated updated_at for order_payments
DROP TRIGGER IF EXISTS trg_order_payments_updated_at ON order_payments;
CREATE TRIGGER trg_order_payments_updated_at
BEFORE UPDATE ON order_payments
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- Update trigger function: protect confirmed and expired orders from deletion alongside paid and shipped
CREATE OR REPLACE FUNCTION prevent_finalized_order_deletion()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IN ('confirmed', 'paid', 'shipped', 'expired') THEN
        RAISE EXCEPTION 'Cannot delete finalized order % with status "%"', OLD.id, OLD.status;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 5. BUSINESS RPCS EVOLUTION
-- ============================================================================

-- 5.1 Drop existing 6-parameter create_order_with_reservation signature to replace cleanly
DROP FUNCTION IF EXISTS create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT);

-- Create new signature supporting p_confirmation_mode (default: 'advance')
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
    v_drop drops%ROWTYPE;
    v_seller profiles%ROWTYPE;
    v_clean_product_ids UUID[];
    v_locked_count INT;
    v_unavailable_ids JSONB;
    v_subtotal_paisa INT := 0;
    v_shipping_paisa INT := 0;
    v_total_paisa INT := 0;
    v_order orders%ROWTYPE;
    v_random_suffix TEXT;
    v_order_code TEXT;
    v_order_token UUID := gen_random_uuid();
    v_clean_name TEXT;
    v_clean_phone TEXT;
    v_clean_address TEXT;
    v_clean_pincode TEXT;
    v_confirmation_mode TEXT;
    v_advance_enabled BOOLEAN;
    v_advance_required_paisa INT := 0;
    v_hold_days INT := 30;
    v_hold_expires_at TIMESTAMPTZ;
BEGIN
    -- 1. Input Sanitization & Validation
    v_clean_name := trim(COALESCE(p_buyer_name, ''));
    v_clean_phone := trim(COALESCE(p_buyer_phone, ''));
    v_clean_address := trim(COALESCE(p_shipping_address, ''));
    v_clean_pincode := trim(COALESCE(p_pincode, ''));
    v_confirmation_mode := lower(trim(COALESCE(p_confirmation_mode, 'advance')));

    IF v_confirmation_mode NOT IN ('advance', 'full_payment') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_CONFIRMATION_MODE',
            'message', 'Confirmation mode must be either "advance" or "full_payment".'
        );
    END IF;

    IF char_length(v_clean_name) < 3 OR char_length(v_clean_name) > 100 THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'INVALID_BUYER_NAME', 
            'message', 'Buyer name must be between 3 and 100 characters.'
        );
    END IF;

    IF NOT (v_clean_phone ~ '^[6-9]\d{9}$' OR v_clean_phone ~ '^91[6-9]\d{9}$') THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'INVALID_BUYER_PHONE', 
            'message', 'Valid 10-digit Indian mobile number required.'
        );
    END IF;

    IF char_length(v_clean_address) < 10 OR char_length(v_clean_address) > 500 THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'INVALID_SHIPPING_ADDRESS', 
            'message', 'Shipping address must be between 10 and 500 characters.'
        );
    END IF;

    IF NOT (v_clean_pincode ~ '^\d{6}$') THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'INVALID_PINCODE', 
            'message', 'Valid 6-digit Indian pincode required.'
        );
    END IF;

    -- 2. Deduplicate Product IDs & Validate Cart Bounds
    SELECT array_agg(DISTINCT id) INTO v_clean_product_ids
    FROM unnest(p_product_ids) AS id
    WHERE id IS NOT NULL;

    IF v_clean_product_ids IS NULL OR array_length(v_clean_product_ids, 1) = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'EMPTY_CART');
    END IF;

    IF array_length(v_clean_product_ids, 1) > 10 THEN
        RETURN jsonb_build_object('success', false, 'error', 'EXCEEDS_CART_LIMIT');
    END IF;

    -- 3. Validate Drop is Active ('live')
    SELECT * INTO v_drop FROM drops WHERE id = p_drop_id AND status = 'live' FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'DROP_NOT_ACTIVE');
    END IF;

    -- 4. Verify all requested products belong to the specified drop
    IF EXISTS (
        SELECT 1 FROM products 
        WHERE id = ANY(v_clean_product_ids) AND drop_id != p_drop_id
    ) THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'MIXED_DROP_PRODUCTS',
            'message', 'All products must belong to the specified drop.'
        );
    END IF;

    -- 5. Lock Requested Products in Strict Ascending UUID Order (Prevents Deadlocks)
    SELECT COUNT(*) INTO v_locked_count
    FROM (
        SELECT id FROM products
        WHERE id = ANY(v_clean_product_ids) 
          AND drop_id = p_drop_id 
          AND status = 'available'
        ORDER BY id ASC
        FOR UPDATE
    ) locked_rows;

    -- 6. If not all items are available, calculate unavailable IDs and fail atomically
    IF v_locked_count < array_length(v_clean_product_ids, 1) THEN
        SELECT coalesce(jsonb_agg(id), '[]'::jsonb) INTO v_unavailable_ids
        FROM (
            SELECT id FROM unnest(v_clean_product_ids) AS id
            EXCEPT
            SELECT p.id FROM products p 
            WHERE p.id = ANY(v_clean_product_ids) 
              AND p.drop_id = p_drop_id 
              AND p.status = 'available'
        ) u;

        RETURN jsonb_build_object(
            'success', false, 
            'error', 'STOCK_UNAVAILABLE',
            'unavailable_product_ids', v_unavailable_ids
        );
    END IF;

    -- 7. Fetch Seller Profile for Policy Resolution
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 8. Authoritatively Calculate Subtotal from Locked Product Rows
    SELECT COALESCE(SUM(price_paisa), 0) INTO v_subtotal_paisa
    FROM products
    WHERE id = ANY(v_clean_product_ids)
      AND drop_id = p_drop_id;

    -- 9. Authoritatively Calculate Shipping from Drop with Seller Fallback
    IF v_subtotal_paisa >= COALESCE(v_drop.free_shipping_threshold_paisa, v_seller.free_shipping_threshold_paisa, 200000) THEN
        v_shipping_paisa := 0;
    ELSE
        v_shipping_paisa := COALESCE(v_drop.shipping_fee_paisa, v_seller.default_shipping_fee_paisa, 8000);
    END IF;

    v_total_paisa := v_subtotal_paisa + v_shipping_paisa;

    -- 10. Resolve Seller Advance & Hold Policy (Drop override > Seller profile default)
    IF v_confirmation_mode = 'advance' THEN
        v_advance_enabled := COALESCE(v_drop.advance_confirmation_enabled, v_seller.advance_confirmation_enabled, true);
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

        v_hold_days := COALESCE(v_drop.hold_duration_days, v_seller.hold_duration_days, 30);
        IF v_hold_days < 1 OR v_hold_days > 30 THEN
            v_hold_days := 30; -- Strict platform cap
        END IF;
        v_hold_expires_at := NOW() + (v_hold_days || ' days')::interval;
    ELSE
        -- Full payment mode
        v_advance_required_paisa := 0;
        v_hold_expires_at := NOW() + INTERVAL '15 minutes';
    END IF;

    -- 11. Generate Collision-Resistant 6-Char Order Code
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

    -- 12. Insert Order Record with Snapshotted Financial Model
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

    -- 13. Insert Order Line Items & Update Products to Reserved State
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

    -- 14. Return Authoritative Order Receipt
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

-- 5.2 Privileged Seller RPC: confirm_order_advance()
-- Confirms advance receipt from buyer, transitions order to 'confirmed',
-- sets payment_status to 'advance_paid', and logs payment entry.
CREATE OR REPLACE FUNCTION confirm_order_advance(
    p_order_id UUID,
    p_reference_id TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_seller profiles%ROWTYPE;
    v_hold_days INT;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
    END IF;

    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id AND seller_id = auth.uid() FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    IF v_order.confirmation_mode != 'advance' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_OPERATION',
            'message', 'Only orders in advance confirmation mode can confirm an advance payment.'
        );
    END IF;

    IF v_order.status IN ('confirmed', 'paid', 'shipped') THEN
        RETURN jsonb_build_object('success', true); -- Idempotent
    END IF;

    IF v_order.status != 'pending' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in state "%s" and cannot be confirmed with advance.', v_order.status)
        );
    END IF;

    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;
    v_hold_days := COALESCE(v_drop.hold_duration_days, v_seller.hold_duration_days, 30);
    IF v_hold_days < 1 OR v_hold_days > 30 THEN
        v_hold_days := 30;
    END IF;

    -- Update order to confirmed with advance paid
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

    -- Insert record into order_payments
    INSERT INTO order_payments (
        order_id, payment_type, amount_paisa, status, reference_id, verified_at, verified_by
    ) VALUES (
        p_order_id, 'advance', v_order.advance_required_paisa, 'verified', p_reference_id, NOW(), auth.uid()
    );

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 5.3 Privileged Seller RPC: mark_order_paid() (Updated for full payment & balance payment)
CREATE OR REPLACE FUNCTION mark_order_paid(
    p_order_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_contested_count INT;
    v_pay_amount INT;
    v_pay_type TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
    END IF;

    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id AND seller_id = auth.uid() FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    -- Idempotency check
    IF v_order.status IN ('paid', 'shipped') THEN
        RETURN jsonb_build_object('success', true);
    END IF;

    -- Only pending, confirmed, or cancelled (uncontested) orders can transition to paid
    IF v_order.status NOT IN ('pending', 'confirmed', 'cancelled') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in state "%s" and cannot be marked paid.', v_order.status)
        );
    END IF;

    -- Lock target products in deterministic ascending UUID order
    PERFORM id FROM products
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
    ORDER BY id ASC
    FOR UPDATE;

    -- Check for contested items
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

    -- Determine payment type and amount to record in payments table
    IF v_order.confirmation_mode = 'advance' AND v_order.advance_paid_paisa > 0 THEN
        v_pay_type := 'balance';
        v_pay_amount := v_order.total_paisa - v_order.advance_paid_paisa;
    ELSE
        v_pay_type := 'full';
        v_pay_amount := v_order.total_paisa;
    END IF;

    -- Transition products to sold
    UPDATE products
    SET status = 'sold',
        reserved_at = NULL,
        reserved_by_order_id = NULL,
        version = version + 1,
        updated_at = NOW()
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);

    -- Transition order to paid (balance = 0, ready_to_ship)
    UPDATE orders
    SET status = 'paid',
        payment_status = 'paid',
        total_paid_paisa = v_order.total_paisa,
        balance_due_paisa = 0,
        fulfilment_status = 'ready_to_ship',
        paid_at = NOW(),
        updated_at = NOW()
    WHERE id = p_order_id;

    -- Log payment record
    IF v_pay_amount > 0 THEN
        INSERT INTO order_payments (
            order_id, payment_type, amount_paisa, status, verified_at, verified_by
        ) VALUES (
            p_order_id, v_pay_type, v_pay_amount, 'verified', NOW(), auth.uid()
        );
    END IF;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- 5.4 Maintenance RPC: release_expired_holds() (Updated for 30-day advance expiry & non-refundable advance)
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

-- 5.5 Buyer Token RPC: get_order_by_token() (Updated with storefront and state fields)
CREATE OR REPLACE FUNCTION get_order_by_token(
    p_order_id UUID,
    p_order_token UUID
) RETURNS JSONB AS $$
DECLARE
    v_order_json JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', o.id,
        'order_code', o.order_code,
        'buyer_name', o.buyer_name,
        'subtotal_paisa', o.subtotal_paisa,
        'shipping_paisa', o.shipping_paisa,
        'total_paisa', o.total_paisa,
        'confirmation_mode', o.confirmation_mode,
        'advance_required_paisa', o.advance_required_paisa,
        'advance_paid_paisa', o.advance_paid_paisa,
        'total_paid_paisa', o.total_paid_paisa,
        'balance_due_paisa', o.balance_due_paisa,
        'payment_status', o.payment_status,
        'fulfilment_status', o.fulfilment_status,
        'status', o.status,
        'hold_expires_at', o.hold_expires_at,
        'store_name', pr.store_name,
        'store_slug', pr.store_slug,
        'upi_id', pr.upi_id,
        'upi_qr_url', pr.upi_qr_url,
        'items', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'product_id', p.id,
                'code', p.code,
                'title', p.title,
                'image_url', p.image_url,
                'price_at_purchase_paisa', oi.price_at_purchase_paisa
            ) ORDER BY p.code ASC), '[]'::jsonb)
            FROM order_items oi
            JOIN products p ON p.id = oi.product_id
            WHERE oi.order_id = o.id
        )
    ) INTO v_order_json
    FROM orders o
    JOIN drops d ON d.id = o.drop_id
    JOIN profiles pr ON pr.id = d.seller_id
    WHERE o.id = p_order_id AND o.order_token = p_order_token;

    IF v_order_json IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    RETURN jsonb_build_object('success', true, 'order', v_order_json);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 6. SECURITY DEFINER HARDENING & PRIVILEGE BOUNDARIES
-- ============================================================================

-- Revoke default public execution
REVOKE ALL ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION confirm_order_advance(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_order_paid(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_order_by_token(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION release_expired_holds() FROM PUBLIC;

-- Public / Buyer-facing operations
GRANT EXECUTE ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_order_by_token(UUID, UUID) TO anon, authenticated, service_role;

-- Privileged seller operations
REVOKE ALL ON FUNCTION confirm_order_advance(UUID, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION confirm_order_advance(UUID, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION mark_order_paid(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION mark_order_paid(UUID) TO authenticated, service_role;

-- System maintenance operation
REVOKE ALL ON FUNCTION release_expired_holds() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION release_expired_holds() TO service_role;
