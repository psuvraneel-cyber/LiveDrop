-- LiveDrop Migration: 012_payment_authority_direct_update_hardening.sql
-- Description: TASK-2.4A.2 Remediation — Enforces database-level payment authority and order lifecycle immutability.
--              Prevents authenticated sellers from bypassing service_role payment RPCs via direct UPDATE on orders.
--              Prevents direct mutation of reserved inventory to fabricate matched paid orders.
--              Preserves legitimate seller operational updates (e.g. tracking_number, courier_partner).
-- Parent Documentation: docs/12-database-design.md, docs/16-security-architecture.md, docs/19-validation-and-business-rules.md
-- Audit Findings: BLOCKER-02 (TASK-2.4A.1 Final Verification)

-- ============================================================================
-- 1. TRIGGER FUNCTION: enforce_orders_payment_immutability()
-- ============================================================================
-- Guarantees that payment-authoritative, financial snapshot, and lifecycle fields
-- on orders can ONLY be mutated by trusted backend callers:
-- - PostgreSQL superuser / database owner (including SECURITY DEFINER RPCs)
-- - service_role database user
-- - JWT session with service_role claim
-- Direct UPDATE requests by authenticated sellers (or anon) that attempt to alter
-- protected fields are immediately rejected with SQLSTATE 42501.
CREATE OR REPLACE FUNCTION enforce_orders_payment_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_trusted BOOLEAN;
    v_jwt_role TEXT;
BEGIN
    -- Resolve JWT role if set in connection context
    BEGIN
        v_jwt_role := COALESCE(
            NULLIF(current_setting('request.jwt.claim.role', true), ''),
            (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        );
    EXCEPTION WHEN OTHERS THEN
        v_jwt_role := NULL;
    END;

    -- Caller is trusted if running as superuser/postgres (which includes all SECURITY DEFINER RPCs),
    -- as service_role, or with service_role JWT claim.
    v_is_trusted := (
        current_user IN ('postgres', 'service_role')
        OR (v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role')
    );

    IF NOT v_is_trusted THEN
        -- Check if any payment, financial, or lifecycle authoritative field is being altered
        IF (OLD.status IS DISTINCT FROM NEW.status) OR
           (OLD.payment_status IS DISTINCT FROM NEW.payment_status) OR
           (OLD.fulfilment_status IS DISTINCT FROM NEW.fulfilment_status) OR
           (OLD.advance_required_paisa IS DISTINCT FROM NEW.advance_required_paisa) OR
           (OLD.advance_paid_paisa IS DISTINCT FROM NEW.advance_paid_paisa) OR
           (OLD.total_paid_paisa IS DISTINCT FROM NEW.total_paid_paisa) OR
           (OLD.balance_due_paisa IS DISTINCT FROM NEW.balance_due_paisa) OR
           (OLD.advance_paid_at IS DISTINCT FROM NEW.advance_paid_at) OR
           (OLD.paid_at IS DISTINCT FROM NEW.paid_at) OR
           (OLD.shipped_at IS DISTINCT FROM NEW.shipped_at) OR
           (OLD.hold_expires_at IS DISTINCT FROM NEW.hold_expires_at) OR
           (OLD.confirmation_mode IS DISTINCT FROM NEW.confirmation_mode) OR
           (OLD.subtotal_paisa IS DISTINCT FROM NEW.subtotal_paisa) OR
           (OLD.shipping_paisa IS DISTINCT FROM NEW.shipping_paisa) OR
           (OLD.total_paisa IS DISTINCT FROM NEW.total_paisa) OR
           (OLD.order_token IS DISTINCT FROM NEW.order_token) OR
           (OLD.order_code IS DISTINCT FROM NEW.order_code) OR
           (OLD.drop_id IS DISTINCT FROM NEW.drop_id)
        THEN
            RAISE EXCEPTION 'Direct mutation of payment or order lifecycle fields is prohibited for authenticated sellers. Use trusted RPCs.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_orders_payment_immutability ON orders;
CREATE TRIGGER trg_enforce_orders_payment_immutability
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION enforce_orders_payment_immutability();

-- ============================================================================
-- 2. TRIGGER FUNCTION: enforce_products_inventory_immutability()
-- ============================================================================
-- Guarantees that active product reservations and reserved product lifecycle transitions
-- cannot be directly altered by authenticated sellers outside trusted RPCs.
CREATE OR REPLACE FUNCTION enforce_products_inventory_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_trusted BOOLEAN;
    v_jwt_role TEXT;
BEGIN
    BEGIN
        v_jwt_role := COALESCE(
            NULLIF(current_setting('request.jwt.claim.role', true), ''),
            (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        );
    EXCEPTION WHEN OTHERS THEN
        v_jwt_role := NULL;
    END;

    v_is_trusted := (
        current_user IN ('postgres', 'service_role')
        OR (v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role')
    );

    IF NOT v_is_trusted THEN
        -- Prevent untrusted caller from altering reservation linkages or transitioning reserved items
        IF (OLD.status = 'reserved' AND NEW.status != 'reserved') OR
           (OLD.reserved_by_order_id IS DISTINCT FROM NEW.reserved_by_order_id) OR
           (OLD.reserved_at IS DISTINCT FROM NEW.reserved_at)
        THEN
            RAISE EXCEPTION 'Direct mutation of product reservation status is prohibited for authenticated sellers. Use trusted RPCs.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_products_inventory_immutability ON products;
CREATE TRIGGER trg_enforce_products_inventory_immutability
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION enforce_products_inventory_immutability();
