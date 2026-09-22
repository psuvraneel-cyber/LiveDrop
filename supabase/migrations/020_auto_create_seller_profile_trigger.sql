-- LiveDrop Migration: 020_auto_create_seller_profile_trigger.sql
-- Description: Automatically provisions boutique seller profile on self-service auth.users insertion.
-- Parent Documentation: docs/12-database-design.md, docs/16-security-architecture.md

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
    -- Only provision profile if store_name is present in metadata
    IF v_store_name IS NOT NULL AND char_length(v_store_name) >= 2 THEN
        v_phone := COALESCE(NEW.raw_user_meta_data->>'phone_number', '919876543210');
        v_upi_id := COALESCE(NEW.raw_user_meta_data->>'upi_id', 'seller@okhdfcbank');
        v_return_address := COALESCE(NEW.raw_user_meta_data->>'return_address', 'Default Address, India');
        
        -- Clean and slugify store name
        v_store_slug := LOWER(REGEXP_REPLACE(v_store_name, '[^a-zA-Z0-9]+', '-', 'g'));
        v_store_slug := TRIM(BOTH '-' FROM v_store_slug);
        IF char_length(v_store_slug) < 3 THEN
            v_store_slug := 'store-' || SUBSTRING(NEW.id::text FROM 1 FOR 8);
        END IF;

        -- Ensure uniqueness of store_slug
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
            default_shipping_fee_paisa
        ) VALUES (
            NEW.id,
            v_store_name,
            v_store_slug,
            v_phone,
            v_upi_id,
            v_upi_id,
            v_store_name,
            v_return_address,
            8000
        )
        ON CONFLICT (id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;
CREATE TRIGGER trg_on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_seller_signup();
