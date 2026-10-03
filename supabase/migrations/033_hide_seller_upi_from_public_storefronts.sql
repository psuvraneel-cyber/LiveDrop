-- LiveDrop Migration: 033_hide_seller_upi_from_public_storefronts.sql
-- Description: Seller UPI ID (upi_vpa) and the seller-uploaded QR image URL (upi_qr_url, which
--              encodes the UPI ID) must not be readable by anonymous visitors. Recreate the
--              public storefront projection without them. Buyers still receive the payee VPA
--              only inside the payment attempt returned by initiate_payment_attempt(), which
--              is needed to render the payment QR and the UPI app intent link.
-- Parent Documentation: docs/16-security-architecture.md, ADR-004

DROP VIEW IF EXISTS public.public_seller_storefronts;

CREATE VIEW public.public_seller_storefronts AS
SELECT
    id,
    store_name,
    store_slug,
    phone_number,
    upi_display_name,
    upi_enabled,
    default_shipping_fee_paisa,
    free_shipping_threshold_paisa,
    advance_confirmation_enabled,
    advance_amount_paisa,
    hold_duration_days,
    created_at
FROM public.profiles
WHERE is_approved = TRUE;

COMMENT ON VIEW public.public_seller_storefronts IS 'Sanitized public projection of approved seller boutique profiles. Excludes UPI ID, UPI QR image and return address (migration 033).';

GRANT SELECT ON public.public_seller_storefronts TO anon, authenticated, service_role;
