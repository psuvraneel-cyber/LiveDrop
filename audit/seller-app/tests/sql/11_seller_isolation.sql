-- =============================================================================
-- Suite 11 — seller isolation (seller B against seller A's data and RPCs)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

-- A buyer order + claimed payment attempt on seller A's live drop.
CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text);
GRANT ALL ON t_ctx TO anon, authenticated, service_role;
DO $$
DECLARE res jsonb; att jsonb;
BEGIN
  PERFORM audit.as_anon();
  res := create_order_with_reservation(audit.drop_a_live(), ARRAY[audit.p_a1()], 'Riya Sen', '9830012345',
                                       '22 Ballygunge Place, Kolkata', '700019', 'full_payment', 'iso-key-1');
  att := initiate_payment_attempt((res->>'order_id')::uuid, res->>'order_token', NULL);
  PERFORM submit_buyer_payment_claim((res->>'order_id')::uuid, res->>'order_token', (att->>'payment_attempt_id')::uuid, '412345678901');
  PERFORM audit.as_postgres();
  INSERT INTO t_ctx VALUES ('order_a', res->>'order_id'), ('token_a', res->>'order_token'), ('attempt_a', att->>'payment_attempt_id');
END $$;

-- 11.1 reads: B sees none of A's operational rows
DO $$
DECLARE o int; p int; pa int; d int; op int; oi int;
BEGIN
  PERFORM audit.as_seller(audit.seller_b());
  SELECT count(*) INTO o FROM orders WHERE drop_id = audit.drop_a_live();
  SELECT count(*) INTO oi FROM order_items WHERE order_id = (SELECT v::uuid FROM t_ctx WHERE k='order_a');
  SELECT count(*) INTO pa FROM payment_attempts WHERE order_id = (SELECT v::uuid FROM t_ctx WHERE k='order_a');
  SELECT count(*) INTO op FROM order_payments;
  SELECT count(*) INTO p FROM products WHERE drop_id = audit.drop_a_live();
  SELECT count(*) INTO d FROM drops WHERE id = audit.drop_a_draft();
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 11.1 seller B reads of seller A: orders=% items=% attempts=% ledger=% products=% draft_drop=%',
    CASE WHEN o+oi+pa+op+p+d = 0 THEN 'PASS' ELSE 'FAIL' END, o, oi, pa, op, p, d;
END $$;

-- 11.1b B can read A's LIVE drop row (public policy) — expected for a public storefront
DO $$
DECLARE d int;
BEGIN
  PERFORM audit.as_seller(audit.seller_b());
  SELECT count(*) INTO d FROM drops WHERE id = audit.drop_a_live();
  PERFORM audit.as_postgres();
  RAISE NOTICE 'INFO 11.1b seller B can read seller A live drop row (drops_public_read): %', d;
END $$;

-- 11.2 B cannot write A's rows directly
DO $$
DECLARE n1 int; n2 int; n3 int;
BEGIN
  PERFORM audit.as_seller(audit.seller_b());
  UPDATE drops SET title = 'B was here' WHERE id = audit.drop_a_live(); GET DIAGNOSTICS n1 = ROW_COUNT;
  UPDATE orders SET buyer_phone = '9000000001' WHERE drop_id = audit.drop_a_live(); GET DIAGNOSTICS n2 = ROW_COUNT;
  DELETE FROM products WHERE drop_id = audit.drop_a_live(); GET DIAGNOSTICS n3 = ROW_COUNT;
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 11.2 seller B direct writes on A: drops=% orders=% products_deleted=%',
    CASE WHEN n1+n2+n3 = 0 THEN 'PASS' ELSE 'FAIL' END, n1, n2, n3;
END $$;

-- 11.3 B cannot insert a product into A's drop
DO $$
BEGIN
  PERFORM audit.as_seller(audit.seller_b());
  BEGIN
    INSERT INTO products (drop_id, code, title, price_paisa, size, image_url)
    VALUES (audit.drop_a_live(), '#Z99', 'Injected', 100, 'S', 'https://x/y.jpg');
    PERFORM audit.as_postgres();
    RAISE NOTICE 'FAIL 11.3 seller B inserted a product into seller A drop';
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM audit.as_postgres();
    RAISE NOTICE 'PASS 11.3 seller B product insert into A drop rejected: %', SQLERRM;
  END;
END $$;

-- 11.4 B cannot drive A's RPCs
DO $$
DECLARE r jsonb; order_a uuid; attempt_a uuid; out text := '';
BEGIN
  SELECT v::uuid INTO order_a FROM t_ctx WHERE k='order_a';
  SELECT v::uuid INTO attempt_a FROM t_ctx WHERE k='attempt_a';
  PERFORM audit.as_seller(audit.seller_b());
  r := verify_manual_upi_payment(attempt_a);            out := out || ' verify=' || COALESCE(r->>'error','OK');
  r := reject_manual_upi_payment(attempt_a, 'x', true); out := out || ' reject=' || COALESCE(r->>'error','OK');
  r := force_release_hold(order_a);                     out := out || ' force_release=' || COALESCE(r->>'error','OK');
  r := mark_product_sold_offline(audit.p_a2());         out := out || ' sold_offline=' || COALESCE(r->>'error','OK');
  r := update_product(audit.p_a2(), 'x', 1, 'S');       out := out || ' update_product=' || COALESCE(r->>'error','OK');
  r := close_drop(audit.drop_a_live());                 out := out || ' close_drop=' || COALESCE(r->>'error','OK');
  r := mark_order_ready_to_ship(order_a);               out := out || ' ready=' || COALESCE(r->>'error','OK');
  r := mark_order_shipped(order_a, 'AWB1', 'DTDC');     out := out || ' ship=' || COALESCE(r->>'error','OK');
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 11.4 seller B RPCs against seller A objects:%', CASE WHEN out NOT LIKE '%=OK%' THEN 'PASS' ELSE 'FAIL' END, out;
END $$;

-- 11.5 B cannot write into A's storage folder; unapproved C can upload to own folder
DO $$
BEGIN
  INSERT INTO storage.buckets (id, name, public) VALUES ('product-images','product-images', true) ON CONFLICT DO NOTHING;
  PERFORM audit.as_seller(audit.seller_b());
  BEGIN
    INSERT INTO storage.objects (bucket_id, name) VALUES ('product-images', audit.seller_a()::text || '/drop/evil.jpg');
    PERFORM audit.as_postgres();
    RAISE NOTICE 'FAIL 11.5a seller B wrote into seller A storage folder';
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM audit.as_postgres();
    RAISE NOTICE 'PASS 11.5a seller B storage write into A folder rejected';
  END;
  PERFORM audit.as_seller(audit.seller_c());
  INSERT INTO storage.objects (bucket_id, name) VALUES ('product-images', audit.seller_c()::text || '/anything/blob.jpg');
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FINDING 11.5b unapproved seller C can upload objects to the public product-images bucket (no approval gate on storage)';
END $$;

-- 11.6 A seller can read the full PII of every buyer of their own drops (expected) — record the fields
DO $$
DECLARE r record;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());
  SELECT buyer_name, buyer_phone, shipping_address, pincode INTO r FROM orders LIMIT 1;
  PERFORM audit.as_postgres();
  RAISE NOTICE 'INFO 11.6 seller A reads own buyer PII: name=% phone=% pincode=%', r.buyer_name, r.buyer_phone, r.pincode;
END $$;

ROLLBACK;
