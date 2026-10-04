-- =============================================================================
-- Suite 13 — direct-UPI payment verification behaviour behind the seller app
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

-- helper: buyer checkout + attempt (+ optional claim). Returns json with ids/tokens.
CREATE OR REPLACE FUNCTION pg_temp.buy(p_drop uuid, p_products uuid[], p_mode text, p_utr text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE o jsonb; a jsonb; c jsonb;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(p_drop, p_products, 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', p_mode, NULL);
  IF NOT (o->>'success')::boolean THEN
    PERFORM audit.as_postgres();
    RETURN o;
  END IF;
  a := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', NULL);
  IF p_utr IS NOT NULL THEN
    c := submit_buyer_payment_claim((o->>'order_id')::uuid, o->>'order_token', (a->>'payment_attempt_id')::uuid, p_utr);
  END IF;
  PERFORM audit.as_postgres();
  RETURN o || jsonb_build_object('attempt_id', a->>'payment_attempt_id', 'attempt_amount', a->>'expected_amount_paisa',
                                 'upi_uri', a->>'upi_uri', 'claim', c);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.verify_as_a(p_attempt uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());
  BEGIN
    r := verify_manual_upi_payment(p_attempt);
  EXCEPTION WHEN OTHERS THEN
    r := jsonb_build_object('success', false, 'error', 'EXCEPTION ' || SQLSTATE, 'message', SQLERRM);
  END;
  PERFORM audit.as_postgres();
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.reap() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM audit.as_service();
  PERFORM release_expired_holds();
  PERFORM audit.as_postgres();
END $$;

-- 13.1 full payment happy path
DO $$
DECLARE b jsonb; v jsonb; o record; led int; prod text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a3()], 'full_payment', '612345678901');
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  RAISE NOTICE 'INFO 13.1a after claim: order status=% payment=% hold_expires_in=%', o.status, o.payment_status, date_trunc('minute', o.hold_expires_at - now());
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT count(*) INTO led FROM order_payments WHERE order_id = o.id;
  SELECT status INTO prod FROM products WHERE id = audit.p_a3();
  RAISE NOTICE '% 13.1b verify -> success=% order=%/%/% total_paid=% ledger_rows=% product=%',
    CASE WHEN (v->>'success')::boolean AND o.status='paid' AND led=1 AND prod='sold' THEN 'PASS' ELSE 'FAIL' END,
    v->>'success', o.status, o.payment_status, o.fulfilment_status, o.total_paid_paisa, led, prod;
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT count(*) INTO led FROM order_payments WHERE order_id = o.id;
  RAISE NOTICE '% 13.1c second verify -> idempotent=% ledger_rows=%', CASE WHEN led=1 THEN 'PASS' ELSE 'FAIL' END, v->>'idempotent', led;
END $$;

-- 13.2 a syntactically valid (possibly fake) UTR during a live may extend the hold only to the
--      30-minute claim window, never to 24 hours (SA-PAY-007, migration 037)
DO $$
DECLARE b jsonb; before_h interval; after_h interval;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  SELECT hold_expires_at - now() INTO before_h FROM orders WHERE id = (b->>'order_id')::uuid;
  PERFORM audit.as_anon();
  PERFORM submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, 'NOTAREALUTR');
  PERFORM audit.as_postgres();
  SELECT hold_expires_at - now() INTO after_h FROM orders WHERE id = (b->>'order_id')::uuid;
  RAISE NOTICE '% 13.2 fabricated UTR "NOTAREALUTR" moved hold from % to % (piece unavailable to other buyers until seller acts)',
    CASE WHEN after_h > interval '30 minutes' THEN 'FINDING' ELSE 'PASS' END, date_trunc('minute', before_h), date_trunc('minute', after_h);
  -- release it for later tests
  PERFORM audit.as_seller(audit.seller_a());
  PERFORM reject_manual_upi_payment((b->>'attempt_id')::uuid, 'test cleanup', true);
  PERFORM audit.as_postgres();
END $$;

-- 13.3 same UTR claimed on two orders; case variant of a verified UTR
DO $$
DECLARE x jsonb; y jsonb; z jsonb; vx jsonb; vy jsonb; vz jsonb;
BEGIN
  x := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', 'ABCDEF123456');
  y := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', 'ABCDEF123456');
  RAISE NOTICE 'INFO 13.3a second order accepted the same UTR at claim time: %', y->'claim'->>'success';
  vx := pg_temp.verify_as_a((x->>'attempt_id')::uuid);
  vy := pg_temp.verify_as_a((y->>'attempt_id')::uuid);
  RAISE NOTICE '% 13.3b verify first=% second=%', CASE WHEN vy->>'error'='REFERENCE_USED_ON_ANOTHER_ORDER' THEN 'PASS' ELSE 'FAIL' END,
    vx->>'success', COALESCE(vy->>'error', vy->>'success');
  -- y is still pending with the duplicate claim; reject it so its piece frees up
  PERFORM audit.as_seller(audit.seller_a());
  PERFORM reject_manual_upi_payment((y->>'attempt_id')::uuid, 'duplicate', true);
  PERFORM audit.as_postgres();
  -- SA-PAY-011 (fixed in 038): the case variant is refused at claim time; if a claim slipped
  -- through (e.g. stored before 038), verification refuses it too.
  z := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', 'abcdef123456');
  IF (z->'claim'->>'success')::boolean THEN
    vz := pg_temp.verify_as_a((z->>'attempt_id')::uuid);
  END IF;
  RAISE NOTICE '% 13.3c lower-case variant of an already verified UTR on a different order: claim=% verify=%',
    CASE WHEN (vz->>'success')::boolean THEN 'FINDING'
         WHEN z->'claim'->>'error' = 'REFERENCE_USED_ON_ANOTHER_ORDER' OR vz->>'error' = 'REFERENCE_USED_ON_ANOTHER_ORDER' THEN 'PASS'
         ELSE 'FAIL' END,
    COALESCE(z->'claim'->>'error', z->'claim'->>'success'), COALESCE(vz->>'error', vz->>'success', 'not attempted');
END $$;

-- reset stock for the remaining tests
UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.4 reject from the app (releaseHold defaults to true) frees the piece immediately
DO $$
DECLARE b jsonb; r jsonb; o text; p text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', '712345678901');
  PERFORM audit.as_seller(audit.seller_a());
  r := reject_manual_upi_payment((b->>'attempt_id')::uuid, 'payment_not_found', true);
  PERFORM audit.as_postgres();
  SELECT status INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status INTO p FROM products WHERE id = audit.p_a1();
  RAISE NOTICE 'INFO 13.4 reject(payment_not_found) -> hold_released=% order=% piece=% (UI offers no "keep hold" choice)', r->>'hold_released', o, p;
END $$;

-- 13.5 LATE CLAIM on an ADVANCE order: only the advance is received
--      Expected (SA-PAY-001): confirmed / advance_paid, balance due = total - advance,
--      piece held for this order again, ledger sum = total_paid.
UPDATE profiles SET advance_confirmation_enabled = true, advance_amount_paisa = 25000 WHERE id = audit.seller_a();
DO $$
DECLARE b jsonb; v jsonb; o record; led_sum int; led_type text; piece record;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'advance', NULL);
  RAISE NOTICE 'INFO 13.5a advance order total=% advance_required=% attempt_amount=%', b->>'total_paisa', b->>'advance_required_paisa', b->>'attempt_amount';
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (b->>'attempt_id')::uuid;
  PERFORM pg_temp.reap();
  PERFORM audit.as_anon();
  PERFORM submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, '812345678901');
  PERFORM audit.as_postgres();
  RAISE NOTICE 'INFO 13.5b after reaper + late UTR: order=% attempt=%',
    (SELECT status FROM orders WHERE id = (b->>'order_id')::uuid), (SELECT status FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid);
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT sum(amount_paisa), string_agg(payment_type, ',') INTO led_sum, led_type FROM order_payments WHERE order_id = o.id AND status = 'verified';
  SELECT status, reserved_by_order_id INTO piece FROM products WHERE id = audit.p_a2();
  RAISE NOTICE '% 13.5c late advance verified -> order %/% total=% total_paid=% advance_paid=% balance_due=% hold_left=% piece=%/% | ledger records %=% paisa | rpc late=% inventory=% refund=%',
    CASE WHEN o.status='paid' AND o.total_paid_paisa > led_sum THEN 'FINDING'
         WHEN (v->>'success')::boolean AND o.status='confirmed' AND o.payment_status='advance_paid'
              AND o.total_paid_paisa = 25000 AND o.advance_paid_paisa = 25000 AND led_sum = o.total_paid_paisa
              AND o.balance_due_paisa = o.total_paisa - 25000 AND o.hold_expires_at > now() + interval '1 day'
              AND piece.status = 'reserved' AND piece.reserved_by_order_id = o.id
              AND (v->>'is_late_claim')::boolean AND (v->>'inventory_available')::boolean
              AND NOT (v->>'refund_required')::boolean THEN 'PASS'
         ELSE 'FAIL' END,
    o.status, o.payment_status, o.total_paisa, o.total_paid_paisa, o.advance_paid_paisa, o.balance_due_paisa,
    date_trunc('day', o.hold_expires_at - now()), piece.status, CASE WHEN piece.reserved_by_order_id = o.id THEN 'this-order' ELSE coalesce(piece.reserved_by_order_id::text, 'none') END,
    led_type, led_sum, v->>'is_late_claim', v->>'inventory_available', v->>'refund_required';
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.6 LATE CLAIM (full payment) after the piece was re-reserved by another buyer
--      Expected (SA-PAY-004): money recorded, order stays cancelled, refund_status = 'required'
--      with refund_amount = the payment, the other buyer keeps the piece.
DO $$
DECLARE b jsonb; other jsonb; v jsonb; o record; led_sum int; piece record;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (b->>'attempt_id')::uuid;
  PERFORM pg_temp.reap();
  other := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  PERFORM audit.as_anon();
  PERFORM submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, '912345678901');
  PERFORM audit.as_postgres();
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT coalesce(sum(amount_paisa), 0) INTO led_sum FROM order_payments WHERE order_id = o.id AND status = 'verified';
  SELECT status, reserved_by_order_id INTO piece FROM products WHERE id = audit.p_a1();
  RAISE NOTICE '% 13.6 late full payment, piece gone -> rpc success=% refund_required=% refund_amount=% | order status=% payment=% total_paid=% ledger=% refund_status=% refund_amount=% reason=% | piece=% held by other buyer=%',
    CASE WHEN o.status='cancelled' AND o.payment_status='paid' AND (to_jsonb(o)->>'refund_status') IS DISTINCT FROM 'required' THEN 'FINDING'
         WHEN (v->>'success')::boolean AND (v->>'refund_required')::boolean
              AND (v->>'refund_amount_paisa')::int = (b->>'attempt_amount')::int
              AND o.status = 'cancelled' AND to_jsonb(o)->>'refund_status' = 'required'
              AND (to_jsonb(o)->>'refund_amount_paisa')::int = (b->>'attempt_amount')::int
              AND to_jsonb(o)->>'refund_reason' = 'LATE_PAYMENT_INVENTORY_UNAVAILABLE' AND to_jsonb(o)->>'refund_required_at' IS NOT NULL
              AND o.total_paid_paisa = led_sum AND o.balance_due_paisa = o.total_paisa - o.total_paid_paisa
              AND piece.status = 'reserved' AND piece.reserved_by_order_id = (other->>'order_id')::uuid THEN 'PASS'
         ELSE 'FAIL' END,
    v->>'success', v->>'refund_required', v->>'refund_amount_paisa', o.status, o.payment_status, o.total_paid_paisa, led_sum,
    to_jsonb(o)->>'refund_status', to_jsonb(o)->>'refund_amount_paisa', to_jsonb(o)->>'refund_reason', piece.status, (piece.reserved_by_order_id = (other->>'order_id')::uuid);
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.7 LATE CLAIM (advance) after the piece was re-reserved
--      Expected (SA-PAY-006): no constraint error; advance recorded with a consistent balance,
--      order stays cancelled, refund_status = 'required' for the advance amount.
DO $$
DECLARE b jsonb; other jsonb; v jsonb; o record; led_sum int;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'advance', NULL);
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (b->>'attempt_id')::uuid;
  PERFORM pg_temp.reap();
  other := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', NULL);
  PERFORM audit.as_anon();
  PERFORM submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, '912345678902');
  PERFORM audit.as_postgres();
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT coalesce(sum(amount_paisa), 0) INTO led_sum FROM order_payments WHERE order_id = o.id AND status = 'verified';
  RAISE NOTICE '% 13.7 late advance, piece gone -> % % | order=%/% total=% total_paid=% advance_paid=% balance_due=% ledger=% refund=%/%',
    CASE WHEN v->>'error' LIKE 'EXCEPTION%' THEN 'FINDING'
         WHEN (v->>'success')::boolean AND (v->>'refund_required')::boolean
              AND o.status = 'cancelled' AND o.payment_status = 'advance_paid'
              AND o.total_paid_paisa = 25000 AND o.advance_paid_paisa = 25000 AND led_sum = o.total_paid_paisa
              AND o.balance_due_paisa = o.total_paisa - 25000
              AND to_jsonb(o)->>'refund_status' = 'required' AND (to_jsonb(o)->>'refund_amount_paisa')::int = 25000 THEN 'PASS'
         ELSE 'FAIL' END,
    coalesce(v->>'error', 'success=' || (v->>'success')), left(COALESCE(v->>'message',''), 90),
    o.status, o.payment_status, o.total_paisa, o.total_paid_paisa, o.advance_paid_paisa, o.balance_due_paisa, led_sum,
    to_jsonb(o)->>'refund_status', to_jsonb(o)->>'refund_amount_paisa';
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();
UPDATE profiles SET advance_confirmation_enabled = false WHERE id = audit.seller_a();

-- 13.8 a claimed-but-unverified payment whose window lapsed (SA-PAY-003 + SA-PAY-007, migration 037)
--      Expected: the reaper cancels the order and frees the piece (no 24h lock), but the claim is
--      never expired: it moves to late_claim_pending_review with its UTR, stays in the seller
--      queue, and verifying it re-secures the piece (still free) -> order paid.
DO $$
DECLARE b jsonb; o text; a record; p text; p_by uuid; queue int; v jsonb; o_after text; claimed_before timestamptz;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a3()], 'full_payment', '102345678901');
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET verification_expires_at = now() - interval '1 minute', expires_at = now() - interval '1 minute'
   WHERE id = (b->>'attempt_id')::uuid;
  SELECT buyer_claimed_at INTO claimed_before FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  PERFORM pg_temp.reap();
  SELECT status INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status, buyer_submitted_utr, buyer_claimed_at INTO a FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  SELECT status, reserved_by_order_id INTO p, p_by FROM products WHERE id = audit.p_a3();
  PERFORM audit.as_seller(audit.seller_a());
  SELECT count(*) INTO queue FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid
     AND status IN ('buyer_claimed','awaiting_seller_verification','late_claim_pending_review');
  PERFORM audit.as_postgres();
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT status INTO o_after FROM orders WHERE id = (b->>'order_id')::uuid;
  RAISE NOTICE '% 13.8 buyer-claimed payment past its window, reaper ran -> order=% attempt=% utr kept=% piece=% still in seller queue=% | verify afterwards -> % late=% (order=%)',
    CASE WHEN a.status = 'expired' OR queue = 0 THEN 'FINDING'
         WHEN o = 'pending' AND p = 'reserved' THEN 'FINDING'
         WHEN o = 'cancelled' AND a.status = 'late_claim_pending_review' AND a.buyer_submitted_utr = '102345678901'
              AND a.buyer_claimed_at = claimed_before AND p = 'available' AND p_by IS NULL
              AND queue = 1 AND (v->>'success')::boolean AND (v->>'is_late_claim')::boolean AND o_after = 'paid' THEN 'PASS'
         ELSE 'FAIL' END,
    o, a.status, (a.buyer_submitted_utr = '102345678901'), p, queue,
    coalesce(v->>'error', 'success=' || (v->>'success')), v->>'is_late_claim', o_after;
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.8b same, but another buyer bought the piece after the release -> refund obligation, other buyer keeps it
DO $$
DECLARE b jsonb; other jsonb; v jsonb; o record; piece record;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', '102345678902');
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET verification_expires_at = now() - interval '1 minute', expires_at = now() - interval '1 minute'
   WHERE id = (b->>'attempt_id')::uuid;
  PERFORM pg_temp.reap();
  other := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO piece FROM products WHERE id = audit.p_a1();
  RAISE NOTICE '% 13.8b lapsed claim, piece resold -> other buyer checkout=% | verify -> % refund_required=% | order=% refund=%/% | piece held by other buyer=%',
    CASE WHEN (SELECT status FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid) = 'expired' THEN 'FINDING'
         WHEN (other->>'success')::boolean AND (v->>'success')::boolean AND (v->>'refund_required')::boolean
              AND o.status = 'cancelled' AND o.refund_status = 'required' AND o.refund_amount_paisa = (b->>'attempt_amount')::int
              AND piece.status = 'reserved' AND piece.reserved_by_order_id = (other->>'order_id')::uuid THEN 'PASS'
         ELSE 'FAIL' END,
    other->>'success', coalesce(v->>'error', 'success=' || (v->>'success')), v->>'refund_required',
    o.status, o.refund_status, o.refund_amount_paisa, (piece.reserved_by_order_id = (other->>'order_id')::uuid);
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.9 UPI deep link built from seller-controlled display name
DO $$
DECLARE u text;
BEGIN
  u := generate_upi_payment_uri('aarohi@okaxis', 'Aarohi #1 Boutique & Co 100%', 150000, 'LD-ABC123-FUL-1A2B', 'LiveDrop LD-ABC123');
  RAISE NOTICE '% 13.9 generate_upi_payment_uri -> %', CASE WHEN u LIKE '%#1%' OR u LIKE '%100%%' THEN 'FINDING' ELSE 'PASS' END, u;
END $$;

-- 13.10 free-shipping threshold: drop threshold, else shop threshold, else none (SA-PAY-008, migration 037)
UPDATE profiles SET free_shipping_threshold_paisa = 200000 WHERE id = audit.seller_a();
DO $$
DECLARE b jsonb; d int; s int; r int;
BEGIN
  SELECT free_shipping_threshold_paisa INTO d FROM drops WHERE id = audit.drop_a_live();
  SELECT free_shipping_threshold_paisa INTO s FROM profiles WHERE id = audit.seller_a();
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', NULL);
  RAISE NOTICE '% 13.10a drop threshold=% profile threshold=% subtotal=% -> shipping charged=% (drop banner promises shipping until %)',
    CASE WHEN (b->>'shipping_paisa')::int = 0 AND (b->>'subtotal_paisa')::int < d THEN 'FINDING' ELSE 'PASS' END,
    d, s, b->>'subtotal_paisa', b->>'shipping_paisa', d;
  UPDATE drops SET free_shipping_threshold_paisa = 100000 WHERE id = audit.drop_a_live();
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  RAISE NOTICE '% 13.10b drop threshold=100000 subtotal=% -> shipping charged=% (drop banner promised free shipping)',
    CASE WHEN (b->>'shipping_paisa')::int > 0 THEN 'FINDING' ELSE 'PASS' END, b->>'subtotal_paisa', b->>'shipping_paisa';
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.10c drop threshold beats the shop threshold in both directions; NULL/NULL charges shipping;
--        resolve_free_shipping_threshold returns the same value checkout applies and is callable by anon.
DO $$
DECLARE b jsonb; c jsonb; n jsonb; r_beats int; r_none int; anon_ok boolean;
BEGIN
  -- shop 100000 (would make Rs 2,500 free), drop 299900 -> shipping charged
  UPDATE profiles SET free_shipping_threshold_paisa = 100000 WHERE id = audit.seller_a();
  UPDATE drops SET free_shipping_threshold_paisa = 299900 WHERE id = audit.drop_a_live();
  PERFORM audit.as_anon();
  r_beats := resolve_free_shipping_threshold(audit.drop_a_live());
  PERFORM audit.as_postgres();
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', NULL);
  -- drop NULL -> the shop threshold applies (100000 <= 150000 -> free)
  UPDATE drops SET free_shipping_threshold_paisa = NULL WHERE id = audit.drop_a_live();
  c := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();
  -- drop NULL and shop NULL -> no free shipping at any subtotal
  UPDATE profiles SET free_shipping_threshold_paisa = NULL WHERE id = audit.seller_a();
  PERFORM audit.as_anon();
  r_none := resolve_free_shipping_threshold(audit.drop_a_live());
  PERFORM audit.as_postgres();
  n := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1(), audit.p_a2(), audit.p_a3()], 'full_payment', NULL);
  anon_ok := has_function_privilege('anon', 'public.resolve_free_shipping_threshold(uuid)', 'EXECUTE');
  RAISE NOTICE '% 13.10c drop 299900 vs shop 100000, subtotal % -> shipping % (resolved %) | drop NULL, shop 100000, subtotal % -> shipping % | drop NULL, shop NULL, subtotal % -> shipping % (resolved %) | anon EXECUTE=%',
    CASE WHEN (b->>'shipping_paisa')::int = 8000 AND r_beats = 299900
              AND (c->>'shipping_paisa')::int = 0
              AND (n->>'shipping_paisa')::int = 8000 AND r_none IS NULL AND anon_ok THEN 'PASS'
         WHEN (n->>'shipping_paisa')::int = 0 OR (b->>'shipping_paisa')::int = 0 THEN 'FINDING'
         ELSE 'FAIL' END,
    b->>'subtotal_paisa', b->>'shipping_paisa', r_beats, c->>'subtotal_paisa', c->>'shipping_paisa',
    n->>'subtotal_paisa', n->>'shipping_paisa', coalesce(r_none::text, 'NULL'), anon_ok;
  UPDATE drops SET free_shipping_threshold_paisa = 299900 WHERE id = audit.drop_a_live();
END $$;

-- 13.10d no hidden Rs 2,000 default on the threshold columns
DO $$
DECLARE dd text; pd text;
BEGIN
  SELECT column_default INTO dd FROM information_schema.columns WHERE table_schema='public' AND table_name='drops' AND column_name='free_shipping_threshold_paisa';
  SELECT column_default INTO pd FROM information_schema.columns WHERE table_schema='public' AND table_name='profiles' AND column_name='free_shipping_threshold_paisa';
  RAISE NOTICE '% 13.10d column defaults: drops=% profiles=%',
    CASE WHEN dd IS NULL AND pd IS NULL THEN 'PASS' ELSE 'FINDING' END, coalesce(dd, 'none'), coalesce(pd, 'none');
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.11 seller can "verify" an attempt the buyer never claimed (no UTR at all)
DO $$
DECLARE b jsonb; v jsonb; ref text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT reference_id INTO ref FROM order_payments WHERE order_id = (b->>'order_id')::uuid;
  RAISE NOTICE 'INFO 13.11 verify of unclaimed attempt -> success=% ledger reference=% (internal reference, not a bank UTR)', v->>'success', ref;
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.12 buyer can replace the UTR while the seller is reviewing it
DO $$
DECLARE b jsonb; c jsonb; utr text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', '111111111111');
  PERFORM audit.as_anon();
  c := submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, '222222222222');
  PERFORM audit.as_postgres();
  SELECT buyer_submitted_utr INTO utr FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  RAISE NOTICE 'INFO 13.12 re-claim with a different UTR -> success=% stored UTR now=% (no history of the first UTR)', c->>'success', utr;
END $$;

-- 13.13 seller turns UPI off mid-drop: buyers can no longer start payment
DO $$
DECLARE o jsonb; a jsonb;
BEGIN
  UPDATE profiles SET upi_enabled = false WHERE id = audit.seller_a();
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_a_live(), ARRAY[audit.p_a3()], 'Late Buyer', '9830077777', '2 Hazra Road, Kolkata', '700026', 'full_payment', NULL);
  IF (o->>'success')::boolean THEN
    a := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', NULL);
  END IF;
  PERFORM audit.as_postgres();
  -- SA-PAY-012 (fixed in 039): checkout refuses before reserving anything.
  RAISE NOTICE '% 13.13 upi_enabled=false: checkout -> % piece=% | initiate_payment_attempt -> %',
    CASE WHEN o->>'error' = 'UPI_DISABLED' AND (SELECT status FROM products WHERE id = audit.p_a3()) = 'available' THEN 'PASS'
         WHEN (o->>'success')::boolean THEN 'FINDING' ELSE 'FAIL' END,
    COALESCE(o->>'error', o->>'success'), (SELECT status FROM products WHERE id = audit.p_a3()), COALESCE(a->>'error', 'not attempted');
  UPDATE profiles SET upi_enabled = true WHERE id = audit.seller_a();
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 13.14 claim window (SA-PAY-007): 30 minutes while the drop is live, 24 hours otherwise;
--       a re-claim with another UTR keeps the original window.
DO $$
DECLARE b jsonb; c jsonb; r jsonb; live_h interval; live_v interval; v1 timestamptz; v2 timestamptz; off_h interval; off_v interval;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', '131400000001');
  SELECT o.hold_expires_at - now(), pa.verification_expires_at - now(), pa.verification_expires_at INTO live_h, live_v, v1
    FROM orders o JOIN payment_attempts pa ON pa.order_id = o.id WHERE o.id = (b->>'order_id')::uuid;
  PERFORM audit.as_anon();
  r := submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, '131400000002');
  PERFORM audit.as_postgres();
  SELECT verification_expires_at INTO v2 FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  RAISE NOTICE '% 13.14a claim during a live -> hold in % / window in % | re-claim with another UTR -> success=% window unchanged=%',
    CASE WHEN live_h > interval '23 hours' THEN 'FINDING'
         WHEN live_h BETWEEN interval '29 minutes' AND interval '30 minutes' AND live_v BETWEEN interval '29 minutes' AND interval '30 minutes'
              AND (r->>'success')::boolean AND v1 = v2 THEN 'PASS'
         ELSE 'FAIL' END,
    date_trunc('second', live_h), date_trunc('second', live_v), r->>'success', (v1 = v2);

  -- the same claim after the live ended (drop no longer live, order still pending). The drop's
  -- status is flipped directly with triggers disabled (close_drop would also cancel the order).
  c := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', NULL);
  SET LOCAL session_replication_role = replica;
  UPDATE drops SET status = 'closed', closed_at = now() WHERE id = audit.drop_a_live();
  SET LOCAL session_replication_role = origin;
  PERFORM audit.as_anon();
  PERFORM submit_buyer_payment_claim((c->>'order_id')::uuid, c->>'order_token', (c->>'attempt_id')::uuid, '131400000003');
  PERFORM audit.as_postgres();
  SET LOCAL session_replication_role = replica;
  UPDATE drops SET status = 'live', closed_at = NULL WHERE id = audit.drop_a_live();
  SET LOCAL session_replication_role = origin;
  SELECT o.hold_expires_at - now(), pa.verification_expires_at - now() INTO off_h, off_v
    FROM orders o JOIN payment_attempts pa ON pa.order_id = o.id WHERE o.id = (c->>'order_id')::uuid;
  RAISE NOTICE '% 13.14b claim when the drop is not live -> hold in % / window in %',
    CASE WHEN off_h BETWEEN interval '23 hours 59 minutes' AND interval '24 hours'
              AND off_v BETWEEN interval '23 hours 59 minutes' AND interval '24 hours' THEN 'PASS'
         ELSE 'FAIL' END,
    date_trunc('second', off_h), date_trunc('second', off_v);
END $$;

ROLLBACK;
