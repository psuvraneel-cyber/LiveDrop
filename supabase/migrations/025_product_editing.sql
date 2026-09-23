-- ============================================================================
-- Migration 025: Authoritative Product Editing RPC & Immutability Hardening
-- Part of Phase 1 Blocker Remediation: Blocker 1H (Inventory Editing - P1)
-- ============================================================================

-- Harden enforce_products_inventory_immutability to disallow direct alteration
-- of price, title, or size when an item is reserved or sold.
CREATE OR REPLACE FUNCTION enforce_products_inventory_immutability()
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
        -- Prevent direct table updates via PostgREST; require authoritative update_product RPC
        IF current_setting('livedrop.updating_product', true) IS DISTINCT FROM 'true' THEN
            RAISE EXCEPTION 'Direct update of products is prohibited for authenticated users. Use authoritative update_product RPC.'
                USING ERRCODE = '42501';
        END IF;

        -- Prevent untrusted caller from altering reservation linkages or transitioning reserved items
        IF (OLD.status = 'reserved' AND NEW.status != 'reserved') OR
           (OLD.reserved_by_order_id IS DISTINCT FROM NEW.reserved_by_order_id) OR
           (OLD.reserved_at IS DISTINCT FROM NEW.reserved_at)
        THEN
            RAISE EXCEPTION 'Direct mutation of product reservation status is prohibited for authenticated sellers. Use trusted RPCs.'
                USING ERRCODE = '42501';
        END IF;

        -- Prevent altering price, title, or size on reserved or sold items
        IF (OLD.status IN ('reserved', 'sold')) AND
           (OLD.price_paisa IS DISTINCT FROM NEW.price_paisa OR
            OLD.title IS DISTINCT FROM NEW.title OR
            OLD.size IS DISTINCT FROM NEW.size)
        THEN
            RAISE EXCEPTION 'Cannot modify product details for reserved or sold items. Status is %.', OLD.status
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_products_inventory_immutability ON products;
CREATE TRIGGER trg_enforce_products_inventory_immutability
    BEFORE UPDATE ON products
    FOR EACH ROW
    EXECUTE FUNCTION enforce_products_inventory_immutability();

-- Authoritative update_product RPC
-- Allows a drop-owning seller to update title, price (in Paisa), and size for available items.
-- Rejects edits when item is reserved or sold.
CREATE OR REPLACE FUNCTION update_product(
    p_product_id UUID,
    p_title TEXT,
    p_price_paisa INT,
    p_size TEXT
) RETURNS JSONB AS $$
DECLARE
    v_seller_id UUID;
    v_product products%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_clean_title TEXT;
    v_clean_size TEXT;
BEGIN
    -- 1. Authentication check
    v_seller_id := auth.uid();
    IF v_seller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to update products.'
        );
    END IF;

    -- 2. Input validation
    v_clean_title := trim(COALESCE(p_title, ''));
    v_clean_size := trim(COALESCE(p_size, ''));

    IF v_clean_title = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_TITLE',
            'message', 'Product title cannot be empty.'
        );
    END IF;

    IF p_price_paisa IS NULL OR p_price_paisa <= 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_PRICE',
            'message', 'Price must be a positive integer in Paisa.'
        );
    END IF;

    IF v_clean_size = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_SIZE',
            'message', 'Product size cannot be empty.'
        );
    END IF;

    -- 3. Row lock on target product
    SELECT * INTO v_product FROM products WHERE id = p_product_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PRODUCT_NOT_FOUND',
            'message', 'Product not found.'
        );
    END IF;

    -- 4. Verify drop ownership
    SELECT * INTO v_drop FROM drops WHERE id = v_product.drop_id AND seller_id = v_seller_id FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'You do not own the drop containing this product.'
        );
    END IF;

    -- 5. Business rule: Product must be available
    IF v_product.status != 'available' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'CANNOT_EDIT_RESERVED_OR_SOLD',
            'message', format('Product is "%s" and cannot be edited. Only available products can be modified.', v_product.status)
        );
    END IF;

    -- 6. Perform authoritative update
    PERFORM set_config('livedrop.updating_product', 'true', true);

    UPDATE products
    SET title = v_clean_title,
        price_paisa = p_price_paisa,
        size = v_clean_size,
        version = version + 1,
        updated_at = NOW()
    WHERE id = p_product_id
    RETURNING * INTO v_product;

    RETURN jsonb_build_object(
        'success', true,
        'product', row_to_json(v_product)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

GRANT EXECUTE ON FUNCTION update_product(UUID, TEXT, INT, TEXT) TO authenticated, service_role;
