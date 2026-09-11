-- LiveDrop Migration: 007_create_triggers.sql
-- Description: Creates trigger functions for automatic updated_at timestamps
--              and finalized order deletion protection.
-- Parent Documentation: docs/12-database-design.md (Section 4, Line 256-257)
-- Audit Findings: F3 (updated_at), F7 (finalized order deletion guard)

-- ============================================================================
-- 1. TRIGGER FUNCTION: Automatic updated_at timestamp
-- ============================================================================
-- Per spec: "Triggers update updated_at = NOW() across all tables on every modification."
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_drops_updated_at
    BEFORE UPDATE ON drops
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_products_updated_at
    BEFORE UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- order_items is INSERT-only by design; no updated_at trigger needed.

-- ============================================================================
-- 2. TRIGGER FUNCTION: Prevent deletion of finalized (paid/shipped) orders
-- ============================================================================
-- Protects historical financial records from accidental or malicious deletion.
-- GST compliance requires retention of completed transaction records.
CREATE OR REPLACE FUNCTION prevent_finalized_order_deletion()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status IN ('paid', 'shipped') THEN
        RAISE EXCEPTION 'Cannot delete finalized order % with status "%"', OLD.id, OLD.status;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_orders_no_delete_finalized
    BEFORE DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION prevent_finalized_order_deletion();
