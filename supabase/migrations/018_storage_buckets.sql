-- LiveDrop Migration: 018_storage_buckets.sql
-- Description: SPRINT 2 (P1) — Provision `product-images` Storage Bucket & Seller-Isolated Policies.
-- Standards: ADR-009, Storage Security & Tenant Isolation Guardrails
-- Objectives: Store boutique garment images under strict seller directory sandboxing.

-- ============================================================================
-- 1. STORAGE BUCKET PROVISIONING
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


-- ============================================================================
-- 2. ROW-LEVEL SECURITY POLICIES ON storage.objects
-- ============================================================================

-- 2.1 Public read access: Anyone (including anonymous buyers) can view product images
DROP POLICY IF EXISTS product_images_public_read ON storage.objects;
CREATE POLICY product_images_public_read ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'product-images');

-- 2.2 Seller upload access: Authenticated sellers can only upload to their own folder:
-- Path schema: product-images/{seller_id}/{drop_id}/{code}_{timestamp}.webp
DROP POLICY IF EXISTS product_images_seller_insert ON storage.objects;
CREATE POLICY product_images_seller_insert ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'product-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 2.3 Seller update access: Authenticated sellers can update their own uploaded files
DROP POLICY IF EXISTS product_images_seller_update ON storage.objects;
CREATE POLICY product_images_seller_update ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'product-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 2.4 Seller delete access: Authenticated sellers can delete their own uploaded files
DROP POLICY IF EXISTS product_images_seller_delete ON storage.objects;
CREATE POLICY product_images_seller_delete ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'product-images'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
