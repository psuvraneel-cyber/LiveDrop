-- LiveDrop Migration: 022_checkout_idempotency_conflict_detection.sql
-- Description: BLOCKER 1C — Server-Backed Checkout Idempotency & Payload Conflict Detection.
-- Security: SECURITY DEFINER with pinned search_path = public, pg_temp

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
