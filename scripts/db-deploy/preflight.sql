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

SELECT
  EXISTS (SELECT 1 FROM information_schema.columns
          WHERE table_schema='public' AND table_name='orders' AND column_name='refund_status') AS m035_already_applied,
  (SELECT installed_version FROM pg_available_extensions WHERE name='pg_cron') AS pg_cron_installed_version,
  EXISTS (SELECT 1 FROM pg_available_extensions WHERE name='pg_cron') AS pg_cron_available,
  to_regclass('supabase_migrations.schema_migrations') IS NOT NULL AS has_migration_history;

SELECT count(*) AS orders_total,
       count(*) FILTER (WHERE status = 'pending' AND hold_expires_at < now()) AS expired_holds_still_pending
FROM public.orders;
