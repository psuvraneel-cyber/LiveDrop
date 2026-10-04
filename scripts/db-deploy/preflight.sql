-- LiveDrop database deploy — PREFLIGHT (read-only).
-- Confirms the target is a LiveDrop database at migration 033+ and reports which of
-- 034–036 are already present. Prints only catalog facts and counts (Actions logs of a
-- public repository are public: never select personal data here).
\set ON_ERROR_STOP on
\pset footer off

SELECT current_setting('server_version') AS server_version, current_user AS deploy_role;

DO $$
BEGIN
  IF to_regclass('public.public_seller_storefronts') IS NULL OR to_regclass('public.payment_attempts') IS NULL THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: this does not look like a LiveDrop database at migration 033 (public_seller_storefronts / payment_attempts missing).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='payment_attempts' AND column_name='verification_expires_at') THEN
    RAISE EXCEPTION 'PREFLIGHT FAILED: migration 014 is missing (payment_attempts.verification_expires_at). Apply 001–033 first.';
  END IF;
END $$;

-- 035 state: 'none' (not applied), 'complete' (column + all four functions), anything else = partial.
SELECT CASE
         WHEN NOT has_col AND n_fn = 0 THEN 'none'
         WHEN has_col AND n_fn = 4 THEN 'complete'
         ELSE 'partial'
       END AS m035_state,
       (SELECT installed_version FROM pg_available_extensions WHERE name='pg_cron') AS pg_cron_installed_version,
       EXISTS (SELECT 1 FROM pg_available_extensions WHERE name='pg_cron') AS pg_cron_available,
       to_regclass('supabase_migrations.schema_migrations') IS NOT NULL AS has_migration_history
FROM (SELECT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema='public' AND table_name='orders' AND column_name='refund_status') AS has_col,
             (to_regprocedure('public.record_refund(uuid,text,text)') IS NOT NULL)::int
           + (to_regprocedure('public.release_stale_hold(uuid)') IS NOT NULL)::int
           + (to_regprocedure('public.apply_upi_payment_transition(uuid,uuid,text,text,uuid)') IS NOT NULL)::int
           + EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.orders'::regclass
                       AND pg_get_constraintdef(oid) ILIKE '%refund_status%') ::int AS n_fn) x
\gset
\echo m035_state=:m035_state

SELECT :'m035_state' = 'partial' AS m035_partial \gset
\if :m035_partial
DO $$ BEGIN
  RAISE EXCEPTION 'PREFLIGHT FAILED: migration 035 is partially present (refund column/functions/constraint incomplete). Investigate before deploying.';
END $$;
\endif

SELECT count(*) AS orders_total,
       count(*) FILTER (WHERE status = 'pending' AND hold_expires_at < now()) AS expired_holds_still_pending
FROM public.orders;
