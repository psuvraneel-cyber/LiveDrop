-- =============================================================================
-- Suite 17 — can a seller erase verified payment ledger rows?
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
--
-- orders_seller_delete (008) lets sellers DELETE their own orders; the only
-- guard is prevent_finalized_order_deletion (latest: 010:274-281), which
-- blocks status confirmed/paid/shipped/expired — not 'cancelled'. Since 023 a
-- verified late claim can leave an order 'cancelled' + payment_status 'paid'
-- with a verified ledger row (refund owed). order_payments.order_id is
-- ON DELETE CASCADE (010:210). Authenticated has no DELETE privilege on
-- order_payments (011:39), but referential actions do not need it.
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

CREATE OR REPLACE FUNCTION pg_temp.seller_delete_order(p_order uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());
  BEGIN
    DELETE FROM orders WHERE id = p_order;
    GET DIAGNOSTICS n = ROW_COUNT;
  EXCEPTION WHEN OTHERS THEN
    PERFORM audit.as_postgres();
    RETURN 'ERR ' || SQLSTATE || ' ' || left(SQLERRM, 120);
  END;
  PERFORM audit.as_postgres();
  RETURN 'OK rows=' || n;
END $$;

-- 17.1 refund-owed late payment (cancelled + paid, verified ledger row) — can the seller delete it?
DO $$
DECLARE b jsonb; other jsonb; v jsonb; before_led int; after_led int; r text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = (b->>'attempt_id')::uuid;
  PERFORM audit.as_service(); PERFORM release_expired_holds(); PERFORM audit.as_postgres();
  other := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a1()], 'full_payment', NULL);
  PERFORM audit.as_anon();
  PERFORM submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, '912345670001');
  PERFORM audit.as_seller(audit.seller_a());
  v := verify_manual_upi_payment((b->>'attempt_id')::uuid);
  PERFORM audit.as_postgres();
  SELECT count(*) INTO before_led FROM order_payments WHERE order_id = (b->>'order_id')::uuid AND status = 'verified';
  r := pg_temp.seller_delete_order((b->>'order_id')::uuid);
  SELECT count(*) INTO after_led FROM order_payments WHERE order_id = (b->>'order_id')::uuid;
  -- Expected (SA-PAY-018): the deletion guard refuses (error names the refund) and the ledger row survives.
  RAISE NOTICE '% 17.1 seller DELETE of a refund-owed order (refund_required=%) -> % | verified ledger rows before=% after=%',
    CASE WHEN after_led < before_led THEN 'FINDING'
         WHEN r LIKE 'ERR%' AND r ILIKE '%refund%' AND before_led = 1 AND after_led = 1
              AND (v->>'refund_required')::boolean
              AND EXISTS (SELECT 1 FROM orders WHERE id = (b->>'order_id')::uuid) THEN 'PASS'
         ELSE 'FAIL' END,
    v->>'refund_required', r, before_led, after_led;
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();
UPDATE profiles SET advance_confirmation_enabled = true, advance_amount_paisa = 25000 WHERE id = audit.seller_a();

-- 17.2 advance received, hold later expired (advance retained, order 'expired') — can the seller delete it?
DO $$
DECLARE b jsonb; v jsonb; o record; before_led int; after_led int; r text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a2()], 'advance', '912345670002');
  PERFORM audit.as_seller(audit.seller_a());
  v := verify_manual_upi_payment((b->>'attempt_id')::uuid);
  PERFORM audit.as_postgres();
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  PERFORM audit.as_service(); PERFORM release_expired_holds(); PERFORM audit.as_postgres();
  SELECT * INTO o FROM orders WHERE id = (b->>'order_id')::uuid;
  SELECT count(*) INTO before_led FROM order_payments WHERE order_id = o.id AND status = 'verified';
  r := pg_temp.seller_delete_order(o.id);
  SELECT count(*) INTO after_led FROM order_payments WHERE order_id = (b->>'order_id')::uuid;
  RAISE NOTICE '% 17.2 seller DELETE of an expired advance-paid order (status=% payment=% advance=%) -> % | verified ledger rows before=% after=%',
    CASE WHEN after_led < before_led THEN 'FINDING' ELSE 'PASS' END, o.status, o.payment_status, o.advance_paid_paisa, r, before_led, after_led;
END $$;

UPDATE products SET status='available', reserved_by_order_id=NULL, reserved_at=NULL WHERE drop_id = audit.drop_a_live();

-- 17.3 control: a fully paid order cannot be deleted
DO $$
DECLARE b jsonb; v jsonb; r text;
BEGIN
  b := pg_temp.buy(audit.drop_a_live(), ARRAY[audit.p_a3()], 'full_payment', '912345670003');
  PERFORM audit.as_seller(audit.seller_a());
  v := verify_manual_upi_payment((b->>'attempt_id')::uuid);
  PERFORM audit.as_postgres();
  r := pg_temp.seller_delete_order((b->>'order_id')::uuid);
  RAISE NOTICE '% 17.3 seller DELETE of a paid order -> %', CASE WHEN r LIKE 'ERR%' THEN 'PASS' ELSE 'FAIL' END, r;
END $$;

ROLLBACK;
