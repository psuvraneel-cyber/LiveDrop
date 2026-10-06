-- =============================================================================
-- Suite 26 — operator dashboard (migration 045, ADR-017)
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('aaaaaaaa-0000-0000-0000-00000000000a', 'ops@livedrop.test', '{"store_name":"Ops"}');
INSERT INTO platform_admins (user_id, note) VALUES ('aaaaaaaa-0000-0000-0000-00000000000a', 'audit');

CREATE OR REPLACE FUNCTION pg_temp.as_admin() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', 'aaaaaaaa-0000-0000-0000-00000000000a', 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END $$;

-- 26.1 anonymous visitors can log page views; bad input is refused; repeats within 30 s collapse
DO $$
DECLARE v1 uuid := gen_random_uuid(); v2 uuid := gen_random_uuid(); r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; r5 jsonb; n int;
BEGIN
  PERFORM audit.as_anon();
  r1 := log_page_view(v1, 'drop', 'Puja-Collection', 'whatsapp', 'mobile', true);
  r2 := log_page_view(v1, 'drop', 'puja-collection', 'whatsapp', 'mobile', true);   -- repeat
  r3 := log_page_view(v2, 'home', NULL, 'facebook', 'desktop', false);
  r4 := log_page_view(v2, 'admin', NULL, 'direct', 'mobile', false);                 -- not a page kind
  r5 := log_page_view(v2, 'drop', 'x'' OR 1=1', 'direct', 'mobile', false);          -- bad slug
  PERFORM audit.as_postgres();
  SELECT count(*) INTO n FROM site_page_views;
  RAISE NOTICE '%', audit.check('26.1',
    (r1->>'success')::boolean AND (r2->>'deduplicated')::boolean AND (r3->>'success')::boolean
    AND r4->>'error' = 'INVALID_INPUT' AND r5->>'error' = 'INVALID_INPUT' AND n = 2
    AND (SELECT drop_slug FROM site_page_views WHERE visitor_id = v1) = 'puja-collection',
    format('logged=%s repeat deduplicated=%s bad kind=%s bad slug=%s rows=%s', r1->>'success', r2->>'deduplicated', r4->>'error', r5->>'error', n));
END $$;

-- 26.2 nobody but the admin reads traffic or the dashboard; the table is closed to clients
DO $$
DECLARE t jsonb; l jsonb; s jsonb; p jsonb; anon_read text;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());
  t := admin_traffic(7); l := admin_live_drops(); s := admin_sales_overview(7); p := admin_payment_attention();
  PERFORM audit.as_anon();
  BEGIN
    PERFORM count(*) FROM site_page_views;
    anon_read := 'allowed';
  EXCEPTION WHEN insufficient_privilege THEN anon_read := 'denied';
  END;
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('26.2',
    t->>'error' = 'UNAUTHORIZED' AND l->>'error' = 'UNAUTHORIZED' AND s->>'error' = 'UNAUTHORIZED'
    AND p->>'error' = 'UNAUTHORIZED' AND anon_read = 'denied'
    AND NOT has_function_privilege('anon', 'public.admin_traffic(integer)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.purge_old_page_views()', 'EXECUTE'),
    format('seller: traffic=%s live=%s sales=%s payments=%s | anon table read=%s', t->>'error', l->>'error', s->>'error', p->>'error', anon_read));
END $$;

-- 26.3 the admin sees traffic totals and live drops with stock and waiting payments
DO $$
DECLARE t jsonb; l jsonb; a jsonb;
BEGIN
  PERFORM audit.as_anon();
  PERFORM log_page_view(gen_random_uuid(), 'drop', 'live-a', 'instagram', 'mobile', false);
  PERFORM pg_temp.as_admin();
  t := admin_traffic(7);
  l := admin_live_drops();
  PERFORM audit.as_postgres();
  SELECT e INTO a FROM jsonb_array_elements(l->'drops') e WHERE (e->>'id')::uuid = audit.drop_a_live();
  RAISE NOTICE '%', audit.check('26.3',
    (t->>'success')::boolean AND (t->'totals'->>'visitors')::int >= 3 AND (t->'totals'->>'returning_buyer_visitors')::int >= 1
    AND jsonb_array_length(t->'daily') = 7
    AND a IS NOT NULL AND (a->>'available')::int >= 1 AND a ? 'payments_waiting',
    format('visitors=%s returning=%s days=%s | live drop A available=%s held=%s waiting=%s',
           t->'totals'->>'visitors', t->'totals'->>'returning_buyer_visitors', jsonb_array_length(t->'daily'),
           a->>'available', a->>'held', a->>'payments_waiting'));
END $$;

-- 26.4 sales and payment attention reflect a claimed payment, with no buyer phone or address
DO $$
DECLARE o jsonb; att jsonb; s jsonb; p jsonb;
BEGIN
  PERFORM audit.as_anon();
  o := create_order_with_reservation(audit.drop_a_live(), ARRAY[audit.p_a1()], 'Ananya Roy', '9830045678',
                                     '14 Lansdowne Road, Kolkata', '700020', 'full_payment', NULL);
  att := initiate_payment_attempt((o->>'order_id')::uuid, o->>'order_token', NULL);
  PERFORM submit_buyer_payment_claim((o->>'order_id')::uuid, o->>'order_token', (att->>'payment_attempt_id')::uuid, '712345678901');
  PERFORM pg_temp.as_admin();
  s := admin_sales_overview(7);
  p := admin_payment_attention();
  PERFORM audit.as_postgres();
  RAISE NOTICE '%', audit.check('26.4',
    (s->>'orders')::int >= 1 AND jsonb_array_length(s->'daily') = 7 AND s ? 'conversion_pct'
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(p->'waiting') e WHERE e->>'order_code' = o->>'order_code')
    AND p::text NOT LIKE '%9830045678%' AND p::text NOT LIKE '%Lansdowne%' AND s::text NOT LIKE '%Ananya%',
    format('orders=%s conversion=%s%% | waiting includes %s; no buyer contact details', s->>'orders', s->>'conversion_pct', o->>'order_code'));
END $$;

-- 26.5 retention removes views older than 180 days only
DO $$
DECLARE n int;
BEGIN
  INSERT INTO site_page_views (visitor_id, page_kind, source, device, created_at)
  VALUES (gen_random_uuid(), 'home', 'direct', 'mobile', NOW() - INTERVAL '181 days');
  n := purge_old_page_views();
  RAISE NOTICE '%', audit.check('26.5', n = 1 AND (SELECT count(*) FROM site_page_views) >= 3,
                                format('purged=%s, recent kept=%s', n, (SELECT count(*) FROM site_page_views)));
END $$;

ROLLBACK;
