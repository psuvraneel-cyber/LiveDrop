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
DO $$
DECLARE b jsonb; r jsonb; v jsonb; o record; att text; prod text; in_queue int;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', '612345000111');
  SELECT status INTO att FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  RAISE NOTICE 'INFO 16.1a buyer claimed payment: attempt=% (order still pending, shown with a Release button)', att;

  PERFORM audit.as_seller(audit.seller_a());
  r := force_release_hold((b->>'order_id')::uuid);
  SELECT count(*) INTO in_queue FROM payment_attempts
   WHERE order_id = (b->>'order_id')::uuid
     AND status IN ('buyer_claimed','awaiting_seller_verification','late_claim_pending_review');
  BEGIN
    v := verify_manual_upi_payment((b->>'attempt_id')::uuid);
  EXCEPTION WHEN OTHERS THEN
    v := jsonb_build_object('success', false, 'error', 'EXCEPTION ' || SQLSTATE, 'message', SQLERRM);
  END;
  PERFORM audit.as_postgres();

  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT status INTO prod FROM products WHERE id = audit.p_a1();
  SELECT status INTO att FROM payment_attempts WHERE id = (b->>'attempt_id')::uuid;
  RAISE NOTICE '% 16.1b force_release_hold with a claim in flight -> release=% | order=% piece=% attempt=% still in seller queue=% | verify afterwards -> %',
    CASE WHEN (r->>'success')::boolean AND o.status = 'cancelled' THEN 'FINDING' ELSE 'PASS' END,
    r->>'success', o.status, prod, att, in_queue, coalesce(v->>'error', 'success=' || (v->>'success'));
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
