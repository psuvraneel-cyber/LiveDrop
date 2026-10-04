-- =============================================================================
-- Suite 20 — P1 round 2 regression checks (migration 038)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- Result lines: PASS / FAIL (behaviour required by the fix), INFO (recorded, no verdict).
--
--   SA-ONB-002  suspension closes live drops safely; checkout and new payment requests refused
--   SA-PAY-011  UTRs normalised; a UTR verified on one order cannot pay for another
--   SA-SEC-003 / SA-SEC-008  storage policies (behaviour is in suites 11 and 18; catalog here)
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();
UPDATE profiles SET free_shipping_threshold_paisa = NULL WHERE id IN (audit.seller_a(), audit.seller_b());
UPDATE drops SET free_shipping_threshold_paisa = NULL;

CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v jsonb);
GRANT ALL ON t_ctx TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.put(p_k text, p_v jsonb) RETURNS void LANGUAGE sql AS $$
  INSERT INTO t_ctx VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v
$$;
CREATE OR REPLACE FUNCTION pg_temp.ctx(p_k text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT v FROM t_ctx WHERE k = p_k
$$;

-- a new unique piece in the given drop
CREATE OR REPLACE FUNCTION pg_temp.piece(p_drop uuid, p_code text, p_price int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO products (drop_id, code, title, price_paisa, size, image_url, image_urls)
  VALUES (p_drop, p_code, 'Suite 20 ' || p_code, p_price, 'Free Size',
          'https://x.supabase.co/s20-' || substr(p_code, 2) || '.jpg',
          ARRAY['https://x.supabase.co/s20-' || substr(p_code, 2) || '.jpg'])
  RETURNING id INTO v;
  RETURN v;
END $$;

-- buyer checkout (anon) + payment attempt (+ optional claim)
CREATE OR REPLACE FUNCTION pg_temp.buy(p_drop uuid, p_products uuid[], p_utr text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE o jsonb; a jsonb; c jsonb;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(p_drop, p_products, 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', 'full_payment', NULL);
  IF NOT (o->>'success')::boolean THEN
    PERFORM audit.as_postgres();
    RETURN o;
  END IF;
  a := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', NULL);
  IF p_utr IS NOT NULL THEN
    c := submit_buyer_payment_claim((o->>'order_id')::uuid, o->>'order_token', (a->>'payment_attempt_id')::uuid, p_utr);
  END IF;
  PERFORM audit.as_postgres();
  RETURN o || jsonb_build_object('attempt_id', a->>'payment_attempt_id', 'claim', c);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.claim(p_order jsonb, p_utr text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c jsonb;
BEGIN
  PERFORM audit.as_anon();
  c := submit_buyer_payment_claim((p_order->>'order_id')::uuid, p_order->>'order_token',
                                  (p_order->>'attempt_id')::uuid, p_utr);
  PERFORM audit.as_postgres();
  RETURN c;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.verify(p_seller uuid, p_attempt uuid, p_utr text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  PERFORM audit.as_seller(p_seller);
  v := verify_manual_upi_payment(p_attempt, p_utr);
  PERFORM audit.as_postgres();
  RETURN v;
END $$;

-- ---------------------------------------------------------------------------
-- SA-PAY-011: UTR normalisation and cross-order reuse
-- ---------------------------------------------------------------------------
DO $$
DECLARE p1 uuid; p2 uuid; p3 uuid; x jsonb; y jsonb; z jsonb; vx jsonb; cy jsonb; vz jsonb; stored text;
BEGIN
  p1 := pg_temp.piece(audit.drop_a_live(), '#U01', 100000);
  p2 := pg_temp.piece(audit.drop_a_live(), '#U02', 100000);
  p3 := pg_temp.piece(audit.drop_a_live(), '#U03', 100000);

  -- 20.1 a claim with lower case and spaces is stored normalised
  x := pg_temp.buy(audit.drop_a_live(), ARRAY[p1], ' abcd 1234 5678 ');
  SELECT buyer_submitted_utr INTO stored FROM payment_attempts WHERE id = (x->>'attempt_id')::uuid;
  RAISE NOTICE '%', audit.check('20.1', (x->'claim'->>'success')::boolean AND stored = 'ABCD12345678',
                                format('claim " abcd 1234 5678 " -> success=%s stored=%s', x->'claim'->>'success', stored));

  vx := pg_temp.verify(audit.seller_a(), (x->>'attempt_id')::uuid);
  RAISE NOTICE '%', audit.check('20.2', (vx->>'success')::boolean, format('verify first order -> %s', COALESCE(vx->>'error', vx->>'success')));

  -- 20.3 the same UTR, different case, refused at claim time on another order
  y := pg_temp.buy(audit.drop_a_live(), ARRAY[p2], NULL);
  cy := pg_temp.claim(y, 'AbCd12345678');
  RAISE NOTICE '%', audit.check('20.3', cy->>'error' = 'REFERENCE_USED_ON_ANOTHER_ORDER',
                                format('claim of a verified UTR (case variant) on another order -> %s', COALESCE(cy->>'error', cy->>'success')));

  -- 20.4 a lower-case legacy claim (stored before 038) cannot be verified on another order
  z := pg_temp.buy(audit.drop_a_live(), ARRAY[p3], '999988887777');
  UPDATE payment_attempts SET buyer_submitted_utr = 'abcd12345678' WHERE id = (z->>'attempt_id')::uuid;
  vz := pg_temp.verify(audit.seller_a(), (z->>'attempt_id')::uuid);
  RAISE NOTICE '%', audit.check('20.4', vz->>'error' = 'REFERENCE_USED_ON_ANOTHER_ORDER',
                                format('verify of a legacy lower-case duplicate -> %s', COALESCE(vz->>'error', vz->>'success')));

  -- 20.5 the seller typing the reference in lower case also hits the check
  vz := pg_temp.verify(audit.seller_a(), (z->>'attempt_id')::uuid, 'abcd 12345678');
  RAISE NOTICE '%', audit.check('20.5', vz->>'error' = 'REFERENCE_USED_ON_ANOTHER_ORDER',
                                format('verify with seller-typed "abcd 12345678" -> %s', COALESCE(vz->>'error', vz->>'success')));

  -- 20.6 re-verifying the first order with a case variant stays idempotent
  vx := pg_temp.verify(audit.seller_a(), (x->>'attempt_id')::uuid, 'abcd12345678');
  RAISE NOTICE '%', audit.check('20.6', (vx->>'success')::boolean, format('re-verify first order with case variant -> %s', COALESCE(vx->>'error', vx->>'success')));

  -- 20.7 the ledger itself refuses a case/space variant of a verified reference
  BEGIN
    INSERT INTO order_payments (order_id, payment_type, payment_method, verification_method, amount_paisa, status, reference_id, verified_at)
    VALUES ((z->>'order_id')::uuid, 'full', 'upi', 'seller_manual', 108000, 'verified', 'abcd 1234 5678', now());
    RAISE NOTICE '%', audit.check('20.7', false, 'ledger accepted a case/space variant of a verified reference');
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE '%', audit.check('20.7', true, 'ledger unique index on the normalised verified reference rejects the variant');
  END;
END $$;

-- ---------------------------------------------------------------------------
-- SA-ONB-002: suspension of a seller with a live drop
-- ---------------------------------------------------------------------------
DO $$
DECLARE pu uuid; pc uuid; pp uuid; pn uuid; ou jsonb; oc jsonb; op jsonb; vp jsonb; n jsonb; ini jsonb; late jsonb; vc jsonb;
        st_drop text; st_u text; st_pu text; st_c text; st_pc text; st_ca text; st_p text;
BEGIN
  pu := pg_temp.piece(audit.drop_a_live(), '#S01', 100000);   -- unclaimed hold
  pc := pg_temp.piece(audit.drop_a_live(), '#S02', 100000);   -- claim awaiting verification
  pp := pg_temp.piece(audit.drop_a_live(), '#S03', 100000);   -- paid
  pn := pg_temp.piece(audit.drop_a_live(), '#S04', 100000);   -- still available

  ou := pg_temp.buy(audit.drop_a_live(), ARRAY[pu], NULL);
  oc := pg_temp.buy(audit.drop_a_live(), ARRAY[pc], '611122223333');
  op := pg_temp.buy(audit.drop_a_live(), ARRAY[pp], '611122224444');
  vp := pg_temp.verify(audit.seller_a(), (op->>'attempt_id')::uuid);
  PERFORM pg_temp.put('oc', oc);

  -- Operator suspends seller A with a direct UPDATE (the SQL path the handoff describes).
  UPDATE profiles SET is_approved = false WHERE id = audit.seller_a();

  SELECT status INTO st_drop FROM drops WHERE id = audit.drop_a_live();
  SELECT status INTO st_u FROM orders WHERE id = (ou->>'order_id')::uuid;
  SELECT status INTO st_pu FROM products WHERE id = pu;
  SELECT status INTO st_c FROM orders WHERE id = (oc->>'order_id')::uuid;
  SELECT status INTO st_pc FROM products WHERE id = pc;
  SELECT status INTO st_ca FROM payment_attempts WHERE id = (oc->>'attempt_id')::uuid;
  SELECT status INTO st_p FROM orders WHERE id = (op->>'order_id')::uuid;

  RAISE NOTICE '%', audit.check('20.10', st_drop = 'closed', format('suspension closes the live drop -> %s', st_drop));
  RAISE NOTICE '%', audit.check('20.11', st_u = 'cancelled' AND st_pu = 'available',
                                format('unclaimed hold released -> order=%s piece=%s', st_u, st_pu));
  RAISE NOTICE '%', audit.check('20.12', st_c = 'pending' AND st_pc = 'reserved' AND st_ca = 'awaiting_seller_verification',
                                format('claim in flight kept -> order=%s piece=%s attempt=%s', st_c, st_pc, st_ca));
  RAISE NOTICE '%', audit.check('20.13', (vp->>'success')::boolean AND st_p = 'paid',
                                format('paid order untouched -> %s', st_p));

  -- 20.14 checkout refused (drop closed by the trigger)
  n := pg_temp.buy(audit.drop_a_live(), ARRAY[pn], NULL);
  RAISE NOTICE '%', audit.check('20.14', n->>'error' IN ('SELLER_SUSPENDED', 'DROP_NOT_LIVE'),
                                format('checkout after suspension -> %s', COALESCE(n->>'error', n->>'success')));

  -- 20.15 no new payment request for the suspended seller
  PERFORM audit.as_anon();
  ini := initiate_payment_attempt((oc->>'order_id')::uuid, oc->>'order_token', NULL);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('20.15', ini->>'error' = 'SELLER_SUSPENDED',
                                format('initiate_payment_attempt after suspension -> %s', COALESCE(ini->>'error', ini->>'success')));

  -- 20.16 a buyer who already paid can still record the UTR (late claim on the released order)
  late := pg_temp.claim(ou, '611122225555');
  RAISE NOTICE '%', audit.check('20.16', (late->>'success')::boolean AND (late->>'is_late_claim')::boolean,
                                format('UTR after suspension -> success=%s late=%s', late->>'success', late->>'is_late_claim'));

  -- 20.17 the seller can still verify the claim that was in flight (money is recorded, not lost)
  vc := pg_temp.verify(audit.seller_a(), (oc->>'attempt_id')::uuid);
  RAISE NOTICE '%', audit.check('20.17', (vc->>'success')::boolean,
                                format('verify claim in flight after suspension -> %s', COALESCE(vc->>'error', vc->>'success')));
END $$;

-- 20.18 checkout guard on its own: an unapproved seller whose drop is still marked live
--       (simulated by suspending with the trigger disabled inside this rolled-back transaction)
DO $$
DECLARE d uuid := 'cccc0000-0000-0000-0000-000000000001'; p uuid; r jsonb;
BEGIN
  INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa, live_started_at)
  VALUES (d, audit.seller_d(), 'Damini Flash Live', 'damini-flash-live', 'live', 8000, now());
  p := pg_temp.piece(d, '#C01', 100000);
  ALTER TABLE profiles DISABLE TRIGGER trg_close_live_drops_on_suspension;
  UPDATE profiles SET is_approved = false WHERE id = audit.seller_d();
  ALTER TABLE profiles ENABLE TRIGGER trg_close_live_drops_on_suspension;
  r := pg_temp.buy(d, ARRAY[p], NULL);
  RAISE NOTICE '%', audit.check('20.18', r->>'error' = 'SELLER_SUSPENDED',
                                format('checkout on a still-live drop of an unapproved seller -> %s', COALESCE(r->>'error', r->>'success')));
  -- restore: close that drop and re-approve D for 20.20
  PERFORM public.close_drop_safely(d);
  UPDATE profiles SET is_approved = true WHERE id = audit.seller_d();
END $$;

-- 20.19 admin_approve_seller(false) uses the same path; re-approval does not reopen anything
DO $$
DECLARE adm jsonb; st text; adm2 jsonb; st2 text;
BEGIN
  PERFORM audit.as_service();
  adm := admin_approve_seller(audit.seller_b(), false);
  PERFORM audit.as_postgres();
  SELECT status INTO st FROM drops WHERE id = audit.drop_b_live();
  PERFORM audit.as_service();
  adm2 := admin_approve_seller(audit.seller_b(), true);
  PERFORM audit.as_postgres();
  SELECT status INTO st2 FROM drops WHERE id = audit.drop_b_live();
  RAISE NOTICE '%', audit.check('20.19', (adm->>'success')::boolean AND st = 'closed' AND st2 = 'closed',
                                format('admin_approve_seller(B,false) -> drop %s; re-approve -> drop %s', st, st2));
END $$;

-- 20.20 seller-initiated close_drop still behaves as before (refactored onto close_drop_safely)
DO $$
DECLARE d uuid := 'dddd0000-0000-0000-0000-000000000001'; p uuid; o jsonb; r jsonb; r2 jsonb; st text;
BEGIN
  INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa, live_started_at)
  VALUES (d, audit.seller_d(), 'Damini Live', 'damini-live', 'live', 8000, now());
  p := pg_temp.piece(d, '#D01', 100000);
  o := pg_temp.buy(d, ARRAY[p], NULL);
  PERFORM audit.as_seller(audit.seller_d());
  r := close_drop(d);
  r2 := close_drop(d);
  PERFORM audit.as_postgres();
  SELECT status INTO st FROM products WHERE id = p;
  RAISE NOTICE '%', audit.check('20.20', (r->>'success')::boolean AND (r->>'released_orders_count')::int = 1
                                         AND st = 'available' AND (r2->>'idempotent')::boolean,
                                format('close_drop -> released=%s piece=%s second call idempotent=%s',
                                       r->>'released_orders_count', st, r2->>'idempotent'));
END $$;

-- ---------------------------------------------------------------------------
-- Catalog: privileges and policies
-- ---------------------------------------------------------------------------
DO $$
DECLARE ok boolean;
BEGIN
  ok := NOT has_function_privilege('anon', 'public.close_drop_safely(uuid)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.close_drop_safely(uuid)', 'EXECUTE');
  RAISE NOTICE '%', audit.check('20.30', ok, 'close_drop_safely is not callable by anon/authenticated');

  ok := NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
                     AND policyname = 'product_images_public_read');
  RAISE NOTICE '%', audit.check('20.31', ok, 'no public read/list policy on product-images');

  ok := (SELECT count(*) FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects'
          AND policyname IN ('product_images_seller_insert', 'product_images_seller_update')
          AND (coalesce(with_check, '') || coalesce(qual, '')) LIKE '%is_seller_approved%') = 2;
  RAISE NOTICE '%', audit.check('20.32', ok, 'upload and overwrite policies require an approved seller');

  ok := to_regclass('public.uq_order_payments_reference_verified_norm') IS NOT NULL;
  RAISE NOTICE '%', audit.check('20.33', ok, 'unique index on the normalised verified reference exists');

  ok := EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_close_live_drops_on_suspension' AND NOT tgisinternal);
  RAISE NOTICE '%', audit.check('20.34', ok, 'suspension trigger installed on profiles');
END $$;

ROLLBACK;
