-- LiveDrop Migration: 024_safe_drop_closure.sql
-- Description: BLOCKER 1F — Safe Drop Closure Protocol & Direct Update Trigger Guard.
-- Security: SECURITY DEFINER with pinned search_path = public, pg_temp

-- ============================================================================
-- 1. TRIGGER GUARD: Block Direct Mutation of drops.status = 'closed'
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_enforce_safe_drop_closure()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.status = 'closed' AND OLD.status <> 'closed' THEN
        -- Allow if invoked via close_drop() RPC which sets transaction-local setting
        IF current_setting('livedrop.closing_drop', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'Direct transition to closed is prohibited. Call close_drop(drop_id) RPC.'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_drops_safe_closure ON drops;
CREATE TRIGGER trg_drops_safe_closure
    BEFORE UPDATE OF status ON drops
    FOR EACH ROW
    EXECUTE FUNCTION trg_enforce_safe_drop_closure();

-- ============================================================================
-- 2. RPC: close_drop(UUID)
-- ============================================================================

CREATE OR REPLACE FUNCTION close_drop(
    p_drop_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_drop drops%ROWTYPE;
    v_order RECORD;
    v_released_orders_count INT := 0;
BEGIN
    -- 1. Authentication Check
    IF current_user <> 'service_role' AND auth.uid() IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to close a drop.'
        );
    END IF;

    -- 2. Fetch and Lock Drop
    SELECT * INTO v_drop
    FROM drops
    WHERE id = p_drop_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'DROP_NOT_FOUND',
            'message', 'The specified drop does not exist.'
        );
    END IF;

    -- 3. Verify Seller Ownership
    IF current_user <> 'service_role' AND v_drop.seller_id <> auth.uid() THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'FORBIDDEN',
            'message', 'You are not authorized to close drops for this boutique.'
        );
    END IF;

    -- 4. Idempotency Check
    IF v_drop.status = 'closed' THEN
        RETURN jsonb_build_object(
            'success', true,
            'drop_id', v_drop.id,
            'status', 'closed',
            'closed_at', v_drop.closed_at,
            'idempotent', true,
            'message', 'Drop is already closed.'
        );
    END IF;

    -- 5. Safe Closure Protocol (if drop is live):
    -- - Available products: naturally hidden from public catalog via view WHERE status = 'live'
    -- - Unpaid unclaimed reservations: gracefully released back to available & cancelled
    -- - Claims awaiting verification: preserved intact (buyer money in flight)
    -- - Advance-paid holds: preserved intact (confirmed hold)
    -- - Fully paid / shipped orders: untouched
    IF v_drop.status = 'live' THEN
        FOR v_order IN
            SELECT o.id FROM orders o
            WHERE o.drop_id = p_drop_id
              AND o.status = 'pending'
              AND o.payment_status = 'unpaid'
              AND NOT EXISTS (
                  SELECT 1 FROM payment_attempts pa
                  WHERE pa.order_id = o.id
                    AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
              )
            ORDER BY o.id ASC
            FOR UPDATE
        LOOP
            -- Release reserved products for this order back to available
            PERFORM id FROM products
            WHERE reserved_by_order_id = v_order.id
            ORDER BY id ASC
            FOR UPDATE;

            UPDATE products
            SET status = 'available',
                reserved_at = NULL,
                reserved_by_order_id = NULL,
                version = version + 1,
                updated_at = NOW()
            WHERE reserved_by_order_id = v_order.id
              AND status = 'reserved';

            -- Cancel the unpaid unclaimed order
            UPDATE orders
            SET status = 'cancelled',
                hold_expires_at = NOW(),
                updated_at = NOW()
            WHERE id = v_order.id;

            -- Expire associated open payment attempts
            UPDATE payment_attempts
            SET status = 'expired',
                updated_at = NOW()
            WHERE order_id = v_order.id
              AND status IN ('created', 'awaiting_payment');

            v_released_orders_count := v_released_orders_count + 1;
        END LOOP;
    END IF;

    -- 6. Transition Drop to Closed with Transaction-Local Exemption
    PERFORM set_config('livedrop.closing_drop', 'true', true);

    UPDATE drops
    SET status = 'closed',
        closed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_drop_id;

    RETURN jsonb_build_object(
        'success', true,
        'drop_id', p_drop_id,
        'status', 'closed',
        'closed_at', NOW(),
        'released_orders_count', v_released_orders_count,
        'message', 'Drop successfully closed. Unclaimed reservations released.'
    );
END;
$$;

REVOKE ALL ON FUNCTION close_drop(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION close_drop(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION close_drop(UUID) TO authenticated, service_role;
