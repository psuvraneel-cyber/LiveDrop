-- LiveDrop Migration: 041_seller_push_notifications.sql
-- Description: SA-NOT-001 — push notifications to the seller app (ADR-015).
--
--   Sellers had no notifications at all: a buyer's payment claim during a live could sit unseen.
--   This migration adds the database half of Firebase Cloud Messaging delivery:
--
--     seller_push_tokens   one row per installed app (FCM registration token) of a seller;
--                          written only through register_push_token / unregister_push_token.
--     profiles.notify_new_orders / notify_payment_claims
--                          the seller's choices (Settings > Notifications), set through
--                          set_notification_prefs.
--     push_outbox          messages waiting to be sent. Filled by triggers:
--                            * a new order on one of the seller's drops      (notify_new_orders)
--                            * a buyer submits a UTR (on time or late)       (notify_payment_claims)
--                          Never readable or writable by clients.
--     claim_push_batch / complete_push
--                          used only by the push-dispatch Edge Function (service_role), which
--                          sends the messages through FCM HTTP v1.
--     ping_push_dispatch   wakes the Edge Function through pg_net right after a message is queued;
--                          a pg_cron job calls it every minute as a backstop.
--
--   Where pg_net / pg_cron are not available (local test clusters) the queue still fills and the
--   wake-up is skipped; nothing fails. Messages contain order codes and amounts, never buyer phone
--   numbers or addresses.
--
-- Rules: SECURITY DEFINER functions pin search_path = public, pg_temp; RLS on every new table;
-- money in integer paisa. Idempotent.
--
-- Regression suite: audit/seller-app/tests/sql/23_push_notifications.sql.

-- ============================================================================
-- 1. Preferences
-- ============================================================================
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS notify_new_orders BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS notify_payment_claims BOOLEAN NOT NULL DEFAULT TRUE;
GRANT SELECT (notify_new_orders, notify_payment_claims) ON public.profiles TO authenticated;

CREATE OR REPLACE FUNCTION public.set_notification_prefs(
    p_new_orders BOOLEAN,
    p_payment_claims BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;
    UPDATE profiles
       SET notify_new_orders = COALESCE(p_new_orders, notify_new_orders),
           notify_payment_claims = COALESCE(p_payment_claims, notify_payment_claims),
           updated_at = NOW()
     WHERE id = auth.uid();
    RETURN jsonb_build_object('success', true,
        'notify_new_orders', (SELECT notify_new_orders FROM profiles WHERE id = auth.uid()),
        'notify_payment_claims', (SELECT notify_payment_claims FROM profiles WHERE id = auth.uid()));
END;
$$;

-- ============================================================================
-- 2. Device tokens
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.seller_push_tokens (
    token TEXT PRIMARY KEY CHECK (char_length(token) BETWEEN 20 AND 4096),
    seller_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    platform TEXT NOT NULL DEFAULT 'android' CHECK (platform IN ('android', 'ios', 'web')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_seller_push_tokens_seller ON public.seller_push_tokens (seller_id);

ALTER TABLE public.seller_push_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.seller_push_tokens FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.seller_push_tokens TO authenticated;
DROP POLICY IF EXISTS seller_push_tokens_owner_read ON public.seller_push_tokens;
CREATE POLICY seller_push_tokens_owner_read ON public.seller_push_tokens
    FOR SELECT TO authenticated USING (seller_id = auth.uid());

-- A token belongs to the phone; if another seller signs in on the same phone it moves to them.
CREATE OR REPLACE FUNCTION public.register_push_token(p_token TEXT, p_platform TEXT DEFAULT 'android')
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_token TEXT := trim(COALESCE(p_token, ''));
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;
    IF char_length(v_token) < 20 OR char_length(v_token) > 4096 THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_TOKEN');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid()) THEN
        RETURN jsonb_build_object('success', false, 'error', 'SELLER_NOT_FOUND');
    END IF;
    INSERT INTO seller_push_tokens (token, seller_id, platform, created_at, last_seen_at)
    VALUES (v_token, auth.uid(), COALESCE(NULLIF(p_platform, ''), 'android'), NOW(), NOW())
    ON CONFLICT (token) DO UPDATE
       SET seller_id = EXCLUDED.seller_id,
           platform = EXCLUDED.platform,
           last_seen_at = NOW();
    RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.unregister_push_token(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;
    DELETE FROM seller_push_tokens WHERE token = p_token AND seller_id = auth.uid();
    RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- 3. Outbox
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.push_outbox (
    id BIGSERIAL PRIMARY KEY,
    seller_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('new_order', 'payment_claim', 'late_claim')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    attempts INT NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at TIMESTAMPTZ,
    last_error TEXT
);
CREATE INDEX IF NOT EXISTS idx_push_outbox_pending ON public.push_outbox (next_attempt_at) WHERE sent_at IS NULL;

ALTER TABLE public.push_outbox ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.push_outbox FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.push_outbox_id_seq FROM PUBLIC, anon, authenticated;

-- Where the Edge Function lives (hosted project). Kept in a table so a staging project can change it.
CREATE TABLE IF NOT EXISTS public.app_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_config FROM PUBLIC, anon, authenticated;
INSERT INTO public.app_config (key, value)
VALUES ('push_dispatch_url', 'https://aoagqdtnrbmayfoajzes.supabase.co/functions/v1/push-dispatch')
ON CONFLICT (key) DO NOTHING;

-- pg_net, when available, lets the database wake the Edge Function at once.
DO $do$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_net') THEN
        BEGIN
            CREATE EXTENSION IF NOT EXISTS pg_net;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE '041: pg_net could not be enabled (% %); push wake-up relies on the pg_cron backstop.', SQLSTATE, SQLERRM;
        END;
    ELSE
        RAISE NOTICE '041: pg_net not available here; push messages are queued but not dispatched.';
    END IF;
END
$do$;

-- Wakes the dispatcher when something is waiting. Never fails the caller.
CREATE OR REPLACE FUNCTION public.ping_push_dispatch()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_url TEXT;
BEGIN
    IF to_regnamespace('net') IS NULL THEN
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM push_outbox WHERE sent_at IS NULL AND attempts < 5 AND next_attempt_at <= NOW()) THEN
        RETURN;
    END IF;
    SELECT value INTO v_url FROM app_config WHERE key = 'push_dispatch_url';
    IF v_url IS NULL THEN
        RETURN;
    END IF;
    EXECUTE 'SELECT net.http_post(url := $1, body := $2, headers := $3)'
      USING v_url, '{"source":"db"}'::jsonb, '{"Content-Type":"application/json"}'::jsonb;
EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'ping_push_dispatch failed: % %', SQLSTATE, SQLERRM;
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_seller_push(
    p_seller UUID, p_kind TEXT, p_title TEXT, p_body TEXT, p_data JSONB
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO push_outbox (seller_id, kind, title, body, data)
    VALUES (p_seller, p_kind, p_title, p_body, COALESCE(p_data, '{}'::jsonb));
    PERFORM public.ping_push_dispatch();
END;
$$;

CREATE OR REPLACE FUNCTION public.rupees_label(p_paisa BIGINT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
    SELECT '₹' || to_char(p_paisa / 100, 'FM99999999') ||
           CASE WHEN p_paisa % 100 = 0 THEN '' ELSE '.' || lpad((p_paisa % 100)::text, 2, '0') END;
$$;

-- New order on one of the seller's drops.
CREATE OR REPLACE FUNCTION public.push_on_new_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_seller UUID;
    v_wants BOOLEAN;
    v_pieces INT;
BEGIN
    SELECT d.seller_id, p.notify_new_orders INTO v_seller, v_wants
      FROM drops d JOIN profiles p ON p.id = d.seller_id
     WHERE d.id = NEW.drop_id;
    IF v_seller IS NULL OR v_wants IS NOT TRUE THEN
        RETURN NEW;
    END IF;
    PERFORM public.enqueue_seller_push(
        v_seller, 'new_order',
        'New order #' || NEW.order_code,
        rupees_label(NEW.total_paisa) || ' reserved. Waiting for the buyer''s payment.',
        jsonb_build_object('type', 'new_order', 'order_id', NEW.id, 'order_code', NEW.order_code));
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- A notification must never block an order.
    RAISE LOG 'push_on_new_order failed: % %', SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_on_new_order ON public.orders;
CREATE TRIGGER trg_push_on_new_order
    AFTER INSERT ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.push_on_new_order();

-- A buyer submitted a UTR (on time or late): the seller has to check it.
CREATE OR REPLACE FUNCTION public.push_on_payment_claim()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_seller UUID;
    v_wants BOOLEAN;
    v_code TEXT;
    v_late BOOLEAN := NEW.status = 'late_claim_pending_review';
BEGIN
    IF NEW.status NOT IN ('awaiting_seller_verification', 'late_claim_pending_review')
       OR NEW.buyer_claimed_at IS NULL
       OR (OLD.buyer_claimed_at IS NOT DISTINCT FROM NEW.buyer_claimed_at
           AND OLD.buyer_submitted_utr IS NOT DISTINCT FROM NEW.buyer_submitted_utr) THEN
        RETURN NEW;   -- not a new claim (e.g. the reaper moving a claim to late review)
    END IF;
    SELECT d.seller_id, p.notify_payment_claims, o.order_code INTO v_seller, v_wants, v_code
      FROM orders o JOIN drops d ON d.id = o.drop_id JOIN profiles p ON p.id = d.seller_id
     WHERE o.id = NEW.order_id;
    IF v_seller IS NULL OR v_wants IS NOT TRUE THEN
        RETURN NEW;
    END IF;
    PERFORM public.enqueue_seller_push(
        v_seller, CASE WHEN v_late THEN 'late_claim' ELSE 'payment_claim' END,
        CASE WHEN v_late THEN 'Late payment for #' ELSE 'Payment to check for #' END || v_code,
        rupees_label(NEW.expected_amount_paisa) || ' claimed. Check your bank app, then verify or reject.',
        jsonb_build_object('type', 'payment_claim', 'order_id', NEW.order_id, 'order_code', v_code,
                           'payment_attempt_id', NEW.id, 'late', v_late));
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'push_on_payment_claim failed: % %', SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_push_on_payment_claim ON public.payment_attempts;
CREATE TRIGGER trg_push_on_payment_claim
    AFTER UPDATE OF status, buyer_claimed_at, buyer_submitted_utr ON public.payment_attempts
    FOR EACH ROW EXECUTE FUNCTION public.push_on_payment_claim();

-- ============================================================================
-- 4. Dispatcher API (service_role only)
-- ============================================================================
-- Hands out up to p_limit due messages with their device tokens. Each claimed message gets its next
-- attempt pushed back, so a crashed dispatcher run is retried later; at most 5 attempts.
CREATE OR REPLACE FUNCTION public.claim_push_batch(p_limit INT DEFAULT 50)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_result JSONB;
BEGIN
    WITH due AS (
        SELECT id FROM push_outbox
         WHERE sent_at IS NULL AND attempts < 5 AND next_attempt_at <= NOW()
         ORDER BY id
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200)
         FOR UPDATE SKIP LOCKED
    ), claimed AS (
        UPDATE push_outbox o
           SET attempts = o.attempts + 1,
               next_attempt_at = NOW() + make_interval(mins => o.attempts + 1)
          FROM due WHERE o.id = due.id
        RETURNING o.*
    )
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'id', c.id, 'kind', c.kind, 'title', c.title, 'body', c.body, 'data', c.data,
               'tokens', COALESCE((SELECT jsonb_agg(t.token) FROM seller_push_tokens t WHERE t.seller_id = c.seller_id), '[]'::jsonb))
             ORDER BY c.id), '[]'::jsonb)
      INTO v_result
      FROM claimed c;
    RETURN v_result;
END;
$$;

-- Records the outcome of one message and forgets tokens FCM reported as no longer registered.
CREATE OR REPLACE FUNCTION public.complete_push(
    p_id BIGINT, p_sent BOOLEAN, p_error TEXT DEFAULT NULL, p_dead_tokens TEXT[] DEFAULT '{}'
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE push_outbox
       SET sent_at = CASE WHEN p_sent THEN NOW() ELSE sent_at END,
           last_error = CASE WHEN p_sent THEN NULL ELSE left(p_error, 500) END
     WHERE id = p_id;
    IF p_dead_tokens IS NOT NULL AND array_length(p_dead_tokens, 1) > 0 THEN
        DELETE FROM seller_push_tokens WHERE token = ANY(p_dead_tokens);
    END IF;
END;
$$;

-- pg_cron backstop: wake the dispatcher every minute when something is due.
DO $do$
DECLARE
    v_job_id BIGINT;
BEGIN
    IF to_regnamespace('cron') IS NULL THEN
        RAISE NOTICE '041: pg_cron not available; push backstop not scheduled.';
        RETURN;
    END IF;
    BEGIN
        FOR v_job_id IN EXECUTE 'SELECT jobid FROM cron.job WHERE jobname = $1' USING 'livedrop-push-dispatch' LOOP
            EXECUTE 'SELECT cron.unschedule($1)' USING v_job_id;
        END LOOP;
        EXECUTE 'SELECT cron.schedule($1, $2, $3)'
        USING 'livedrop-push-dispatch', '* * * * *', 'SELECT public.ping_push_dispatch();';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '041: could not schedule the push backstop (% %).', SQLSTATE, SQLERRM;
    END;
END
$do$;

-- ============================================================================
-- 5. Privileges
-- ============================================================================
REVOKE ALL ON FUNCTION public.set_notification_prefs(BOOLEAN, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_notification_prefs(BOOLEAN, BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION public.register_push_token(TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_push_token(TEXT, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.unregister_push_token(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unregister_push_token(TEXT) TO authenticated;

REVOKE ALL ON FUNCTION public.claim_push_batch(INT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_push_batch(INT) TO service_role;
REVOKE ALL ON FUNCTION public.complete_push(BIGINT, BOOLEAN, TEXT, TEXT[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_push(BIGINT, BOOLEAN, TEXT, TEXT[]) TO service_role;

REVOKE ALL ON FUNCTION public.ping_push_dispatch() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enqueue_seller_push(UUID, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.push_on_new_order() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.push_on_payment_claim() FROM PUBLIC, anon, authenticated;
