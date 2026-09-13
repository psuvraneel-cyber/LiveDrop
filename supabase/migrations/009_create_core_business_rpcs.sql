-- LiveDrop Migration: 009_create_core_business_rpcs.sql
-- Description: Creates core transactional database RPC functions for atomic order creation,
--              inventory hold reservation, payment confirmation, hold expiration reaper,
--              receipt verification, and seller manual overrides.
-- Parent Documentation: docs/04-technical-design.md, docs/13-api-contract.md, docs/15-concurrency-and-reservation-spec.md
-- Governing Rules: AGENTS.md, ADR-002, ADR-003, ADR-009

-- Ensure standard Supabase roles exist for local/WASM testing engines
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- ============================================================================
-- 1. RPC: release_expired_holds()
-- ============================================================================
-- Reaps abandoned carts whose 15-minute hold timer has expired.
-- Resets reserved products to 'available' and sets pending orders to 'cancelled'.
-- Safe to invoke repeatedly (idempotent).
CREATE OR REPLACE FUNCTION release_expired_holds()
RETURNS VOID AS $$
DECLARE
    v_expired_order RECORD;
BEGIN
    FOR v_expired_order IN
        SELECT id FROM orders
        WHERE status = 'pending' AND hold_expires_at < clock_timestamp()
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

        -- Mark order cancelled / expired
        UPDATE orders
        SET status = 'cancelled',
            updated_at = NOW()
        WHERE id = v_expired_order.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 2. RPC: create_order_with_reservation()
-- ============================================================================
-- Atomic checkout transaction:
-- 1. Validates buyer data (name, phone, address, pincode).
-- 2. Validates drop is 'live'.
-- 3. Canonicalizes & deduplicates product IDs.
-- 4. Checks cart limit (1 to 10 items).
-- 5. Verifies all products belong to the target drop.
-- 6. Reaps expired holds (lazy reclamation per ADR-009).
-- 7. Locks available products in strict ascending UUID order (prevents deadlocks).
-- 8. Validates all requested products are available.
-- 9. Authoritatively calculates subtotal & shipping in integer Paisa.
-- 10. Inserts order with randomized order_code (LD-XXXXXX) and 128-bit order_token.
-- 11. Inserts order_items line items.
-- 12. Marks products as reserved.
CREATE OR REPLACE FUNCTION create_order_with_reservation(
    p_drop_id UUID,
    p_product_ids UUID[],
    p_buyer_name TEXT,
    p_buyer_phone TEXT,
    p_shipping_address TEXT,
    p_pincode TEXT
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
BEGIN
    -- 1. Input Sanitization & Tier 2 Validation
    v_clean_name := trim(COALESCE(p_buyer_name, ''));
    v_clean_phone := trim(COALESCE(p_buyer_phone, ''));
    v_clean_address := trim(COALESCE(p_shipping_address, ''));
    v_clean_pincode := trim(COALESCE(p_pincode, ''));

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

    -- 3. Validate Drop is Active ('live') and lock to prevent concurrent close (F-01 fix)
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

    -- 5. Lazy Expiration Cleanup REMOVED (F-02 fix: global reaper caused cross-order deadlock surface)
    -- Expired holds are invisible to checkout because step 6 filters status = 'available'.
    -- Dedicated cron job handles periodic cleanup via release_expired_holds().

    -- 6. Lock Requested Products in Strict Ascending UUID Order (Prevents Deadlocks)
    SELECT COUNT(*) INTO v_locked_count
    FROM (
        SELECT id FROM products
        WHERE id = ANY(v_clean_product_ids) 
          AND drop_id = p_drop_id 
          AND status = 'available'
        ORDER BY id ASC
        FOR UPDATE
    ) locked_rows;

    -- 7. If not all items are available, calculate unavailable IDs and fail atomically
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

    -- 8. Fetch Seller Profile for Fallback Shipping Policy
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 9. Authoritatively Calculate Subtotal from Locked Product Rows in Paisa (F-05 fix: mirrored filter)
    SELECT COALESCE(SUM(price_paisa), 0) INTO v_subtotal_paisa
    FROM products
    WHERE id = ANY(v_clean_product_ids)
      AND drop_id = p_drop_id;

    -- 10. Authoritatively Calculate Shipping from Drop with Seller Fallback
    IF v_subtotal_paisa >= COALESCE(v_drop.free_shipping_threshold_paisa, v_seller.free_shipping_threshold_paisa, 200000) THEN
        v_shipping_paisa := 0;
    ELSE
        v_shipping_paisa := COALESCE(v_drop.shipping_fee_paisa, v_seller.default_shipping_fee_paisa, 8000);
    END IF;

    v_total_paisa := v_subtotal_paisa + v_shipping_paisa;

    -- 11. Generate Collision-Resistant 6-Char Order Code from full [A-Z0-9] charset (F-06 fix: 36^6 code space)
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

    -- Safety: Fail loudly if code space is exhausted (should never happen with 2.18B combinations)
    IF EXISTS (SELECT 1 FROM orders WHERE order_code = v_order_code) THEN
        RAISE EXCEPTION 'Failed to generate unique order code after 100 attempts';
    END IF;

    -- 12. Insert Order Record
    INSERT INTO orders (
        drop_id, order_code, order_token, buyer_name, buyer_phone,
        shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa,
        status, hold_expires_at
    ) VALUES (
        p_drop_id, v_order_code, v_order_token, v_clean_name, v_clean_phone,
        v_clean_address, v_clean_pincode, v_subtotal_paisa, v_shipping_paisa, v_total_paisa,
        'pending', NOW() + INTERVAL '15 minutes'
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

    -- 14. Return Authoritative Order Receipt (Paisa values for financial integrity)
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'order_token', v_order.order_token,
        'subtotal_paisa', v_order.subtotal_paisa,
        'shipping_paisa', v_order.shipping_paisa,
        'total_paisa', v_order.total_paisa,
        'hold_expires_at', v_order.hold_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 3. RPC: mark_order_paid()
-- ============================================================================
-- Authenticated seller RPC to confirm payment:
-- 1. Verifies caller is authenticated and owns the drop.
-- 2. Lock order and target products deterministically.
-- 3. Guards against conflict if items were claimed by another buyer after hold expired.
-- 4. Transitions products to 'sold'.
-- 5. Transitions order to 'paid'.
-- 6. Idempotent on already paid orders.
CREATE OR REPLACE FUNCTION mark_order_paid(
    p_order_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_contested_count INT;
BEGIN
    -- 1. Verify Caller is Authenticated
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    -- 2. Lock Order Row Deterministically
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
    END IF;

    -- 3. Verify Seller Ownership of the Order's Drop (F-03 fix: lock to prevent ownership TOCTOU)
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id AND seller_id = auth.uid() FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    -- 4. Idempotency Check: Already Finalized
    IF v_order.status IN ('paid', 'shipped') THEN
        RETURN jsonb_build_object('success', true);
    END IF;

    -- 4b. Explicit State Gate: Only pending or cancelled orders may transition to paid (F-04 fix)
    IF v_order.status NOT IN ('pending', 'cancelled') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order is in state "%s" and cannot be marked paid.', v_order.status)
        );
    END IF;

    -- 5. Lock Target Products in Deterministic Ascending UUID Order (Deadlock Freedom)
    PERFORM id FROM products
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
    ORDER BY id ASC
    FOR UPDATE;

    -- 6. Check for Contested Items (reclaimed by another order or marked sold)
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

    -- 7. Transition Products to Sold (F-08 fix: clear hold reference; ownership tracked in order_items)
    UPDATE products
    SET status = 'sold',
        reserved_at = NULL,
        reserved_by_order_id = NULL,
        version = version + 1,
        updated_at = NOW()
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);

    -- 8. Transition Order to Paid
    UPDATE orders
    SET status = 'paid',
        paid_at = NOW(),
        updated_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 4. RPC: get_order_by_token()
-- ============================================================================
-- Token-gated order retrieval for unauthenticated buyers.
-- Returns structured order data and nested line items if secret order_token matches.
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
        'status', o.status,
        'hold_expires_at', o.hold_expires_at,
        'store_name', pr.store_name,
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
-- 5. RPC: force_release_hold()
-- ============================================================================
-- Authenticated seller override to cancel a pending order and return items to available.
-- IMPORTANT (F-02 Audit): Confirmed orders (advance_paid) are INTENTIONALLY excluded.
-- A confirmed order has already received advance payment; cancelling it would require
-- a refund-first workflow which is out of scope until TASK-2.4B introduces payment
-- provider integration with refund capabilities.
CREATE OR REPLACE FUNCTION force_release_hold(
    p_order_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    SELECT o.* INTO v_order
    FROM orders o
    JOIN drops d ON d.id = o.drop_id
    WHERE o.id = p_order_id AND d.seller_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    IF v_order.status != 'pending' THEN
        RETURN jsonb_build_object('success', false, 'error', 'ONLY_PENDING_CAN_BE_RELEASED');
    END IF;

    -- Lock products deterministically
    PERFORM id FROM products
    WHERE reserved_by_order_id = p_order_id AND status = 'reserved'
    ORDER BY id ASC
    FOR UPDATE;

    -- Return products to available
    UPDATE products
    SET status = 'available',
        reserved_at = NULL,
        reserved_by_order_id = NULL,
        version = version + 1,
        updated_at = NOW()
    WHERE reserved_by_order_id = p_order_id AND status = 'reserved';

    -- Mark order cancelled
    UPDATE orders
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 6. RPC: mark_product_sold_offline()
-- ============================================================================
-- Authenticated seller override to mark an available product sold offline immediately.
CREATE OR REPLACE FUNCTION mark_product_sold_offline(
    p_product_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_prod products%ROWTYPE;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    SELECT p.* INTO v_prod
    FROM products p
    JOIN drops d ON d.id = p.drop_id
    WHERE p.id = p_product_id AND d.seller_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'PRODUCT_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    IF v_prod.status = 'sold' THEN
        RETURN jsonb_build_object('success', false, 'error', 'ALREADY_SOLD');
    END IF;

    IF v_prod.status = 'reserved' THEN
        RETURN jsonb_build_object('success', false, 'error', 'PRODUCT_RESERVED');
    END IF;

    UPDATE products
    SET status = 'sold',
        version = version + 1,
        updated_at = NOW()
    WHERE id = p_product_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 7. SECURITY DEFINER HARDENING & PRIVILEGE MODEL
-- ============================================================================
-- Revoke all default public execution rights
REVOKE ALL ON FUNCTION release_expired_holds() FROM PUBLIC;
REVOKE ALL ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_order_paid(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_order_by_token(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION force_release_hold(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION mark_product_sold_offline(UUID) FROM PUBLIC;

-- Buyer-facing public operations (accessible by anonymous buyers and authenticated users)
GRANT EXECUTE ON FUNCTION create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION get_order_by_token(UUID, UUID) TO anon, authenticated, service_role;

-- Seller-only privileged operations (explicitly revoked from anon, granted only to authenticated sellers and service role)
REVOKE ALL ON FUNCTION mark_order_paid(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION mark_order_paid(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION force_release_hold(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION force_release_hold(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION mark_product_sold_offline(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION mark_product_sold_offline(UUID) TO authenticated, service_role;

-- System / Cron maintenance operation (strictly restricted to backend service_role)
REVOKE ALL ON FUNCTION release_expired_holds() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION release_expired_holds() TO service_role;

