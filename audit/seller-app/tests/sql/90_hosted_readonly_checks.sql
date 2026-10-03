-- =============================================================================
-- LiveDrop Seller-App Audit — READ-ONLY checks to run on the HOSTED project
-- (Supabase Dashboard -> SQL Editor). Every statement below only reads catalog
-- metadata; nothing is modified. Run on staging first, then production.
--
-- These confirm or refute findings that the local audit could only prove under
-- an emulation of Supabase's default privileges.
-- =============================================================================

-- H1 (finding SA-SEC-001): can anon/authenticated write through the storefront view?
--     Secure result: only SELECT for anon/authenticated.
SELECT grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'public_seller_storefronts'
  AND grantee IN ('anon', 'authenticated')
GROUP BY grantee;

-- H2: is the view auto-updatable? ('YES' + UPDATE privilege in H1 = writable by the API)
SELECT table_name, is_updatable, is_insertable_into
FROM information_schema.views
WHERE table_schema = 'public';

-- H3: view options (security_invoker off means base-table RLS is evaluated as the view owner)
SELECT c.relname, c.reloptions, pg_get_userbyid(c.relowner) AS owner
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'v';

-- H4: default privileges that will apply to future objects created by postgres in public
SELECT pg_get_userbyid(d.defaclrole) AS creator, d.defaclobjtype AS object_type, d.defaclacl
FROM pg_default_acl d JOIN pg_namespace n ON n.oid = d.defaclnamespace
WHERE n.nspname = 'public';

-- H5: functions callable by anon (should be only the buyer RPCs + harmless helpers)
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.prosecdef AS security_definer
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY 1;

-- H6: migrations actually applied on this project (compare with supabase/migrations/001..033)
SELECT version, name FROM supabase_migrations.schema_migrations ORDER BY version;

-- H7: Realtime publication membership (seller app relies on orders; buyer web on products)
SELECT pubname, schemaname, tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime' ORDER BY 3;

-- H8: is pg_cron available/installed (alternative to the GitHub Actions reaper)
SELECT name, installed_version FROM pg_available_extensions WHERE name IN ('pg_cron', 'pg_net');

-- H9: orders whose reservation already expired but are still holding stock
--     (measures real-world reaper lag; read-only)
SELECT count(*) AS expired_but_still_pending, min(hold_expires_at) AS oldest_expiry
FROM public.orders WHERE status = 'pending' AND hold_expires_at < now();

-- H10: verified late claims that left orders cancelled but marked paid (refund owed)
SELECT id, order_code, status, payment_status, total_paid_paisa, left(notes, 80) AS notes
FROM public.orders WHERE status IN ('cancelled', 'expired') AND payment_status = 'paid';

-- H11: orders whose recorded paid amount exceeds the verified ledger (late-advance defect)
SELECT o.id, o.order_code, o.total_paid_paisa, COALESCE(SUM(op.amount_paisa), 0) AS ledger_paisa
FROM public.orders o LEFT JOIN public.order_payments op ON op.order_id = o.id AND op.status = 'verified'
GROUP BY o.id HAVING o.total_paid_paisa <> COALESCE(SUM(op.amount_paisa), 0);

-- H12 (finding SA-SEC-008 / SA-SEC-003): storage policies — a SELECT policy for
--     role public on product-images lets anyone list every object.
SELECT policyname, roles, cmd, qual, with_check
FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects' ORDER BY policyname;

-- H13 (finding SA-PAY-018): orders with verified ledger rows that the seller
--      DELETE policy would still allow to be deleted (status not protected)
SELECT o.status, count(*) AS orders_with_ledger
FROM public.orders o
WHERE EXISTS (SELECT 1 FROM public.order_payments op WHERE op.order_id = o.id AND op.status = 'verified')
  AND o.status NOT IN ('confirmed', 'paid', 'shipped', 'expired')
GROUP BY o.status;

-- =============================================================================
-- Optional non-destructive HTTP probe for storage listing (SA-SEC-008):
--   curl -s -X POST '<URL>/storage/v1/object/list/product-images' \
--     -H 'apikey: <ANON_KEY>' -H 'Authorization: Bearer <ANON_KEY>' \
--     -H 'Content-Type: application/json' -d '{"prefix":"","limit":5}'
-- Secure: []   Vulnerable: a JSON array of seller-id folders
-- =============================================================================
-- Optional non-destructive HTTP probe for H1 (uses a UUID that cannot exist, so
-- no row can be touched). Replace <URL> and <ANON_KEY>.
--
--   curl -i -X PATCH '<URL>/rest/v1/public_seller_storefronts?id=eq.00000000-0000-0000-0000-000000000000' \
--     -H 'apikey: <ANON_KEY>' -H 'Authorization: Bearer <ANON_KEY>' \
--     -H 'Content-Type: application/json' -H 'Prefer: return=representation' \
--     -d '{"store_name":"probe"}'
--
-- Secure:     HTTP 401/403 with code 42501 "permission denied for view public_seller_storefronts"
-- Vulnerable: HTTP 200 with body []   (the update was authorised; it only matched no rows)
-- =============================================================================
