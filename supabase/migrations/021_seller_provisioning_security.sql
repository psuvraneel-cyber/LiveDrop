-- LiveDrop Migration: 021_seller_provisioning_security.sql
-- Description: Phase 1A (P0 Blocker) — Authoritative Seller Provisioning Security & Approval Gate.
-- Standards: ADR-001 (PostgreSQL Authority), docs/16-security-architecture.md
-- Security: Prevents unapproved self-service sellers from publishing live drops or operating.

-- ============================================================================
-- 1. SCHEMA ENHANCEMENTS (TABLE: profiles)
-- ============================================================================

-- 1.1 Add approval lifecycle columns
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES auth.users(id);

-- 1.2 Seed profiles: Ensure existing development/test sellers are approved
UPDATE public.profiles
SET is_approved = TRUE,
    approved_at = NOW()
WHERE is_approved IS FALSE AND id IN (
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    '7b218d60-3a09-4044-80c1-ce7018c4a401'::uuid,
    '6a107c50-2908-4033-70b0-bd6007b393f0'::uuid,
    'd0000000-0000-0000-0000-000000000001'::uuid,
    'd0000000-0000-0000-0000-000000000002'::uuid,
    'd0000000-0000-0000-0000-000000000003'::uuid
);

-- ============================================================================
-- 2. TRIGGER: enforce_profiles_approval_immutability()
-- ============================================================================
-- Authenticated sellers CANNOT update is_approved, approved_at, or approved_by.
-- Only database owner / service_role can approve sellers.

CREATE OR REPLACE FUNCTION public.enforce_profiles_approval_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_trusted BOOLEAN;
    v_jwt_role TEXT;
BEGIN
    BEGIN
        v_jwt_role := COALESCE(
            NULLIF(current_setting('request.jwt.claim.role', true), ''),
            (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        );
    EXCEPTION WHEN OTHERS THEN
        v_jwt_role := NULL;
    END;

    v_is_trusted := (
        current_user IN ('postgres', 'service_role')
        OR (v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role')
    );

    IF NOT v_is_trusted THEN
        IF TG_OP = 'INSERT' THEN
            IF NEW.is_approved IS TRUE OR NEW.approved_at IS NOT NULL OR NEW.approved_by IS NOT NULL THEN
                RAISE EXCEPTION 'Modifying seller approval status is strictly restricted to platform administrators.'
                    USING ERRCODE = '42501';
            END IF;
        ELSIF TG_OP = 'UPDATE' THEN
            IF (OLD.is_approved IS DISTINCT FROM NEW.is_approved) OR
               (OLD.approved_at IS DISTINCT FROM NEW.approved_at) OR
               (OLD.approved_by IS DISTINCT FROM NEW.approved_by)
            THEN
                RAISE EXCEPTION 'Modifying seller approval status is strictly restricted to platform administrators.'
                    USING ERRCODE = '42501';
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_profiles_approval_immutability ON public.profiles;
CREATE TRIGGER trg_enforce_profiles_approval_immutability
    BEFORE INSERT OR UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_profiles_approval_immutability();

-- ============================================================================
-- 3. TRIGGER: enforce_drops_seller_approval()
-- ============================================================================
-- Guarantees that only approved sellers can publish drops with status = 'live'.

CREATE OR REPLACE FUNCTION public.enforce_drops_seller_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_approved BOOLEAN;
BEGIN
    IF NEW.status = 'live' THEN
        SELECT is_approved INTO v_is_approved
        FROM public.profiles
        WHERE id = NEW.seller_id;

        IF v_is_approved IS NOT TRUE THEN
            RAISE EXCEPTION 'Seller account is pending platform verification. Unapproved sellers cannot publish live drops.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_drops_seller_approval ON public.drops;
CREATE TRIGGER trg_enforce_drops_seller_approval
    BEFORE INSERT OR UPDATE ON public.drops
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_drops_seller_approval();

-- ============================================================================
-- 4. RPC: admin_approve_seller()
-- ============================================================================
-- Server-authoritative mechanism for platform administrators to approve/suspend sellers.

CREATE OR REPLACE FUNCTION public.admin_approve_seller(
    p_seller_id UUID,
    p_approved BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_jwt_role TEXT;
    v_is_admin BOOLEAN;
    v_seller public.profiles%ROWTYPE;
BEGIN
    -- Only service_role is authorized to execute administrative approval
    BEGIN
        v_jwt_role := COALESCE(
            NULLIF(current_setting('request.jwt.claim.role', true), ''),
            (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        );
    EXCEPTION WHEN OTHERS THEN
        v_jwt_role := NULL;
    END;

    v_is_admin := (
        current_user IN ('postgres', 'service_role')
        OR (v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role')
    );

    IF NOT v_is_admin THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Only platform administrators can approve sellers.'
        );
    END IF;

    SELECT * INTO v_seller FROM public.profiles WHERE id = p_seller_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'SELLER_NOT_FOUND',
            'message', 'Seller profile does not exist.'
        );
    END IF;

    UPDATE public.profiles
    SET is_approved = p_approved,
        approved_at = CASE WHEN p_approved THEN NOW() ELSE NULL END,
        approved_by = CASE WHEN p_approved THEN auth.uid() ELSE NULL END,
        updated_at = NOW()
    WHERE id = p_seller_id;

    RETURN jsonb_build_object(
        'success', true,
        'seller_id', p_seller_id,
        'is_approved', p_approved,
        'message', CASE WHEN p_approved THEN 'Seller approved successfully.' ELSE 'Seller approval revoked.' END
    );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_seller(UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_approve_seller(UUID, BOOLEAN) FROM anon;
REVOKE ALL ON FUNCTION public.admin_approve_seller(UUID, BOOLEAN) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_seller(UUID, BOOLEAN) TO service_role;

-- ============================================================================
-- 5. UPDATE TRIGGER FUNCTION: handle_new_seller_signup()
-- ============================================================================
-- Newly created profiles explicitly default is_approved to FALSE.

CREATE OR REPLACE FUNCTION public.handle_new_seller_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_store_name TEXT;
    v_store_slug TEXT;
    v_phone TEXT;
    v_upi_id TEXT;
    v_return_address TEXT;
BEGIN
    v_store_name := NEW.raw_user_meta_data->>'store_name';
    IF v_store_name IS NOT NULL AND char_length(v_store_name) >= 2 THEN
        v_phone := COALESCE(NEW.raw_user_meta_data->>'phone_number', '919876543210');
        v_upi_id := COALESCE(NEW.raw_user_meta_data->>'upi_id', 'seller@okhdfcbank');
        v_return_address := COALESCE(NEW.raw_user_meta_data->>'return_address', 'Default Address, India');
        
        v_store_slug := LOWER(REGEXP_REPLACE(v_store_name, '[^a-zA-Z0-9]+', '-', 'g'));
        v_store_slug := TRIM(BOTH '-' FROM v_store_slug);
        IF char_length(v_store_slug) < 3 THEN
            v_store_slug := 'store-' || SUBSTRING(NEW.id::text FROM 1 FOR 8);
        END IF;

        IF EXISTS (SELECT 1 FROM public.profiles WHERE store_slug = v_store_slug) THEN
            v_store_slug := v_store_slug || '-' || SUBSTRING(NEW.id::text FROM 1 FOR 6);
        END IF;

        INSERT INTO public.profiles (
            id,
            store_name,
            store_slug,
            phone_number,
            upi_id,
            upi_vpa,
            upi_display_name,
            return_address,
            default_shipping_fee_paisa,
            is_approved
        ) VALUES (
            NEW.id,
            v_store_name,
            v_store_slug,
            v_phone,
            v_upi_id,
            v_upi_id,
            v_store_name,
            v_return_address,
            8000,
            FALSE
        )
        ON CONFLICT (id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

-- ============================================================================
-- 6. PUBLIC PROJECTION HARDENING: Filter unapproved sellers
-- ============================================================================
-- Ensures unapproved sellers cannot have their storefront retrieved publicly.

CREATE OR REPLACE VIEW public.public_seller_storefronts AS
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
FROM public.profiles
WHERE is_approved = TRUE;

GRANT SELECT ON public.public_seller_storefronts TO anon, authenticated, service_role;

