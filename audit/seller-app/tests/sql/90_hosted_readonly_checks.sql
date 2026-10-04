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

-- H6: migrations actually applied on this project (compare with supabase/migrations/001..036)
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
-- Post-remediation checks (after migrations 034, 035, 036 are applied). Read-only.
-- =============================================================================

-- H14 (034, SA-SEC-001): client roles must hold SELECT only on every public view.
--      Expected: zero rows.
SELECT c.relname AS view_name, g.rolname, pr.p AS privilege
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS g(rolname)
CROSS JOIN unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) AS pr(p)
WHERE n.nspname = 'public' AND c.relkind = 'v' AND has_table_privilege(g.rolname, c.oid, pr.p)
ORDER BY 1, 2, 3;

-- H15 (035, SA-PAY-004): structured refund obligations — what sellers owe, per drop.
SELECT o.drop_id, count(*) AS refunds_owed, sum(o.refund_amount_paisa) AS owed_paisa, min(o.refund_required_at) AS oldest
FROM public.orders o WHERE o.refund_status = 'required'
GROUP BY o.drop_id ORDER BY oldest;

-- H16 (035): internal helpers are not callable by client roles; record_refund is seller/backend only.
--      Expected: every *_anon / *_auth column false except record_refund_auth = true.
SELECT has_function_privilege('anon', 'public.release_stale_hold(uuid)', 'EXECUTE') AS release_stale_hold_anon,
       has_function_privilege('authenticated', 'public.release_stale_hold(uuid)', 'EXECUTE') AS release_stale_hold_auth,
       has_function_privilege('anon', 'public.apply_upi_payment_transition(uuid,uuid,text,text,uuid)', 'EXECUTE') AS transition_anon,
       has_function_privilege('authenticated', 'public.apply_upi_payment_transition(uuid,uuid,text,text,uuid)', 'EXECUTE') AS transition_auth,
       has_function_privilege('anon', 'public.record_refund(uuid,text,text)', 'EXECUTE') AS record_refund_anon,
       has_function_privilege('authenticated', 'public.record_refund(uuid,text,text)', 'EXECUTE') AS record_refund_auth;

-- H17 (036, SA-OPS-001): in-database reaper schedule. Run only when H8 shows pg_cron installed.
--      Expected: one active job every minute, recent runs 'succeeded'.
-- SELECT jobid, jobname, schedule, command, active FROM cron.job WHERE jobname = 'livedrop-release-expired-holds';
-- SELECT status, start_time, end_time, return_message FROM cron.job_run_details
--  WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'livedrop-release-expired-holds')
--  ORDER BY start_time DESC LIMIT 10;

-- H18 (035, SA-OPS-001): unclaimed holds past expiry (reaper lag). Expected: 0 within ~2 minutes.
--      Pending orders past expiry WITH a payment claim are expected to stay (H19).
SELECT count(*) AS expired_unclaimed_holds, min(o.hold_expires_at) AS oldest_expiry
FROM public.orders o
WHERE o.status = 'pending' AND o.hold_expires_at < now() - interval '2 minutes'
  AND NOT EXISTS (SELECT 1 FROM public.payment_attempts pa WHERE pa.order_id = o.id
                    AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review'));

-- H19 (035, SA-PAY-003): overdue payment claims still waiting for the seller (never auto-expired).
SELECT pa.status, count(*) AS claims, min(coalesce(pa.verification_expires_at, pa.buyer_claimed_at)) AS oldest
FROM public.payment_attempts pa
WHERE pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
  AND coalesce(pa.verification_expires_at, pa.expires_at) < now()
GROUP BY pa.status;

-- H20 (owner reconciliation, SA-PAY-003 history): claims the PRE-035 reaper expired although the
--      buyer had submitted a UTR and nothing was verified. Review each with the seller; 035 does not
--      change these rows automatically.
SELECT pa.id AS payment_attempt_id, o.order_code, o.status AS order_status, pa.payment_type,
       pa.expected_amount_paisa, pa.buyer_submitted_utr, pa.buyer_claimed_at, pa.updated_at AS expired_at
FROM public.payment_attempts pa JOIN public.orders o ON o.id = pa.order_id
WHERE pa.status = 'expired' AND pa.buyer_submitted_utr IS NOT NULL AND pa.seller_verified_at IS NULL
  AND NOT EXISTS (SELECT 1 FROM public.order_payments op
                   WHERE op.order_id = o.id AND op.status = 'verified'
                     AND op.metadata ->> 'payment_attempt_id' = pa.id::text)
ORDER BY pa.buyer_claimed_at;

-- H21 (038, SA-SEC-003 / SA-SEC-008): product-images policies. Expected: no product_images_public_read;
--      product_images_seller_read for authenticated (own folder); insert/update mention is_seller_approved.
SELECT policyname, cmd, roles::text AS roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'product_images_%'
ORDER BY policyname;

-- H22 (038, SA-PAY-011): verified references that collide after normalisation (upper case, no spaces).
--      Expected: no rows. Rows here are one bank transfer recorded for two orders — review with the seller.
SELECT public.normalize_payment_reference(op.reference_id) AS normalised_reference,
       array_agg(o.order_code ORDER BY op.verified_at) AS order_codes,
       sum(op.amount_paisa) AS amount_paisa_total
FROM public.order_payments op JOIN public.orders o ON o.id = op.order_id
WHERE op.status = 'verified' AND public.normalize_payment_reference(op.reference_id) IS NOT NULL
GROUP BY 1 HAVING count(*) > 1;

-- H23 (038, SA-ONB-002): live drops of sellers who are not approved. Expected: no rows.
SELECT d.id AS drop_id, d.slug, d.seller_id
FROM public.drops d JOIN public.profiles p ON p.id = d.seller_id
WHERE d.status = 'live' AND p.is_approved IS NOT TRUE;

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
