-- =============================================================================
-- Suite 25 — UPI payment link for personal UPI IDs (migration 043, SA-PAY-015)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

DO $$
DECLARE u text; d text; a jsonb; o jsonb;
BEGIN
  -- 25.1 plain P2P form: no merchant fields, exact amount, order code in the note
  u := generate_upi_payment_uri(' Aarohi@OkAxis ', 'Aarohi #1 Boutique & Co 100%', 100, 'LD-ABC123-ADV-1A2B', 'LiveDrop LD-ABC123 advance');
  RAISE NOTICE '%', audit.check('25.1',
    u = 'upi://pay?pa=aarohi@okaxis&pn=Aarohi%201%20Boutique%20Co%20100&am=1.00&cu=INR&tn=LiveDrop%20LD-ABC123%20advance',
    u);
  RAISE NOTICE '%', audit.check('25.2', u NOT LIKE '%&tr=%' AND u NOT LIKE '%&mc=%' AND u NOT LIKE '%&url=%',
    'no merchant-only parameters (tr, mc, url)');

  -- 25.3 empty or symbol-only names fall back; long names are shortened
  d := generate_upi_payment_uri('a@okaxis', '###', 150000, 'x', NULL);
  RAISE NOTICE '%', audit.check('25.3',
    d LIKE '%&pn=LiveDrop%20Seller&%' AND d LIKE '%&am=1500.00&%' AND d LIKE '%&tn=LiveDrop%20Order'
    AND length(split_part(split_part(generate_upi_payment_uri('a@okaxis', repeat('A', 200), 100, 'x', 'n'), '&pn=', 2), '&', 1)) = 50,
    d);

  -- 25.4 a real payment attempt returns the new form
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_a_live(), ARRAY[audit.p_a1()], 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', 'full_payment', NULL);
  a := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', NULL);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('25.4',
    (a->>'success')::boolean AND a->>'upi_uri' LIKE 'upi://pay?pa=%' AND a->>'upi_uri' NOT LIKE '%&tr=%'
    AND a->>'upi_uri' LIKE '%' || (o->>'order_code') || '%',
    a->>'upi_uri');
END $$;

ROLLBACK;
