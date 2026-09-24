-- LiveDrop Migration: 030_fix_advance_paid_balance_payment_resolution.sql
-- Description: Ensure get_order_by_token resolves balance payment attempts and amounts
--              when an order's payment_status is 'advance_paid', rather than recycling
--              historical verified advance payment attempts.

CREATE OR REPLACE FUNCTION public.get_order_by_token(
    p_order_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order RECORD;
    v_drop RECORD;
    v_seller RECORD;
    v_items JSONB;
    v_active_attempt RECORD;
    v_upi_uri TEXT;
    v_attempt_json JSONB;
BEGIN
    -- 1. Locate order by order_token
    SELECT * INTO v_order FROM orders WHERE order_token::text = p_order_token;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'No active order found for the provided token.'
        );
    END IF;

    -- 2. Fetch drop and seller profiles
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 3. Fetch aggregated line items
    SELECT jsonb_agg(
        jsonb_build_object(
            'product_id', oi.product_id,
            'code', p.code,
            'title', p.title,
            'image_url', p.image_url,
            'price_at_purchase_paisa', oi.price_at_purchase_paisa
        ) ORDER BY p.code ASC
    ) INTO v_items
    FROM order_items oi
    JOIN products p ON p.id = oi.product_id
    WHERE oi.order_id = v_order.id;

    -- 4. Fetch active payment attempt based on order payment lifecycle
    IF v_order.payment_status = 'advance_paid' THEN
        -- When advance is already verified, the only active attempt is for the remaining balance.
        SELECT * INTO v_active_attempt
        FROM payment_attempts
        WHERE order_id = v_order.id
          AND payment_type = 'balance'
          AND status IN ('created', 'awaiting_payment', 'awaiting_seller_verification', 'late_claim_pending_review')
        ORDER BY created_at DESC
        LIMIT 1;

        -- If no active pending balance attempt, check for any balance attempt (e.g. verified or historical)
        IF NOT FOUND THEN
            SELECT * INTO v_active_attempt
            FROM payment_attempts
            WHERE order_id = v_order.id
              AND payment_type = 'balance'
            ORDER BY created_at DESC
            LIMIT 1;
        END IF;

    ELSIF v_order.payment_status = 'paid' THEN
        -- When fully paid, fetch latest attempt for receipt display
        SELECT * INTO v_active_attempt
        FROM payment_attempts
        WHERE order_id = v_order.id
        ORDER BY created_at DESC
        LIMIT 1;

    ELSE
        -- Unpaid: fetch active attempt for advance or full payment
        SELECT * INTO v_active_attempt
        FROM payment_attempts
        WHERE order_id = v_order.id
          AND status IN ('created', 'awaiting_payment', 'awaiting_seller_verification', 'late_claim_pending_review')
        ORDER BY created_at DESC
        LIMIT 1;

        IF NOT FOUND THEN
            SELECT * INTO v_active_attempt
            FROM payment_attempts
            WHERE order_id = v_order.id
            ORDER BY created_at DESC
            LIMIT 1;
        END IF;
    END IF;

    IF v_active_attempt.id IS NOT NULL THEN
        v_upi_uri := generate_upi_payment_uri(
            v_active_attempt.payee_vpa_snapshot,
            v_active_attempt.payee_display_name_snapshot,
            v_active_attempt.expected_amount_paisa,
            v_active_attempt.transaction_reference,
            'LiveDrop ' || v_order.order_code || CASE WHEN v_active_attempt.payment_type = 'balance' THEN ' balance' ELSE '' END
        );

        v_attempt_json := jsonb_build_object(
            'id', v_active_attempt.id,
            'payment_type', v_active_attempt.payment_type,
            'payment_method', v_active_attempt.payment_method,
            'expected_amount_paisa', v_active_attempt.expected_amount_paisa,
            'payee_vpa', v_active_attempt.payee_vpa_snapshot,
            'payee_display_name', v_active_attempt.payee_display_name_snapshot,
            'payee_vpa_snapshot', v_active_attempt.payee_vpa_snapshot,
            'payee_display_name_snapshot', v_active_attempt.payee_display_name_snapshot,
            'transaction_reference', v_active_attempt.transaction_reference,
            'status', v_active_attempt.status,
            'buyer_submitted_utr', v_active_attempt.buyer_submitted_utr,
            'buyer_claimed_at', v_active_attempt.buyer_claimed_at,
            'seller_verified_at', v_active_attempt.seller_verified_at,
            'rejection_reason', v_active_attempt.rejection_reason,
            'verification_expires_at', v_active_attempt.verification_expires_at,
            'expires_at', v_active_attempt.expires_at,
            'created_at', v_active_attempt.created_at,
            'updated_at', v_active_attempt.updated_at,
            'upi_uri', v_upi_uri
        );
    ELSE
        v_attempt_json := NULL;
        IF COALESCE(v_seller.upi_vpa, v_seller.upi_id) IS NOT NULL THEN
            v_upi_uri := generate_upi_payment_uri(
                COALESCE(v_seller.upi_vpa, v_seller.upi_id),
                COALESCE(v_seller.upi_display_name, v_seller.store_name, 'LiveDrop Seller'),
                CASE 
                    WHEN v_order.payment_status = 'advance_paid' THEN v_order.balance_due_paisa
                    WHEN v_order.confirmation_mode = 'advance' THEN v_order.advance_required_paisa 
                    ELSE v_order.total_paisa 
                END,
                v_order.order_code,
                'LiveDrop ' || v_order.order_code || CASE WHEN v_order.payment_status = 'advance_paid' THEN ' balance' ELSE '' END
            );
        END IF;
    END IF;

    -- 5. Construct Authoritative Receipt Payload with fulfillment & tracking metadata
    RETURN jsonb_build_object(
        'success', true,
        'order', jsonb_build_object(
            'id', v_order.id,
            'order_code', v_order.order_code,
            'buyer_name', v_order.buyer_name,
            'subtotal_paisa', v_order.subtotal_paisa,
            'shipping_paisa', v_order.shipping_paisa,
            'total_paisa', v_order.total_paisa,
            'confirmation_mode', v_order.confirmation_mode,
            'advance_required_paisa', v_order.advance_required_paisa,
            'advance_paid_paisa', v_order.advance_paid_paisa,
            'total_paid_paisa', v_order.total_paid_paisa,
            'balance_due_paisa', v_order.balance_due_paisa,
            'payment_status', v_order.payment_status,
            'fulfilment_status', v_order.fulfilment_status,
            'status', v_order.status,
            'hold_expires_at', v_order.hold_expires_at,
            'shipped_at', v_order.shipped_at,
            'tracking_number', v_order.tracking_number,
            'courier_partner', v_order.courier_partner,
            'notes', v_order.notes,
            'store_name', v_seller.store_name,
            'store_slug', v_seller.store_slug,
            'upi_id', COALESCE(v_seller.upi_vpa, v_seller.upi_id),
            'upi_enabled', v_seller.upi_enabled,
            'upi_qr_url', v_seller.upi_qr_url,
            'upi_uri', v_upi_uri,
            'items', COALESCE(v_items, '[]'::jsonb),
            'payment_attempt', v_attempt_json,
            'active_payment_attempt', v_attempt_json
        )
    );
END;
$$;

-- Canonical 2-parameter overload
CREATE OR REPLACE FUNCTION public.get_order_by_token(
    p_order_id UUID,
    p_order_token TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_res JSONB;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND order_token::text = p_order_token) THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    v_res := get_order_by_token(p_order_token);
    RETURN v_res;
END;
$$;

REVOKE ALL ON FUNCTION public.get_order_by_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_order_by_token(TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.get_order_by_token(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_order_by_token(UUID, TEXT) TO anon, authenticated, service_role;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
