-- LiveDrop Migration: 036_schedule_reaper_in_database.sql
-- Description: SA-OPS-001 — run the hold reaper inside the database every minute.
--
--   release_expired_holds() used to be triggered only by a GitHub Actions schedule
--   (.github/workflows/reaper-cron.yml, cron */5), which GitHub ran roughly five times a day.
--   Expired holds kept unique pieces off sale for hours. Migration 035 adds lazy expiry inside
--   create_order_with_reservation; this migration adds the authoritative schedule:
--
--     pg_cron job 'livedrop-release-expired-holds', every minute: SELECT public.release_expired_holds();
--
--   The reaper never waits for row locks (SKIP LOCKED) and never touches orders with a buyer
--   payment claim, so overlapping runs (pg_cron + the GitHub Actions backup trigger) are safe.
--
--   Where pg_cron is not available (local test clusters, PGlite) this migration is a no-op that
--   only raises a NOTICE; it never fails the migration run. The GitHub Actions workflow remains as
--   a backup trigger.
--
-- Verification on a hosted project (read-only):
--   SELECT jobname, schedule, command, active FROM cron.job WHERE jobname = 'livedrop-release-expired-holds';
--   SELECT status, start_time, end_time, return_message FROM cron.job_run_details
--    WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'livedrop-release-expired-holds')
--    ORDER BY start_time DESC LIMIT 5;

DO $do$
DECLARE
    v_job_id BIGINT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron') THEN
        RAISE NOTICE '036_schedule_reaper_in_database: pg_cron is not available on this server; in-database reaper schedule skipped (lazy expiry in create_order_with_reservation and the external trigger still apply).';
        RETURN;
    END IF;

    BEGIN
        -- Supabase installs pg_cron into pg_catalog (its objects live in schema cron).
        CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

        -- Replace any previous definition of the job (idempotent re-run).
        FOR v_job_id IN
            EXECUTE 'SELECT jobid FROM cron.job WHERE jobname = $1'
            USING 'livedrop-release-expired-holds'
        LOOP
            EXECUTE 'SELECT cron.unschedule($1)' USING v_job_id;
        END LOOP;

        EXECUTE 'SELECT cron.schedule($1, $2, $3)'
        USING 'livedrop-release-expired-holds', '* * * * *', 'SELECT public.release_expired_holds();';

        RAISE NOTICE '036_schedule_reaper_in_database: pg_cron job livedrop-release-expired-holds scheduled every minute.';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '036_schedule_reaper_in_database: could not schedule the reaper with pg_cron (% %); skipped. Enable pg_cron for this project and re-run this migration.',
            SQLSTATE, SQLERRM;
    END;
END
$do$;
