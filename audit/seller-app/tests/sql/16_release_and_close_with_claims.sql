-- =============================================================================
-- Suite 16 — seller "Release" / "Close drop" while a buyer payment claim is in flight
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
--
-- The seller app shows a red "Release" button on every pending order card
-- (seller-app/lib/presentation/orders/order_card.dart:407-427) and calls
-- force_release_hold (migration 009, never revised after the payment-attempt
-- model of 013/023 was introduced). close_drop (024) is the control: it was
-- written to preserve orders whose buyer has already claimed payment.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

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
  RETURN o || jsonb_build_object('attempt_id', a->>'payment_attempt_id', 'claim', c);
END $$;

-- 16.1 "Release" on an order whose buyer has already paid and submitted a UTR
--      Expected (SA-PAY-005): error PAYMENT_CLAIM_PENDING (with the claim's attempt id and UTR),
--      order / piece / attempt unchanged, claim still in the queue and still verifiable.
DO $$
DECLARE b jsonb; r jsonb; v jsonb; o record; att text; prod text; prod_by uuid; in_queue int; o_final text;
        ctid_before tid[]; ctid_after tid[];
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', '612345000111');
  SELECT status INTO att FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  RAISE NOTICE 'INFO 16.1a buyer claimed payment: attempt=% (order still pending, shown with a Release button)', att;
  -- physical row versions before the release attempt: any UPDATE creates a new ctid
  SELECT ARRAY[(SELECT ctid FROM orders WHERE id = (b->>'order_id')::uuid),
               (SELECT ctid FROM products WHERE id = audit.p_a1()),
               (SELECT ctid FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid)] INTO ctid_before;

  PERFORM audit.as_seller(audit.seller_a());
  r := force_release_hold((b->>'order_id')::uuid);
  SELECT count(*) INTO in_queue FROM payment_attempts
   WHERE order_id = (b->>'order_id')::uuid
     AND status IN ('buyer_claimed','awaiting_seller_verification','late_claim_pending_review');
  PERFORM audit.as_postgres();

  -- state right after the release attempt
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status, reserved_by_order_id INTO prod, prod_by FROM products WHERE id = audit.p_a1();
  SELECT status INTO att FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  SELECT ARRAY[(SELECT ctid FROM orders WHERE id = (b->>'order_id')::uuid),
               (SELECT ctid FROM products WHERE id = audit.p_a1()),
               (SELECT ctid FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid)] INTO ctid_after;

  PERFORM audit.as_seller(audit.seller_a());
  BEGIN
    v := verify_manual_upi_payment((b->>'attempt_id')::uuid);
  EXCEPTION WHEN OTHERS THEN
    v := jsonb_build_object('success', false, 'error', 'EXCEPTION ' || SQLSTATE, 'message', SQLERRM);
  END;
  PERFORM audit.as_postgres();
  SELECT status INTO o_final FROM orders WHERE id = (b->>'order_id')::uuid;

  RAISE NOTICE '% 16.1b force_release_hold with a claim in flight -> % | after release: order=% piece=% held by order=% attempt=% rows unchanged=% in seller queue=% | verify afterwards -> % (order=%)',
    CASE WHEN (r->>'success')::boolean AND o.status = 'cancelled' THEN 'FINDING'
         WHEN r->>'error' = 'PAYMENT_CLAIM_PENDING'
              AND r->>'payment_attempt_id' = b->>'attempt_id' AND r->>'buyer_submitted_utr' = '612345000111'
              AND o.status = 'pending' AND ctid_after = ctid_before
              AND prod = 'reserved' AND prod_by = o.id AND att = 'awaiting_seller_verification' AND in_queue = 1
              AND (v->>'success')::boolean AND o_final = 'paid' THEN 'PASS'
         ELSE 'FAIL' END,
    coalesce(r->>'error', 'release=' || (r->>'success')), o.status, prod, (prod_by = o.id), att, (ctid_after = ctid_before), in_queue,
    coalesce(v->>'error', 'success=' || (v->>'success')), o_final;
END $$;

-- 16.1c control: "Release" without a payment claim still works and expires the unclaimed attempt
DO $$
DECLARE b jsonb; r jsonb; o text; prod text; att text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a3()], 'full_payment', NULL);
  PERFORM audit.as_seller(audit.seller_a());
  r := force_release_hold((b->>'order_id')::uuid);
  PERFORM audit.as_postgres();
  SELECT status INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status INTO prod FROM products WHERE id = audit.p_a3();
  SELECT status INTO att FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  RAISE NOTICE '% 16.1c force_release_hold without a claim -> release=% order=% piece=% attempt=%',
    CASE WHEN (r->>'success')::boolean AND o = 'cancelled' AND prod = 'available' AND att = 'expired' THEN 'PASS' ELSE 'FAIL' END,
    coalesce(r->>'error', r->>'success'), o, prod, att;
END $$;

-- 16.2 control: close_drop preserves the same situation (claimed order keeps its piece)
DO $$
DECLARE b jsonb; c jsonb; o record; prod text; att text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'full_payment', '612345000222');
  PERFORM audit.as_seller(audit.seller_a());
  c := close_drop(audit.drop_a_live());
  PERFORM audit.as_postgres();
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status INTO prod FROM products WHERE id = audit.p_a2();
  SELECT status INTO att FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  RAISE NOTICE '% 16.2 close_drop with a claim in flight -> close=% order=% piece=% attempt=%',
    CASE WHEN o.status = 'pending' AND prod = 'reserved' AND att = 'awaiting_seller_verification' THEN 'PASS' ELSE 'FAIL' END,
    c->>'success', o.status, prod, att;
END $$;

ROLLBACK;
