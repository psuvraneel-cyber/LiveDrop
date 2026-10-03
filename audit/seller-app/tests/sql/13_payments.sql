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

-- 13.2 any syntactically valid UTR extends the inventory hold from 15 minutes to 24 hours
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
    CASE WHEN after_h > interval '23 hours' THEN 'FINDING' ELSE 'PASS' END, date_trunc('minute', before_h), date_trunc('minute', after_h);
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
  z := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', 'abcdef123456');
  vz := pg_temp.verify_as_a((z->>'attempt_id')::uuid);
  RAISE NOTICE '% 13.3c lower-case variant of an already verified UTR verified on a different order: %',
    CASE WHEN (vz->>'success')::boolean THEN 'FINDING' ELSE 'PASS' END, COALESCE(vz->>'error', vz->>'success');
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

-- 13.8 a claimed-but-unverified payment must not expire after 24h (SA-PAY-003)
--      Expected: the reaper leaves order, attempt and piece untouched; the claim stays in the
--      seller queue (overdue) and can still be verified.
DO $$
DECLARE b jsonb; o text; a text; p text; p_by uuid; queue int; v jsonb; o_after text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a3()], 'full_payment', '102345678901');
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET verification_expires_at = now() - interval '1 minute', expires_at = now() - interval '1 minute'
   WHERE id = (b->>'attempt_id')::uuid;
  PERFORM pg_temp.reap();
  SELECT status INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status INTO a FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  SELECT status, reserved_by_order_id INTO p, p_by FROM products WHERE id = audit.p_a3();
  PERFORM audit.as_seller(audit.seller_a());
  SELECT count(*) INTO queue FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid
     AND status IN ('buyer_claimed','awaiting_seller_verification','late_claim_pending_review');
  PERFORM audit.as_postgres();
  v := pg_temp.verify_as_a((b->>'attempt_id')::uuid);
  SELECT status INTO o_after FROM orders WHERE id = (b->>'order_id')::uuid;
  RAISE NOTICE '% 13.8 buyer-claimed payment after 24h without seller action -> order=% attempt=% piece=% held by order=% still in seller queue=% | verify afterwards -> % (order=%)',
    CASE WHEN o='cancelled' AND queue=0 THEN 'FINDING'
         WHEN o='pending' AND a='awaiting_seller_verification' AND p='reserved' AND p_by = (b->>'order_id')::uuid
              AND queue=1 AND (v->>'success')::boolean AND o_after='paid' THEN 'PASS'
         ELSE 'FAIL' END,
    o, a, p, (p_by = (b->>'order_id')::uuid), queue, coalesce(v->>'error', 'success=' || (v->>'success')), o_after;
END $$;

-- 13.9 UPI deep link built from seller-controlled display name
DO $$
DECLARE u text;
BEGIN
  u := generate_upi_payment_uri('aarohi@okaxis', 'Aarohi #1 Boutique & Co 100%', 150000, 'LD-ABC123-FUL-1A2B', 'LiveDrop LD-ABC123');
  RAISE NOTICE '% 13.9 generate_upi_payment_uri -> %', CASE WHEN u LIKE '%#1%' OR u LIKE '%100%%' THEN 'FINDING' ELSE 'PASS' END, u;
END $$;

-- 13.10 free-shipping threshold configured on the drop vs the threshold the RPC applies
DO $$
DECLARE b jsonb; d int; s int;
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
  a := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', NULL);
  PERFORM audit.as_postgres();
  RAISE NOTICE 'INFO 13.13 upi_enabled=false: checkout success=% (piece reserved) but initiate_payment_attempt -> %',
    o->>'success', a->>'error';
  UPDATE profiles SET upi_enabled = true WHERE id = audit.seller_a();
END $$;

ROLLBACK;
