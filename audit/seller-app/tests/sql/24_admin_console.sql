-- =============================================================================
-- Suite 24 — operator console (migration 042, SA-OPS-002 / SA-ONB-001)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

-- The console's admin account (signs up like anyone, then the owner lists it in platform_admins).
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('aaaaaaaa-0000-0000-0000-00000000000a', 'ops@livedrop.test', '{"store_name":"Ops"}');
INSERT INTO platform_admins (user_id, note) VALUES ('aaaaaaaa-0000-0000-0000-00000000000a', 'audit');
UPDATE auth.users SET raw_user_meta_data = raw_user_meta_data || '{"utr_number":"412345678901"}'
 WHERE id = audit.seller_c();

-- Session whose JWT says the password was used p_age seconds ago (NULL: no password in amr).
CREATE OR REPLACE FUNCTION pg_temp.as_user_pw(p_user uuid, p_age int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', json_build_object(
      'sub', p_user, 'role', 'authenticated',
      'amr', CASE WHEN p_age IS NULL THEN json_build_array(json_build_object('method', 'otp', 'timestamp', extract(epoch FROM now())::bigint))
                  ELSE json_build_array(json_build_object('method', 'password', 'timestamp', extract(epoch FROM now())::bigint - p_age)) END
    )::text, true);
  PERFORM set_config('role', 'authenticated', true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.admin() RETURNS uuid LANGUAGE sql AS $$ SELECT 'aaaaaaaa-0000-0000-0000-00000000000a'::uuid $$;

-- 24.1 sellers and anon cannot use the console; tables are not readable by clients
DO $$
DECLARE w jsonb; l jsonb; s jsonb; r jsonb; n int;
BEGIN
  PERFORM pg_temp.as_user_pw(audit.seller_a(), 5);
  w := admin_whoami();
  l := admin_list_sellers('all');
  s := admin_set_seller_approval(audit.seller_c(), true, NULL);
  r := admin_refunds_due();
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('24.1',
    (w->>'is_admin')::boolean = false AND l->>'error' = 'UNAUTHORIZED' AND s->>'error' = 'UNAUTHORIZED'
    AND r->>'error' = 'UNAUTHORIZED'
    AND (SELECT is_approved FROM profiles WHERE id = audit.seller_c()) = false
    AND NOT has_function_privilege('anon', 'public.admin_list_sellers(text)', 'EXECUTE')
    AND NOT has_table_privilege('authenticated', 'public.platform_admins', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.admin_actions', 'SELECT')
    AND NOT has_function_privilege('authenticated', 'public.admin_write_denied()', 'EXECUTE'),
    format('seller: whoami=%s list=%s approve=%s refunds=%s; anon/authenticated locked out of tables and helpers',
           w->>'is_admin', l->>'error', s->>'error', r->>'error'));
END $$;

-- 24.2 the admin sees pending sellers with their onboarding-fee UTR, and not themselves
DO $$
DECLARE w jsonb; l jsonb; c jsonb;
BEGIN
  PERFORM pg_temp.as_user_pw(pg_temp.admin(), 5);
  w := admin_whoami();
  l := admin_list_sellers('pending');
  PERFORM audit.as_postgres();
  SELECT e INTO c FROM jsonb_array_elements(l->'sellers') e WHERE (e->>'id')::uuid = audit.seller_c();
  RAISE NOTICE '%', audit.check('24.2',
    (w->>'is_admin')::boolean AND (l->>'success')::boolean AND c->>'onboarding_fee_utr' = '412345678901'
    AND c->>'status' = 'pending'
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(l->'sellers') e WHERE (e->>'id')::uuid = pg_temp.admin())
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(l->'sellers') e WHERE e->>'status' <> 'pending'),
    format('whoami=%s pending=%s seller C utr=%s status=%s', w->>'is_admin', jsonb_array_length(l->'sellers'),
           c->>'onboarding_fee_utr', c->>'status'));
END $$;

-- 24.3 writes need a password sign-in within 10 minutes
DO $$
DECLARE r1 jsonb; r2 jsonb;
BEGIN
  PERFORM pg_temp.as_user_pw(pg_temp.admin(), NULL);
  r1 := admin_set_seller_approval(audit.seller_c(), true, NULL);
  PERFORM pg_temp.as_user_pw(pg_temp.admin(), 3600);
  r2 := admin_set_seller_approval(audit.seller_c(), true, NULL);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('24.3',
    r1->>'error' = 'REAUTH_REQUIRED' AND r2->>'error' = 'REAUTH_REQUIRED'
    AND (SELECT is_approved FROM profiles WHERE id = audit.seller_c()) = false,
    format('no password in token -> %s | password 1 h ago -> %s', r1->>'error', r2->>'error'));
END $$;

-- 24.4 approve, then suspend with a reason: drops close, status and log follow
DO $$
DECLARE a jsonb; s0 jsonb; s jsonb; l jsonb; live_before int; live_after int; logged int;
BEGIN
  PERFORM pg_temp.as_user_pw(pg_temp.admin(), 5);
  a := admin_set_seller_approval(audit.seller_c(), true, NULL);
  PERFORM audit.as_postgres();
  SELECT count(*) INTO live_before FROM drops WHERE seller_id = audit.seller_a() AND status = 'live';
  PERFORM pg_temp.as_user_pw(pg_temp.admin(), 5);
  s0 := admin_set_seller_approval(audit.seller_a(), false, ' ');
  s := admin_set_seller_approval(audit.seller_a(), false, 'Fee chargeback');
  l := admin_list_sellers('suspended');
  PERFORM audit.as_postgres();
  SELECT count(*) INTO live_after FROM drops WHERE seller_id = audit.seller_a() AND status = 'live';
  SELECT count(*) INTO logged FROM admin_actions WHERE admin_id = pg_temp.admin();
  RAISE NOTICE '%', audit.check('24.4',
    (a->>'success')::boolean AND (SELECT is_approved FROM profiles WHERE id = audit.seller_c())
    AND (SELECT approved_by FROM profiles WHERE id = audit.seller_c()) = pg_temp.admin()
    AND s0->>'error' = 'REASON_REQUIRED' AND (s->>'success')::boolean
    AND live_before > 0 AND live_after = 0
    AND (l->'sellers'->0->>'id')::uuid = audit.seller_a() AND l->'sellers'->0->>'last_suspension_reason' = 'Fee chargeback'
    AND logged = 2,
    format('approve C=%s | suspend without reason=%s, with reason=%s | A live drops %s -> %s | suspended list=%s | log rows=%s',
           a->>'success', s0->>'error', s->>'success', live_before, live_after, jsonb_array_length(l->'sellers'), logged));
END $$;

-- 24.5 refunds: listed when due, recorded once through record_refund rules, logged; sellers still
--      cannot record refunds for other sellers' orders
DO $$
DECLARE o jsonb; due jsonb; bad jsonb; ok jsonb; again jsonb; other jsonb; found jsonb; n_log int;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_b_live(), ARRAY[audit.p_b1()], 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', 'full_payment', NULL);
  PERFORM audit.as_postgres();
  UPDATE orders SET status = 'cancelled', total_paid_paisa = total_paisa, balance_due_paisa = 0,
                    refund_status = 'required', refund_amount_paisa = total_paisa,
                    refund_reason = 'audit: sold elsewhere', refund_required_at = now()
   WHERE id = (o->>'order_id')::uuid;

  PERFORM pg_temp.as_user_pw(audit.seller_a(), 5);
  other := record_refund((o->>'order_id')::uuid, 'UTR-OTHER-SELLER', NULL);
  PERFORM pg_temp.as_user_pw(pg_temp.admin(), 5);
  due := admin_refunds_due();
  found := admin_find_order(lower(o->>'order_code'));
  bad := admin_record_refund((o->>'order_id')::uuid, 'x', NULL);
  ok := admin_record_refund((o->>'order_id')::uuid, 'IMPS 5123 4567', 'paid by ops');
  again := admin_record_refund((o->>'order_id')::uuid, 'IMPS 5123 4567', NULL);
  PERFORM audit.as_postgres();
  SELECT count(*) INTO n_log FROM admin_actions WHERE action = 'record_refund' AND target_id = (o->>'order_id')::uuid;
  RAISE NOTICE '%', audit.check('24.5',
    other->>'error' = 'ORDER_NOT_FOUND_OR_UNAUTHORIZED'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(due->'orders') e WHERE e->>'order_code' = o->>'order_code' AND (e->>'refund_amount_paisa')::int = (SELECT total_paisa FROM orders WHERE id = (o->>'order_id')::uuid))
    AND found->'order'->>'order_code' = o->>'order_code' AND found::text NOT LIKE '%9830045678%' AND found::text NOT LIKE '%Lansdowne%'
    AND bad->>'error' = 'INVALID_REFUND_REFERENCE' AND (ok->>'success')::boolean AND (again->>'idempotent')::boolean
    AND (SELECT refund_status FROM orders WHERE id = (o->>'order_id')::uuid) = 'refunded'
    AND (SELECT refund_recorded_by FROM orders WHERE id = (o->>'order_id')::uuid) = pg_temp.admin()
    AND n_log = 1 AND COALESCE(current_setting('livedrop.admin_refund', true), '') = '',
    format('other seller=%s | due listed, lookup ok, no buyer phone/address | bad ref=%s ok=%s again idempotent=%s | log rows=%s',
           other->>'error', bad->>'error', ok->>'success', again->>'idempotent', n_log));
END $$;

-- 24.6 the admin flag alone does nothing for a non-admin calling record_refund directly
DO $$
DECLARE oid uuid; r jsonb;
BEGIN
  SELECT target_id INTO oid FROM admin_actions WHERE action = 'record_refund' LIMIT 1;
  UPDATE orders SET refund_status = 'required', refund_reference = NULL, refunded_at = NULL WHERE id = oid;
  PERFORM pg_temp.as_user_pw(audit.seller_a(), 5);
  PERFORM set_config('livedrop.admin_refund', 'on', true);
  r := record_refund(oid, 'UTR-SPOOF-1', NULL);
  PERFORM set_config('livedrop.admin_refund', '', true);
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('24.6', r->>'error' = 'ORDER_NOT_FOUND_OR_UNAUTHORIZED'
                                AND (SELECT refund_status FROM orders WHERE id = oid) = 'required',
                                format('seller A (not the owner, not admin) with the flag set -> %s', r->>'error'));
END $$;

ROLLBACK;
