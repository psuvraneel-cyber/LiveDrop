-- ============================================================================
-- Migration 026: Authoritative Fulfillment State Machine (Blocker 1I - P1)
-- ============================================================================
-- Enforces intermediate packing verification (ready_to_ship) before dispatch.
-- Disallows skipping packing by requiring fulfilment_status = 'ready_to_ship'
-- in mark_order_shipped RPC. Adds packed_at timestamp and mark_order_ready_to_ship RPC.

-- 1. Add packed_at column to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS packed_at TIMESTAMPTZ;

-- 2. Create authoritative mark_order_ready_to_ship RPC
-- Transitions order from 'not_ready' -> 'ready_to_ship', sets packed_at timestamp.
CREATE OR REPLACE FUNCTION mark_order_ready_to_ship(
    p_order_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_seller_id UUID;
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
BEGIN
    -- Authentication check
    v_seller_id := auth.uid();
    IF v_seller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to mark orders ready to ship.'
        );
    END IF;

    -- Row lock order
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'Order not found.'
        );
    END IF;

    -- Drop ownership verification
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id AND seller_id = v_seller_id FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'FORBIDDEN',
            'message', 'You are not authorized to fulfill orders for this drop.'
        );
    END IF;

    -- Idempotency check
    IF v_order.fulfilment_status = 'ready_to_ship' THEN
        RETURN jsonb_build_object(
            'success', true,
            'idempotent', true,
            'order_id', v_order.id,
            'order_code', v_order.order_code,
            'fulfilment_status', v_order.fulfilment_status,
            'packed_at', v_order.packed_at
        );
    END IF;

    -- Terminal state check
    IF v_order.status = 'shipped' OR v_order.fulfilment_status = 'shipped' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ALREADY_SHIPPED',
            'message', 'Order has already been shipped.'
        );
    END IF;

    -- Financial settlement check: Must be fully paid
    IF v_order.payment_status <> 'paid' OR v_order.balance_due_paisa > 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_PAID',
            'message', 'Order cannot be marked ready to ship until payment is fully settled.'
        );
    END IF;

    -- Valid order status check
    IF v_order.status NOT IN ('paid', 'confirmed') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_ORDER_STATE',
            'message', format('Order status "%s" cannot transition to ready_to_ship.', v_order.status)
        );
    END IF;

    -- Authoritative transition
    UPDATE orders
    SET fulfilment_status = 'ready_to_ship',
        packed_at = COALESCE(packed_at, NOW()),
        updated_at = NOW()
    WHERE id = v_order.id
    RETURNING * INTO v_order;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'fulfilment_status', v_order.fulfilment_status,
        'packed_at', v_order.packed_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION mark_order_ready_to_ship(UUID) TO authenticated, service_role;

-- 3. Harden mark_order_shipped RPC to strictly require fulfilment_status = 'ready_to_ship'
CREATE OR REPLACE FUNCTION mark_order_shipped(
    p_order_id UUID,
    p_tracking_number TEXT,
    p_courier_partner TEXT,
    p_notes TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_seller_id UUID;
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_clean_tracking TEXT;
    v_clean_courier TEXT;
    v_clean_notes TEXT;
BEGIN
    -- 1. Authentication check
    v_seller_id := auth.uid();
    IF v_seller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to fulfill orders.'
        );
    END IF;

    -- 2. Fetch and lock order
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'Order not found.'
        );
    END IF;

    -- 3. Verify drop ownership
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id AND seller_id = v_seller_id FOR SHARE;
    IF NOT FOUND THEN
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

    -- SEC-05 Enforcement: Strict check that packaging was completed
    IF v_order.fulfilment_status <> 'ready_to_ship' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_READY_TO_SHIP',
            'message', format('Order fulfilment status is "%s". Order must be marked ready_to_ship before shipping.', v_order.fulfilment_status)
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION mark_order_shipped(UUID, TEXT, TEXT, TEXT) TO authenticated, service_role;
