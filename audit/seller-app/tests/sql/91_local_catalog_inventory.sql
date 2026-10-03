-- =============================================================================
-- Catalog inventory of the LOCAL audit database (after migrations 001-033 on
-- top of 00_supabase_shim.sql). Read-only. Produces evidence/schema-inventory.out.
-- The same questions for the hosted project are in 90_hosted_readonly_checks.sql.
-- =============================================================================
\pset pager off

\echo == Tables: RLS enabled / forced
SELECT c.relname, c.relrowsecurity AS rls, c.relforcerowsecurity AS forced
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY 1;

\echo == Views and auto-updatability (information_schema)
SELECT table_name, is_updatable, is_insertable_into
FROM information_schema.views WHERE table_schema = 'public' ORDER BY 1;

\echo == Column updatability of public_seller_storefronts
SELECT column_name, is_updatable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'public_seller_storefronts'
ORDER BY ordinal_position;

\echo == Table/view privileges for anon & authenticated (Supabase default privileges emulated)
SELECT table_name, grantee, string_agg(privilege_type, ',' ORDER BY privilege_type) AS privs
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated')
GROUP BY table_name, grantee ORDER BY 1, 2;

\echo == Policies
SELECT tablename, policyname, cmd, roles, permissive
FROM pg_policies WHERE schemaname IN ('public', 'storage') ORDER BY 1, 2;
