-- LiveDrop Migration: 031_seller_storefronts_and_catalog_showcase.sql
-- Description: Expose support contact & created_at in public_seller_storefronts,
--              grant public read for 'closed' drops alongside 'live' drops for approved sellers,
--              and enhance public_products_catalog to project available showcase garments from closed drops.
-- Parent Documentation: docs/12-database-design.md, docs/16-security-architecture.md, ADR-002, ADR-009, SEC-01

-- Defensively guarantee is_approved column exists on profiles (per migration 021)
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT FALSE;

-- ============================================================================
-- 1. PUBLIC PROJECTION VIEW: public_seller_storefronts
-- ============================================================================
-- Exposes public branding, checkout settings, and public support contact (phone_number)
-- strictly for platform-approved sellers (WHERE is_approved = TRUE, per SEC-01 & Phase 1A).
-- Keeps physical return address private.

DROP VIEW IF EXISTS public.public_seller_storefronts CASCADE;

CREATE VIEW public.public_seller_storefronts AS
SELECT 
    id,
    store_name,
    store_slug,
    phone_number,
    upi_vpa,
    upi_display_name,
    upi_qr_url,
    upi_enabled,
    default_shipping_fee_paisa,
    free_shipping_threshold_paisa,
    advance_confirmation_enabled,
    advance_amount_paisa,
    hold_duration_days,
    created_at
FROM public.profiles
WHERE is_approved = TRUE;

COMMENT ON VIEW public.public_seller_storefronts IS 'Sanitized public projection of approved seller boutique profiles for buyer webfront, including verified support contact.';

GRANT SELECT ON public.public_seller_storefronts TO anon, authenticated, service_role;


-- ============================================================================
-- 2. TABLE: drops — RLS POLICY FOR PUBLIC STOREFRONTS
-- ============================================================================
-- Allow anonymous buyers and visitors to view both 'live' and 'closed' drops
-- belonging to approved boutique sellers.
-- Draft drops remain strictly inaccessible to anyone other than the owning seller.

-- Helper function to allow drops RLS policy to check seller approval
-- without granting anon table-level SELECT access to sensitive return addresses in profiles.
CREATE OR REPLACE FUNCTION public.is_seller_approved(p_seller_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_seller_id AND is_approved = TRUE
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_seller_approved(UUID) TO anon, authenticated, service_role;

DROP POLICY IF EXISTS drops_public_read_live ON public.drops;
DROP POLICY IF EXISTS drops_public_read ON public.drops;

CREATE POLICY drops_public_read ON public.drops
    FOR SELECT
    TO anon, authenticated
    USING (
        status IN ('live', 'closed')
        AND public.is_seller_approved(seller_id)
    );


-- ============================================================================
-- 3. PUBLIC PROJECTION VIEW: public_products_catalog
-- ============================================================================
-- Projects garments for live drops (all statuses: available, reserved, sold)
-- and for closed drops (strictly available items only for showcase lookbooks).
-- Conceals reserved_by_order_id.
-- Includes drop metadata and seller_id for efficient grouping on boutique storefronts.
-- Restricts garments strictly to approved boutique sellers.

DROP VIEW IF EXISTS public.public_products_catalog CASCADE;

CREATE VIEW public.public_products_catalog AS
SELECT 
    p.id,
    p.drop_id,
    d.seller_id,
    p.code,
    p.title,
    p.price_paisa,
    p.size,
    p.image_url,
    p.status,
    p.reserved_at,
    p.version,
    p.created_at,
    p.image_urls,
    d.status AS drop_status,
    d.title AS drop_title,
    d.slug AS drop_slug,
    d.created_at AS drop_created_at
FROM public.products p
JOIN public.drops d ON d.id = p.drop_id
JOIN public.profiles pr ON pr.id = d.seller_id
WHERE d.status IN ('live', 'closed')
  AND pr.is_approved = TRUE
  AND (d.status = 'live' OR p.status = 'available');

COMMENT ON VIEW public.public_products_catalog IS 'Sanitized public projection of garments belonging to active live drops or available showcase pieces from closed drops of approved sellers.';

GRANT SELECT ON public.public_products_catalog TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
