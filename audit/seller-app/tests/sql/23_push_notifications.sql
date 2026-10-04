-- =============================================================================
-- Suite 23 — push notifications (migration 041, SA-NOT-001)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

CREATE OR REPLACE FUNCTION pg_temp.buy(p_piece uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE o jsonb; a jsonb; c jsonb;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_a_live(), ARRAY[p_piece], 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', 'full_payment', NULL);
  a := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', NULL);
  c := submit_buyer_payment_claim((o->>'order_id')::uuid, o->>'order_token', (a->>'payment_attempt_id')::uuid, '712345678901');
  PERFORM audit.as_postgres();
  RETURN o || jsonb_build_object('attempt_id', a->>'payment_attempt_id', 'claim', c);
END $$;

DO $$
DECLARE r1 jsonb; r2 jsonb; r3 jsonb; n_a int; n_b int; t text := repeat('f', 30) || ':APA91b-test-token';
BEGIN
  -- 23.1 sellers register their own token; another seller can neither read nor remove it
  PERFORM audit.as_seller(audit.seller_a());
  r1 := register_push_token(t, 'android');
  r2 := register_push_token('short', 'android');
  SELECT count(*) INTO n_a FROM seller_push_tokens;
  PERFORM audit.as_seller(audit.seller_b());
  SELECT count(*) INTO n_b FROM seller_push_tokens;
  r3 := unregister_push_token(t);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('23.1', (r1->>'success')::boolean AND r2->>'error' = 'INVALID_TOKEN' AND n_a = 1 AND n_b = 0
                                         AND (SELECT seller_id FROM seller_push_tokens WHERE token = t) = audit.seller_a(),
                                format('register=%s short=%s A sees %s, B sees %s, B unregister leaves it with A', r1->>'success', r2->>'error', n_a, n_b));

  -- 23.2 the same phone signing in as seller B moves the token to B
  PERFORM audit.as_seller(audit.seller_b());
  PERFORM register_push_token(t, 'android');
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('23.2', (SELECT seller_id FROM seller_push_tokens WHERE token = t) = audit.seller_b(),
                                'token moves to the seller now signed in on that phone');
  UPDATE seller_push_tokens SET seller_id = audit.seller_a() WHERE token = t;
END $$;

-- 23.3 a new order and a payment claim queue one message each, with no buyer phone or address
DO $$
DECLARE b jsonb; n_order int; n_claim int; leak int;
BEGIN
  b := pg_temp.buy(audit.p_a1());
  SELECT count(*) INTO n_order FROM push_outbox WHERE seller_id = audit.seller_a() AND kind = 'new_order' AND data->>'order_id' = b->>'order_id';
  SELECT count(*) INTO n_claim FROM push_outbox WHERE seller_id = audit.seller_a() AND kind = 'payment_claim' AND data->>'order_id' = b->>'order_id';
  SELECT count(*) INTO leak FROM push_outbox WHERE body LIKE '%9830045678%' OR body LIKE '%Lansdowne%' OR title LIKE '%Ananya%';
  RAISE NOTICE '%', audit.check('23.3', n_order = 1 AND n_claim = 1 AND leak = 0,
                                format('new_order=%s payment_claim=%s messages with buyer phone/address/name=%s', n_order, n_claim, leak));
  RAISE NOTICE 'INFO 23.3 messages: %', (SELECT string_agg(title || ' | ' || body, ' || ' ORDER BY id) FROM push_outbox WHERE data->>'order_id' = b->>'order_id');
END $$;

-- 23.4 preferences are respected; only the owner can change their own
DO $$
DECLARE r jsonb; before int; after int;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());
  r := set_notification_prefs(false, NULL);
  PERFORM audit.as_postgres();
  SELECT count(*) INTO before FROM push_outbox WHERE kind = 'new_order';
  PERFORM pg_temp.buy(audit.p_a2());
  SELECT count(*) INTO after FROM push_outbox WHERE kind = 'new_order';
  RAISE NOTICE '%', audit.check('23.4', (r->>'notify_new_orders')::boolean = false AND (r->>'notify_payment_claims')::boolean = true AND after = before,
                                format('new-order alerts off -> new_order messages %s -> %s; claim alerts still %s', before, after, r->>'notify_payment_claims'));
  UPDATE profiles SET notify_new_orders = true WHERE id = audit.seller_a();
END $$;

-- 23.5 the reaper moving a claim to late review does not notify again; a real late claim does
DO $$
DECLARE b jsonb; n_before int; n_after int; late int;
BEGIN
  b := pg_temp.buy(audit.p_a3());
  SELECT count(*) INTO n_before FROM push_outbox WHERE data->>'order_id' = b->>'order_id';
  UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = (b->>'order_id')::uuid;
  UPDATE payment_attempts SET verification_expires_at = now() - interval '1 minute', expires_at = now() - interval '1 minute'
   WHERE id = (b->>'attempt_id')::uuid;
  PERFORM release_expired_holds();
  SELECT count(*) INTO n_after FROM push_outbox WHERE data->>'order_id' = b->>'order_id';
  -- buyer resubmits a different UTR after the hold lapsed: late claim
  PERFORM audit.as_anon();
  PERFORM submit_buyer_payment_claim((b->>'order_id')::uuid, b->>'order_token', (b->>'attempt_id')::uuid, '812345678902');
  PERFORM audit.as_postgres();
  SELECT count(*) INTO late FROM push_outbox WHERE data->>'order_id' = b->>'order_id' AND kind = 'late_claim';
  RAISE NOTICE '%', audit.check('23.5', n_after = n_before AND late = 1,
                                format('reaper move: %s -> %s messages; late claim messages=%s', n_before, n_after, late));
END $$;

-- 23.6 dispatcher API: service_role only; claims due messages with tokens; completes and drops dead tokens
DO $$
DECLARE batch jsonb; first_id bigint; denied text; dead text := repeat('d', 30) || ':dead-token';
BEGIN
  INSERT INTO seller_push_tokens (token, seller_id) VALUES (dead, audit.seller_a());
  BEGIN
    PERFORM audit.as_seller(audit.seller_a());
    PERFORM claim_push_batch(10);
    denied := 'callable';
  EXCEPTION WHEN insufficient_privilege THEN denied := 'permission denied';
  END;
  PERFORM audit.as_service();
  batch := claim_push_batch(10);
  first_id := (batch->0->>'id')::bigint;
  PERFORM complete_push(first_id, true, NULL, ARRAY[dead]);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('23.6', denied = 'permission denied' AND jsonb_array_length(batch) >= 3
                                         AND jsonb_array_length(batch->0->'tokens') = 2
                                         AND (SELECT sent_at IS NOT NULL FROM push_outbox WHERE id = first_id)
                                         AND NOT EXISTS (SELECT 1 FROM seller_push_tokens WHERE token = dead)
                                         AND (SELECT attempts FROM push_outbox WHERE id = first_id) = 1,
                                format('seller call=%s; batch=%s messages; tokens on first=%s; dead token removed', denied,
                                       jsonb_array_length(batch), jsonb_array_length(batch->0->'tokens')));
  -- claimed but not completed messages are not handed out again immediately
  PERFORM audit.as_service();
  batch := claim_push_batch(10);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('23.7', jsonb_array_length(batch) = 0, format('second claim right away returns %s messages', jsonb_array_length(batch)));
END $$;

-- 23.8 catalog: no client access to the outbox; RLS everywhere
DO $$
BEGIN
  RAISE NOTICE '%', audit.check('23.8',
    NOT has_table_privilege('authenticated', 'public.push_outbox', 'SELECT')
    AND NOT has_table_privilege('anon', 'public.push_outbox', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.seller_push_tokens', 'INSERT')
    AND NOT has_table_privilege('anon', 'public.seller_push_tokens', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.app_config', 'SELECT')
    AND (SELECT bool_and(relrowsecurity) FROM pg_class WHERE oid IN ('public.push_outbox'::regclass, 'public.seller_push_tokens'::regclass, 'public.app_config'::regclass))
    AND NOT has_function_privilege('anon', 'public.register_push_token(text,text)', 'EXECUTE'),
    'outbox/tokens/config locked down; RLS on; token RPCs for sellers only');
END $$;

ROLLBACK;
