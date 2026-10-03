-- =============================================================================
-- LiveDrop Seller-App Audit — request-context helpers and fixture
-- AUDIT-ONLY. Lives in schema `audit`, which is not part of the product schema.
-- =============================================================================
CREATE SCHEMA IF NOT EXISTS audit;
GRANT USAGE ON SCHEMA audit TO anon, authenticated, service_role;

-- Fixed identities used by every suite.
CREATE OR REPLACE FUNCTION audit.seller_a() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '11111111-1111-1111-1111-111111111111'::uuid $$;
CREATE OR REPLACE FUNCTION audit.seller_b() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '22222222-2222-2222-2222-222222222222'::uuid $$;
CREATE OR REPLACE FUNCTION audit.seller_c() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '33333333-3333-3333-3333-333333333333'::uuid $$; -- never approved
CREATE OR REPLACE FUNCTION audit.seller_d() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT '44444444-4444-4444-4444-444444444444'::uuid $$; -- approved, no drops
CREATE OR REPLACE FUNCTION audit.drop_a_live() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'aaaa0000-0000-0000-0000-000000000001'::uuid $$;
CREATE OR REPLACE FUNCTION audit.drop_a_draft() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'aaaa0000-0000-0000-0000-000000000002'::uuid $$;
CREATE OR REPLACE FUNCTION audit.drop_b_live() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'bbbb0000-0000-0000-0000-000000000001'::uuid $$;
CREATE OR REPLACE FUNCTION audit.p_a1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'a1000000-0000-0000-0000-000000000001'::uuid $$; -- #A01 Rs1500
CREATE OR REPLACE FUNCTION audit.p_a2() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'a1000000-0000-0000-0000-000000000002'::uuid $$; -- #A02 Rs2500
CREATE OR REPLACE FUNCTION audit.p_a3() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'a1000000-0000-0000-0000-000000000003'::uuid $$; -- #A03 Rs500
CREATE OR REPLACE FUNCTION audit.p_b1() RETURNS uuid LANGUAGE sql IMMUTABLE AS $$ SELECT 'b1000000-0000-0000-0000-000000000001'::uuid $$; -- #B01 Rs1000

-- Request context switches (same GUCs PostgREST sets per request).
CREATE OR REPLACE FUNCTION audit.as_postgres() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.headers', '', true);
END $$;

CREATE OR REPLACE FUNCTION audit.as_anon(p_order_token text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.headers',
    CASE WHEN p_order_token IS NULL THEN '{}' ELSE json_build_object('x-order-token', p_order_token)::text END, true);
  PERFORM set_config('role', 'anon', true);
END $$;

CREATE OR REPLACE FUNCTION audit.as_seller(p_seller uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', p_seller, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.headers', '{}', true);
  PERFORM set_config('role', 'authenticated', true);
END $$;

CREATE OR REPLACE FUNCTION audit.as_service() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
  PERFORM set_config('request.jwt.claims', '{"role":"service_role"}', true);
  PERFORM set_config('request.jwt.claim.sub', '', true);
  PERFORM set_config('request.jwt.claim.role', '', true);
  PERFORM set_config('request.headers', '{}', true);
  PERFORM set_config('role', 'service_role', true);
END $$;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA audit TO anon, authenticated, service_role;

-- Fixture: four sellers created through the real signup trigger (020/021),
-- two live drops, one draft drop, four products. Run as postgres inside a
-- transaction that the suite rolls back.
CREATE OR REPLACE FUNCTION audit.seed() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
   (audit.seller_a(), 'a@audit.test', jsonb_build_object('store_name','Aarohi Boutique','phone_number','9876500001','upi_id','aarohi@okaxis','return_address','12 MG Road, Kolkata 700001')),
   (audit.seller_b(), 'b@audit.test', jsonb_build_object('store_name','Bela Weaves','phone_number','9876500002','upi_id','bela@okicici','return_address','5 Park Street, Kolkata 700016')),
   (audit.seller_c(), 'c@audit.test', jsonb_build_object('store_name','Chitra Unapproved','phone_number','9876500003','upi_id','chitra@ybl','return_address','9 Lake Road, Kolkata 700029')),
   (audit.seller_d(), 'd@audit.test', jsonb_build_object('store_name','Damini No Drops','phone_number','9876500004','upi_id','damini@paytm','return_address','1 Salt Lake, Kolkata 700064'));

  -- Platform approval as the trusted owner (what admin_approve_seller does).
  UPDATE profiles SET is_approved = true, approved_at = now()
   WHERE id IN (audit.seller_a(), audit.seller_b(), audit.seller_d());

  INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa, free_shipping_threshold_paisa, live_started_at)
  VALUES (audit.drop_a_live(), audit.seller_a(), 'Aarohi Saturday Live', 'aarohi-saturday-live', 'live', 8000, 299900, now()),
         (audit.drop_a_draft(), audit.seller_a(), 'Aarohi Next Week', 'aarohi-next-week', 'draft', 8000, NULL, NULL),
         (audit.drop_b_live(), audit.seller_b(), 'Bela Weaves Live', 'bela-weaves-live', 'live', 6000, NULL, now());

  INSERT INTO products (id, drop_id, code, title, price_paisa, size, image_url, image_urls) VALUES
   (audit.p_a1(), audit.drop_a_live(), '#A01', 'Kantha Stitch Saree', 150000, 'Free Size', 'https://x.supabase.co/a1.jpg', ARRAY['https://x.supabase.co/a1.jpg']),
   (audit.p_a2(), audit.drop_a_live(), '#A02', 'Banarasi Silk Saree', 250000, 'Free Size', 'https://x.supabase.co/a2.jpg', ARRAY['https://x.supabase.co/a2.jpg']),
   (audit.p_a3(), audit.drop_a_live(), '#A03', 'Cotton Kurti', 50000, 'M', 'https://x.supabase.co/a3.jpg', ARRAY['https://x.supabase.co/a3.jpg']),
   (audit.p_b1(), audit.drop_b_live(), '#B01', 'Tant Saree', 100000, 'Free Size', 'https://x.supabase.co/b1.jpg', ARRAY['https://x.supabase.co/b1.jpg']);
END $$;

-- Small assertion helper: prints PASS/FAIL lines that the runner greps.
CREATE OR REPLACE FUNCTION audit.check(p_id text, p_ok boolean, p_detail text) RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN p_ok THEN 'PASS ' ELSE 'FAIL ' END || p_id || ' — ' || p_detail
$$;
GRANT EXECUTE ON FUNCTION audit.check(text, boolean, text) TO anon, authenticated, service_role;
