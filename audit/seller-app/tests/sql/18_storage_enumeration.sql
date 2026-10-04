-- =============================================================================
-- Suite 18 — can anyone enumerate product images, including unpublished ones?
-- AUDIT-ONLY. Runs inside a transaction that is rolled back.
--
-- product_images_public_read (027:23-26) grants SELECT on every object in the
-- bucket to role `public`. The Storage list/search API runs as the caller with
-- RLS, so this policy is what decides whether anonymous visitors can list
-- folders. Seller app paths are {seller_id}/{drop_id}/{code}_{queue}_{n}.jpg ('#' becomes '_')
-- (seller_repository.dart:738-739) — draft-drop photos are uploaded before the
-- drop goes live.
-- =============================================================================
\set ON_ERROR_STOP 1
BEGIN;
SELECT audit.seed();

DO $$
DECLARE n int; sample text[];
BEGIN
  INSERT INTO storage.buckets (id, name, public) VALUES ('product-images', 'product-images', true) ON CONFLICT DO NOTHING;

  -- seller A uploads photos for a DRAFT drop (not yet visible to buyers)
  PERFORM audit.as_seller(audit.seller_a());
  INSERT INTO storage.objects (bucket_id, name)
  VALUES ('product-images', audit.seller_a()::text || '/' || audit.drop_a_draft()::text || '/_D01_queue_1_0.jpg');
  -- an object left by unapproved seller C (uploaded before 038 blocked it; inserted as owner here)
  PERFORM audit.as_postgres();
  INSERT INTO storage.objects (bucket_id, name)
  VALUES ('product-images', audit.seller_c()::text || '/whatever/not-a-product.jpg');

  -- anonymous visitor lists the bucket (what storage.list()/search() would return)
  PERFORM audit.as_anon();
  SELECT count(*), array_agg(name ORDER BY name) INTO n, sample
  FROM storage.objects WHERE bucket_id = 'product-images';
  PERFORM audit.as_postgres();

  RAISE NOTICE '% 18.1 anon can list % object(s) in product-images, incl. draft-drop and unapproved-seller paths: %',
    CASE WHEN n >= 1 THEN 'FINDING' ELSE 'PASS' END, n, sample;

  -- 18.1b other sellers cannot list A's folder; A sees only their own objects (needed for upsert)
  PERFORM audit.as_seller(audit.seller_b());
  SELECT count(*) INTO n FROM storage.objects WHERE bucket_id = 'product-images';
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 18.1b seller B lists % object(s) in the bucket (own folder only)',
    CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END, n;
END $$;

DO $$
DECLARE n int; own int;
BEGIN
  PERFORM audit.as_seller(audit.seller_a());
  SELECT count(*), count(*) FILTER (WHERE (storage.foldername(name))[1] = audit.seller_a()::text)
    INTO n, own FROM storage.objects WHERE bucket_id = 'product-images';
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 18.1c seller A lists % object(s), % in own folder (own objects stay listable for upsert)',
    CASE WHEN n = own AND own >= 1 THEN 'PASS' ELSE 'FAIL' END, n, own;
END $$;

-- 18.2 is the draft drop itself visible to anon? (control: catalogue rules)
DO $$
DECLARE n int;
BEGIN
  PERFORM audit.as_anon();
  SELECT count(*) INTO n FROM drops WHERE id = audit.drop_a_draft();
  PERFORM audit.as_postgres();
  RAISE NOTICE '% 18.2 anon sees the draft drop row: % (images above leak what the catalogue hides)',
    CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END, n;
END $$;

ROLLBACK;
