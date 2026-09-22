-- LiveDrop Migration: 016_public_projection_views.sql
-- Description: SPRINT 1 (P0) — Secure Public Projection Views, Column Masking & PII Hardening.
-- Standards: ADR-009 (Strict Integer Paisa), Data Privacy & Tenant Isolation Guardrails
-- Security: Revokes direct anon table SELECT on profiles & products; grants sanitized projection views.

-- ============================================================================
-- 1. PUBLIC PROJECTION VIEW: public_seller_storefronts
-- ============================================================================
-- Exposes only public branding and checkout settings.
-- Strictly conceals private seller phone number, physical return address, and internal timestamps.

CREATE OR REPLACE VIEW public_seller_storefronts AS
SELECT 
    id,
    store_name,
    store_slug,
    upi_vpa,
    upi_display_name,
    upi_qr_url,
    upi_enabled,
    default_shipping_fee_paisa,
    free_shipping_threshold_paisa,
    advance_confirmation_enabled,
    advance_amount_paisa,
    hold_duration_days
FROM profiles;

COMMENT ON VIEW public_seller_storefronts IS 'Sanitized public projection of seller boutique profiles for buyer webfront.';


-- ============================================================================
-- 2. PUBLIC PROJECTION VIEW: public_products_catalog
-- ============================================================================
-- Exposes catalog garments for live drops.
-- Strictly conceals reserved_by_order_id (buyer order UUID) from public scraping.

CREATE OR REPLACE VIEW public_products_catalog AS
SELECT 
    p.id,
    p.drop_id,
    p.code,
    p.title,
    p.price_paisa,
    p.size,
    p.image_url,
    p.status,
    p.reserved_at,
    p.version,
    p.created_at
FROM products p
JOIN drops d ON d.id = p.drop_id
WHERE d.status = 'live';

COMMENT ON VIEW public_products_catalog IS 'Sanitized public projection of garments belonging to active live drops.';


-- ============================================================================
-- 3. PERMISSIONS & PRIVILEGE HARDENING
-- ============================================================================

-- 3.1 Revoke direct base table SELECT from anonymous users
REVOKE SELECT ON profiles FROM anon;
REVOKE SELECT ON products FROM anon;

-- 3.2 Update RLS Policies on profiles
DROP POLICY IF EXISTS profiles_public_read ON profiles;

-- Authenticated sellers can only read their own profile row
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'profiles' AND policyname = 'profiles_seller_select'
    ) THEN
        CREATE POLICY profiles_seller_select ON profiles
            FOR SELECT
            TO authenticated
            USING (id = auth.uid());
    END IF;
END $$;

-- 3.3 Update RLS Policies on products
DROP POLICY IF EXISTS products_public_read_live ON products;

-- 3.4 Grant SELECT on sanitized projection views to all client roles
GRANT SELECT ON public_seller_storefronts TO anon, authenticated, service_role;
GRANT SELECT ON public_products_catalog TO anon, authenticated, service_role;
