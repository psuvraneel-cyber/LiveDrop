-- =============================================================================
-- Suite 21 — P1 round 4 regression checks (migration 039)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
--
--   SA-DROP-001 / SA-DROP-002  drop state machine and slug lock
--   SA-PAY-012                 checkout refused when the seller cannot be paid
--   SA-INV-001                 offline sale and its 30-minute undo (ADR-014)
--   SA-AUTH-004                payee change needs a recent password sign-in; every change is logged
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

-- Seller session whose JWT says the password was used p_age seconds ago (NULL: no password in amr).
CREATE OR REPLACE FUNCTION pg_temp.as_seller_pw(p_seller uuid, p_age int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', json_build_object(
      'sub', p_seller, 'role', 'authenticated',
      'amr', CASE WHEN p_age IS NULL THEN json_build_array(json_build_object('method', 'otp', 'timestamp', extract(epoch FROM now())::bigint))
                  ELSE json_build_array(json_build_object('method', 'password', 'timestamp', extract(epoch FROM now())::bigint - p_age)) END
    )::text, true);
  PERFORM set_config('role', 'authenticated', true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.try(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE n int; v_hint text;
BEGIN
  EXECUTE p_sql;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN 'OK rows=' || n;
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  RETURN 'ERR ' || SQLSTATE || ' ' || COALESCE(NULLIF(v_hint, ''), '-');
END $$;

CREATE OR REPLACE FUNCTION pg_temp.piece(p_drop uuid, p_code text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  INSERT INTO products (drop_id, code, title, price_paisa, size, image_url, image_urls)
  VALUES (p_drop, p_code, 'Suite 21 ' || p_code, 100000, 'Free Size', 'https://x.supabase.co/s21.jpg', ARRAY['https://x.supabase.co/s21.jpg'])
  RETURNING id INTO v;
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.checkout(p_drop uuid, p_piece uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE o jsonb;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(p_drop, ARRAY[p_piece], 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', 'full_payment', NULL);
  PERFORM audit.as_postgres();
  RETURN o;
END $$;

-- ---------------------------------------------------------------------------
-- SA-DROP-001 / SA-DROP-002
-- ---------------------------------------------------------------------------
DO $$
DECLARE d uuid := 'dddd0000-0000-0000-0000-000000000021'; r1 text; r2 text; r3 text; r4 text; r5 text; c jsonb;
BEGIN
  INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa) VALUES (d, audit.seller_d(), 'D21', 'd-21', 'draft', 8000);
  PERFORM audit.as_seller(audit.seller_d());
  r1 := pg_temp.try(format('UPDATE drops SET status = %L WHERE id = %L', 'closed', d));          -- draft -> closed
  r2 := pg_temp.try(format('UPDATE drops SET slug = %L WHERE id = %L', 'd-21-renamed', d));     -- draft slug edit
  r3 := pg_temp.try(format('UPDATE drops SET status = %L, live_started_at = now() WHERE id = %L', 'live', d));
  c := close_drop(d);
  r4 := pg_temp.try(format('UPDATE drops SET slug = %L WHERE id = %L', 'd-21-after', d));       -- closed slug edit
  r5 := pg_temp.try(format('UPDATE drops SET title = %L WHERE id = %L', 'D21 renamed', d));     -- other fields stay editable
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('21.1', r1 LIKE 'ERR 42501%', 'draft -> closed refused (close guard from 024 or lifecycle guard): ' || r1);
  RAISE NOTICE '%', audit.check('21.2', r2 LIKE 'OK rows=1' AND r3 LIKE 'OK rows=1' AND (c->>'success')::boolean,
                                format('draft slug edit=%s, draft -> live=%s, close_drop=%s', r2, r3, c->>'success'));
  RAISE NOTICE '%', audit.check('21.3', r4 LIKE 'ERR 42501%DROP_SLUG_LOCKED%', 'slug edit on a closed drop refused: ' || r4);
  RAISE NOTICE '%', audit.check('21.4', r5 LIKE 'OK rows=1', 'title edit on a closed drop still allowed: ' || r5);
END $$;

-- ---------------------------------------------------------------------------
-- SA-PAY-012
-- ---------------------------------------------------------------------------
DO $$
DECLARE p uuid; o1 jsonb; o2 jsonb; o3 jsonb; st text;
BEGIN
  p := pg_temp.piece(audit.drop_a_live(), '#U21');
  UPDATE profiles SET upi_enabled = false WHERE id = audit.seller_a();
  o1 := pg_temp.checkout(audit.drop_a_live(), p);
  UPDATE profiles SET upi_enabled = true WHERE id = audit.seller_a();
  ALTER TABLE profiles DISABLE TRIGGER trg_guard_and_log_payee_change;
  -- Constraints already make a profile without any UPI ID nearly impossible; drop them (rolled back with
  -- the suite) to exercise the checkout guard as defence in depth.
  ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_upi_id_check;
  ALTER TABLE profiles DROP CONSTRAINT IF EXISTS chk_profiles_upi_vpa;
  UPDATE profiles SET upi_vpa = NULL, upi_id = '' WHERE id = audit.seller_a();
  o2 := pg_temp.checkout(audit.drop_a_live(), p);
  UPDATE profiles SET upi_id = 'aarohi@okaxis' WHERE id = audit.seller_a();
  ALTER TABLE profiles ENABLE TRIGGER trg_guard_and_log_payee_change;
  SELECT status INTO st FROM products WHERE id = p;
  o3 := pg_temp.checkout(audit.drop_a_live(), p);
  RAISE NOTICE '%', audit.check('21.10', o1->>'error' = 'UPI_DISABLED' AND o2->>'error' = 'UPI_NOT_CONFIGURED' AND st = 'available',
                                format('UPI off -> %s; no payee UPI ID -> %s; piece stayed %s', o1->>'error', o2->>'error', st));
  RAISE NOTICE '%', audit.check('21.11', (o3->>'success')::boolean, 'control: checkout with UPI on -> ' || COALESCE(o3->>'error', o3->>'success'));
END $$;

-- ---------------------------------------------------------------------------
-- SA-INV-001 (ADR-014)
-- ---------------------------------------------------------------------------
DO $$
DECLARE p1 uuid; p2 uuid; p3 uuid; m jsonb; u jsonb; u2 jsonb; u3 jsonb; u4 jsonb; u5 jsonb; o jsonb; st text; at timestamptz;
BEGIN
  p1 := pg_temp.piece(audit.drop_a_live(), '#V01');
  p2 := pg_temp.piece(audit.drop_a_live(), '#V02');
  p3 := pg_temp.piece(audit.drop_a_live(), '#V03');

  PERFORM audit.as_seller(audit.seller_a());
  m := mark_product_sold_offline(p1);
  PERFORM audit.as_postgres();
  SELECT status, sold_offline_at INTO st, at FROM products WHERE id = p1;
  RAISE NOTICE '%', audit.check('21.20', (m->>'success')::boolean AND st = 'sold' AND at IS NOT NULL AND m ? 'undo_until',
                                format('mark sold offline -> %s status=%s sold_offline_at set=%s', m->>'success', st, at IS NOT NULL));

  -- another seller cannot undo it
  PERFORM audit.as_seller(audit.seller_b());
  u := undo_mark_product_sold_offline(p1);
  PERFORM audit.as_seller(audit.seller_a());
  u2 := undo_mark_product_sold_offline(p1);
  u3 := undo_mark_product_sold_offline(p1);
  PERFORM audit.as_postgres();
  SELECT status, sold_offline_at INTO st, at FROM products WHERE id = p1;
  RAISE NOTICE '%', audit.check('21.21', u->>'error' = 'PRODUCT_NOT_FOUND_OR_UNAUTHORIZED', 'other seller undo -> ' || COALESCE(u->>'error', u->>'success'));
  RAISE NOTICE '%', audit.check('21.22', (u2->>'success')::boolean AND st = 'available' AND at IS NULL AND (u3->>'idempotent')::boolean,
                                format('undo within 30 min -> %s, piece=%s, second undo idempotent=%s', u2->>'success', st, u3->>'idempotent'));

  -- past the window
  PERFORM audit.as_seller(audit.seller_a());
  PERFORM mark_product_sold_offline(p2);
  PERFORM audit.as_postgres();
  UPDATE products SET sold_offline_at = now() - interval '31 minutes' WHERE id = p2;
  PERFORM audit.as_seller(audit.seller_a());
  u4 := undo_mark_product_sold_offline(p2);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('21.23', u4->>'error' = 'UNDO_WINDOW_EXPIRED', 'undo after 31 min -> ' || COALESCE(u4->>'error', u4->>'success'));

  -- a piece sold through an order is not "sold offline"
  o := pg_temp.checkout(audit.drop_a_live(), p3);
  UPDATE products SET status = 'sold' WHERE id = p3;
  PERFORM audit.as_seller(audit.seller_a());
  u5 := undo_mark_product_sold_offline(p3);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('21.24', u5->>'error' = 'NOT_SOLD_OFFLINE', 'undo on an order-sold piece -> ' || COALESCE(u5->>'error', u5->>'success'));

  -- direct UPDATE still refused for sellers
  PERFORM audit.as_seller(audit.seller_a());
  st := pg_temp.try(format('UPDATE products SET status = %L, sold_offline_at = NULL WHERE id = %L', 'available', p2));
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('21.25', st LIKE 'ERR 42501%', 'direct UPDATE back to available -> ' || st);
END $$;

-- 21.26 an order created after the piece was relisted blocks a later undo of a new offline sale
DO $$
DECLARE p uuid; o jsonb; u jsonb;
BEGIN
  p := pg_temp.piece(audit.drop_a_live(), '#V04');
  o := pg_temp.checkout(audit.drop_a_live(), p);
  -- seller cannot mark a reserved piece sold (unchanged rule)
  PERFORM audit.as_seller(audit.seller_a());
  u := mark_product_sold_offline(p);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('21.26', u->>'error' = 'PRODUCT_RESERVED', 'mark sold on a reserved piece -> ' || COALESCE(u->>'error', u->>'success'));
  -- simulate: piece ended up sold_offline while a live order references it
  UPDATE products SET status = 'sold', sold_offline_at = now(), reserved_by_order_id = NULL, reserved_at = NULL WHERE id = p;
  PERFORM audit.as_seller(audit.seller_a());
  u := undo_mark_product_sold_offline(p);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('21.27', u->>'error' = 'PRODUCT_HAS_ORDER', 'undo while a live order references the piece -> ' || COALESCE(u->>'error', u->>'success'));
END $$;

-- ---------------------------------------------------------------------------
-- SA-AUTH-004
-- ---------------------------------------------------------------------------
DO $$
DECLARE r1 text; r2 text; r3 text; r4 text; r5 text; n int; n_other int; w text;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());                         -- token without amr
  r1 := pg_temp.try(format('UPDATE profiles SET upi_id = %L WHERE id = %L', 'thief@ybl', audit.seller_a()));
  PERFORM pg_temp.as_seller_pw(audit.seller_a(), 3600);              -- password used an hour ago
  r2 := pg_temp.try(format('UPDATE profiles SET upi_vpa = %L WHERE id = %L', 'thief@ybl', audit.seller_a()));
  PERFORM pg_temp.as_seller_pw(audit.seller_a(), NULL);              -- signed in with OTP/magic link only
  r3 := pg_temp.try(format('UPDATE profiles SET phone_number = %L WHERE id = %L', '9000000001', audit.seller_a()));
  PERFORM pg_temp.as_seller_pw(audit.seller_a(), 60);                -- just re-entered the password
  r4 := pg_temp.try(format('UPDATE profiles SET upi_vpa = %L, upi_display_name = %L WHERE id = %L', 'aarohi.new@okaxis', 'Aarohi B', audit.seller_a()));
  PERFORM audit.as_seller(audit.seller_a());                         -- unrelated field, old token
  r5 := pg_temp.try(format('UPDATE profiles SET store_name = %L WHERE id = %L', 'Aarohi Boutique II', audit.seller_a()));
  SELECT count(*) INTO n FROM payee_change_log;                      -- what seller A can read
  PERFORM audit.as_seller(audit.seller_b());
  SELECT count(*) INTO n_other FROM payee_change_log;
  w := pg_temp.try(format('DELETE FROM payee_change_log WHERE seller_id = %L', audit.seller_a()));
  PERFORM audit.as_postgres();

  RAISE NOTICE '%', audit.check('21.30', r1 LIKE 'ERR 42501%REAUTH_REQUIRED%' AND r2 LIKE 'ERR 42501%REAUTH_REQUIRED%' AND r3 LIKE 'ERR 42501%REAUTH_REQUIRED%',
                                format('no amr -> %s | password 1 h ago -> %s | OTP only -> %s', r1, r2, r3));
  RAISE NOTICE '%', audit.check('21.31', r4 = 'OK rows=1' AND r5 = 'OK rows=1', format('fresh password -> %s | store name with old token -> %s', r4, r5));
  RAISE NOTICE '%', audit.check('21.32', n = 2 AND n_other = 0 AND w LIKE 'ERR 42501%',
                                format('seller A sees %s log rows (vpa + display name), seller B sees %s, seller delete -> %s', n, n_other, w));
  RAISE NOTICE '%', audit.check('21.33', (SELECT count(*) FROM payee_change_log WHERE seller_id = audit.seller_a()
                                          AND field = 'upi_vpa' AND new_value = 'aarohi.new@okaxis' AND changed_by = audit.seller_a()
                                          AND changed_by_role = 'authenticated') = 1,
                                'log row records old/new value, who and which role');
END $$;

-- 21.34 trusted operator changes are logged too and need no password
DO $$
DECLARE r text;
BEGIN
  PERFORM audit.as_service();
  r := pg_temp.try(format('UPDATE profiles SET upi_id = %L WHERE id = %L', 'bela.new@okicici', audit.seller_b()));
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('21.34', r = 'OK rows=1' AND EXISTS (SELECT 1 FROM payee_change_log WHERE seller_id = audit.seller_b()
                                                                     AND field = 'upi_id' AND changed_by_role = 'service_role'),
                                'service_role change -> ' || r || ', logged');
END $$;

-- ---------------------------------------------------------------------------
-- Catalog
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  RAISE NOTICE '%', audit.check('21.40',
    NOT has_function_privilege('anon', 'public.undo_mark_product_sold_offline(uuid)', 'EXECUTE')
    AND has_function_privilege('authenticated', 'public.undo_mark_product_sold_offline(uuid)', 'EXECUTE'),
    'undo_mark_product_sold_offline: sellers only');
  RAISE NOTICE '%', audit.check('21.41',
    NOT has_table_privilege('anon', 'public.payee_change_log', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.payee_change_log', 'INSERT')
    AND NOT has_table_privilege('authenticated', 'public.payee_change_log', 'UPDATE')
    AND NOT has_table_privilege('authenticated', 'public.payee_change_log', 'DELETE')
    AND (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.payee_change_log'::regclass),
    'payee_change_log: RLS on, sellers read only, anon nothing');
END $$;

ROLLBACK;
