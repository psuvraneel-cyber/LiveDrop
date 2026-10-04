-- =============================================================================
-- Suite 19 — P0 remediation regression checks (migrations 034, 035, 036, 037)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- Result lines: PASS / FAIL (behaviour required by the P0 contract), FINDING (a fixed
-- defect has come back), INFO (behaviour recorded, no verdict).
--
-- Every case creates its own pieces in seller A's live drop, so cases do not depend on
-- each other except where a case id is read from t_ctx (refund / deletion cases).
-- Prices: 120000 paisa -> total 128000 (8000 shipping); 240000 paisa -> total 240000
-- (seller A free-shipping threshold 200000, drop threshold unset so the shop threshold applies
-- — migration 037 rule). Advance: 25000 paisa; hold: 30 days.
-- Claim windows (037): a claim on a pending order holds 30 minutes during a live, else 24 hours;
-- after hold and window lapse the order is released and the claim moves to late review.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();
UPDATE profiles SET advance_confirmation_enabled = true, advance_amount_paisa = 25000,
                    free_shipping_threshold_paisa = 200000 WHERE id = audit.seller_a();
UPDATE drops SET free_shipping_threshold_paisa = NULL WHERE id = audit.drop_a_live();

CREATE TEMP TABLE t_ctx (k text PRIMARY KEY, v text);
GRANT ALL ON t_ctx TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION pg_temp.put(p_k text, p_v text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO t_ctx VALUES (p_k, p_v) ON CONFLICT (k) DO UPDATE SET v = EXCLUDED.v
$$;
CREATE OR REPLACE FUNCTION pg_temp.ctx(p_k text) RETURNS uuid LANGUAGE sql AS $$
  SELECT v::uuid FROM t_ctx WHERE k = p_k
$$;

-- a new unique piece in seller A's live drop
CREATE OR REPLACE FUNCTION pg_temp.piece(p_code text, p_price int) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO products (drop_id, code, title, price_paisa, size, image_url, image_urls)
  VALUES (audit.drop_a_live(), p_code, 'Suite 19 ' || p_code, p_price, 'Free Size',
          'https://x.supabase.co/s19-' || substr(p_code, 2) || '.jpg',
          ARRAY['https://x.supabase.co/s19-' || substr(p_code, 2) || '.jpg'])
  RETURNING id INTO v;
  RETURN v;
END $$;

-- buyer checkout (anon) + payment attempt (+ optional on-time claim)
CREATE OR REPLACE FUNCTION pg_temp.buy(p_products uuid[], p_mode text, p_utr text DEFAULT NULL, p_type text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE o jsonb; a jsonb; c jsonb;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_a_live(), p_products, 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', p_mode, NULL);
  IF NOT (o->>'success')::boolean THEN
    PERFORM audit.as_postgres();
    RETURN o;
  END IF;
  a := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', p_type);
  IF p_utr IS NOT NULL THEN
    c := submit_buyer_payment_claim((o->>'order_id')::uuid, o->>'order_token', (a->>'payment_attempt_id')::uuid, p_utr);
  END IF;
  PERFORM audit.as_postgres();
  RETURN o || jsonb_build_object('attempt_id', a->>'payment_attempt_id',
                                 'attempt_amount', (a->>'expected_amount_paisa')::int, 'claim', c);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.initiate(p_order jsonb, p_type text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE a jsonb;
BEGIN
  PERFORM audit.as_anon();
  a := initiate_payment_attempt((p_order->>'order_id')::uuid, p_order->>'order_token', p_type);
  PERFORM audit.as_postgres();
  RETURN a;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.claim(p_order jsonb, p_attempt uuid, p_utr text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c jsonb;
BEGIN
  PERFORM audit.as_anon();
  c := submit_buyer_payment_claim((p_order->>'order_id')::uuid, p_order->>'order_token', p_attempt, p_utr);
  PERFORM audit.as_postgres();
  RETURN c;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.verify_as(p_seller uuid, p_attempt uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM audit.as_seller(p_seller);
  BEGIN
    r := verify_manual_upi_payment(p_attempt);
  EXCEPTION WHEN OTHERS THEN
    r := jsonb_build_object('success', false, 'error', 'EXCEPTION ' || SQLSTATE, 'message', SQLERRM);
  END;
  PERFORM audit.as_postgres();
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.reject_as(p_seller uuid, p_attempt uuid, p_release boolean) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM audit.as_seller(p_seller);
  r := reject_manual_upi_payment(p_attempt, 'payment_not_found', p_release);
  PERFORM audit.as_postgres();
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.release_as(p_seller uuid, p_order uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM audit.as_seller(p_seller);
  r := force_release_hold(p_order);
  PERFORM audit.as_postgres();
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.reap() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM audit.as_service();
  PERFORM release_expired_holds();
  PERFORM audit.as_postgres();
END $$;

-- push an order's hold (and optionally an attempt's windows) into the past
CREATE OR REPLACE FUNCTION pg_temp.expire(p_order uuid, p_attempt uuid DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = p_order;
  IF p_attempt IS NOT NULL THEN
    UPDATE payment_attempts
       SET expires_at = now() - interval '1 minute',
           verification_expires_at = CASE WHEN verification_expires_at IS NULL THEN NULL ELSE now() - interval '1 minute' END
     WHERE id = p_attempt;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.ledger(p_order uuid) RETURNS int LANGUAGE sql AS $$
  SELECT coalesce(sum(amount_paisa), 0)::int FROM order_payments WHERE order_id = p_order AND status = 'verified'
$$;

-- physical row versions (any UPDATE creates a new ctid): proves "no write happened"
CREATE OR REPLACE FUNCTION pg_temp.rowvers(p_order uuid, p_attempt uuid, p_piece uuid) RETURNS text LANGUAGE sql AS $$
  SELECT concat_ws('|', (SELECT ctid::text FROM orders WHERE id = p_order),
                        (SELECT ctid::text FROM payment_attempts WHERE id = p_attempt),
                        (SELECT ctid::text FROM products WHERE id = p_piece))
$$;

-- every key the P0 contract requires in a verify success response
CREATE OR REPLACE FUNCTION pg_temp.has_verify_keys(v jsonb) RETURNS boolean LANGUAGE sql AS $$
  SELECT v ?& ARRAY['success','idempotent','is_late_claim','inventory_available','refund_required','refund_amount_paisa',
                    'order_id','order_code','order_status','status','payment_status','fulfilment_status',
                    'total_paid_paisa','balance_due_paisa','advance_paid_paisa','payment_type','amount_paisa',
                    'payment_attempt_id','attempt_id','payment_id','message']
$$;

-- run a statement as a seller and report rows / SQLSTATE
CREATE OR REPLACE FUNCTION pg_temp.try_as(p_seller uuid, p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  PERFORM audit.as_seller(p_seller);
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

-- ---------------------------------------------------------------------------
-- 19.1 SA-OPS-001 lazy expiry: an expired, UNCLAIMED hold is released by checkout
-- ---------------------------------------------------------------------------
DO $$
DECLARE p1 uuid; p2 uuid; x jsonb; y jsonb; xo text; xa text; c1 record; c2 text;
BEGIN
  p1 := pg_temp.piece('#L01', 120000);
  p2 := pg_temp.piece('#L02', 50000);
  x := pg_temp.buy(ARRAY[p1, p2], 'full_payment');
  PERFORM pg_temp.expire((x->>'order_id')::uuid, (x->>'attempt_id')::uuid);
  y := pg_temp.buy(ARRAY[p1], 'full_payment');
  SELECT status INTO xo FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status INTO xa FROM payment_attempts WHERE id = (x->>'attempt_id')::uuid;
  SELECT status, reserved_by_order_id INTO c1 FROM products WHERE id = p1;
  SELECT status INTO c2 FROM products WHERE id = p2;
  RAISE NOTICE '% 19.1 checkout of a piece behind an expired, unclaimed hold -> % | stale order=% its attempt=% | piece=% held by new order=% | other piece of the stale order=%',
    CASE WHEN y->>'error' = 'STOCK_UNAVAILABLE' THEN 'FINDING'
         WHEN (y->>'success')::boolean AND xo = 'cancelled' AND xa = 'expired'
              AND c1.status = 'reserved' AND c1.reserved_by_order_id = (y->>'order_id')::uuid AND c2 = 'available' THEN 'PASS'
         ELSE 'FAIL' END,
    coalesce(y->>'error', 'success=' || (y->>'success')), xo, xa, c1.status,
    (c1.reserved_by_order_id = (y->>'order_id')::uuid), c2;
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.1 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.2 lazy expiry and claims (SA-PAY-003 / SA-PAY-007, migration 037)
--  a) hold lapsed but the claim's verification window is still open -> nothing is released
--  b) hold AND window lapsed -> released to the next buyer; the claim moves to late review
--     (UTR kept) instead of expiring
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; x jsonb; y jsonb; before_v text; after_v text; o text; a record; c record;
BEGIN
  p := pg_temp.piece('#L03', 120000);
  x := pg_temp.buy(ARRAY[p], 'full_payment', '719000000001');
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (x->>'order_id')::uuid;
  before_v := pg_temp.rowvers((x->>'order_id')::uuid, (x->>'attempt_id')::uuid, p);
  y := pg_temp.buy(ARRAY[p], 'full_payment');
  after_v := pg_temp.rowvers((x->>'order_id')::uuid, (x->>'attempt_id')::uuid, p);
  SELECT status INTO o FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status, buyer_submitted_utr INTO a FROM payment_attempts WHERE id = (x->>'attempt_id')::uuid;
  SELECT status, reserved_by_order_id INTO c FROM products WHERE id = p;
  RAISE NOTICE '% 19.2a checkout of a piece behind an expired hold whose claim window is still open -> % | order=% attempt=% utr=% piece=% held by claimant=% rows unchanged=%',
    CASE WHEN (y->>'success')::boolean THEN 'FINDING'
         WHEN y->>'error' = 'STOCK_UNAVAILABLE' AND o = 'pending' AND a.status = 'awaiting_seller_verification'
              AND a.buyer_submitted_utr = '719000000001' AND c.status = 'reserved'
              AND c.reserved_by_order_id = (x->>'order_id')::uuid AND before_v = after_v THEN 'PASS'
         ELSE 'FAIL' END,
    coalesce(y->>'error', 'success=' || (y->>'success')), o, a.status, a.buyer_submitted_utr, c.status,
    (c.reserved_by_order_id = (x->>'order_id')::uuid), (before_v = after_v);

  -- b) now the window has lapsed too
  PERFORM pg_temp.expire((x->>'order_id')::uuid, (x->>'attempt_id')::uuid);
  y := pg_temp.buy(ARRAY[p], 'full_payment');
  SELECT status INTO o FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status, buyer_submitted_utr, buyer_claimed_at INTO a FROM payment_attempts WHERE id = (x->>'attempt_id')::uuid;
  SELECT status, reserved_by_order_id INTO c FROM products WHERE id = p;
  RAISE NOTICE '% 19.2b checkout of a piece behind an expired hold whose claim window lapsed -> % | claimant order=% attempt=% utr=% | piece=% held by new buyer=%',
    CASE WHEN a.status = 'expired' THEN 'FINDING'
         WHEN (y->>'success')::boolean AND o = 'cancelled' AND a.status = 'late_claim_pending_review'
              AND a.buyer_submitted_utr = '719000000001' AND a.buyer_claimed_at IS NOT NULL
              AND c.status = 'reserved' AND c.reserved_by_order_id = (y->>'order_id')::uuid THEN 'PASS'
         ELSE 'FAIL' END,
    coalesce(y->>'error', 'success=' || (y->>'success')), o, a.status, a.buyer_submitted_utr, c.status,
    (c.reserved_by_order_id = (y->>'order_id')::uuid);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.2 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.3 internal helpers are not executable by client roles
-- ---------------------------------------------------------------------------
DO $$
DECLARE f text; granted text := ''; anon_call text; seller_call text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.release_stale_hold(uuid)',
                           'public.order_has_open_payment_claim(uuid)',
                           'public.apply_upi_payment_transition(uuid,uuid,text,text,uuid)',
                           'public.upi_verification_response(uuid,uuid,uuid,boolean,boolean,boolean,text)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') THEN granted := granted || ' anon:' || f; END IF;
    IF has_function_privilege('authenticated', f, 'EXECUTE') THEN granted := granted || ' authenticated:' || f; END IF;
  END LOOP;
  PERFORM audit.as_anon();
  BEGIN
    PERFORM public.release_stale_hold(gen_random_uuid());
    anon_call := 'allowed';
  EXCEPTION WHEN insufficient_privilege THEN
    anon_call := 'permission denied';
  END;
  PERFORM audit.as_seller(audit.seller_a());
  BEGIN
    PERFORM public.release_stale_hold(gen_random_uuid());
    seller_call := 'allowed';
  EXCEPTION WHEN insufficient_privilege THEN
    seller_call := 'permission denied';
  END;
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 19.3 release_stale_hold / order_has_open_payment_claim / apply_upi_payment_transition / upi_verification_response not executable by anon or authenticated -> grants:% | anon call: % | seller call: %',
    CASE WHEN granted = '' AND anon_call = 'permission denied' AND seller_call = 'permission denied' THEN 'PASS' ELSE 'FINDING' END,
    CASE WHEN granted = '' THEN ' none' ELSE granted END, anon_call, seller_call;
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.3 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.4 SA-PAY-001 late ADVANCE, pieces still available -> confirmed / advance_paid
-- 19.4b the revived order then takes its balance normally
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; x jsonb; c jsonb; v jsonb; o record; pc record; led int; bal jsonb; v2 jsonb;
BEGIN
  p := pg_temp.piece('#L04', 240000);
  x := pg_temp.buy(ARRAY[p], 'advance');
  PERFORM pg_temp.expire((x->>'order_id')::uuid, (x->>'attempt_id')::uuid);
  PERFORM pg_temp.reap();
  c := pg_temp.claim(x, (x->>'attempt_id')::uuid, '819000000004');
  v := pg_temp.verify_as(audit.seller_a(), (x->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO pc FROM products WHERE id = p;
  led := pg_temp.ledger(o.id);
  PERFORM pg_temp.put('19.4.order', o.id::text);
  RAISE NOTICE '% 19.4 late advance (claim=%) with the piece still free -> order=%/% advance_paid=% total_paid=% balance_due=% (total %) ledger=% hold_left=% piece=% held=% | rpc late=% inventory=% refund=%',
    CASE WHEN o.status = 'paid' THEN 'FINDING'
         WHEN (v->>'success')::boolean AND c->>'status' = 'late_claim_pending_review'
              AND (v->>'is_late_claim')::boolean AND (v->>'inventory_available')::boolean
              AND NOT (v->>'refund_required')::boolean AND (v->>'refund_amount_paisa')::int = 0
              AND pg_temp.has_verify_keys(v)
              AND o.status = 'confirmed' AND o.payment_status = 'advance_paid'
              AND o.advance_paid_paisa = 25000 AND o.total_paid_paisa = 25000 AND o.balance_due_paisa = 215000
              AND o.advance_paid_at IS NOT NULL AND o.hold_expires_at > now() + interval '29 days'
              AND (to_jsonb(o)->>'refund_status') = 'none' AND led = 25000
              AND pc.status = 'reserved' AND pc.reserved_by_order_id = o.id THEN 'PASS'
         ELSE 'FAIL' END,
    c->>'status', o.status, o.payment_status, o.advance_paid_paisa, o.total_paid_paisa, o.balance_due_paisa, o.total_paisa,
    led, date_trunc('day', o.hold_expires_at - now()), pc.status, (pc.reserved_by_order_id = o.id),
    v->>'is_late_claim', v->>'inventory_available', v->>'refund_required';

  -- 19.4b balance on the revived order
  bal := pg_temp.initiate(x, NULL);
  PERFORM pg_temp.claim(x, (bal->>'payment_attempt_id')::uuid, '819000000005');
  v2 := pg_temp.verify_as(audit.seller_a(), (bal->>'payment_attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO pc FROM products WHERE id = p;
  led := pg_temp.ledger(o.id);
  RAISE NOTICE '% 19.4b balance (%=% paisa) on the revived order -> % | order=%/% total_paid=% balance_due=% ledger=% piece=% | response keys complete=%',
    CASE WHEN (v2->>'success')::boolean AND NOT (v2->>'idempotent')::boolean AND pg_temp.has_verify_keys(v2)
              AND o.status = 'paid' AND o.payment_status = 'paid' AND o.total_paid_paisa = 240000
              AND o.balance_due_paisa = 0 AND led = 240000 AND pc.status = 'sold' THEN 'PASS'
         ELSE 'FAIL' END,
    bal->>'payment_type', bal->>'expected_amount_paisa', coalesce(v2->>'error', 'success=' || (v2->>'success')),
    o.status, o.payment_status, o.total_paid_paisa, o.balance_due_paisa, led, pc.status, pg_temp.has_verify_keys(v2);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.4 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.5 SA-PAY-004 late FULL payment, piece resold -> refund required (+ idempotent replay)
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; x jsonb; other jsonb; v jsonb; v2 jsonb; o record; pc record; led int; rows_before int; rows_after int;
BEGIN
  p := pg_temp.piece('#L05', 120000);
  x := pg_temp.buy(ARRAY[p], 'full_payment');
  PERFORM pg_temp.expire((x->>'order_id')::uuid, (x->>'attempt_id')::uuid);
  PERFORM pg_temp.reap();
  other := pg_temp.buy(ARRAY[p], 'full_payment');
  PERFORM pg_temp.claim(x, (x->>'attempt_id')::uuid, '819000000006');
  v := pg_temp.verify_as(audit.seller_a(), (x->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO pc FROM products WHERE id = p;
  led := pg_temp.ledger(o.id);
  PERFORM pg_temp.put('19.5.order', o.id::text);
  RAISE NOTICE '% 19.5 late full payment, piece resold -> rpc refund_required=% refund_amount=% inventory=% | order=%/% total_paid=% balance=% refund=%/% reason=% ledger=% | other buyer keeps piece=% | response keys complete=%',
    CASE WHEN (v->>'success')::boolean AND (to_jsonb(o)->>'refund_status') IS DISTINCT FROM 'required' THEN 'FINDING'
         WHEN (v->>'success')::boolean AND NOT (v->>'idempotent')::boolean AND (v->>'is_late_claim')::boolean
              AND (v->>'refund_required')::boolean AND (v->>'refund_amount_paisa')::int = 128000
              AND NOT (v->>'inventory_available')::boolean AND pg_temp.has_verify_keys(v)
              AND v->>'order_status' = 'cancelled' AND v->>'status' = 'cancelled'
              AND o.status = 'cancelled' AND o.payment_status = 'paid' AND o.total_paid_paisa = 128000
              AND o.balance_due_paisa = 0 AND (to_jsonb(o)->>'refund_status') = 'required' AND (to_jsonb(o)->>'refund_amount_paisa')::int = 128000
              AND (to_jsonb(o)->>'refund_reason') = 'LATE_PAYMENT_INVENTORY_UNAVAILABLE' AND (to_jsonb(o)->>'refund_required_at') IS NOT NULL
              AND led = 128000 AND pc.status = 'reserved' AND pc.reserved_by_order_id = (other->>'order_id')::uuid THEN 'PASS'
         ELSE 'FAIL' END,
    v->>'refund_required', v->>'refund_amount_paisa', v->>'inventory_available', o.status, o.payment_status,
    o.total_paid_paisa, o.balance_due_paisa, (to_jsonb(o)->>'refund_status'), (to_jsonb(o)->>'refund_amount_paisa')::int, (to_jsonb(o)->>'refund_reason'), led,
    (pc.reserved_by_order_id = (other->>'order_id')::uuid), pg_temp.has_verify_keys(v);

  SELECT count(*) INTO rows_before FROM order_payments WHERE order_id = o.id;
  v2 := pg_temp.verify_as(audit.seller_a(), (x->>'attempt_id')::uuid);
  SELECT count(*) INTO rows_after FROM order_payments WHERE order_id = o.id;
  RAISE NOTICE '% 19.5b verify replay -> success=% idempotent=% refund_required=% keys complete=% | ledger rows before=% after=%',
    CASE WHEN (v2->>'success')::boolean AND (v2->>'idempotent')::boolean AND (v2->>'refund_required')::boolean
              AND pg_temp.has_verify_keys(v2) AND rows_before = 1 AND rows_after = 1 THEN 'PASS' ELSE 'FAIL' END,
    v2->>'success', v2->>'idempotent', v2->>'refund_required', pg_temp.has_verify_keys(v2), rows_before, rows_after;
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.5 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.6 SA-PAY-006 late ADVANCE, piece resold -> no constraint error, refund required
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; x jsonb; other jsonb; v jsonb; o record; pc record; led int;
BEGIN
  p := pg_temp.piece('#L06', 240000);
  x := pg_temp.buy(ARRAY[p], 'advance');
  PERFORM pg_temp.expire((x->>'order_id')::uuid, (x->>'attempt_id')::uuid);
  PERFORM pg_temp.reap();
  other := pg_temp.buy(ARRAY[p], 'full_payment');
  PERFORM pg_temp.claim(x, (x->>'attempt_id')::uuid, '819000000007');
  v := pg_temp.verify_as(audit.seller_a(), (x->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO pc FROM products WHERE id = p;
  led := pg_temp.ledger(o.id);
  PERFORM pg_temp.put('19.6.order', o.id::text);
  RAISE NOTICE '% 19.6 late advance, piece resold -> % | order=%/% total=% total_paid=% advance_paid=% balance_due=% refund=%/% ledger=% | other buyer keeps piece=%',
    CASE WHEN v->>'error' LIKE 'EXCEPTION%' THEN 'FINDING'
         WHEN (v->>'success')::boolean AND (v->>'refund_required')::boolean AND (v->>'refund_amount_paisa')::int = 25000
              AND o.status = 'cancelled' AND o.payment_status = 'advance_paid' AND o.total_paid_paisa = 25000
              AND o.advance_paid_paisa = 25000 AND o.balance_due_paisa = 215000
              AND (to_jsonb(o)->>'refund_status') = 'required' AND (to_jsonb(o)->>'refund_amount_paisa')::int = 25000 AND led = 25000
              AND pc.status = 'reserved' AND pc.reserved_by_order_id = (other->>'order_id')::uuid THEN 'PASS'
         ELSE 'FAIL' END,
    coalesce(v->>'error', 'success=' || (v->>'success')), o.status, o.payment_status, o.total_paisa, o.total_paid_paisa,
    o.advance_paid_paisa, o.balance_due_paisa, (to_jsonb(o)->>'refund_status'), (to_jsonb(o)->>'refund_amount_paisa')::int, led,
    (pc.reserved_by_order_id = (other->>'order_id')::uuid);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.6 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.7 refund fields cannot be changed by the seller's direct UPDATE (RPC only)
-- ---------------------------------------------------------------------------
DO $$
DECLARE oid uuid := pg_temp.ctx('19.6.order'); r1 text; r2 text; r3 text; r4 text; o record;
BEGIN
  IF oid IS NULL THEN RAISE NOTICE 'FAIL 19.7 setup missing (19.6 did not run)'; RETURN; END IF;
  r1 := pg_temp.try_as(audit.seller_a(), format('UPDATE orders SET refund_status = %L, refund_amount_paisa = 0 WHERE id = %L', 'none', oid));
  r2 := pg_temp.try_as(audit.seller_a(), format('UPDATE orders SET refund_status = %L, refund_reference = %L, refunded_at = now() WHERE id = %L', 'refunded', 'FAKE1234', oid));
  r3 := pg_temp.try_as(audit.seller_a(), format('UPDATE orders SET refund_amount_paisa = 1 WHERE id = %L', oid));
  r4 := pg_temp.try_as(audit.seller_a(), format('UPDATE orders SET shipping_address = %L WHERE id = %L', '15 Lansdowne Road, Kolkata', oid));
  SELECT refund_status, refund_amount_paisa, refund_reference INTO o FROM orders WHERE id = oid;
  RAISE NOTICE '% 19.7 seller direct UPDATE of refund fields -> clear=% | mark refunded=% | amount=% | control (shipping_address)=% | stored refund=%/%/%',
    CASE WHEN r1 LIKE 'OK rows=1' OR r2 LIKE 'OK rows=1' OR r3 LIKE 'OK rows=1' THEN 'FINDING'
         WHEN r1 LIKE 'ERR 42501%' AND r2 LIKE 'ERR 42501%' AND r3 LIKE 'ERR 42501%' AND r4 = 'OK rows=1'
              AND o.refund_status = 'required' AND o.refund_amount_paisa = 25000 AND o.refund_reference IS NULL THEN 'PASS'
         ELSE 'FAIL' END,
    left(r1, 16), left(r2, 16), left(r3, 16), r4, o.refund_status, o.refund_amount_paisa, coalesce(o.refund_reference, 'null');
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.7 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.8 SA-PAY-018 orders with a ledger row or a refund obligation cannot be deleted
-- ---------------------------------------------------------------------------
DO $$
DECLARE o5 uuid := pg_temp.ctx('19.5.order'); p uuid; x jsonb; y jsonb; r_ref text; r_led text; r_ctl text;
        led_before int; led_after int; pay_rows int;
BEGIN
  IF o5 IS NULL THEN RAISE NOTICE 'FAIL 19.8 setup missing (19.5 did not run)'; RETURN; END IF;
  -- a) refund-owed order (cancelled, verified ledger row, refund_status=required)
  led_before := pg_temp.ledger(o5);
  r_ref := pg_temp.try_as(audit.seller_a(), format('DELETE FROM orders WHERE id = %L', o5));
  led_after := pg_temp.ledger(o5);
  -- b) cancelled order that only has a (non-verified) ledger row
  p := pg_temp.piece('#L08', 120000);
  x := pg_temp.buy(ARRAY[p], 'full_payment');
  PERFORM pg_temp.release_as(audit.seller_a(), (x->>'order_id')::uuid);
  INSERT INTO order_payments (order_id, payment_type, amount_paisa, status, reference_id)
  VALUES ((x->>'order_id')::uuid, 'full', 100, 'pending', 'S19-PENDING-0001');
  r_led := pg_temp.try_as(audit.seller_a(), format('DELETE FROM orders WHERE id = %L', (x->>'order_id')::uuid));
  SELECT count(*) INTO pay_rows FROM order_payments WHERE order_id = (x->>'order_id')::uuid;
  -- c) control: a cancelled order without any payment record can still be deleted
  p := pg_temp.piece('#L09', 120000);
  y := pg_temp.buy(ARRAY[p], 'full_payment');
  PERFORM pg_temp.release_as(audit.seller_a(), (y->>'order_id')::uuid);
  r_ctl := pg_temp.try_as(audit.seller_a(), format('DELETE FROM orders WHERE id = %L', (y->>'order_id')::uuid));
  RAISE NOTICE '% 19.8 seller DELETE: refund-owed order -> % (ledger % -> %) | cancelled order with a ledger row -> % (rows kept=%) | control without payments -> %',
    CASE WHEN led_after < led_before OR r_led LIKE 'OK rows=1' THEN 'FINDING'
         WHEN r_ref LIKE 'ERR P0001%refund%' AND led_before = 128000 AND led_after = 128000
              AND r_led LIKE 'ERR P0001%ledger%' AND pay_rows = 1 AND r_ctl = 'OK rows=1' THEN 'PASS'
         ELSE 'FAIL' END,
    left(r_ref, 70), led_before, led_after, left(r_led, 70), pay_rows, r_ctl;
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.8 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.9 record_refund(p_order_id, p_refund_reference, p_note)
-- ---------------------------------------------------------------------------
DO $$
DECLARE o5 uuid := pg_temp.ctx('19.5.order'); o4 uuid := pg_temp.ctx('19.4.order'); o6 uuid := pg_temp.ctx('19.6.order');
        anon_priv boolean; anon_call text; r_other jsonb; r_bad1 jsonb; r_bad2 jsonb; r_none jsonb; r_ok jsonb;
        r_replay jsonb; r_diff jsonb; r_svc jsonb; ord record; ord6 record; r_del text;
BEGIN
  IF o5 IS NULL OR o4 IS NULL OR o6 IS NULL THEN RAISE NOTICE 'FAIL 19.9 setup missing (19.4/19.5/19.6 did not run)'; RETURN; END IF;
  anon_priv := has_function_privilege('anon', 'public.record_refund(uuid,text,text)', 'EXECUTE');
  PERFORM audit.as_anon();
  BEGIN
    PERFORM record_refund(o5, 'ANON-1234', NULL);
    anon_call := 'allowed';
  EXCEPTION WHEN insufficient_privilege THEN
    anon_call := 'permission denied';
  END;
  PERFORM audit.as_seller(audit.seller_b());
  r_other := record_refund(o5, 'UPI-REF-0001', NULL);
  PERFORM audit.as_seller(audit.seller_a());
  r_bad1 := record_refund(o5, 'ab', NULL);
  r_bad2 := record_refund(o5, 'REF;DROP TABLE', NULL);
  r_none := record_refund(o4, 'UPI-REF-0002', NULL);
  r_ok := record_refund(o5, '  UPI-REF 9876/01  ', 'Refunded via GPay to the buyer');
  r_replay := record_refund(o5, 'UPI-REF 9876/01', NULL);
  r_diff := record_refund(o5, 'UPI-REF-OTHER', NULL);
  PERFORM audit.as_service();
  r_svc := record_refund(o6, 'BANK-NEFT-77', NULL);
  PERFORM audit.as_postgres();
  SELECT * INTO ord FROM orders WHERE id = o5;
  SELECT * INTO ord6 FROM orders WHERE id = o6;

  RAISE NOTICE '% 19.9a anon cannot execute record_refund -> EXECUTE granted=% call=%',
    CASE WHEN NOT anon_priv AND anon_call = 'permission denied' THEN 'PASS' ELSE 'FINDING' END, anon_priv, anon_call;
  RAISE NOTICE '% 19.9b other seller -> %',
    CASE WHEN r_other->>'error' = 'ORDER_NOT_FOUND_OR_UNAUTHORIZED' THEN 'PASS'
         WHEN (r_other->>'success')::boolean THEN 'FINDING' ELSE 'FAIL' END, coalesce(r_other->>'error', r_other->>'success');
  RAISE NOTICE '% 19.9c invalid references "ab" / "REF;DROP TABLE" -> % / %',
    CASE WHEN r_bad1->>'error' = 'INVALID_REFUND_REFERENCE' AND r_bad2->>'error' = 'INVALID_REFUND_REFERENCE' THEN 'PASS' ELSE 'FAIL' END,
    coalesce(r_bad1->>'error', r_bad1->>'success'), coalesce(r_bad2->>'error', r_bad2->>'success');
  RAISE NOTICE '% 19.9d order without a refund obligation -> %',
    CASE WHEN r_none->>'error' = 'NO_REFUND_DUE' THEN 'PASS' ELSE 'FAIL' END, coalesce(r_none->>'error', r_none->>'success');
  RAISE NOTICE '% 19.9e happy path -> success=% idempotent=% status=% amount=% reference="%" refunded_at set=% | stored by seller A=% note appended=%',
    CASE WHEN (r_ok->>'success')::boolean AND NOT (r_ok->>'idempotent')::boolean
              AND r_ok ?& ARRAY['success','idempotent','order_id','order_code','refund_status','refund_amount_paisa','refund_reference','refunded_at']
              AND r_ok->>'refund_status' = 'refunded' AND (r_ok->>'refund_amount_paisa')::int = 128000
              AND r_ok->>'refund_reference' = 'UPI-REF 9876/01' AND r_ok->>'refunded_at' IS NOT NULL
              AND ord.refund_status = 'refunded' AND ord.refund_recorded_by = audit.seller_a()
              AND ord.notes LIKE '%Refunded via GPay to the buyer%' THEN 'PASS'
         ELSE 'FAIL' END,
    r_ok->>'success', r_ok->>'idempotent', r_ok->>'refund_status', r_ok->>'refund_amount_paisa', r_ok->>'refund_reference',
    (r_ok->>'refunded_at' IS NOT NULL), (ord.refund_recorded_by = audit.seller_a()), (ord.notes LIKE '%Refunded via GPay to the buyer%');
  RAISE NOTICE '% 19.9f replay with the same reference -> success=% idempotent=% | different reference -> %',
    CASE WHEN (r_replay->>'success')::boolean AND (r_replay->>'idempotent')::boolean AND r_diff->>'error' = 'NO_REFUND_DUE' THEN 'PASS' ELSE 'FAIL' END,
    r_replay->>'success', r_replay->>'idempotent', coalesce(r_diff->>'error', r_diff->>'success');
  RAISE NOTICE '% 19.9g trusted backend (service_role) -> % | order status=% recorded_by=%',
    CASE WHEN (r_svc->>'success')::boolean AND ord6.refund_status = 'refunded' AND ord6.refund_recorded_by IS NULL
              AND ord6.refund_reference = 'BANK-NEFT-77' THEN 'PASS' ELSE 'FAIL' END,
    coalesce(r_svc->>'error', 'success=' || (r_svc->>'success')), ord6.refund_status, coalesce(ord6.refund_recorded_by::text, 'null');

  -- a refunded order is still not deletable (its ledger and refund record are kept)
  r_del := pg_temp.try_as(audit.seller_a(), format('DELETE FROM orders WHERE id = %L', o5));
  RAISE NOTICE '% 19.9h seller DELETE of a refunded order -> %',
    CASE WHEN r_del LIKE 'ERR P0001%refund%' THEN 'PASS' WHEN r_del LIKE 'OK rows=1' THEN 'FINDING' ELSE 'FAIL' END, left(r_del, 80);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.9 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.10 SA-PAY-005 force_release_hold
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; x jsonb; y jsonb; z jsonb; r jsonb; r2 jsonb; r3 jsonb; before_v text; after_v text;
        o text; a text; pc record; yo text; ya text; yp text; zc jsonb;
BEGIN
  -- a) on-time claim in flight
  p := pg_temp.piece('#L10', 120000);
  x := pg_temp.buy(ARRAY[p], 'full_payment', '819000000010');
  before_v := pg_temp.rowvers((x->>'order_id')::uuid, (x->>'attempt_id')::uuid, p);
  r := pg_temp.release_as(audit.seller_a(), (x->>'order_id')::uuid);
  after_v := pg_temp.rowvers((x->>'order_id')::uuid, (x->>'attempt_id')::uuid, p);
  SELECT status INTO o FROM orders WHERE id = (x->>'order_id')::uuid;
  SELECT status INTO a FROM payment_attempts WHERE id = (x->>'attempt_id')::uuid;
  SELECT status, reserved_by_order_id INTO pc FROM products WHERE id = p;
  RAISE NOTICE '% 19.10a release with a claim in flight -> % attempt=% utr=% message=% | order=% attempt=% piece=% held=% rows unchanged=%',
    CASE WHEN (r->>'success')::boolean THEN 'FINDING'
         WHEN r->>'error' = 'PAYMENT_CLAIM_PENDING' AND r->>'payment_attempt_id' = x->>'attempt_id'
              AND r->>'buyer_submitted_utr' = '819000000010' AND r->>'message' LIKE '%Verify or reject it in Payments%'
              AND o = 'pending' AND a = 'awaiting_seller_verification' AND pc.status = 'reserved'
              AND pc.reserved_by_order_id = (x->>'order_id')::uuid AND before_v = after_v THEN 'PASS'
         ELSE 'FAIL' END,
    coalesce(r->>'error', 'success=' || (r->>'success')), (r->>'payment_attempt_id' = x->>'attempt_id'), r->>'buyer_submitted_utr',
    (r->>'message' IS NOT NULL), o, a, pc.status, (pc.reserved_by_order_id = (x->>'order_id')::uuid), (before_v = after_v);

  -- b) no claim: release works and expires the unclaimed attempt
  p := pg_temp.piece('#L11', 120000);
  y := pg_temp.buy(ARRAY[p], 'full_payment');
  r2 := pg_temp.release_as(audit.seller_a(), (y->>'order_id')::uuid);
  SELECT status INTO yo FROM orders WHERE id = (y->>'order_id')::uuid;
  SELECT status INTO ya FROM payment_attempts WHERE id = (y->>'attempt_id')::uuid;
  SELECT status INTO yp FROM products WHERE id = p;
  RAISE NOTICE '% 19.10b release without a claim -> success=% released=% expired attempts=% | order=% attempt=% piece=%',
    CASE WHEN (r2->>'success')::boolean AND yo = 'cancelled' AND ya = 'expired' AND yp = 'available'
              AND (r2->>'expired_attempts_count')::int = 1 AND (r2->>'released_products_count')::int = 1 THEN 'PASS'
         ELSE 'FAIL' END,
    r2->>'success', r2->>'released_products_count', r2->>'expired_attempts_count', yo, ya, yp;

  -- c) a LATE claim on a still-pending order also blocks the release
  p := pg_temp.piece('#L12', 120000);
  z := pg_temp.buy(ARRAY[p], 'full_payment');
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (z->>'attempt_id')::uuid;
  zc := pg_temp.claim(z, (z->>'attempt_id')::uuid, '819000000012');
  r3 := pg_temp.release_as(audit.seller_a(), (z->>'order_id')::uuid);
  RAISE NOTICE '% 19.10c release while a late claim (%) is pending on a pending order -> % (order=%)',
    CASE WHEN r3->>'error' = 'PAYMENT_CLAIM_PENDING' AND zc->>'status' = 'late_claim_pending_review'
              AND (SELECT status FROM orders WHERE id = (z->>'order_id')::uuid) = 'pending' THEN 'PASS'
         WHEN (r3->>'success')::boolean THEN 'FINDING' ELSE 'FAIL' END,
    zc->>'status', coalesce(r3->>'error', 'success=' || (r3->>'success')),
    (SELECT status FROM orders WHERE id = (z->>'order_id')::uuid);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.10 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.11 SA-PAY-003 / SA-PAY-007 reaper (037): pending orders whose hold AND claim window lapsed are
--       released and their claims move to late review (never expired); a confirmed order with a
--       balance claim stays; unclaimed holds are released
-- 19.12 lapsed claims are still verifiable (late path); unclaimed attempts past their window expire
-- ---------------------------------------------------------------------------
DO $$
DECLARE pc_a uuid; pc_b uuid; pc_c uuid; pc_d uuid; pc_e uuid; pc_f uuid;
        a jsonb; b jsonb; c jsonb; d jsonb; e jsonb; eb jsonb; f jsonb; cc jsonb;
        va_ jsonb; vc_ jsonb; ve_ jsonb; vf_ jsonb;
        a_before text; c_before text; e_before text; a_after text; c_after text; e_after text;
        sA text; sB text; sC text; sD text; sE text; ok_a boolean; ok_c boolean; ok_e boolean; ok_b boolean; ok_d boolean;
BEGIN
  -- A: on-time claim, window and hold both past
  pc_a := pg_temp.piece('#L20', 120000);
  a := pg_temp.buy(ARRAY[pc_a], 'full_payment', '819000000020');
  PERFORM pg_temp.expire((a->>'order_id')::uuid, (a->>'attempt_id')::uuid);
  -- B: unclaimed hold past expiry
  pc_b := pg_temp.piece('#L21', 120000);
  b := pg_temp.buy(ARRAY[pc_b], 'full_payment');
  PERFORM pg_temp.expire((b->>'order_id')::uuid, (b->>'attempt_id')::uuid);
  -- C: late claim on an order that is still pending (attempt window passed before the claim)
  pc_c := pg_temp.piece('#L22', 120000);
  c := pg_temp.buy(ARRAY[pc_c], 'full_payment');
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (c->>'attempt_id')::uuid;
  cc := pg_temp.claim(c, (c->>'attempt_id')::uuid, '819000000022');
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (c->>'order_id')::uuid;
  -- D: advance paid, 30-day hold lapsed, no balance claim -> expires (advance retained)
  pc_d := pg_temp.piece('#L23', 240000);
  d := pg_temp.buy(ARRAY[pc_d], 'advance', '819000000023');
  PERFORM pg_temp.verify_as(audit.seller_a(), (d->>'attempt_id')::uuid);
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (d->>'order_id')::uuid;
  -- E: advance paid, hold lapsed, balance claimed but not yet verified -> stays
  pc_e := pg_temp.piece('#L24', 240000);
  e := pg_temp.buy(ARRAY[pc_e], 'advance', '819000000024');
  PERFORM pg_temp.verify_as(audit.seller_a(), (e->>'attempt_id')::uuid);
  eb := pg_temp.initiate(e, NULL);
  PERFORM pg_temp.claim(e, (eb->>'payment_attempt_id')::uuid, '819000000025');
  PERFORM pg_temp.expire((e->>'order_id')::uuid, (eb->>'payment_attempt_id')::uuid);

  a_before := pg_temp.rowvers((a->>'order_id')::uuid, (a->>'attempt_id')::uuid, pc_a);
  c_before := pg_temp.rowvers((c->>'order_id')::uuid, (c->>'attempt_id')::uuid, pc_c);
  e_before := pg_temp.rowvers((e->>'order_id')::uuid, (eb->>'payment_attempt_id')::uuid, pc_e);

  PERFORM pg_temp.reap();

  a_after := pg_temp.rowvers((a->>'order_id')::uuid, (a->>'attempt_id')::uuid, pc_a);
  c_after := pg_temp.rowvers((c->>'order_id')::uuid, (c->>'attempt_id')::uuid, pc_c);
  e_after := pg_temp.rowvers((e->>'order_id')::uuid, (eb->>'payment_attempt_id')::uuid, pc_e);

  SELECT o.status || '/' || pa.status || '/' || p.status INTO sA FROM orders o, payment_attempts pa, products p
   WHERE o.id = (a->>'order_id')::uuid AND pa.id = (a->>'attempt_id')::uuid AND p.id = pc_a;
  SELECT o.status || '/' || pa.status || '/' || p.status INTO sB FROM orders o, payment_attempts pa, products p
   WHERE o.id = (b->>'order_id')::uuid AND pa.id = (b->>'attempt_id')::uuid AND p.id = pc_b;
  SELECT o.status || '/' || pa.status || '/' || p.status INTO sC FROM orders o, payment_attempts pa, products p
   WHERE o.id = (c->>'order_id')::uuid AND pa.id = (c->>'attempt_id')::uuid AND p.id = pc_c;
  SELECT o.status || '/' || o.payment_status || '/' || o.advance_paid_paisa || '/' || p.status INTO sD FROM orders o, products p
   WHERE o.id = (d->>'order_id')::uuid AND p.id = pc_d;
  SELECT o.status || '/' || pa.status || '/' || p.status INTO sE FROM orders o, payment_attempts pa, products p
   WHERE o.id = (e->>'order_id')::uuid AND pa.id = (eb->>'payment_attempt_id')::uuid AND p.id = pc_e;

  ok_a := sA = 'cancelled/late_claim_pending_review/available'
          AND (SELECT buyer_submitted_utr FROM payment_attempts WHERE id = (a->>'attempt_id')::uuid) = '819000000020';
  ok_b := sB = 'cancelled/expired/available';
  ok_c := cc->>'status' = 'late_claim_pending_review' AND sC = 'cancelled/late_claim_pending_review/available'
          AND (SELECT buyer_submitted_utr FROM payment_attempts WHERE id = (c->>'attempt_id')::uuid) = '819000000022';
  ok_d := sD = 'expired/advance_paid/25000/available';
  ok_e := sE = 'confirmed/awaiting_seller_verification/reserved' AND e_before = e_after;
  RAISE NOTICE '% 19.11 one reaper run -> lapsed claim A=% (changed=%) | late claim on pending C=% (changed=%) | overdue balance claim E=% (untouched=%) | unclaimed B=% | lapsed advance D=%',
    CASE WHEN sA LIKE '%/expired/%' OR sC LIKE '%/expired/%' OR sE LIKE 'expired%' OR sE LIKE '%/expired/%' THEN 'FINDING'
         WHEN sA LIKE 'pending/%/reserved' THEN 'FINDING'
         WHEN ok_a AND ok_b AND ok_c AND ok_d AND ok_e THEN 'PASS'
         ELSE 'FAIL' END,
    sA, (a_before <> a_after), sC, (c_before <> c_after), sE, (e_before = e_after), sB, sD;

  -- 19.12 the overdue claims are still verifiable; an unclaimed attempt past its window is not
  va_ := pg_temp.verify_as(audit.seller_a(), (a->>'attempt_id')::uuid);
  vc_ := pg_temp.verify_as(audit.seller_a(), (c->>'attempt_id')::uuid);
  ve_ := pg_temp.verify_as(audit.seller_a(), (eb->>'payment_attempt_id')::uuid);
  pc_f := pg_temp.piece('#L25', 120000);
  f := pg_temp.buy(ARRAY[pc_f], 'full_payment');
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (f->>'attempt_id')::uuid;
  vf_ := pg_temp.verify_as(audit.seller_a(), (f->>'attempt_id')::uuid);
  RAISE NOTICE '% 19.12 verify after the window: claim A -> %/% (late=%) | late claim C -> %/% (late=%) | balance claim E -> %/% | control: unclaimed attempt past expiry -> % (attempt=%)',
    CASE WHEN (va_->>'success')::boolean AND va_->>'order_status' = 'paid' AND (va_->>'is_late_claim')::boolean
              AND (vc_->>'success')::boolean AND vc_->>'order_status' = 'paid' AND (vc_->>'is_late_claim')::boolean
              AND (ve_->>'success')::boolean AND ve_->>'order_status' = 'paid'
              AND vf_->>'error' = 'PAYMENT_ATTEMPT_EXPIRED'
              AND (SELECT status FROM payment_attempts WHERE id = (f->>'attempt_id')::uuid) = 'expired' THEN 'PASS'
         WHEN NOT coalesce((va_->>'success')::boolean, false) OR NOT coalesce((ve_->>'success')::boolean, false) THEN 'FINDING'
         ELSE 'FAIL' END,
    coalesce(va_->>'error', 'ok'), va_->>'order_status', va_->>'is_late_claim', coalesce(vc_->>'error', 'ok'), vc_->>'order_status', vc_->>'is_late_claim',
    coalesce(ve_->>'error', 'ok'), ve_->>'order_status', coalesce(vf_->>'error', 'success=' || (vf_->>'success')),
    (SELECT status FROM payment_attempts WHERE id = (f->>'attempt_id')::uuid);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.11 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.13 on-time verification requires the pieces to be held by the order (no writes otherwise)
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; g jsonb; v jsonb; before_v text; after_v text; rows int;
BEGIN
  p := pg_temp.piece('#L26', 120000);
  g := pg_temp.buy(ARRAY[p], 'full_payment', '819000000026');
  -- simulate drift: the piece is no longer reserved for this order
  UPDATE products SET status = 'available', reserved_by_order_id = NULL, reserved_at = NULL WHERE id = p;
  before_v := pg_temp.rowvers((g->>'order_id')::uuid, (g->>'attempt_id')::uuid, p);
  v := pg_temp.verify_as(audit.seller_a(), (g->>'attempt_id')::uuid);
  after_v := pg_temp.rowvers((g->>'order_id')::uuid, (g->>'attempt_id')::uuid, p);
  SELECT count(*) INTO rows FROM order_payments WHERE order_id = (g->>'order_id')::uuid;
  RAISE NOTICE '% 19.13 verify when the piece is not reserved for the order -> % | ledger rows=% rows unchanged=%',
    CASE WHEN v->>'error' = 'INVENTORY_CONFLICT' AND rows = 0 AND before_v = after_v THEN 'PASS'
         WHEN (v->>'success')::boolean THEN 'FINDING' ELSE 'FAIL' END,
    coalesce(v->>'error', 'success=' || (v->>'success')), rows, (before_v = after_v);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.13 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.14 a late payment that cannot be applied (more than the order total) records nothing
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; h jsonb; hf jsonb; c jsonb; v jsonb; before_v text; after_v text; o record;
BEGIN
  p := pg_temp.piece('#L27', 240000);
  h := pg_temp.buy(ARRAY[p], 'advance');                 -- advance attempt (25000)
  hf := pg_temp.initiate(h, 'full');                     -- a second attempt for the full 240000
  PERFORM pg_temp.claim(h, (h->>'attempt_id')::uuid, '819000000027');
  PERFORM pg_temp.verify_as(audit.seller_a(), (h->>'attempt_id')::uuid);   -- confirmed, 25000 paid
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (hf->>'payment_attempt_id')::uuid;
  c := pg_temp.claim(h, (hf->>'payment_attempt_id')::uuid, '819000000028');   -- late claim of the full amount
  before_v := pg_temp.rowvers((h->>'order_id')::uuid, (hf->>'payment_attempt_id')::uuid, p);
  v := pg_temp.verify_as(audit.seller_a(), (hf->>'payment_attempt_id')::uuid);
  after_v := pg_temp.rowvers((h->>'order_id')::uuid, (hf->>'payment_attempt_id')::uuid, p);
  SELECT status, total_paid_paisa INTO o FROM orders WHERE id = (h->>'order_id')::uuid;
  RAISE NOTICE '% 19.14 late full-amount claim on an advance-paid order -> % | order=% total_paid=% ledger=% rows unchanged=%',
    CASE WHEN v->>'error' = 'PAYMENT_AMOUNT_MISMATCH' AND c->>'status' = 'late_claim_pending_review'
              AND o.status = 'confirmed' AND o.total_paid_paisa = 25000 AND pg_temp.ledger((h->>'order_id')::uuid) = 25000
              AND before_v = after_v THEN 'PASS'
         WHEN (v->>'success')::boolean OR v->>'error' LIKE 'EXCEPTION%' THEN 'FINDING'
         ELSE 'FAIL' END,
    coalesce(v->>'error', 'success=' || (v->>'success')), o.status, o.total_paid_paisa,
    pg_temp.ledger((h->>'order_id')::uuid), (before_v = after_v);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.14 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.15 reject keeps the hold while another payment claim on the order is in flight
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; j jsonb; jf jsonb; r1 jsonb; r2 jsonb; s1 text; s2 text;
BEGIN
  p := pg_temp.piece('#L28', 240000);
  j := pg_temp.buy(ARRAY[p], 'advance');
  jf := pg_temp.initiate(j, 'full');
  PERFORM pg_temp.claim(j, (j->>'attempt_id')::uuid, '819000000029');
  PERFORM pg_temp.claim(j, (jf->>'payment_attempt_id')::uuid, '819000000030');
  r1 := pg_temp.reject_as(audit.seller_a(), (j->>'attempt_id')::uuid, true);
  SELECT o.status || '/' || pr.status INTO s1 FROM orders o, products pr WHERE o.id = (j->>'order_id')::uuid AND pr.id = p;
  r2 := pg_temp.reject_as(audit.seller_a(), (jf->>'payment_attempt_id')::uuid, true);
  SELECT o.status || '/' || pr.status INTO s2 FROM orders o, products pr WHERE o.id = (j->>'order_id')::uuid AND pr.id = p;
  RAISE NOTICE '% 19.15 reject with another claim pending -> hold_released=% (order/piece=%) | reject of the last claim -> hold_released=% (order/piece=%)',
    CASE WHEN (r1->>'hold_released')::boolean THEN 'FINDING'
         WHEN (r1->>'success')::boolean AND NOT (r1->>'hold_released')::boolean AND s1 = 'pending/reserved'
              AND (r2->>'hold_released')::boolean AND s2 = 'cancelled/available' THEN 'PASS'
         ELSE 'FAIL' END,
    r1->>'hold_released', s1, r2->>'hold_released', s2;
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.15 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.16 late BALANCE after the advance hold expired, pieces still free -> order paid
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; k jsonb; kb jsonb; c jsonb; v jsonb; o record; pc text;
BEGIN
  p := pg_temp.piece('#L29', 240000);
  k := pg_temp.buy(ARRAY[p], 'advance', '819000000031');
  PERFORM pg_temp.verify_as(audit.seller_a(), (k->>'attempt_id')::uuid);
  kb := pg_temp.initiate(k, NULL);
  PERFORM pg_temp.expire((k->>'order_id')::uuid, (kb->>'payment_attempt_id')::uuid);
  PERFORM pg_temp.reap();
  c := pg_temp.claim(k, (kb->>'payment_attempt_id')::uuid, '819000000032');
  v := pg_temp.verify_as(audit.seller_a(), (kb->>'payment_attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (k->>'order_id')::uuid;
  SELECT status INTO pc FROM products WHERE id = p;
  RAISE NOTICE '% 19.16 late balance (claim=%) on an expired advance order, piece free -> % | order=%/% total_paid=% ledger=% piece=%',
    CASE WHEN (v->>'success')::boolean AND (v->>'is_late_claim')::boolean AND (v->>'inventory_available')::boolean
              AND c->>'status' = 'late_claim_pending_review' AND o.status = 'paid' AND o.payment_status = 'paid'
              AND o.total_paid_paisa = 240000 AND pg_temp.ledger(o.id) = 240000 AND pc = 'sold' THEN 'PASS'
         ELSE 'FAIL' END,
    c->>'status', coalesce(v->>'error', 'success=' || (v->>'success')), o.status, o.payment_status, o.total_paid_paisa,
    pg_temp.ledger(o.id), pc;
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.16 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.17 refund CHECK constraints hold even for trusted writers
-- ---------------------------------------------------------------------------
DO $$
DECLARE oid uuid := pg_temp.ctx('19.4.order'); r1 text; r2 text; r3 text;
BEGIN
  IF oid IS NULL THEN RAISE NOTICE 'FAIL 19.17 setup missing (19.4 did not run)'; RETURN; END IF;
  BEGIN
    UPDATE orders SET refund_status = 'required', refund_amount_paisa = total_paid_paisa + 1 WHERE id = oid;
    r1 := 'accepted';
  EXCEPTION WHEN check_violation THEN r1 := 'rejected';
  END;
  BEGIN
    UPDATE orders SET refund_status = 'refunded', refund_amount_paisa = 100 WHERE id = oid;
    r2 := 'accepted';
  EXCEPTION WHEN check_violation THEN r2 := 'rejected';
  END;
  BEGIN
    UPDATE orders SET refund_status = 'none', refund_amount_paisa = 100 WHERE id = oid;
    r3 := 'accepted';
  EXCEPTION WHEN check_violation THEN r3 := 'rejected';
  END;
  RAISE NOTICE '% 19.17 refund constraints: amount above total paid -> % | refunded without reference -> % | amount with status none -> %',
    CASE WHEN r1 = 'rejected' AND r2 = 'rejected' AND r3 = 'rejected' THEN 'PASS' ELSE 'FAIL' END, r1, r2, r3;
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.17 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.18 SA-OPS-001 migration 036 without pg_cron is a no-op (with pg_cron: job scheduled)
-- ---------------------------------------------------------------------------
DO $$
DECLARE avail boolean; installed boolean; has_schema boolean; jobs int;
BEGIN
  avail := EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'pg_cron');
  installed := EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron');
  has_schema := EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'cron');
  IF NOT avail THEN
    RAISE NOTICE '% 19.18 pg_cron not available here: 036 applied as a no-op (extension installed=%, cron schema=%)',
      CASE WHEN NOT installed AND NOT has_schema THEN 'PASS' ELSE 'FAIL' END, installed, has_schema;
  ELSIF installed THEN
    EXECUTE 'SELECT count(*) FROM cron.job WHERE jobname = $1 AND schedule = $2 AND command ILIKE $3'
       INTO jobs USING 'livedrop-release-expired-holds', '* * * * *', '%release_expired_holds%';
    RAISE NOTICE '% 19.18 pg_cron installed: livedrop-release-expired-holds scheduled every minute (jobs=%)',
      CASE WHEN jobs = 1 THEN 'PASS' ELSE 'FAIL' END, jobs;
  ELSE
    RAISE NOTICE 'INFO 19.18 pg_cron is available but not installed (036 logged why it could not create it)';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 19.19 every SECURITY DEFINER function in public pins search_path = public, pg_temp
-- ---------------------------------------------------------------------------
DO $$
DECLARE n_all int; n_bad int; bad text;
BEGIN
  SELECT count(*) INTO n_all
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public' AND p.prosecdef;
  SELECT count(*), string_agg(p.oid::regprocedure::text, ', ')
    INTO n_bad, bad
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
   WHERE ns.nspname = 'public' AND p.prosecdef
     AND NOT ('search_path=public, pg_temp' = ANY (coalesce(p.proconfig, '{}'::text[])));
  RAISE NOTICE '% 19.19 SECURITY DEFINER functions with pinned search_path: % of % (unpinned: %)',
    CASE WHEN n_bad = 0 THEN 'PASS' ELSE 'FINDING' END, n_all - n_bad, n_all, coalesce(bad, 'none');
END $$;

-- ---------------------------------------------------------------------------
-- 19.20 SA-SEC-001 privileges: views SELECT-only, no TRUNCATE on tables, safe defaults
-- ---------------------------------------------------------------------------
DO $$
DECLARE r record; bad_views text := ''; bad_tables text := ''; bad_new text := ''; n_views int := 0;
BEGIN
  FOR r IN SELECT c.oid, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relkind = 'v' LOOP
    n_views := n_views + 1;
    IF EXISTS (SELECT 1 FROM unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) AS pr(p),
                             unnest(ARRAY['anon','authenticated']) AS g(rol)
                WHERE has_table_privilege(g.rol, r.oid, pr.p)) THEN
      bad_views := bad_views || ' ' || r.relname;
    END IF;
  END LOOP;
  FOR r IN SELECT c.oid, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') LOOP
    IF EXISTS (SELECT 1 FROM unnest(ARRAY['TRUNCATE','REFERENCES','TRIGGER']) AS pr(p),
                             unnest(ARRAY['anon','authenticated']) AS g(rol)
                WHERE has_table_privilege(g.rol, r.oid, pr.p)) THEN
      bad_tables := bad_tables || ' ' || r.relname;
    END IF;
  END LOOP;
  RAISE NOTICE '% 19.20a no view in public grants anything but SELECT to anon/authenticated (% views; offenders:%)',
    CASE WHEN bad_views = '' THEN 'PASS' ELSE 'FINDING' END, n_views, coalesce(nullif(bad_views, ''), ' none');
  RAISE NOTICE '% 19.20b no table in public grants TRUNCATE/REFERENCES/TRIGGER to anon/authenticated (offenders:%)',
    CASE WHEN bad_tables = '' THEN 'PASS' ELSE 'FINDING' END, coalesce(nullif(bad_tables, ''), ' none');

  -- objects created later by the migration role inherit the tightened default privileges
  CREATE TABLE public.s19_future_table (id int PRIMARY KEY);
  CREATE VIEW public.s19_future_view AS SELECT id FROM public.s19_future_table;
  FOR r IN SELECT c.oid, c.relname FROM pg_class c WHERE c.oid IN ('public.s19_future_table'::regclass, 'public.s19_future_view'::regclass) LOOP
    IF EXISTS (SELECT 1 FROM unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) AS pr(p)
                WHERE has_table_privilege('anon', r.oid, pr.p))
       OR EXISTS (SELECT 1 FROM unnest(ARRAY['TRUNCATE','REFERENCES','TRIGGER']) AS pr(p)
                   WHERE has_table_privilege('authenticated', r.oid, pr.p)) THEN
      bad_new := bad_new || ' ' || r.relname;
    END IF;
  END LOOP;
  RAISE NOTICE '% 19.20c new tables/views get no anon INSERT/UPDATE/DELETE/TRUNCATE and no authenticated TRUNCATE by default (offenders:%)',
    CASE WHEN bad_new = '' THEN 'PASS' ELSE 'FINDING' END, coalesce(nullif(bad_new, ''), ' none');
  DROP VIEW public.s19_future_view;
  DROP TABLE public.s19_future_table;
END $$;

-- ---------------------------------------------------------------------------
-- 19.22 SA-PAY-007 claim window and lapsed-claim recovery (migration 037)
-- ---------------------------------------------------------------------------
DO $$
DECLARE p1 uuid; p2 uuid; p3 uuid; p4 uuid; x jsonb; y jsonb; z jsonb; w jsonb; other jsonb;
        h1 interval; v1 interval; h2 interval; v2 interval; q int; vz jsonb; vw jsonb; oz record; ow record; pz record; pw record;
        a_status text; dl0 timestamptz; dl1 timestamptz; rc jsonb;
BEGIN
  -- a) claim during a live -> hold and window 30 minutes
  p1 := pg_temp.piece('#L40', 120000);
  x := pg_temp.buy(ARRAY[p1], 'full_payment', '819000000040');
  SELECT o.hold_expires_at - now(), pa.verification_expires_at - now(), pa.verification_expires_at INTO h1, v1, dl0
    FROM orders o JOIN payment_attempts pa ON pa.order_id = o.id WHERE pa.id = (x->>'attempt_id')::uuid;
  rc := pg_temp.claim(x, (x->>'attempt_id')::uuid, '819000000041');   -- re-claim with another UTR
  SELECT verification_expires_at INTO dl1 FROM payment_attempts WHERE id = (x->>'attempt_id')::uuid;
  RAISE NOTICE '% 19.22a claim during a live -> hold in % window in % (claim response window=%) | re-claim keeps the window=%',
    CASE WHEN h1 > interval '30 minutes' THEN 'FINDING'
         WHEN h1 BETWEEN interval '29 minutes' AND interval '30 minutes' AND v1 BETWEEN interval '29 minutes' AND interval '30 minutes'
              AND (x->'claim'->>'verification_expires_at')::timestamptz = dl0 AND dl0 = dl1 AND (rc->>'success')::boolean THEN 'PASS'
         ELSE 'FAIL' END,
    date_trunc('second', h1), date_trunc('second', v1), x->'claim'->>'verification_expires_at', (dl0 = dl1);

  -- b) claim when the drop is not live (flipped directly with triggers off) -> 24 hours
  p2 := pg_temp.piece('#L41', 120000);
  y := pg_temp.buy(ARRAY[p2], 'full_payment');
  SET LOCAL session_replication_role = replica;
  UPDATE drops SET status = 'closed', closed_at = now() WHERE id = audit.drop_a_live();
  SET LOCAL session_replication_role = origin;
  PERFORM pg_temp.claim(y, (y->>'attempt_id')::uuid, '819000000042');
  SET LOCAL session_replication_role = replica;
  UPDATE drops SET status = 'live', closed_at = NULL WHERE id = audit.drop_a_live();
  SET LOCAL session_replication_role = origin;
  SELECT o.hold_expires_at - now(), pa.verification_expires_at - now() INTO h2, v2
    FROM orders o JOIN payment_attempts pa ON pa.order_id = o.id WHERE pa.id = (y->>'attempt_id')::uuid;
  RAISE NOTICE '% 19.22b claim on a drop that is not live -> hold in % window in %',
    CASE WHEN h2 BETWEEN interval '23 hours 59 minutes' AND interval '24 hours'
              AND v2 BETWEEN interval '23 hours 59 minutes' AND interval '24 hours' THEN 'PASS' ELSE 'FAIL' END,
    date_trunc('second', h2), date_trunc('second', v2);

  -- c) ADVANCE claim lapses -> reaper -> order cancelled, piece free, claim in late review and still
  --    selected by the seller queue filter -> verify -> order restored as confirmed/advance_paid
  p3 := pg_temp.piece('#L42', 240000);
  z := pg_temp.buy(ARRAY[p3], 'advance', '819000000043');
  PERFORM pg_temp.expire((z->>'order_id')::uuid, (z->>'attempt_id')::uuid);
  PERFORM pg_temp.reap();
  SELECT o.status || '/' || pa.status || '/' || pr.status INTO a_status
    FROM orders o, payment_attempts pa, products pr
   WHERE o.id = (z->>'order_id')::uuid AND pa.id = (z->>'attempt_id')::uuid AND pr.id = p3;
  PERFORM audit.as_seller(audit.seller_a());
  SELECT count(*) INTO q FROM payment_attempts pa JOIN orders o ON o.id = pa.order_id
   WHERE pa.id = (z->>'attempt_id')::uuid
     AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review');
  PERFORM audit.as_postgres();
  vz := pg_temp.verify_as(audit.seller_a(), (z->>'attempt_id')::uuid);
  SELECT * INTO oz FROM orders WHERE id = (z->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO pz FROM products WHERE id = p3;
  RAISE NOTICE '% 19.22c lapsed ADVANCE claim after reaper -> % (seller queue rows=%) | verify -> % late=% | order=%/% advance_paid=% ledger=% piece=% held=%',
    CASE WHEN a_status LIKE '%/expired/%' OR q = 0 THEN 'FINDING'
         WHEN a_status = 'cancelled/late_claim_pending_review/available' AND q = 1
              AND (vz->>'success')::boolean AND (vz->>'is_late_claim')::boolean AND NOT (vz->>'refund_required')::boolean
              AND oz.status = 'confirmed' AND oz.payment_status = 'advance_paid' AND oz.advance_paid_paisa = 25000
              AND pg_temp.ledger(oz.id) = 25000 AND pz.status = 'reserved' AND pz.reserved_by_order_id = oz.id THEN 'PASS'
         ELSE 'FAIL' END,
    a_status, q, coalesce(vz->>'error', 'success=' || (vz->>'success')), vz->>'is_late_claim',
    oz.status, oz.payment_status, oz.advance_paid_paisa, pg_temp.ledger(oz.id), pz.status, (pz.reserved_by_order_id = oz.id);

  -- d) FULL claim lapses -> reaper -> another buyer takes the piece -> verify -> refund obligation
  p4 := pg_temp.piece('#L43', 120000);
  w := pg_temp.buy(ARRAY[p4], 'full_payment', '819000000044');
  PERFORM pg_temp.expire((w->>'order_id')::uuid, (w->>'attempt_id')::uuid);
  PERFORM pg_temp.reap();
  other := pg_temp.buy(ARRAY[p4], 'full_payment');
  vw := pg_temp.verify_as(audit.seller_a(), (w->>'attempt_id')::uuid);
  SELECT * INTO ow FROM orders WHERE id = (w->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO pw FROM products WHERE id = p4;
  RAISE NOTICE '% 19.22d lapsed FULL claim, piece resold -> other checkout=% | verify -> % refund_required=% | order=%/% refund=%/% ledger=% | other buyer keeps piece=%',
    CASE WHEN (SELECT status FROM payment_attempts WHERE id = (w->>'attempt_id')::uuid) = 'expired' THEN 'FINDING'
         WHEN (other->>'success')::boolean AND (vw->>'success')::boolean AND (vw->>'refund_required')::boolean
              AND ow.status = 'cancelled' AND ow.refund_status = 'required' AND ow.refund_amount_paisa = 128000
              AND pg_temp.ledger(ow.id) = 128000 AND ow.total_paid_paisa = 128000
              AND pw.status = 'reserved' AND pw.reserved_by_order_id = (other->>'order_id')::uuid THEN 'PASS'
         ELSE 'FAIL' END,
    other->>'success', coalesce(vw->>'error', 'success=' || (vw->>'success')), vw->>'refund_required',
    ow.status, ow.payment_status, ow.refund_status, ow.refund_amount_paisa, pg_temp.ledger(ow.id),
    (pw.reserved_by_order_id = (other->>'order_id')::uuid);
EXCEPTION WHEN OTHERS THEN
  PERFORM audit.as_postgres();
  RAISE NOTICE 'FAIL 19.22 unexpected error: % %', SQLSTATE, SQLERRM;
END $$;

-- ---------------------------------------------------------------------------
-- 19.23 money in flight: no claimed attempt (UTR submitted) was ever set to 'expired' in this suite
-- ---------------------------------------------------------------------------
DO $$
DECLARE n int; ids text;
BEGIN
  SELECT count(*), string_agg(id::text, ', ') INTO n, ids
    FROM payment_attempts WHERE status = 'expired' AND buyer_submitted_utr IS NOT NULL;
  RAISE NOTICE '% 19.23 expired attempts carrying a buyer UTR: % (%)',
    CASE WHEN n = 0 THEN 'PASS' ELSE 'FINDING' END, n, coalesce(ids, 'none');
END $$;

-- ---------------------------------------------------------------------------
-- 19.21 ledger invariant: total_paid_paisa = SUM(verified ledger) for every order touched here
-- ---------------------------------------------------------------------------
DO $$
DECLARE n_all int; n_bad int; bad text;
BEGIN
  SELECT count(*) INTO n_all FROM orders;
  SELECT count(*), string_agg(s.order_code || ' ' || s.total_paid_paisa || '<>' || s.led, ', ')
    INTO n_bad, bad
    FROM (SELECT o.order_code, o.total_paid_paisa,
                 (SELECT coalesce(sum(op.amount_paisa), 0) FROM order_payments op
                   WHERE op.order_id = o.id AND op.status = 'verified') AS led
            FROM orders o) s
   WHERE s.total_paid_paisa <> s.led;
  RAISE NOTICE '% 19.21 ledger invariant holds for % of % orders (violations: %)',
    CASE WHEN n_bad = 0 THEN 'PASS' ELSE 'FAIL' END, n_all - n_bad, n_all, coalesce(bad, 'none');
END $$;

ROLLBACK;
