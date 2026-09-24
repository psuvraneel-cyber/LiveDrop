-- LiveDrop Migration: 028_fix_get_order_by_token_overload_ambiguity.sql
-- Description: Drop ambiguous get_order_by_token(UUID, UUID) overload to resolve PostgREST PGRST203 (HTTP 300 Multiple Choices).
-- Standards: ADR-001 (PostgreSQL Authority), docs/12-database-design.md, docs/16-security-architecture.md

-- ============================================================================
-- 1. DROP AMBIGUOUS 2-PARAMETER OVERLOAD: get_order_by_token(UUID, UUID)
-- ============================================================================
-- PostgREST cannot disambiguate between get_order_by_token(UUID, TEXT) and 
-- get_order_by_token(UUID, UUID) when called with named JSON arguments
-- { p_order_id: ..., p_order_token: ... }, causing HTTP 300 / PGRST203.
-- Since p_order_token as TEXT seamlessly validates against order_token::text
-- while accepting all UUID strings, dropping the (UUID, UUID) overload restores
-- clean RPC resolution for both PostgREST and application clients.

DROP FUNCTION IF EXISTS public.get_order_by_token(UUID, UUID);

-- ============================================================================
-- 2. ENSURE CANONICAL 2-PARAMETER RPC: get_order_by_token(UUID, TEXT)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_order_by_token(
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

REVOKE ALL ON FUNCTION public.get_order_by_token(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_order_by_token(UUID, TEXT) TO anon, authenticated, service_role;

-- Notify PostgREST schema cache reload
NOTIFY pgrst, 'reload schema';
