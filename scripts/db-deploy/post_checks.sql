-- LiveDrop database deploy — POST-DEPLOY CHECKS (read-only, aggregate output only).
-- Mirrors audit/seller-app/tests/sql/90_hosted_readonly_checks.sql H1, H7, H8, H14, H16–H19
-- plus counts for H11/H13/H15/H20. Output is safe for public Actions logs (no personal data).
-- Exits non-zero (ON_ERROR_STOP + RAISE) when a security expectation fails.
\set ON_ERROR_STOP on
\pset footer off
\if :{?strict_cron}
\else
\set strict_cron off
\endif
SET livedrop.strict_cron = :'strict_cron';

\echo '== H1: grants on public_seller_storefronts (expected: SELECT only)'
SELECT grantee, string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'public_seller_storefronts'
  AND grantee IN ('anon', 'authenticated')
GROUP BY grantee ORDER BY grantee;

\echo '== H14: write privileges of anon/authenticated on any public view (expected: 0)'
SELECT count(*) AS view_write_privileges
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN (VALUES ('anon'), ('authenticated')) AS g(rolname)
CROSS JOIN unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) AS pr(p)
WHERE n.nspname = 'public' AND c.relkind = 'v' AND has_table_privilege(g.rolname, c.oid, pr.p);

\echo '== H16: internal helpers not callable by clients; record_refund for sellers only'
SELECT has_function_privilege('anon', 'public.release_stale_hold(uuid)', 'EXECUTE') AS release_stale_hold_anon,
       has_function_privilege('authenticated', 'public.release_stale_hold(uuid)', 'EXECUTE') AS release_stale_hold_auth,
       has_function_privilege('anon', 'public.record_refund(uuid,text,text)', 'EXECUTE') AS record_refund_anon,
       has_function_privilege('authenticated', 'public.record_refund(uuid,text,text)', 'EXECUTE') AS record_refund_auth;

DO $$
DECLARE v_bad int; v_view text; v_role text;
BEGIN
  -- Every public view: client roles hold nothing but SELECT (H14, incl. REFERENCES/TRIGGER).
  SELECT count(*) INTO v_bad
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  CROSS JOIN (VALUES ('anon'), ('authenticated')) AS g(rolname)
  CROSS JOIN unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) AS pr(p)
  WHERE n.nspname = 'public' AND c.relkind = 'v' AND has_table_privilege(g.rolname, c.oid, pr.p);
  IF v_bad > 0 THEN RAISE EXCEPTION 'CHECK FAILED (SA-SEC-001): % non-SELECT privileges remain on public views', v_bad; END IF;

  -- H1: the buyer-facing projection views must stay readable by both client roles.
  FOREACH v_view IN ARRAY ARRAY['public.public_seller_storefronts', 'public.public_products_catalog'] LOOP
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      IF to_regclass(v_view) IS NULL OR NOT has_table_privilege(v_role, v_view, 'SELECT') THEN
        RAISE EXCEPTION 'CHECK FAILED (H1): % cannot SELECT %', v_role, v_view;
      END IF;
    END LOOP;
  END LOOP;

  -- H16: function privilege matrix.
  IF to_regprocedure('public.record_refund(uuid,text,text)') IS NULL
     OR to_regprocedure('public.release_stale_hold(uuid)') IS NULL
     OR to_regprocedure('public.apply_upi_payment_transition(uuid,uuid,text,text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'CHECK FAILED: migration 035 functions missing';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.record_refund(uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CHECK FAILED (H16): sellers cannot execute record_refund';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
    IF has_function_privilege(v_role, 'public.release_stale_hold(uuid)', 'EXECUTE')
       OR has_function_privilege(v_role, 'public.apply_upi_payment_transition(uuid,uuid,text,text,uuid)', 'EXECUTE') THEN
      RAISE EXCEPTION 'CHECK FAILED (H16): % can execute an internal helper', v_role;
    END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.record_refund(uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CHECK FAILED (H16): anon can execute record_refund';
  END IF;
  IF to_regprocedure('public.resolve_free_shipping_threshold(uuid)') IS NULL THEN
    RAISE NOTICE 'migration 037 not applied yet (resolve_free_shipping_threshold missing)';
  ELSIF NOT has_function_privilege('anon', 'public.resolve_free_shipping_threshold(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CHECK FAILED (037): buyers cannot execute resolve_free_shipping_threshold';
  ELSE
    RAISE NOTICE 'PASS 037 present (free-shipping rule + 30-minute live claim hold)';
  END IF;
  RAISE NOTICE 'PASS security checks (H1/H14/H16)';
END $$;

\echo '== H21/H22: migration 038 (storage policies, suspension trigger, UTR guards)'
SELECT policyname, cmd, roles::text AS roles,
       (coalesce(qual, '') || coalesce(with_check, '')) LIKE '%is_seller_approved%' AS requires_approval
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'product_images_%'
ORDER BY policyname;
DO $$
DECLARE v_strict boolean := current_setting('livedrop.strict_cron') IN ('on', 'true', '1'); v_dupes int;
BEGIN
  IF to_regprocedure('public.close_drop_safely(uuid)') IS NULL THEN
    RAISE NOTICE 'migration 038 not applied yet (close_drop_safely missing)';
    RETURN;
  END IF;
  -- H21 (SA-SEC-003 / SA-SEC-008)
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
               AND policyname = 'product_images_public_read')
     OR (SELECT count(*) FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
           AND policyname IN ('product_images_seller_insert', 'product_images_seller_update')
           AND (coalesce(qual, '') || coalesce(with_check, '')) LIKE '%is_seller_approved%') <> 2 THEN
    IF v_strict THEN
      RAISE EXCEPTION 'CHECK FAILED (H21, SA-SEC-003/SA-SEC-008): product-images storage policies not updated — run section 1 of migration 038 in the Supabase SQL editor';
    END IF;
    RAISE WARNING 'H21: product-images storage policies not updated yet';
  ELSE
    RAISE NOTICE 'PASS H21 storage: no public listing; uploads need an approved seller';
  END IF;
  -- H22 (SA-ONB-002, SA-PAY-011)
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_close_live_drops_on_suspension' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CHECK FAILED (H22, SA-ONB-002): suspension trigger missing';
  END IF;
  IF has_function_privilege('anon', 'public.close_drop_safely(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.close_drop_safely(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CHECK FAILED (H22): close_drop_safely is callable by clients';
  END IF;
  IF to_regclass('public.uq_order_payments_reference_verified_norm') IS NULL THEN
    SELECT count(*) INTO v_dupes FROM (
      SELECT public.normalize_payment_reference(reference_id) FROM public.order_payments
       WHERE status = 'verified' AND public.normalize_payment_reference(reference_id) IS NOT NULL
       GROUP BY 1 HAVING count(*) > 1) d;
    RAISE WARNING 'H22 (SA-PAY-011): unique index on normalised verified references missing; % duplicate reference group(s) need review (see 90_hosted_readonly_checks.sql H22)', v_dupes;
  ELSE
    RAISE NOTICE 'PASS H22 suspension trigger, helper privileges and normalised UTR index';
  END IF;
  -- Approved = false while a drop is live should be impossible after 038.
  IF EXISTS (SELECT 1 FROM public.drops d JOIN public.profiles p ON p.id = d.seller_id
              WHERE d.status = 'live' AND p.is_approved IS NOT TRUE) THEN
    RAISE WARNING 'H22: a live drop belongs to a seller who is not approved (close it with close_drop)';
  END IF;
END $$;

\echo '== H24: migration 039 (drop lifecycle, payee change guard, offline-sale undo)'
DO $$
BEGIN
  IF to_regprocedure('public.undo_mark_product_sold_offline(uuid)') IS NULL THEN
    RAISE NOTICE 'migration 039 not applied yet (undo_mark_product_sold_offline missing)';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_enforce_drop_lifecycle' AND NOT tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_guard_and_log_payee_change' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'CHECK FAILED (H24): drop lifecycle or payee change trigger missing';
  END IF;
  IF has_function_privilege('anon', 'public.undo_mark_product_sold_offline(uuid)', 'EXECUTE')
     OR has_table_privilege('anon', 'public.payee_change_log', 'SELECT')
     OR has_table_privilege('authenticated', 'public.payee_change_log', 'INSERT')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.payee_change_log'::regclass) THEN
    RAISE EXCEPTION 'CHECK FAILED (H24): 039 privileges are wrong';
  END IF;
  RAISE NOTICE 'PASS H24 drop lifecycle, payee change guard and log, offline-sale undo';
END $$;
SELECT count(*) AS h24_payee_changes_last_30_days FROM public.payee_change_log WHERE changed_at > now() - interval '30 days';

\echo '== H25: migration 040 (seller_sales_summary for analytics)'
DO $$
BEGIN
  IF to_regprocedure('public.seller_sales_summary(timestamptz,integer)') IS NULL THEN
    RAISE NOTICE 'migration 040 not applied yet (seller_sales_summary missing; the app falls back to local analytics)';
  ELSIF has_function_privilege('anon', 'public.seller_sales_summary(timestamptz,integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.seller_sales_summary(timestamptz,integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CHECK FAILED (H25): seller_sales_summary privileges are wrong';
  ELSE
    RAISE NOTICE 'PASS H25 seller_sales_summary: sellers only';
  END IF;
END $$;

\echo '== H26: migration 041 (push notifications)'
DO $$
BEGIN
  IF to_regprocedure('public.claim_push_batch(integer)') IS NULL THEN
    RAISE NOTICE 'migration 041 not applied yet';
  ELSIF has_table_privilege('authenticated', 'public.push_outbox', 'SELECT')
     OR has_function_privilege('authenticated', 'public.claim_push_batch(integer)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.register_push_token(text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CHECK FAILED (H26): push notification privileges are wrong';
  ELSE
    RAISE NOTICE 'PASS H26 push: outbox private, dispatcher API service-only, pg_net=% cron job=%',
      to_regnamespace('net') IS NOT NULL,
      (to_regclass('cron.job') IS NOT NULL);
  END IF;
END $$;
SELECT count(*) FILTER (WHERE sent_at IS NULL) AS h26_push_pending, count(*) FILTER (WHERE sent_at IS NULL AND attempts >= 5) AS h26_push_failed FROM public.push_outbox;

\echo '== H27: migration 042 (operator console)'
DO $$
BEGIN
  IF to_regprocedure('public.admin_set_seller_approval(uuid,boolean,text)') IS NULL THEN
    RAISE NOTICE 'migration 042 not applied yet';
  ELSIF has_table_privilege('authenticated', 'public.platform_admins', 'SELECT')
     OR has_table_privilege('authenticated', 'public.admin_actions', 'SELECT')
     OR has_function_privilege('anon', 'public.admin_list_sellers(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.admin_write_denied()', 'EXECUTE')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.platform_admins'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.admin_actions'::regclass) THEN
    RAISE EXCEPTION 'CHECK FAILED (H27): operator console privileges are wrong';
  ELSE
    RAISE NOTICE 'PASS H27 admin console: tables private with RLS, RPCs signed-in only, helpers internal';
  END IF;
END $$;
SELECT count(*) AS h27_platform_admins FROM public.platform_admins;

\echo '== H28: migration 043 (UPI link for personal UPI IDs)'
DO $$
DECLARE u text := public.generate_upi_payment_uri('check@okaxis', 'A #1 & Co 100%', 100, 'REF-1', 'LiveDrop LD-ABC123 advance');
BEGIN
  IF u LIKE '%&tr=%' THEN
    RAISE NOTICE 'migration 043 not applied yet (link still carries tr)';
  ELSIF u <> 'upi://pay?pa=check@okaxis&pn=A%201%20Co%20100&am=1.00&cu=INR&tn=LiveDrop%20LD-ABC123%20advance' THEN
    RAISE EXCEPTION 'CHECK FAILED (H28): unexpected UPI link %', u;
  ELSE
    RAISE NOTICE 'PASS H28 UPI link: plain P2P form, no merchant fields, name sanitised';
  END IF;
END $$;

\echo '== H29: migration 044 (order receipt WhatsApp number)'
DO $$
BEGIN
  IF position('whatsapp_number' IN pg_get_functiondef('public.get_order_by_token(text)'::regprocedure)) = 0 THEN
    RAISE NOTICE 'migration 044 not applied yet';
  ELSE
    RAISE NOTICE 'PASS H29 order receipt includes the seller WhatsApp number';
  END IF;
END $$;

\echo '== H30: migration 045 (admin dashboard analytics)'
DO $$
BEGIN
  IF to_regclass('public.site_page_views') IS NULL THEN
    RAISE NOTICE 'migration 045 not applied yet';
  ELSIF has_table_privilege('anon', 'public.site_page_views', 'SELECT')
     OR has_table_privilege('authenticated', 'public.site_page_views', 'SELECT')
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.site_page_views'::regclass)
     OR NOT has_function_privilege('anon', 'public.log_page_view(uuid,text,text,text,text,boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_traffic(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'CHECK FAILED (H30): analytics privileges are wrong';
  ELSE
    RAISE NOTICE 'PASS H30 analytics: page views private with RLS, logging anon-only via RPC, reports admin-only';
  END IF;
END $$;
SELECT count(*) AS h30_page_views_last_24h FROM public.site_page_views WHERE created_at > NOW() - INTERVAL '24 hours';

\echo '== H7: realtime publication (expected: orders, payment_attempts, products)'
SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' ORDER BY 1;

\echo '== H8/H17: pg_cron and the reaper job (expected: one active job, every minute)'
SELECT name, installed_version FROM pg_available_extensions WHERE name = 'pg_cron';
DO $$
DECLARE r record; n int := 0; v_strict boolean := current_setting('livedrop.strict_cron') IN ('on', 'true', '1');
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    IF v_strict THEN RAISE EXCEPTION 'CHECK FAILED (SA-OPS-001): pg_cron is not installed — enable it in Supabase (Database -> Extensions) and re-run apply'; END IF;
    RAISE WARNING 'pg_cron is not installed yet';
    RETURN;
  END IF;
  FOR r IN EXECUTE $q$SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'livedrop-release-expired-holds'$q$ LOOP
    n := n + 1;
    RAISE NOTICE 'cron job % schedule=% active=%', r.jobname, r.schedule, r.active;
    IF v_strict AND (NOT r.active OR r.schedule <> '* * * * *') THEN
      RAISE EXCEPTION 'CHECK FAILED (SA-OPS-001): reaper job is inactive or not every minute';
    END IF;
  END LOOP;
  IF n <> 1 THEN
    IF v_strict THEN RAISE EXCEPTION 'CHECK FAILED (SA-OPS-001): expected exactly one reaper job, found %', n; END IF;
    RAISE WARNING 'reaper job count is % (expected 1)', n;
  END IF;
  FOR r IN EXECUTE $q$SELECT status, start_time FROM cron.job_run_details
                     WHERE jobid IN (SELECT jobid FROM cron.job WHERE jobname = 'livedrop-release-expired-holds')
                     ORDER BY start_time DESC LIMIT 5$q$ LOOP
    RAISE NOTICE 'reaper run % at %', r.status, r.start_time;
  END LOOP;
  IF n = 1 THEN RAISE NOTICE 'PASS reaper schedule (H17)'; END IF;
END $$;

\echo '== H18/H19: holds and claims (counts only)'
SELECT
  (SELECT count(*) FROM public.orders o
    WHERE o.status = 'pending' AND o.hold_expires_at < now() - interval '2 minutes'
      AND NOT EXISTS (SELECT 1 FROM public.payment_attempts pa WHERE pa.order_id = o.id
                        AND pa.status IN ('buyer_claimed','awaiting_seller_verification','late_claim_pending_review'))) AS h18_expired_unclaimed_holds,
  (SELECT count(*) FROM public.payment_attempts pa
    WHERE pa.status IN ('buyer_claimed','awaiting_seller_verification','late_claim_pending_review')
      AND coalesce(pa.verification_expires_at, pa.expires_at) < now()) AS h19_overdue_claims;

\echo '== Owner review counts (details: run H11/H13/H15/H20 from 90_hosted_readonly_checks.sql in the SQL editor)'
SELECT
  (SELECT count(*) FROM (SELECT o.id FROM public.orders o LEFT JOIN public.order_payments op
                           ON op.order_id = o.id AND op.status = 'verified'
                         GROUP BY o.id, o.total_paid_paisa
                         HAVING o.total_paid_paisa <> COALESCE(SUM(op.amount_paisa), 0)) x) AS h11_orders_paid_total_differs_from_ledger,
  (SELECT count(*) FROM public.orders WHERE refund_status = 'required') AS h15_refunds_owed,
  (SELECT count(*) FROM public.payment_attempts pa
    WHERE pa.status = 'expired' AND pa.buyer_submitted_utr IS NOT NULL AND pa.seller_verified_at IS NULL) AS h20_claims_expired_by_old_reaper;
