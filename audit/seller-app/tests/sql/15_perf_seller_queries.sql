-- =============================================================================
-- Suite 15 — cost of the seller app's unpaginated queries under RLS (local)
-- AUDIT-ONLY. Seeds a season of data for one seller inside a transaction,
-- times the exact query shapes the app issues, then rolls back.
-- Numbers are from a dev host; absolute values differ on Supabase, the growth
-- curve (everything is O(all rows ever)) is the point.
-- =============================================================================
\set ON_ERROR_STOP 1
\timing off
BEGIN;
SELECT audit.seed();

-- 20 drops x 100 pieces, ~3,000 orders, 1-2 items each, one attempt each
INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa)
SELECT gen_random_uuid(), audit.seller_a(), 'Season drop ' || g, 'season-drop-' || g, 'closed', 8000
FROM generate_series(1, 20) g;

INSERT INTO products (drop_id, code, title, price_paisa, size, image_url, status)
SELECT d.id, '#S' || lpad(g::text, 3, '0'), 'Saree ' || g, 100000 + g * 100, 'Free Size', 'https://x/p.jpg', 'sold'
FROM drops d CROSS JOIN generate_series(1, 100) g
WHERE d.seller_id = audit.seller_a() AND d.slug LIKE 'season-drop-%';

CREATE TEMP TABLE t_orders AS
SELECT gen_random_uuid() AS id, p.drop_id, p.id AS product_id, p.price_paisa, row_number() OVER () AS n
FROM products p JOIN drops d ON d.id = p.drop_id
WHERE d.slug LIKE 'season-drop-%';

INSERT INTO orders (id, drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
                    subtotal_paisa, shipping_paisa, total_paisa, status, confirmation_mode,
                    total_paid_paisa, balance_due_paisa, payment_status, fulfilment_status, hold_expires_at, created_at)
SELECT id, drop_id, 'LD-' || lpad(upper(to_hex(n)), 6, '0'), 'Buyer ' || n, '98300' || lpad((n % 100000)::text, 5, '0'),
       n || ' Park Street, Kolkata', '700016', price_paisa, 8000, price_paisa + 8000,
       CASE WHEN n % 10 = 0 THEN 'cancelled' ELSE 'shipped' END, 'full_payment',
       CASE WHEN n % 10 = 0 THEN 0 ELSE price_paisa + 8000 END,
       CASE WHEN n % 10 = 0 THEN price_paisa + 8000 ELSE 0 END,
       CASE WHEN n % 10 = 0 THEN 'unpaid' ELSE 'paid' END,
       CASE WHEN n % 10 = 0 THEN 'not_ready' ELSE 'shipped' END,
       now() - interval '1 day', now() - (n || ' minutes')::interval
FROM t_orders;

INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
SELECT id, product_id, price_paisa FROM t_orders;

INSERT INTO payment_attempts (order_id, payment_type, expected_amount_paisa, payee_vpa_snapshot, transaction_reference, status, expires_at)
SELECT id, 'full', price_paisa + 8000, 'aarohi@okaxis', 'REF-' || n, CASE WHEN n % 10 = 0 THEN 'expired' ELSE 'verified' END, now()
FROM t_orders;

ANALYZE;

DO $$
DECLARE t0 timestamptz; ms numeric; n int; bytes bigint;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());

  -- SellerRepository.getAllOrders() — no drop filter, no limit, nested items + products
  t0 := clock_timestamp();
  SELECT count(*), sum(length(j::text)) INTO n, bytes FROM (
    SELECT to_jsonb(o) || jsonb_build_object('order_items', (
      SELECT coalesce(jsonb_agg(to_jsonb(oi) || jsonb_build_object('products',
               (SELECT jsonb_build_object('code', p.code, 'title', p.title, 'image_url', p.image_url) FROM products p WHERE p.id = oi.product_id))), '[]')
      FROM order_items oi WHERE oi.order_id = o.id)) AS j
    FROM orders o ORDER BY o.created_at DESC) s;
  ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
  RAISE NOTICE 'INFO 15.1 getAllOrders(): % orders, ~% KB JSON, % ms (called by Dashboard x2, Kanban, Analytics, Shipping shortcut, every realtime event)', n, round(bytes/1024.0), round(ms);

  -- SA-PERF-001 (fixed in round 4c): the app now asks for the newest 300 orders at most, and
  -- analytics come from seller_sales_summary (migration 040) instead of the full download above.
  t0 := clock_timestamp();
  SELECT count(*), sum(length(j::text)) INTO n, bytes FROM (
    SELECT to_jsonb(o) || jsonb_build_object('order_items', (
      SELECT coalesce(jsonb_agg(to_jsonb(oi) || jsonb_build_object('products',
               (SELECT jsonb_build_object('code', p.code, 'title', p.title, 'image_url', p.image_url) FROM products p WHERE p.id = oi.product_id))), '[]')
      FROM order_items oi WHERE oi.order_id = o.id)) AS j
    FROM orders o ORDER BY o.created_at DESC LIMIT 300) s;
  ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
  RAISE NOTICE '% 15.1b getAllOrders(limit 300): % orders, ~% KB JSON, % ms',
    CASE WHEN n <= 300 THEN 'PASS' ELSE 'FAIL' END, n, round(bytes/1024.0), round(ms);

  IF to_regprocedure('public.seller_sales_summary(timestamptz,integer)') IS NOT NULL THEN
    t0 := clock_timestamp();
    SELECT length(seller_sales_summary(now() - interval '30 days', 330)::text) INTO bytes;
    ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
    RAISE NOTICE '% 15.1c seller_sales_summary (analytics): % bytes, % ms (was the full download above)',
      CASE WHEN bytes < 8192 THEN 'PASS' ELSE 'FAIL' END, bytes, round(ms);
  END IF;

  -- SellerRepository.getPendingVerifications() — RLS EXISTS join per attempt
  t0 := clock_timestamp();
  SELECT count(*) INTO n FROM payment_attempts pa JOIN orders o ON o.id = pa.order_id
   WHERE pa.status IN ('buyer_claimed','awaiting_seller_verification','late_claim_pending_review');
  ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
  RAISE NOTICE 'INFO 15.2 getPendingVerifications(): % rows, % ms', n, round(ms, 1);

  -- SellerRepository.getProducts(dropId) for one drop
  t0 := clock_timestamp();
  SELECT count(*) INTO n FROM products WHERE drop_id = audit.drop_a_live();
  ms := extract(epoch FROM clock_timestamp() - t0) * 1000;
  RAISE NOTICE 'INFO 15.3 getProducts(liveDrop): % rows, % ms', n, round(ms, 1);

  PERFORM audit.as_postgres();
END $$;

-- Plan of the RLS-filtered order list (what PostgREST executes for the seller)
SELECT audit.as_seller(audit.seller_a());
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT o.id, o.order_code, o.status FROM orders o ORDER BY o.created_at DESC;
SELECT audit.as_postgres();

ROLLBACK;
