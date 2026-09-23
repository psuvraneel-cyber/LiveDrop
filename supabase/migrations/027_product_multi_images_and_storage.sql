-- LiveDrop Migration: 027_product_multi_images_and_storage.sql
-- Description: Multi-angle garment photos support and product-images storage bucket provisioning.
-- Standards: ADR-001 (PostgreSQL Authority), docs/12-database-design.md, docs/16-security-architecture.md

-- ============================================================================
-- 1. STORAGE BUCKET PROVISIONING: product-images
-- ============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'product-images',
    'product-images',
    true,
    5242880, -- 5 MB limit
    ARRAY['image/webp', 'image/jpeg', 'image/png']
)
ON CONFLICT (id) DO UPDATE SET
    public = true,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/webp', 'image/jpeg', 'image/png'];

-- RLS policies on storage.objects
DROP POLICY IF EXISTS product_images_public_read ON storage.objects;
CREATE POLICY product_images_public_read ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS product_images_seller_insert ON storage.objects;
CREATE POLICY product_images_seller_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'product-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS product_images_seller_update ON storage.objects;
CREATE POLICY product_images_seller_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'product-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

DROP POLICY IF EXISTS product_images_seller_delete ON storage.objects;
CREATE POLICY product_images_seller_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'product-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- ============================================================================
-- 2. PRODUCTS TABLE: MULTI-IMAGE ARRAY (image_urls)
-- ============================================================================

ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS image_urls TEXT[] NOT NULL DEFAULT '{}';

-- Backfill existing products so image_urls contains the primary image_url
UPDATE public.products
SET image_urls = ARRAY[image_url]
WHERE image_urls = '{}' OR image_urls IS NULL;

-- Permissions
GRANT SELECT (image_urls) ON public.products TO anon, authenticated;
GRANT INSERT (image_urls), UPDATE (image_urls) ON public.products TO authenticated;
