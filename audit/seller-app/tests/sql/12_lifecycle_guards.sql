-- =============================================================================
-- Suite 12 — drop / product / order lifecycle guards as seen by the seller app
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text);
GRANT ALL ON t_ctx TO anon, authenticated, service_role;

-- helper: run a statement as seller A and report SQLSTATE
CREATE OR REPLACE FUNCTION pg_temp.try_as_a(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());
  BEGIN
    EXECUTE p_sql;
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM audit.as_postgres();
    RETURN 'OK rows=' || n;
  EXCEPTION WHEN OTHERS THEN
    PERFORM audit.as_postgres();
    RETURN 'ERR ' || SQLSTATE || ' ' || left(SQLERRM, 110);
  END;
END $$;

-- 12.1 product codes produced/accepted by the seller app vs the DB CHECK '^#[A-Z0-9]{1,6}$'
DO $$
DECLARE c text; r text;
BEGIN
  FOREACH c IN ARRAY ARRAY['#A04', 'A05', '#SAREE01', '#a06', '#A-07', '#'] LOOP
    r := pg_temp.try_as_a(format(
      'INSERT INTO products (drop_id, code, title, price_paisa, size, image_url) VALUES (%L, %L, %L, 1000, %L, %L)',
      audit.drop_a_draft(), upper(c), 'Code test', 'M', 'https://x/c.jpg'));
    RAISE NOTICE 'INFO 12.1 createProduct(code=%) after app uppercasing -> %', c, r;
  END LOOP;
END $$;

-- 12.2 direct status/price mutations from the app's authenticated role
DO $$
BEGIN
  RAISE NOTICE 'INFO 12.2a direct UPDATE products price -> %', pg_temp.try_as_a(format('UPDATE products SET price_paisa = 1 WHERE id = %L', audit.p_a3()));
  RAISE NOTICE 'INFO 12.2b direct UPDATE products status sold -> %', pg_temp.try_as_a(format('UPDATE products SET status = %L WHERE id = %L', 'sold', audit.p_a3()));
  RAISE NOTICE 'INFO 12.2c direct DELETE available product -> %', pg_temp.try_as_a(format('DELETE FROM products WHERE id = %L', audit.p_a3()));
END $$;

-- 12.3 products inserted directly with non-initial states (no INSERT trigger)
DO $$
DECLARE r1 text; r2 text;
BEGIN
  r1 := pg_temp.try_as_a(format('INSERT INTO products (drop_id, code, title, price_paisa, size, image_url, status) VALUES (%L, %L, %L, 1000, %L, %L, %L)',
        audit.drop_a_live(), '#X01', 'Born sold', 'M', 'https://x/x.jpg', 'sold'));
  r2 := pg_temp.try_as_a(format('INSERT INTO products (drop_id, code, title, price_paisa, size, image_url, status) VALUES (%L, %L, %L, 1000, %L, %L, %L)',
        audit.drop_a_live(), '#X02', 'Born reserved', 'M', 'https://x/x.jpg', 'reserved'));
  RAISE NOTICE '% 12.3 seller can INSERT product already sold (%) / reserved with no order (%)',
    CASE WHEN r1 LIKE 'OK%' OR r2 LIKE 'OK%' THEN 'FINDING' ELSE 'PASS' END, r1, r2;
END $$;

-- 12.4 drop status machine via direct UPDATE (what DropsListScreen does)
DO $$
BEGIN
  RAISE NOTICE 'INFO 12.4a live -> closed direct UPDATE -> %', pg_temp.try_as_a(format('UPDATE drops SET status=%L WHERE id=%L', 'closed', audit.drop_a_live()));
  -- SA-DROP-002 (fixed in 039): the slug is locked once the drop has gone live.
  RAISE NOTICE '%', (SELECT CASE WHEN r LIKE 'ERR 42501%' THEN 'PASS' ELSE 'FINDING' END || ' 12.4c slug change on LIVE drop -> ' || r
                       FROM (SELECT pg_temp.try_as_a(format('UPDATE drops SET slug=%L WHERE id=%L', 'renamed-mid-live', audit.drop_a_live())) AS r) x);
  RAISE NOTICE '%', (SELECT CASE WHEN r LIKE 'OK%' THEN 'PASS' ELSE 'FAIL' END || ' 12.4c2 slug change on DRAFT drop (control) -> ' || r
                       FROM (SELECT pg_temp.try_as_a(format('UPDATE drops SET slug=%L WHERE id=%L', 'aarohi-next-week-v2', audit.drop_a_draft())) AS r) x);
  RAISE NOTICE 'INFO 12.4d second live drop for same seller -> %', pg_temp.try_as_a(format('UPDATE drops SET status=%L, live_started_at=now() WHERE id=%L', 'live', audit.drop_a_draft()));
END $$;

-- 12.5 close via RPC, then "Re-open Draft" and go live again (SA-DROP-001, fixed in 039: forbidden).
--      Uses its own drop for seller D so seller A's live drop stays live for later cases.
DO $$
DECLARE r jsonb; s1 text; s2 text; d uuid := 'dddd0000-0000-0000-0000-000000000005';
BEGIN
  INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa) VALUES (d, audit.seller_d(), 'D one-off', 'd-one-off', 'draft', 8000);
  PERFORM audit.as_seller(audit.seller_d());
  BEGIN UPDATE drops SET status = 'live', live_started_at = now() WHERE id = d; END;
  r := close_drop(d);
  BEGIN UPDATE drops SET status = 'draft' WHERE id = d; s1 := 'OK';
  EXCEPTION WHEN OTHERS THEN s1 := 'ERR ' || SQLSTATE || ' ' || left(SQLERRM, 60); END;
  BEGIN UPDATE drops SET status = 'live', live_started_at = now() WHERE id = d; s2 := 'OK';
  EXCEPTION WHEN OTHERS THEN s2 := 'ERR ' || SQLSTATE || ' ' || left(SQLERRM, 60); END;
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 12.5 close_drop=% then closed->draft=% then closed->live=%',
    CASE WHEN (r->>'success')::boolean AND s1 LIKE 'ERR 42501%' AND s2 LIKE 'ERR 42501%' THEN 'PASS'
         WHEN s1 LIKE 'OK%' OR s2 LIKE 'OK%' THEN 'FINDING' ELSE 'FAIL' END, r->>'success', s1, s2;
  s1 := pg_temp.try_as_a(format('UPDATE drops SET status=%L WHERE id=%L', 'draft', audit.drop_a_live()));
  RAISE NOTICE '% 12.4b live -> draft direct UPDATE (unpublish without releasing holds) -> %',
    CASE WHEN s1 LIKE 'ERR 42501%' THEN 'PASS' ELSE 'FINDING' END, s1;
END $$;

-- 12.6 approval gate: unapproved seller C
DO $$
DECLARE r1 text; r2 text; r3 text;
BEGIN
  PERFORM audit.as_seller(audit.seller_c());
  BEGIN
    INSERT INTO drops (id, seller_id, title, slug, status) VALUES ('cccc0000-0000-0000-0000-000000000001', audit.seller_c(), 'C draft', 'c-draft', 'draft');
    r1 := 'OK';
  EXCEPTION WHEN OTHERS THEN r1 := 'ERR ' || SQLSTATE; END;
  BEGIN
    INSERT INTO products (drop_id, code, title, price_paisa, size, image_url) VALUES ('cccc0000-0000-0000-0000-000000000001', '#C01', 'C item', 1000, 'M', 'https://x/c.jpg');
    r2 := 'OK';
  EXCEPTION WHEN OTHERS THEN r2 := 'ERR ' || SQLSTATE; END;
  BEGIN
    UPDATE drops SET status = 'live' WHERE id = 'cccc0000-0000-0000-0000-000000000001';
    r3 := 'OK';
  EXCEPTION WHEN OTHERS THEN r3 := 'ERR ' || SQLSTATE || ' ' || SQLERRM; END;
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 12.6 unapproved seller: create draft=% add product=% go live=%',
    CASE WHEN r3 LIKE 'ERR 42501%' THEN 'PASS' ELSE 'FAIL' END, r1, r2, r3;
END $$;

-- 12.7 suspension: revoke approval of seller B while its drop is live, then a buyer checks out
DO $$
DECLARE r jsonb; adm jsonb; vis int;
BEGIN
  PERFORM audit.as_service();
  adm := admin_approve_seller(audit.seller_b(), false);
  PERFORM audit.as_anon();
  SELECT count(*) INTO vis FROM public_products_catalog WHERE drop_id = audit.drop_b_live();
  r := create_order_with_reservation(audit.drop_b_live(), ARRAY[audit.p_b1()], 'Suspension Test', '9830099999',
                                     '1 Test Lane, Kolkata', '700001', 'full_payment', NULL);
  PERFORM audit.as_postgres();
  -- SA-ONB-002 (fixed in 038): suspension closes the live drop; checkout is refused.
  RAISE NOTICE '% 12.7 after admin_approve_seller(B,false)=%: catalog rows visible=% checkout=% (drop status=%)',
    CASE WHEN (r->>'success')::boolean THEN 'FINDING'
         WHEN r->>'error' IN ('SELLER_SUSPENDED', 'DROP_NOT_LIVE')
              AND (SELECT status FROM drops WHERE id = audit.drop_b_live()) = 'closed' THEN 'PASS'
         ELSE 'FAIL' END,
    adm->>'success', vis, COALESCE(r->>'error', r->>'success'),
    (SELECT status FROM drops WHERE id = audit.drop_b_live());
END $$;

-- 12.8 fulfilment prerequisites
DO $$
DECLARE o jsonb; a jsonb; r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; oid uuid;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_a_draft(), ARRAY[audit.p_a3()], 'Nope', '9830011111', '1 Test Lane Kolkata', '700001', 'full_payment', NULL);
  RAISE NOTICE '% 12.8a checkout on draft drop -> %', CASE WHEN o->>'error' = 'DROP_NOT_LIVE' THEN 'PASS' ELSE 'FAIL' END, o->>'error';
  -- seller A's live drop is still live (12.4b/12.5 no longer change it)
  o := create_order_with_reservation(audit.drop_a_live(), ARRAY[audit.p_a1()], 'Pooja Das', '9830022222', '3 Gariahat Road, Kolkata', '700029', 'full_payment', NULL);
  oid := (o->>'order_id')::uuid;
  PERFORM audit.as_seller(audit.seller_a());
  r1 := mark_order_ready_to_ship(oid);
  r2 := mark_order_shipped(oid, 'AWB123', 'DTDC');
  PERFORM audit.as_anon();
  a := initiate_payment_attempt(oid, o->>'order_token', NULL);
  PERFORM submit_buyer_payment_claim(oid, o->>'order_token', (a->>'payment_attempt_id')::uuid, '512345678901');
  PERFORM audit.as_seller(audit.seller_a());
  PERFORM verify_manual_upi_payment((a->>'payment_attempt_id')::uuid);
  r3 := mark_order_shipped(oid, 'AWB123', 'DTDC');
  r4 := mark_order_ready_to_ship(oid);
  r5 := mark_order_shipped(oid, 'AWB123', 'DTDC');
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 12.8b unpaid ready=% unpaid ship=% | paid-not-ready ship=% | ready=% ship=% | second ship=%',
    CASE WHEN r1->>'error'='ORDER_NOT_PAID' AND r2->>'error'='ORDER_NOT_PAID' AND r3->>'error'='ORDER_NOT_READY_TO_SHIP'
              AND (r4->>'success')::boolean AND (r5->>'success')::boolean THEN 'PASS' ELSE 'FAIL' END,
    r1->>'error', r2->>'error', r3->>'error', r4->>'success', r5->>'success',
    (SELECT 'status=' || status || ' fulfil=' || fulfilment_status FROM orders WHERE id = oid);
  PERFORM audit.as_seller(audit.seller_a());
  r5 := mark_order_shipped(oid, 'AWB999', 'DTDC');
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 12.8c double ship -> %', CASE WHEN r5->>'error'='ALREADY_SHIPPED' THEN 'PASS' ELSE 'FAIL' END, r5->>'error';
END $$;

-- 12.9 seller overrides on reserved stock
DO $$
DECLARE o jsonb; r jsonb;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_a_live(), ARRAY[audit.p_a2()], 'Hold Test', '9830033333', '7 Hindustan Park, Kolkata', '700029', 'full_payment', NULL);
  PERFORM audit.as_seller(audit.seller_a());
  r := mark_product_sold_offline(audit.p_a2());
  PERFORM audit.as_postgres();
  RAISE NOTICE 'INFO 12.9 mark_product_sold_offline on a reserved piece -> % (app offers "Mark Sold" on reserved items)', r->>'error';
END $$;

-- 12.10 direct UPDATE of buyer contact fields on an order (allowed, no audit trail)
DO $$
BEGIN
  RAISE NOTICE 'INFO 12.10 seller direct UPDATE orders.shipping_address -> %',
    pg_temp.try_as_a(format('UPDATE orders SET shipping_address=%L WHERE drop_id=%L', 'Changed by seller 123', audit.drop_a_live()));
  RAISE NOTICE 'INFO 12.10b seller direct UPDATE orders.status -> %',
    pg_temp.try_as_a(format('UPDATE orders SET status=%L WHERE drop_id=%L', 'paid', audit.drop_a_live()));
END $$;

ROLLBACK;
