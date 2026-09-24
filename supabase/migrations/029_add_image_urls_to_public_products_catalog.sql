-- LiveDrop Migration: 029_add_image_urls_to_public_products_catalog.sql
-- Description: Expose product multi-angle garment photos (image_urls) in public_products_catalog view.
-- Standards: ADR-001 (PostgreSQL Authority), docs/12-database-design.md, docs/16-security-architecture.md

CREATE OR REPLACE VIEW public.public_products_catalog AS
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
    p.created_at,
    p.image_urls
FROM public.products p
JOIN public.drops d ON d.id = p.drop_id
WHERE d.status = 'live';

COMMENT ON VIEW public.public_products_catalog IS 'Sanitized public projection of garments belonging to active live drops, including multi-angle photos.';

GRANT SELECT ON public.public_products_catalog TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
