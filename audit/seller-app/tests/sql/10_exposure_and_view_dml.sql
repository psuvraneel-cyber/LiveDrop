-- =============================================================================
-- Suite 10 — public data exposure and DML through public projection views
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
-- Result lines: PASS / FAIL (expected secure behaviour), FINDING (insecure
-- behaviour reproduced), INFO (behaviour recorded, no verdict).
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

-- 10.1 anon cannot read the profiles base table (migration 016 revoked SELECT)
DO $$
DECLARE n int;
BEGIN
  PERFORM audit.as_anon();
  BEGIN
    SELECT count(*) INTO n FROM profiles;
    RAISE NOTICE 'FAIL 10.1 anon can read profiles base table (% rows)', n;
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS 10.1 anon SELECT on profiles denied: %', SQLERRM;
  END;
  PERFORM audit.as_postgres();
END $$;

-- 10.2 what anon can read from the storefront projection
DO $$
DECLARE r record; n int;
BEGIN
  PERFORM audit.as_anon();
  SELECT count(*) INTO n FROM public_seller_storefronts;
  RAISE NOTICE 'INFO 10.2 anon sees % storefront rows (approved sellers only; expected 3)', n;
  FOR r IN SELECT store_slug, phone_number FROM public_seller_storefronts ORDER BY store_slug LOOP
    RAISE NOTICE 'INFO 10.2   % exposes phone_number=%', r.store_slug, r.phone_number;
  END LOOP;
  PERFORM audit.as_postgres();
END $$;

-- 10.3 anon UPDATE through the auto-updatable storefront view (cross-tenant write)
DO $$
DECLARE n int; v record;
BEGIN
  PERFORM audit.as_anon();
  BEGIN
    UPDATE public_seller_storefronts
       SET store_name = 'PWNED BY ANON',
           phone_number = '9000000000',
           upi_display_name = 'Attacker',
           upi_enabled = false,
           default_shipping_fee_paisa = 999900,
           advance_confirmation_enabled = true,
           advance_amount_paisa = 100
     WHERE id = audit.seller_a();
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM audit.as_postgres();
    SELECT store_name, phone_number, upi_display_name, upi_enabled, default_shipping_fee_paisa, advance_amount_paisa
      INTO v FROM profiles WHERE id = audit.seller_a();
    IF n = 1 AND v.store_name = 'PWNED BY ANON' THEN
      RAISE NOTICE 'FINDING 10.3 anon updated seller A profile via public_seller_storefronts: rows=% store_name=% phone=% upi_enabled=% shipping_fee=% advance=%',
        n, v.store_name, v.phone_number, v.upi_enabled, v.default_shipping_fee_paisa, v.advance_amount_paisa;
    ELSE
      RAISE NOTICE 'PASS 10.3 anon UPDATE through view had no effect (rows=%)', n;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM audit.as_postgres();
    RAISE NOTICE 'PASS 10.3 anon UPDATE through view denied: %', SQLERRM;
  END;
END $$;

-- 10.4 anon DELETE through the view (approved seller without drops)
DO $$
DECLARE n int; still int;
BEGIN
  PERFORM audit.as_anon();
  BEGIN
    DELETE FROM public_seller_storefronts WHERE id = audit.seller_d();
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM audit.as_postgres();
    SELECT count(*) INTO still FROM profiles WHERE id = audit.seller_d();
    IF n = 1 AND still = 0 THEN
      RAISE NOTICE 'FINDING 10.4 anon deleted seller D profile through public_seller_storefronts (rows=%)', n;
    ELSE
      RAISE NOTICE 'PASS 10.4 anon DELETE through view had no effect (rows=%, profile present=%)', n, still;
    END IF;
  EXCEPTION
    WHEN insufficient_privilege THEN
      PERFORM audit.as_postgres();
      RAISE NOTICE 'PASS 10.4 anon DELETE through view denied: %', SQLERRM;
    WHEN foreign_key_violation THEN
      PERFORM audit.as_postgres();
      RAISE NOTICE 'INFO 10.4 delete blocked only by FK: %', SQLERRM;
  END;
END $$;

-- 10.5 authenticated seller B rewrites seller A storefront through the view
DO $$
DECLARE n int; v text;
BEGIN
  PERFORM audit.as_seller(audit.seller_b());
  BEGIN
    UPDATE public_seller_storefronts SET store_slug = 'hijacked-slug' WHERE id = audit.seller_a();
    GET DIAGNOSTICS n = ROW_COUNT;
    PERFORM audit.as_postgres();
    SELECT store_slug INTO v FROM profiles WHERE id = audit.seller_a();
    IF v = 'hijacked-slug' THEN
      RAISE NOTICE 'FINDING 10.5 seller B changed seller A store_slug via view (rows=%, slug=%) — storefront URL hijack', n, v;
    ELSE
      RAISE NOTICE 'PASS 10.5 seller B could not change seller A slug (rows=%)', n;
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM audit.as_postgres();
    RAISE NOTICE 'PASS 10.5 denied: %', SQLERRM;
  END;
END $$;

-- 10.6 the same UPDATE against the base table is blocked by RLS (control)
DO $$
DECLARE n int;
BEGIN
  PERFORM audit.as_seller(audit.seller_b());
  UPDATE profiles SET store_name = 'B writes A' WHERE id = audit.seller_a();
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 10.6 control: base-table UPDATE of another seller affected % rows (RLS)', CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END, n;
END $$;

-- 10.7 anon products base table: only granted columns readable
DO $$
DECLARE n int;
BEGIN
  PERFORM audit.as_anon();
  SELECT count(*) INTO n FROM (SELECT id, code, status FROM products) s;
  RAISE NOTICE 'INFO 10.7 anon reads % product rows (live drops of any seller) via column grant', n;
  BEGIN
    PERFORM reserved_by_order_id FROM products LIMIT 1;
    RAISE NOTICE 'FAIL 10.7 anon can read products.reserved_by_order_id';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS 10.7 anon cannot read products.reserved_by_order_id';
  END;
  PERFORM audit.as_postgres();
END $$;

-- 10.8 anon orders: no rows without the capability token
DO $$
DECLARE n int;
BEGIN
  PERFORM audit.as_anon();
  SELECT count(*) INTO n FROM orders;
  RAISE NOTICE '% 10.8 anon without x-order-token sees % orders', CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END, n;
  PERFORM audit.as_postgres();
END $$;

-- 10.9 privileges that exist only because of platform default grants
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.privilege_type
      FROM information_schema.role_table_grants p
     WHERE p.table_schema = 'public' AND p.table_name = 'public_seller_storefronts' AND p.grantee = 'anon'
     ORDER BY 1
  LOOP
    RAISE NOTICE 'INFO 10.9 anon holds % on public_seller_storefronts', r.privilege_type;
  END LOOP;
END $$;

ROLLBACK;
