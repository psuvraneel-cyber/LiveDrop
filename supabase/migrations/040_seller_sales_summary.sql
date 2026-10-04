-- LiveDrop Migration: 040_seller_sales_summary.sql
-- Description: P1 fix from the seller-app audit (audit/seller-app/), round 4c.
--
--   SA-PERF-001  The seller app downloaded every order of the seller, with nested items and
--                products, and computed analytics in Dart on the UI thread: about 2.4 MB of JSON per
--                season on every analytics open. seller_sales_summary computes the same figures in
--                the database and returns a few hundred bytes.
--
-- SECURITY INVOKER: row-level security on orders / order_items / products decides what is counted,
-- so a seller only ever sees their own sales. search_path is pinned anyway.
-- Money is integer paisa. Idempotent.
--
-- Figures (same rules as the app's previous Dart computation in getSellerAnalytics):
--   total_revenue_paisa  paid or shipped orders created at/after p_from: total_paid_paisa
--                        (total_paisa when nothing is recorded as paid)
--   items_sold           order items of those orders
--   active_holds         order items of pending or confirmed orders (any date)
--   top_products         those orders' items grouped by product code, most sold first (max 10)
--   daily                the last 7 local days (p_utc_offset_minutes), paid or shipped orders by
--                        COALESCE(paid_at, created_at)
--
-- Regression suite: audit/seller-app/tests/sql/22_p1_round4c.sql; cost in 15_perf_seller_queries.sql.

CREATE OR REPLACE FUNCTION public.seller_sales_summary(
    p_from TIMESTAMPTZ,
    p_utc_offset_minutes INT DEFAULT 330
)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
WITH sold AS (
    SELECT o.id, o.created_at, o.paid_at,
           CASE WHEN o.total_paid_paisa > 0 THEN o.total_paid_paisa ELSE o.total_paisa END AS amount_paisa
      FROM orders o
     WHERE o.status IN ('paid', 'shipped')
),
in_range AS (
    SELECT * FROM sold WHERE created_at >= p_from
),
range_items AS (
    SELECT oi.price_at_purchase_paisa, p.code, p.title, p.image_url
      FROM in_range r
      JOIN order_items oi ON oi.order_id = r.id
      LEFT JOIN products p ON p.id = oi.product_id
),
local_today AS (
    SELECT ((clock_timestamp() AT TIME ZONE 'UTC') + make_interval(mins => p_utc_offset_minutes))::date AS d
),
days AS (
    SELECT (lt.d - g)::date AS day FROM local_today lt, generate_series(6, 0, -1) AS g
)
SELECT jsonb_build_object(
    'total_revenue_paisa', COALESCE((SELECT sum(amount_paisa) FROM in_range), 0)::bigint,
    'items_sold', (SELECT count(*) FROM range_items),
    'active_holds', (SELECT count(*)
                       FROM orders o JOIN order_items oi ON oi.order_id = o.id
                      WHERE o.status IN ('pending', 'confirmed')),
    'top_products', COALESCE((
        SELECT jsonb_agg(t ORDER BY t.sold_count DESC, t.code)
          FROM (SELECT COALESCE(code, 'Piece') AS code,
                       COALESCE(max(title), COALESCE(code, 'Piece')) AS title,
                       count(*) AS sold_count,
                       sum(price_at_purchase_paisa)::bigint AS revenue_paisa,
                       max(image_url) AS image_url
                  FROM range_items
                 GROUP BY COALESCE(code, 'Piece')
                 ORDER BY count(*) DESC, COALESCE(code, 'Piece')
                 LIMIT 10) t
    ), '[]'::jsonb),
    'daily', (
        SELECT jsonb_agg(jsonb_build_object('date', d.day, 'total_paisa', COALESCE(x.total, 0)) ORDER BY d.day)
          FROM days d
          LEFT JOIN (
              SELECT ((COALESCE(s.paid_at, s.created_at) AT TIME ZONE 'UTC') + make_interval(mins => p_utc_offset_minutes))::date AS day,
                     sum(s.amount_paisa)::bigint AS total
                FROM sold s
               GROUP BY 1
          ) x ON x.day = d.day
    )
);
$$;

REVOKE ALL ON FUNCTION public.seller_sales_summary(TIMESTAMPTZ, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.seller_sales_summary(TIMESTAMPTZ, INT) TO authenticated, service_role;
