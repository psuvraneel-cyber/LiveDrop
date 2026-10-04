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
  RAISE NOTICE 'PASS security checks (H1/H14/H16)';
END $$;

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
