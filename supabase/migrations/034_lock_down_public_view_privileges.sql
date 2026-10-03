-- LiveDrop Migration: 034_lock_down_public_view_privileges.sql
-- Description: SA-SEC-001 — anonymous users could rewrite or delete approved sellers' storefront
--              rows through the public projection views.
--
--   public_seller_storefronts is a single-table, auto-updatable view over profiles. Supabase's
--   default privileges grant ALL on every new object in schema public to anon and authenticated,
--   and the migrations that (re)created the projection views (016, 029, 031, 033) only added
--   GRANT SELECT. The views run with their owner's rights (no security_invoker), so INSERT /
--   UPDATE / DELETE through the view bypassed the RLS policies on profiles.
--
-- Fix:
--   1. Every view in schema public: REVOKE ALL from PUBLIC, anon, authenticated, then grant back
--      SELECT only (never widening access: a role that could not read a view before still cannot).
--      The two known projection views are handled explicitly as well.
--   2. Views stay owner-rights views on purpose: anon has no SELECT on profiles/products, so a
--      security_invoker view would return nothing to buyers.
--   3. Default privileges for objects created later by the migration role: anon gets no
--      INSERT/UPDATE/DELETE/TRUNCATE/REFERENCES/TRIGGER on new tables or views; authenticated gets
--      no TRUNCATE/REFERENCES/TRIGGER (TRUNCATE ignores RLS).
--   4. Existing tables in public: revoke TRUNCATE, REFERENCES and TRIGGER from anon/authenticated.
--
-- RLS is not touched. service_role keeps its privileges (trusted backend role).
-- Regression: audit/seller-app/tests/sql/10_exposure_and_view_dml.sql (10.3-10.5, 10.9) and
--             audit/seller-app/tests/sql/19_p0_remediation.sql (view and default-privilege checks).

-- ============================================================================
-- 1. Views in schema public: SELECT only for client roles
-- ============================================================================
DO $$
DECLARE
    v_view RECORD;
    v_anon_could_read BOOLEAN;
    v_auth_could_read BOOLEAN;
BEGIN
    FOR v_view IN
        SELECT c.oid, n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind = 'v'
        ORDER BY c.relname
    LOOP
        v_anon_could_read := has_table_privilege('anon', v_view.oid, 'SELECT');
        v_auth_could_read := has_table_privilege('authenticated', v_view.oid, 'SELECT');

        EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC, anon, authenticated',
                       v_view.nspname, v_view.relname);

        IF v_anon_could_read THEN
            EXECUTE format('GRANT SELECT ON TABLE %I.%I TO anon', v_view.nspname, v_view.relname);
        END IF;
        IF v_auth_could_read THEN
            EXECUTE format('GRANT SELECT ON TABLE %I.%I TO authenticated', v_view.nspname, v_view.relname);
        END IF;
        EXECUTE format('GRANT SELECT ON TABLE %I.%I TO service_role', v_view.nspname, v_view.relname);
    END LOOP;
END $$;

-- The two public projection views are meant to be read by buyers (anon) and sellers.
REVOKE ALL ON TABLE public.public_seller_storefronts FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.public_seller_storefronts TO anon, authenticated, service_role;

REVOKE ALL ON TABLE public.public_products_catalog FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.public_products_catalog TO anon, authenticated, service_role;

-- ============================================================================
-- 2. Default privileges for tables/views created later by this (migration) role
-- ============================================================================
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM anon;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
    REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM authenticated;

-- ============================================================================
-- 3. Existing tables in public: TRUNCATE / REFERENCES / TRIGGER are never needed by clients
-- ============================================================================
DO $$
DECLARE
    v_table RECORD;
BEGIN
    FOR v_table IN
        SELECT n.nspname, c.relname
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relkind IN ('r', 'p', 'f')
        ORDER BY c.relname
    LOOP
        EXECUTE format('REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLE %I.%I FROM PUBLIC, anon, authenticated',
                       v_table.nspname, v_table.relname);
    END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
