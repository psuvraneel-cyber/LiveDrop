-- =============================================================================
-- Suite 22 — P1 round 4c regression checks (migration 040, SA-PERF-001)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
--
-- seller_sales_summary must give the figures the app used to compute in Dart, only for the
-- calling seller's own orders (RLS), and must not be callable by anon.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

-- Orders inserted directly as postgres (the fixture path); statuses as the RPCs would leave them.
CREATE OR REPLACE FUNCTION pg_temp.order_with_item(
    p_drop uuid, p_product uuid, p_status text, p_total int, p_paid int,
    p_created timestamptz, p_paid_at timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE o uuid;
BEGIN
  INSERT INTO orders (drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
                      subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
                      advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
                      payment_status, fulfilment_status, status, hold_expires_at, created_at, paid_at)
  VALUES (p_drop, 'LD-' || upper(substr(md5(random()::text), 1, 6)), 'Ananya Roy', '9830045678',
          '14 Lansdowne Road, Kolkata', '700020', p_total, 0, p_total, 'full_payment',
          0, 0, p_paid, p_total - p_paid,
          CASE WHEN p_paid >= p_total THEN 'paid' ELSE 'unpaid' END,
          CASE WHEN p_status = 'shipped' THEN 'shipped' ELSE 'not_ready' END,
          p_status, now() + interval '1 day', p_created, p_paid_at)
  RETURNING id INTO o;
  INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa) VALUES (o, p_product, p_total);
  RETURN o;
END $$;

DO $$
DECLARE s jsonb; s_b jsonb; days jsonb; today_total bigint; anon_err text;
BEGIN
  -- seller A: two paid orders this week (one a minute ago, so it is "today" at any hour), one shipped last month, one pending hold
  PERFORM pg_temp.order_with_item(audit.drop_a_live(), audit.p_a1(), 'paid',    150000, 150000, now() - interval '1 minute', now() - interval '1 minute');
  PERFORM pg_temp.order_with_item(audit.drop_a_live(), audit.p_a2(), 'shipped', 250000, 250000, now() - interval '2 days', now() - interval '2 days');
  PERFORM pg_temp.order_with_item(audit.drop_a_live(), audit.p_a3(), 'shipped',  50000,  50000, now() - interval '40 days', now() - interval '40 days');
  PERFORM pg_temp.order_with_item(audit.drop_a_live(), audit.p_a3(), 'pending',  50000,      0, now() - interval '5 minutes');
  -- seller B: one paid order (must never show in A's summary)
  PERFORM pg_temp.order_with_item(audit.drop_b_live(), audit.p_b1(), 'paid',    100000, 100000, now() - interval '1 hour', now() - interval '1 hour');

  PERFORM audit.as_seller(audit.seller_a());
  s := seller_sales_summary(now() - interval '7 days', 330);
  PERFORM audit.as_seller(audit.seller_b());
  s_b := seller_sales_summary(now() - interval '7 days', 330);
  PERFORM audit.as_postgres();

  RAISE NOTICE '%', audit.check('22.1', (s->>'total_revenue_paisa')::bigint = 400000 AND (s->>'items_sold')::int = 2,
                                format('seller A last 7 days: revenue=%s items=%s (expected 400000 / 2)', s->>'total_revenue_paisa', s->>'items_sold'));
  RAISE NOTICE '%', audit.check('22.2', (s->>'active_holds')::int = 1, format('active holds=%s (expected 1)', s->>'active_holds'));
  RAISE NOTICE '%', audit.check('22.3', (s_b->>'total_revenue_paisa')::bigint = 100000,
                                format('seller B sees only its own sales: revenue=%s', s_b->>'total_revenue_paisa'));
  days := s->'daily';
  SELECT (d->>'total_paisa')::bigint INTO today_total FROM jsonb_array_elements(days) d ORDER BY d->>'date' DESC LIMIT 1;
  RAISE NOTICE '%', audit.check('22.4', jsonb_array_length(days) = 7 AND today_total >= 150000,
                                format('daily buckets=%s, today=%s', jsonb_array_length(days), today_total));
  RAISE NOTICE '%', audit.check('22.5', jsonb_array_length(s->'top_products') = 2
                                         AND s->'top_products'->0->>'code' IN ('#A01', '#A02'),
                                format('top products=%s', s->'top_products'));

  BEGIN
    PERFORM audit.as_anon();
    PERFORM seller_sales_summary(now() - interval '7 days', 330);
    anon_err := 'callable';
  EXCEPTION WHEN insufficient_privilege THEN
    anon_err := 'permission denied';
  END;
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('22.6', anon_err = 'permission denied', 'anon cannot execute seller_sales_summary: ' || anon_err);
  RAISE NOTICE '%', audit.check('22.7', octet_length(s::text) < 4000,
                                format('summary payload %s bytes (the app used to download every order)', octet_length(s::text)));
END $$;

ROLLBACK;
