-- LiveDrop Migration: 045_admin_dashboard_analytics.sql
-- Description: operator dashboard — traffic history, live drops, sales and payments needing
-- attention (owner request 2026-10-06, ADR-017).
--
--   site_page_views      anonymous page views from the buyer website, written only through
--                        log_page_view. A row holds a random per-browser visitor id, the kind of
--                        page, the drop slug, the traffic source, a coarse device type and whether
--                        that browser has ordered before. No IP address, user agent, name, phone or
--                        order id. Kept 180 days (pg_cron job; cleanup function otherwise).
--   log_page_view        anon/authenticated; validates every field and ignores a repeat of the
--                        same visitor/page/drop within 30 seconds.
--   admin_traffic / admin_live_drops / admin_sales_overview / admin_payment_attention
--                        platform admins only (is_platform_admin, migration 042); read-only.
--
--   Live visitor counts are not stored: the website announces anonymous presence on a Supabase
--   Realtime channel and /admin counts it in the browser.
--
-- Rules: SECURITY DEFINER functions pin search_path = public, pg_temp; RLS on the new table with no
-- client privileges; money in integer paisa. Idempotent.
--
-- Regression suite: audit/seller-app/tests/sql/26_admin_dashboard.sql.

-- ============================================================================
-- 1. Anonymous page views
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.site_page_views (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    visitor_id UUID NOT NULL,
    page_kind TEXT NOT NULL CHECK (page_kind IN ('home', 'shop', 'store', 'drop', 'cart', 'checkout', 'order', 'legal', 'other')),
    drop_slug TEXT CHECK (drop_slug IS NULL OR drop_slug ~ '^[a-z0-9][a-z0-9-]{0,79}$'),
    source TEXT NOT NULL CHECK (source IN ('whatsapp', 'facebook', 'instagram', 'google', 'direct', 'other')),
    device TEXT NOT NULL CHECK (device IN ('mobile', 'tablet', 'desktop')),
    returning_buyer BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.site_page_views ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.site_page_views FROM PUBLIC, anon, authenticated;
CREATE INDEX IF NOT EXISTS idx_site_page_views_created ON public.site_page_views (created_at);
CREATE INDEX IF NOT EXISTS idx_site_page_views_visitor ON public.site_page_views (visitor_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.log_page_view(
    p_visitor_id UUID,
    p_page_kind TEXT,
    p_drop_slug TEXT DEFAULT NULL,
    p_source TEXT DEFAULT 'direct',
    p_device TEXT DEFAULT 'mobile',
    p_returning_buyer BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_slug TEXT := NULLIF(lower(trim(COALESCE(p_drop_slug, ''))), '');
BEGIN
    IF p_visitor_id IS NULL
       OR p_page_kind NOT IN ('home', 'shop', 'store', 'drop', 'cart', 'checkout', 'order', 'legal', 'other')
       OR COALESCE(p_source, '') NOT IN ('whatsapp', 'facebook', 'instagram', 'google', 'direct', 'other')
       OR COALESCE(p_device, '') NOT IN ('mobile', 'tablet', 'desktop')
       OR (v_slug IS NOT NULL AND v_slug !~ '^[a-z0-9][a-z0-9-]{0,79}$') THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INPUT');
    END IF;

    -- A reload or double render within 30 seconds is the same view.
    IF EXISTS (
        SELECT 1 FROM site_page_views
         WHERE visitor_id = p_visitor_id AND page_kind = p_page_kind
           AND drop_slug IS NOT DISTINCT FROM v_slug
           AND created_at > NOW() - INTERVAL '30 seconds'
    ) THEN
        RETURN jsonb_build_object('success', true, 'deduplicated', true);
    END IF;

    INSERT INTO site_page_views (visitor_id, page_kind, drop_slug, source, device, returning_buyer)
    VALUES (p_visitor_id, p_page_kind, v_slug, p_source, p_device, COALESCE(p_returning_buyer, false));
    RETURN jsonb_build_object('success', true, 'deduplicated', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.purge_old_page_views()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    DELETE FROM site_page_views WHERE created_at < NOW() - INTERVAL '180 days';
    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

DO $do$
DECLARE
    v_job_id BIGINT;
BEGIN
    IF to_regnamespace('cron') IS NULL THEN
        RAISE NOTICE '045: pg_cron not available; page-view retention not scheduled.';
        RETURN;
    END IF;
    BEGIN
        FOR v_job_id IN EXECUTE 'SELECT jobid FROM cron.job WHERE jobname = $1' USING 'livedrop-purge-page-views' LOOP
            EXECUTE 'SELECT cron.unschedule($1)' USING v_job_id;
        END LOOP;
        EXECUTE 'SELECT cron.schedule($1, $2, $3)'
        USING 'livedrop-purge-page-views', '15 21 * * *', 'SELECT public.purge_old_page_views();';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '045: could not schedule page-view retention (% %).', SQLSTATE, SQLERRM;
    END;
END
$do$;

-- ============================================================================
-- 2. Admin read RPCs (platform admins only)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_denied()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT CASE WHEN public.is_platform_admin() THEN NULL
                ELSE jsonb_build_object('success', false, 'error', 'UNAUTHORIZED',
                                        'message', 'Only LiveDrop administrators can do this.') END;
$$;

-- Visitors and page views per day (IST), by source, device, page and drop.
CREATE OR REPLACE FUNCTION public.admin_traffic(p_days INT DEFAULT 7)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_denied JSONB := public.admin_denied();
    v_days INT := LEAST(GREATEST(COALESCE(p_days, 7), 1), 180);
    v_from TIMESTAMPTZ;
BEGIN
    IF v_denied IS NOT NULL THEN RETURN v_denied; END IF;
    v_from := date_trunc('day', NOW() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata' - make_interval(days => v_days - 1);

    RETURN jsonb_build_object(
        'success', true,
        'days', v_days,
        'totals', (SELECT jsonb_build_object(
                       'visitors', count(DISTINCT visitor_id),
                       'page_views', count(*),
                       'returning_buyer_visitors', count(DISTINCT visitor_id) FILTER (WHERE returning_buyer))
                     FROM site_page_views WHERE created_at >= v_from),
        'daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d::date, 'visitors', COALESCE(t.visitors, 0),
                                                               'page_views', COALESCE(t.views, 0)) ORDER BY d), '[]'::jsonb)
                    FROM generate_series((v_from AT TIME ZONE 'Asia/Kolkata')::date,
                                         (NOW() AT TIME ZONE 'Asia/Kolkata')::date, INTERVAL '1 day') d
                    LEFT JOIN (SELECT (created_at AT TIME ZONE 'Asia/Kolkata')::date AS day,
                                      count(DISTINCT visitor_id) AS visitors, count(*) AS views
                                 FROM site_page_views WHERE created_at >= v_from GROUP BY 1) t ON t.day = d::date),
        'by_source', (SELECT COALESCE(jsonb_agg(jsonb_build_object('source', source, 'visitors', n) ORDER BY n DESC), '[]'::jsonb)
                        FROM (SELECT source, count(DISTINCT visitor_id) AS n FROM site_page_views
                               WHERE created_at >= v_from GROUP BY source) s),
        'by_device', (SELECT COALESCE(jsonb_agg(jsonb_build_object('device', device, 'visitors', n) ORDER BY n DESC), '[]'::jsonb)
                        FROM (SELECT device, count(DISTINCT visitor_id) AS n FROM site_page_views
                               WHERE created_at >= v_from GROUP BY device) s),
        'by_page', (SELECT COALESCE(jsonb_agg(jsonb_build_object('page', page_kind, 'views', n) ORDER BY n DESC), '[]'::jsonb)
                      FROM (SELECT page_kind, count(*) AS n FROM site_page_views
                             WHERE created_at >= v_from GROUP BY page_kind) s),
        'top_drops', (SELECT COALESCE(jsonb_agg(jsonb_build_object('drop_slug', drop_slug, 'visitors', n) ORDER BY n DESC), '[]'::jsonb)
                        FROM (SELECT drop_slug, count(DISTINCT visitor_id) AS n FROM site_page_views
                               WHERE created_at >= v_from AND drop_slug IS NOT NULL
                               GROUP BY drop_slug ORDER BY n DESC LIMIT 10) s)
    );
END;
$$;

-- Every live drop now: stock, last-hour orders and verified money, payments waiting.
CREATE OR REPLACE FUNCTION public.admin_live_drops()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_denied JSONB := public.admin_denied();
BEGIN
    IF v_denied IS NOT NULL THEN RETURN v_denied; END IF;
    RETURN jsonb_build_object('success', true, 'drops', (
        SELECT COALESCE(jsonb_agg(x ORDER BY x.live_started_at DESC NULLS LAST), '[]'::jsonb) FROM (
            SELECT d.id, d.title, d.slug, d.live_started_at, p.store_name, p.store_slug,
                   (SELECT count(*) FROM products pr WHERE pr.drop_id = d.id AND pr.status = 'available') AS available,
                   (SELECT count(*) FROM products pr WHERE pr.drop_id = d.id AND pr.status = 'reserved') AS held,
                   (SELECT count(*) FROM products pr WHERE pr.drop_id = d.id AND pr.status = 'sold') AS sold,
                   (SELECT count(*) FROM orders o WHERE o.drop_id = d.id AND o.created_at > NOW() - INTERVAL '1 hour') AS orders_last_hour,
                   (SELECT COALESCE(sum(a.expected_amount_paisa), 0) FROM payment_attempts a JOIN orders o ON o.id = a.order_id
                     WHERE o.drop_id = d.id AND a.status = 'verified' AND a.seller_verified_at > NOW() - INTERVAL '1 hour') AS verified_paisa_last_hour,
                   (SELECT count(*) FROM payment_attempts a JOIN orders o ON o.id = a.order_id
                     WHERE o.drop_id = d.id AND a.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')) AS payments_waiting
              FROM drops d JOIN profiles p ON p.id = d.seller_id
             WHERE d.status = 'live'
        ) x));
END;
$$;

-- Orders and verified money over a period, top sellers and products, visitor → order conversion.
CREATE OR REPLACE FUNCTION public.admin_sales_overview(p_days INT DEFAULT 7)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_denied JSONB := public.admin_denied();
    v_days INT := LEAST(GREATEST(COALESCE(p_days, 7), 1), 365);
    v_from TIMESTAMPTZ;
    v_orders BIGINT;
    v_visitors BIGINT;
BEGIN
    IF v_denied IS NOT NULL THEN RETURN v_denied; END IF;
    v_from := date_trunc('day', NOW() AT TIME ZONE 'Asia/Kolkata') AT TIME ZONE 'Asia/Kolkata' - make_interval(days => v_days - 1);
    SELECT count(*) INTO v_orders FROM orders WHERE created_at >= v_from;
    SELECT count(DISTINCT visitor_id) INTO v_visitors FROM site_page_views WHERE created_at >= v_from;

    RETURN jsonb_build_object(
        'success', true,
        'days', v_days,
        'orders', v_orders,
        'paid_orders', (SELECT count(*) FROM orders WHERE created_at >= v_from AND payment_status IN ('advance_paid', 'paid')),
        'cancelled_orders', (SELECT count(*) FROM orders WHERE created_at >= v_from AND status = 'cancelled'),
        'verified_paisa', (SELECT COALESCE(sum(expected_amount_paisa), 0) FROM payment_attempts
                            WHERE status = 'verified' AND seller_verified_at >= v_from),
        'refunds_owed_paisa', (SELECT COALESCE(sum(refund_amount_paisa), 0) FROM orders WHERE refund_status = 'required'),
        'visitors', v_visitors,
        'conversion_pct', CASE WHEN v_visitors > 0 THEN round(100.0 * v_orders / v_visitors, 1) ELSE NULL END,
        'daily', (SELECT COALESCE(jsonb_agg(jsonb_build_object('date', d::date, 'orders', COALESCE(o.n, 0),
                                                               'verified_paisa', COALESCE(v.paisa, 0)) ORDER BY d), '[]'::jsonb)
                    FROM generate_series((v_from AT TIME ZONE 'Asia/Kolkata')::date,
                                         (NOW() AT TIME ZONE 'Asia/Kolkata')::date, INTERVAL '1 day') d
                    LEFT JOIN (SELECT (created_at AT TIME ZONE 'Asia/Kolkata')::date AS day, count(*) AS n
                                 FROM orders WHERE created_at >= v_from GROUP BY 1) o ON o.day = d::date
                    LEFT JOIN (SELECT (seller_verified_at AT TIME ZONE 'Asia/Kolkata')::date AS day, sum(expected_amount_paisa) AS paisa
                                 FROM payment_attempts WHERE status = 'verified' AND seller_verified_at >= v_from GROUP BY 1) v
                           ON v.day = d::date),
        'top_sellers', (SELECT COALESCE(jsonb_agg(s ORDER BY s.verified_paisa DESC), '[]'::jsonb) FROM (
                            SELECT p.store_name, p.store_slug, count(DISTINCT o.id) AS orders,
                                   COALESCE(sum(a.expected_amount_paisa) FILTER (WHERE a.status = 'verified'), 0) AS verified_paisa
                              FROM orders o JOIN drops d ON d.id = o.drop_id JOIN profiles p ON p.id = d.seller_id
                              LEFT JOIN payment_attempts a ON a.order_id = o.id AND a.seller_verified_at >= v_from
                             WHERE o.created_at >= v_from
                             GROUP BY p.store_name, p.store_slug ORDER BY verified_paisa DESC LIMIT 10) s),
        'top_products', (SELECT COALESCE(jsonb_agg(t ORDER BY t.sold DESC), '[]'::jsonb) FROM (
                            SELECT pr.code, pr.title, p.store_name, count(*) AS sold, sum(oi.price_at_purchase_paisa) AS revenue_paisa
                              FROM order_items oi JOIN orders o ON o.id = oi.order_id
                              JOIN products pr ON pr.id = oi.product_id JOIN drops d ON d.id = o.drop_id
                              JOIN profiles p ON p.id = d.seller_id
                             WHERE o.created_at >= v_from AND o.payment_status IN ('advance_paid', 'paid')
                             GROUP BY pr.code, pr.title, p.store_name ORDER BY sold DESC LIMIT 10) t)
    );
END;
$$;

-- Payments the platform should chase: claims waiting long, late claims, refunds owed, rejections.
CREATE OR REPLACE FUNCTION public.admin_payment_attention()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_denied JSONB := public.admin_denied();
BEGIN
    IF v_denied IS NOT NULL THEN RETURN v_denied; END IF;
    RETURN jsonb_build_object(
        'success', true,
        'waiting', (SELECT COALESCE(jsonb_agg(x ORDER BY x.claimed_at), '[]'::jsonb) FROM (
                        SELECT o.order_code, p.store_name, a.payment_type, a.expected_amount_paisa, a.status,
                               COALESCE(a.buyer_claimed_at, a.updated_at) AS claimed_at,
                               round(extract(epoch FROM NOW() - COALESCE(a.buyer_claimed_at, a.updated_at)) / 60)::int AS minutes_waiting
                          FROM payment_attempts a JOIN orders o ON o.id = a.order_id
                          JOIN drops d ON d.id = o.drop_id JOIN profiles p ON p.id = d.seller_id
                         WHERE a.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
                         ORDER BY claimed_at LIMIT 100) x),
        'refunds_owed', (SELECT COALESCE(jsonb_agg(x ORDER BY x.refund_required_at NULLS LAST), '[]'::jsonb) FROM (
                        SELECT o.order_code, p.store_name, o.refund_amount_paisa, o.refund_reason, o.refund_required_at
                          FROM orders o JOIN drops d ON d.id = o.drop_id JOIN profiles p ON p.id = d.seller_id
                         WHERE o.refund_status = 'required' LIMIT 100) x),
        'recently_rejected', (SELECT COALESCE(jsonb_agg(x ORDER BY x.updated_at DESC), '[]'::jsonb) FROM (
                        SELECT o.order_code, p.store_name, a.expected_amount_paisa, a.rejection_reason, a.updated_at
                          FROM payment_attempts a JOIN orders o ON o.id = a.order_id
                          JOIN drops d ON d.id = o.drop_id JOIN profiles p ON p.id = d.seller_id
                         WHERE a.status = 'rejected' AND a.updated_at > NOW() - INTERVAL '7 days'
                         ORDER BY a.updated_at DESC LIMIT 50) x)
    );
END;
$$;

-- ============================================================================
-- 3. Privileges
-- ============================================================================
REVOKE ALL ON FUNCTION public.log_page_view(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.log_page_view(UUID, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.purge_old_page_views() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_old_page_views() TO service_role;
REVOKE ALL ON FUNCTION public.admin_denied() FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.admin_traffic(INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_traffic(INT) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_live_drops() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_live_drops() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_sales_overview(INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_sales_overview(INT) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_payment_attention() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_payment_attention() TO authenticated;
