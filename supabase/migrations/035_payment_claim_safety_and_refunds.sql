-- LiveDrop Migration: 035_payment_claim_safety_and_refunds.sql
-- Description: P0 payment / inventory safety fixes from the seller-app audit (audit/seller-app/).
--
--   SA-PAY-001  Late ADVANCE claim was verified as a full payment (order paid, ledger = advance).
--   SA-PAY-002  Late-claim verification checked availability without a lock and overwrote a piece
--               another buyer had just reserved (one garment sold twice).
--   SA-PAY-003  The reaper expired buyer-claimed payments after 24 h; the claim vanished from the
--               seller's queue and the piece was released.
--   SA-PAY-004  A verified late payment whose pieces were resold left the refund obligation only in
--               free text (orders.notes) — invisible in the app.
--   SA-PAY-005  force_release_hold cancelled orders whose buyer had already claimed payment.
--   SA-OPS-001  Expired holds were only released by an unreliable external scheduler; checkout now
--               releases an expired, unclaimed hold on the requested pieces itself (lazy expiry).
--   Fixed alongside:
--   SA-PAY-006  Late advance on a resold piece raised chk_orders_balance_formula.
--   SA-PAY-018  Deleting a refund-owed order cascaded away its verified ledger rows.
--   SA-INT-002  verify_manual_upi_payment (attempt -> order) and the reaper (order -> attempt)
--               locked in opposite order and deadlocked.
--
-- Rules applied everywhere in this migration:
--   * Lock order: orders -> payment_attempts -> products (products always ORDER BY id).
--   * The reaper and the lazy-expiry helper never wait for a lock (FOR UPDATE SKIP LOCKED); a row
--     they cannot lock immediately is left for the next run.
--   * Money in flight never auto-expires: an order with an attempt in buyer_claimed /
--     awaiting_seller_verification / late_claim_pending_review is never cancelled or expired by
--     the reaper, lazy expiry or force_release_hold, and such attempts are never expired.
--   * Ledger invariant: orders.total_paid_paisa = SUM(order_payments.amount_paisa) of verified rows.
--   * Money is integer paisa. SECURITY DEFINER functions pin search_path = public, pg_temp.
--   * Signatures, grants and existing response keys of the redefined RPCs are unchanged.
--
-- Regression suites: audit/seller-app/tests/sql/13, 14_concurrency.sh, 16, 17, 19.

-- ============================================================================
-- 1. orders: structured refund obligation (SA-PAY-004)
-- ============================================================================
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refund_status TEXT NOT NULL DEFAULT 'none';
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refund_amount_paisa INT NOT NULL DEFAULT 0;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refund_reason TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refund_required_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refund_reference TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refunded_at TIMESTAMPTZ;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS refund_recorded_by UUID REFERENCES auth.users(id);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'chk_orders_refund_status' AND conrelid = 'public.orders'::regclass) THEN
        ALTER TABLE public.orders ADD CONSTRAINT chk_orders_refund_status
            CHECK (refund_status IN ('none', 'required', 'refunded'));
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'chk_orders_refund_amount_nonneg' AND conrelid = 'public.orders'::regclass) THEN
        ALTER TABLE public.orders ADD CONSTRAINT chk_orders_refund_amount_nonneg
            CHECK (refund_amount_paisa >= 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'chk_orders_refund_amount_consistency' AND conrelid = 'public.orders'::regclass) THEN
        ALTER TABLE public.orders ADD CONSTRAINT chk_orders_refund_amount_consistency
            CHECK (
                (refund_status = 'none' AND refund_amount_paisa = 0)
                OR (refund_status <> 'none' AND refund_amount_paisa > 0 AND refund_amount_paisa <= total_paid_paisa)
            );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'chk_orders_refunded_requires_reference' AND conrelid = 'public.orders'::regclass) THEN
        ALTER TABLE public.orders ADD CONSTRAINT chk_orders_refunded_requires_reference
            CHECK (refund_status <> 'refunded' OR (refund_reference IS NOT NULL AND refunded_at IS NOT NULL));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_refund_required
    ON public.orders (drop_id)
    WHERE refund_status = 'required';

COMMENT ON COLUMN public.orders.refund_status IS
    'none | required | refunded. Set to required when a verified payment cannot be honoured (late payment for pieces already resold). Only RPCs may change it.';
COMMENT ON COLUMN public.orders.refund_amount_paisa IS
    'Integer paisa owed back to the buyer (cumulative). 0 when refund_status = none.';

-- 1.1 Existing data: late payments verified by migration 023 for pieces that were already resold
--     carry metadata.refund_required = true on their ledger row and only a free-text note on the
--     order. Give them the structured refund obligation so they appear in the seller's refund list.
UPDATE public.orders o
   SET refund_status = 'required',
       refund_amount_paisa = r.amount_paisa,
       refund_reason = 'LATE_PAYMENT_INVENTORY_UNAVAILABLE',
       refund_required_at = r.first_verified_at
  FROM (
        SELECT op.order_id,
               SUM(op.amount_paisa)::INT AS amount_paisa,
               MIN(COALESCE(op.verified_at, op.created_at)) AS first_verified_at
          FROM public.order_payments op
         WHERE op.status = 'verified'
           AND op.metadata ->> 'refund_required' = 'true'
         GROUP BY op.order_id
       ) r
 WHERE o.id = r.order_id
   AND o.refund_status = 'none'
   AND o.status IN ('cancelled', 'expired')
   AND r.amount_paisa > 0
   AND r.amount_paisa <= o.total_paid_paisa;

-- 1.2 Existing data: before this migration force_release_hold could cancel an order whose buyer
--     had already claimed payment (SA-PAY-005). Such claims stay in the seller's queue but could
--     never be verified (INVALID_ORDER_STATE). Route them to late review so verification records
--     the money and either re-secures the pieces or raises a refund obligation.
UPDATE public.payment_attempts pa
   SET status = 'late_claim_pending_review',
       updated_at = NOW()
  FROM public.orders o
 WHERE o.id = pa.order_id
   AND o.status IN ('cancelled', 'expired')
   AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification');

-- ============================================================================
-- 2. Sellers cannot change refund fields with a direct UPDATE (extends migration 012)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.enforce_orders_payment_immutability()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_trusted BOOLEAN;
    v_jwt_role TEXT;
BEGIN
    -- Resolve JWT role if set in connection context
    BEGIN
        v_jwt_role := COALESCE(
            NULLIF(current_setting('request.jwt.claim.role', true), ''),
            (NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        );
    EXCEPTION WHEN OTHERS THEN
        v_jwt_role := NULL;
    END;

    -- Caller is trusted if running as superuser/postgres (which includes all SECURITY DEFINER RPCs),
    -- as service_role, or with service_role JWT claim.
    v_is_trusted := (
        current_user IN ('postgres', 'service_role')
        OR (v_jwt_role IS NOT NULL AND v_jwt_role = 'service_role')
    );

    IF NOT v_is_trusted THEN
        -- Check if any payment, financial, refund or lifecycle authoritative field is being altered
        IF (OLD.status IS DISTINCT FROM NEW.status) OR
           (OLD.payment_status IS DISTINCT FROM NEW.payment_status) OR
           (OLD.fulfilment_status IS DISTINCT FROM NEW.fulfilment_status) OR
           (OLD.advance_required_paisa IS DISTINCT FROM NEW.advance_required_paisa) OR
           (OLD.advance_paid_paisa IS DISTINCT FROM NEW.advance_paid_paisa) OR
           (OLD.total_paid_paisa IS DISTINCT FROM NEW.total_paid_paisa) OR
           (OLD.balance_due_paisa IS DISTINCT FROM NEW.balance_due_paisa) OR
           (OLD.advance_paid_at IS DISTINCT FROM NEW.advance_paid_at) OR
           (OLD.paid_at IS DISTINCT FROM NEW.paid_at) OR
           (OLD.shipped_at IS DISTINCT FROM NEW.shipped_at) OR
           (OLD.hold_expires_at IS DISTINCT FROM NEW.hold_expires_at) OR
           (OLD.confirmation_mode IS DISTINCT FROM NEW.confirmation_mode) OR
           (OLD.subtotal_paisa IS DISTINCT FROM NEW.subtotal_paisa) OR
           (OLD.shipping_paisa IS DISTINCT FROM NEW.shipping_paisa) OR
           (OLD.total_paisa IS DISTINCT FROM NEW.total_paisa) OR
           (OLD.order_token IS DISTINCT FROM NEW.order_token) OR
           (OLD.order_code IS DISTINCT FROM NEW.order_code) OR
           (OLD.drop_id IS DISTINCT FROM NEW.drop_id) OR
           (OLD.refund_status IS DISTINCT FROM NEW.refund_status) OR
           (OLD.refund_amount_paisa IS DISTINCT FROM NEW.refund_amount_paisa) OR
           (OLD.refund_reason IS DISTINCT FROM NEW.refund_reason) OR
           (OLD.refund_required_at IS DISTINCT FROM NEW.refund_required_at) OR
           (OLD.refund_reference IS DISTINCT FROM NEW.refund_reference) OR
           (OLD.refunded_at IS DISTINCT FROM NEW.refunded_at) OR
           (OLD.refund_recorded_by IS DISTINCT FROM NEW.refund_recorded_by)
        THEN
            RAISE EXCEPTION 'Direct mutation of payment or order lifecycle fields is prohibited for authenticated sellers. Use trusted RPCs.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- ============================================================================
-- 3. Orders that carry payment records or a refund obligation cannot be deleted (SA-PAY-018)
-- ============================================================================
-- order_payments.order_id is ON DELETE CASCADE; deleting such an order would erase the only record
-- that the buyer's money was received. SECURITY DEFINER so the ledger check never depends on the
-- deleting role's RLS visibility.
CREATE OR REPLACE FUNCTION public.prevent_finalized_order_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF OLD.status IN ('confirmed', 'paid', 'shipped', 'expired') THEN
        RAISE EXCEPTION 'Cannot delete finalized order % with status "%"', OLD.id, OLD.status;
    END IF;

    IF OLD.refund_status IS DISTINCT FROM 'none' THEN
        RAISE EXCEPTION 'Cannot delete order % with refund status "%": the refund obligation and its payment records must be kept', OLD.id, OLD.refund_status;
    END IF;

    IF EXISTS (SELECT 1 FROM public.order_payments WHERE order_id = OLD.id) THEN
        RAISE EXCEPTION 'Cannot delete order % because it has payment ledger records', OLD.id;
    END IF;

    RETURN OLD;
END;
$$;

-- ============================================================================
-- 4. Internal: verification response (all keys always present)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.upi_verification_response(
    p_order_id UUID,
    p_payment_attempt_id UUID,
    p_payment_id UUID,
    p_idempotent BOOLEAN,
    p_is_late_claim BOOLEAN,
    p_inventory_available BOOLEAN,
    p_message TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_attempt payment_attempts%ROWTYPE;
    v_payment order_payments%ROWTYPE;
    v_is_late BOOLEAN;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id;
    SELECT * INTO v_attempt FROM payment_attempts WHERE id = p_payment_attempt_id;

    IF p_payment_id IS NOT NULL THEN
        SELECT * INTO v_payment FROM order_payments WHERE id = p_payment_id;
    ELSE
        SELECT * INTO v_payment
          FROM order_payments
         WHERE order_id = p_order_id
           AND metadata ->> 'payment_attempt_id' = p_payment_attempt_id::text
         ORDER BY created_at DESC
         LIMIT 1;
    END IF;

    v_is_late := COALESCE(p_is_late_claim, (v_payment.metadata ->> 'is_late_claim')::boolean, false);

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', COALESCE(p_idempotent, false),
        'is_late_claim', v_is_late,
        'inventory_available', p_inventory_available,
        'refund_required', (v_order.refund_status = 'required'),
        'refund_amount_paisa', v_order.refund_amount_paisa,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'order_status', v_order.status,
        'status', v_order.status,
        'payment_status', v_order.payment_status,
        'fulfilment_status', v_order.fulfilment_status,
        'total_paid_paisa', v_order.total_paid_paisa,
        'balance_due_paisa', v_order.balance_due_paisa,
        'advance_paid_paisa', v_order.advance_paid_paisa,
        'payment_type', v_attempt.payment_type,
        'amount_paisa', v_attempt.expected_amount_paisa,
        'payment_attempt_id', v_attempt.id,
        'attempt_id', v_attempt.id,
        'payment_id', v_payment.id,
        'message', p_message
    );
END;
$$;

-- ============================================================================
-- 5. Internal: the per-type payment transition shared by on-time and late verification
-- ============================================================================
-- Called only by verify_manual_upi_payment after authorization, idempotency, expiry and
-- reference checks. Locks: orders -> payment_attempts -> products. Every rejection happens before
-- the first write; a payment that cannot be applied is never half-recorded.
CREATE OR REPLACE FUNCTION public.apply_upi_payment_transition(
    p_order_id UUID,
    p_payment_attempt_id UUID,
    p_verified_ref TEXT,
    p_clean_utr TEXT,
    p_actor UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_attempt payment_attempts%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_seller profiles%ROWTYPE;
    v_is_late BOOLEAN;
    v_type TEXT;
    v_amount INT;
    v_items INT;
    v_held INT;
    v_obtainable INT;
    v_ledger_sum BIGINT;
    v_new_total_paid BIGINT;
    v_new_advance_paid BIGINT;
    v_amount_fits BOOLEAN;
    v_inventory_available BOOLEAN;
    v_outcome TEXT;            -- confirm_advance | mark_paid | refund_required
    v_hold_days INT;
    v_rows INT;
    v_payment_id UUID;
    v_metadata JSONB;
    v_message TEXT;
BEGIN
    -- 1. Order, then attempt (the caller already holds both locks; re-locking is immediate).
    SELECT * INTO v_order FROM orders WHERE id = p_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND',
                                  'message', 'Associated order not found.');
    END IF;

    SELECT * INTO v_attempt
      FROM payment_attempts
     WHERE id = p_payment_attempt_id AND order_id = v_order.id
     FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
                                  'message', 'Payment attempt does not exist.');
    END IF;

    IF v_attempt.status = 'verified' THEN
        RETURN public.upi_verification_response(v_order.id, v_attempt.id, NULL, true, NULL, NULL,
                                                'Payment attempt has already been verified.');
    END IF;

    v_is_late := (v_attempt.status = 'late_claim_pending_review');
    v_type := v_attempt.payment_type;
    v_amount := v_attempt.expected_amount_paisa;

    -- 2. Lock the order's pieces BEFORE looking at their status (SA-PAY-002).
    PERFORM 1
      FROM products
     WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id)
     ORDER BY id
     FOR UPDATE;

    SELECT count(*)::INT,
           (count(*) FILTER (WHERE p.status = 'reserved' AND p.reserved_by_order_id = v_order.id))::INT,
           (count(*) FILTER (WHERE p.status = 'available'
                                OR (p.status = 'reserved' AND p.reserved_by_order_id = v_order.id)))::INT
      INTO v_items, v_held, v_obtainable
      FROM order_items oi
      JOIN products p ON p.id = oi.product_id
     WHERE oi.order_id = v_order.id;

    -- 3. The ledger must already agree with the order before more money is applied.
    SELECT COALESCE(SUM(amount_paisa), 0) INTO v_ledger_sum
      FROM order_payments
     WHERE order_id = v_order.id AND status = 'verified';

    IF v_ledger_sum <> v_order.total_paid_paisa THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'LEDGER_INCONSISTENT',
            'message', 'The payment records of this order do not add up to its amount paid. Nothing was recorded; contact support before verifying.'
        );
    END IF;

    v_new_total_paid := v_order.total_paid_paisa::BIGINT + v_amount;
    v_new_advance_paid := v_order.advance_paid_paisa::BIGINT + CASE WHEN v_type = 'advance' THEN v_amount ELSE 0 END;
    v_amount_fits := v_new_total_paid <= v_order.total_paisa
                 AND (v_type <> 'advance' OR v_new_advance_paid <= v_order.advance_required_paisa);

    -- 4. Decide the outcome (no writes yet).
    IF NOT v_is_late THEN
        IF v_type = 'advance' AND (v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid') THEN
            RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE',
                'message', 'Order is not in pending unpaid state for advance verification.');
        ELSIF v_type = 'full' AND (v_order.status <> 'pending' OR v_order.payment_status <> 'unpaid') THEN
            RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE',
                'message', 'Full payment requires an order in pending unpaid state.');
        ELSIF v_type = 'balance' AND (v_order.status <> 'confirmed' OR v_order.payment_status <> 'advance_paid') THEN
            RETURN jsonb_build_object('success', false, 'error', 'INVALID_ORDER_STATE',
                'message', 'Balance payment requires an order in confirmed advance_paid state.');
        END IF;

        IF v_held <> v_items THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVENTORY_CONFLICT',
                'message', 'One or more pieces of this order are no longer reserved for it. Nothing was recorded; check the order before verifying.'
            );
        END IF;

        v_inventory_available := true;
        v_outcome := CASE WHEN v_type = 'advance' THEN 'confirm_advance' ELSE 'mark_paid' END;
    ELSE
        IF NOT v_amount_fits THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'PAYMENT_AMOUNT_MISMATCH',
                'message', format('This payment (%s paisa) cannot be applied: the order total is %s paisa and %s paisa is already recorded. Nothing was recorded; reject the claim and refund the buyer if the money arrived.',
                                  v_amount, v_order.total_paisa, v_order.total_paid_paisa)
            );
        END IF;

        v_inventory_available := (v_obtainable = v_items);

        IF v_inventory_available THEN
            v_outcome := CASE WHEN v_type = 'advance' THEN 'confirm_advance' ELSE 'mark_paid' END;
        ELSIF v_order.status IN ('cancelled', 'expired') THEN
            v_outcome := 'refund_required';
        ELSE
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVENTORY_CONFLICT',
                'message', 'One or more pieces of this order are no longer reserved for it. Nothing was recorded; check the order before verifying.'
            );
        END IF;
    END IF;

    IF (v_outcome = 'confirm_advance' AND NOT (
            v_order.confirmation_mode = 'advance'
        AND v_order.total_paid_paisa = 0
        AND v_order.advance_paid_paisa = 0
        AND v_amount = v_order.advance_required_paisa))
       OR (v_outcome = 'mark_paid' AND v_new_total_paid <> v_order.total_paisa) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_AMOUNT_MISMATCH',
            'message', format('This payment (%s paisa) does not match what the order needs (total %s paisa, %s paisa already recorded). Nothing was recorded.',
                              v_amount, v_order.total_paisa, v_order.total_paid_paisa)
        );
    END IF;

    -- 5. Ledger row first: a verified reference exists only once (uq_order_payments_reference_verified).
    v_metadata := jsonb_build_object(
        'payment_attempt_id', v_attempt.id,
        'verified_by', p_actor,
        'verified_at', NOW()
    );
    IF v_is_late THEN
        v_metadata := v_metadata || jsonb_build_object(
            'is_late_claim', true,
            'inventory_reinstated', v_inventory_available
        );
        IF v_outcome = 'refund_required' THEN
            v_metadata := v_metadata || jsonb_build_object('refund_required', true);
        END IF;
    END IF;

    BEGIN
        INSERT INTO order_payments (
            order_id, payment_type, payment_method, verification_method, amount_paisa,
            status, reference_id, verified_at, verified_by, metadata
        ) VALUES (
            v_order.id, v_type, 'upi', 'seller_manual', v_amount,
            'verified', p_verified_ref, NOW(), p_actor, v_metadata
        )
        RETURNING id INTO v_payment_id;
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'REFERENCE_USED_ON_ANOTHER_ORDER',
            'message', 'This payment reference or UTR has already been verified on another order.'
        );
    END;

    -- 6. Pieces. Rows are locked (step 2); the status predicates make every write conditional.
    IF v_outcome = 'confirm_advance' THEN
        UPDATE products
           SET status = 'reserved',
               reserved_by_order_id = v_order.id,
               reserved_at = NOW(),
               version = version + 1,
               updated_at = NOW()
         WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id)
           AND status = 'available';
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows + v_held <> v_items THEN
            RAISE EXCEPTION 'INVENTORY_CONFLICT: order % has % pieces, % re-reserved, % already held', v_order.id, v_items, v_rows, v_held;
        END IF;
    ELSIF v_outcome = 'mark_paid' THEN
        UPDATE products
           SET status = 'sold',
               reserved_at = NULL,
               reserved_by_order_id = NULL,
               version = version + 1,
               updated_at = NOW()
         WHERE id IN (SELECT product_id FROM order_items WHERE order_id = v_order.id)
           AND (status = 'available' OR (status = 'reserved' AND reserved_by_order_id = v_order.id));
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        IF v_rows <> v_items THEN
            RAISE EXCEPTION 'INVENTORY_CONFLICT: order % has % pieces but % could be marked sold', v_order.id, v_items, v_rows;
        END IF;
    END IF;

    -- 7. Order.
    IF v_outcome = 'confirm_advance' THEN
        SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;
        SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;
        v_hold_days := COALESCE(v_drop.hold_duration_days, v_seller.hold_duration_days, 30);
        IF v_hold_days < 1 OR v_hold_days > 30 THEN
            v_hold_days := 30;
        END IF;

        UPDATE orders
           SET status = 'confirmed',
               payment_status = 'advance_paid',
               advance_paid_paisa = v_amount,
               total_paid_paisa = v_amount,
               balance_due_paisa = total_paisa - v_amount,
               fulfilment_status = 'not_ready',
               advance_paid_at = NOW(),
               hold_expires_at = NOW() + (v_hold_days || ' days')::INTERVAL,
               updated_at = NOW()
         WHERE id = v_order.id;

        v_message := CASE WHEN v_is_late
                          THEN 'Late advance payment verified. The pieces are held for this buyer; the balance is still due.'
                          ELSE 'Advance payment verified.' END;
    ELSIF v_outcome = 'mark_paid' THEN
        UPDATE orders
           SET status = 'paid',
               payment_status = 'paid',
               total_paid_paisa = total_paisa,
               balance_due_paisa = 0,
               fulfilment_status = 'not_ready',
               paid_at = NOW(),
               updated_at = NOW()
         WHERE id = v_order.id;

        v_message := CASE WHEN v_is_late
                          THEN 'Late payment verified and inventory successfully secured for order.'
                          ELSE 'Payment verified.' END;
    ELSE
        -- refund_required: the money was received but the pieces belong to someone else now.
        -- Order status stays cancelled/expired; amounts stay consistent with the ledger (SA-PAY-006).
        UPDATE orders
           SET total_paid_paisa = v_new_total_paid,
               balance_due_paisa = total_paisa - v_new_total_paid,
               payment_status = CASE
                                    WHEN v_new_total_paid >= total_paisa THEN 'paid'
                                    WHEN v_new_total_paid > 0 THEN 'advance_paid'
                                    ELSE payment_status
                                END,
               advance_paid_paisa = v_new_advance_paid,
               advance_paid_at = CASE WHEN v_type = 'advance' THEN COALESCE(advance_paid_at, NOW()) ELSE advance_paid_at END,
               refund_status = 'required',
               refund_amount_paisa = refund_amount_paisa + v_amount,
               refund_reason = 'LATE_PAYMENT_INVENTORY_UNAVAILABLE',
               refund_required_at = NOW(),
               notes = COALESCE(notes || E'\n', '')
                       || 'LATE_CLAIM_PAYMENT_VERIFIED: Inventory was already reallocated. Refund or boutique resolution required.',
               updated_at = NOW()
         WHERE id = v_order.id;

        v_message := 'Late payment verified, but items are no longer available. Seller refund or resolution required.';
    END IF;

    -- 8. Attempt.
    UPDATE payment_attempts
       SET status = 'verified',
           seller_verified_at = NOW(),
           verified_by = p_actor,
           buyer_submitted_utr = COALESCE(NULLIF(p_clean_utr, ''), buyer_submitted_utr),
           updated_at = NOW()
     WHERE id = v_attempt.id;

    -- 9. Ledger invariant (rolls the whole verification back if it ever breaks).
    SELECT COALESCE(SUM(amount_paisa), 0) INTO v_ledger_sum
      FROM order_payments
     WHERE order_id = v_order.id AND status = 'verified';
    SELECT * INTO v_order FROM orders WHERE id = v_order.id;
    IF v_ledger_sum <> v_order.total_paid_paisa THEN
        RAISE EXCEPTION 'LEDGER_INVARIANT_VIOLATION: order % total_paid_paisa=% but verified ledger sum=%',
            v_order.id, v_order.total_paid_paisa, v_ledger_sum;
    END IF;

    RETURN public.upi_verification_response(v_order.id, v_attempt.id, v_payment_id, false, v_is_late,
                                            v_inventory_available, v_message);
END;
$$;

-- ============================================================================
-- 6. RPC: verify_manual_upi_payment (signature unchanged)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.verify_manual_upi_payment(
    p_payment_attempt_id UUID,
    p_utr TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id UUID;
    v_order orders%ROWTYPE;
    v_attempt payment_attempts%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_is_service BOOLEAN;
    v_clean_utr TEXT;
    v_verified_ref TEXT;
    v_existing_order_id UUID;
BEGIN
    -- 1. Find the attempt's order WITHOUT locking the attempt (lock order: orders -> attempts -> products).
    SELECT order_id INTO v_order_id FROM payment_attempts WHERE id = p_payment_attempt_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt does not exist.'
        );
    END IF;

    -- 2. Lock the order, then lock and re-read the attempt.
    SELECT * INTO v_order FROM orders WHERE id = v_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND',
            'message', 'Associated order not found.'
        );
    END IF;

    SELECT * INTO v_attempt
      FROM payment_attempts
     WHERE id = p_payment_attempt_id AND order_id = v_order.id
     FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt does not exist.'
        );
    END IF;

    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;

    -- 3. Authorization: drop-owning seller or trusted backend (service_role request).
    v_is_service := COALESCE(current_setting('role', true), '') = 'service_role'
                 OR COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                             NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                             '') = 'service_role';
    IF NOT v_is_service AND (auth.uid() IS NULL OR auth.uid() <> v_drop.seller_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Only the drop-owning seller or trusted backend service can verify this payment.'
        );
    END IF;

    -- 4. Idempotency on the attempt.
    IF v_attempt.status = 'verified' THEN
        RETURN public.upi_verification_response(v_order.id, v_attempt.id, NULL, true, NULL, NULL,
                                                'Payment attempt has already been verified.');
    END IF;

    -- 5. On-time attempts: terminal orders cannot be verified; UNCLAIMED attempts past their window
    --    expire. A CLAIMED attempt (buyer_claimed / awaiting_seller_verification) stays verifiable
    --    after its window: money in flight never auto-expires (SA-PAY-003).
    IF v_attempt.status <> 'late_claim_pending_review' THEN
        IF v_order.status IN ('cancelled', 'expired') THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'INVALID_ORDER_STATE',
                'message', format('Order is in terminal state "%s" and cannot be verified.', v_order.status)
            );
        END IF;

        IF v_attempt.status NOT IN ('buyer_claimed', 'awaiting_seller_verification')
           AND (v_attempt.status = 'expired'
                OR (v_attempt.verification_expires_at IS NOT NULL AND v_attempt.verification_expires_at <= NOW())
                OR (v_attempt.expires_at <= NOW())) THEN
            UPDATE payment_attempts SET status = 'expired', updated_at = NOW() WHERE id = v_attempt.id;
            RETURN jsonb_build_object(
                'success', false,
                'error', 'PAYMENT_ATTEMPT_EXPIRED',
                'message', 'Payment verification window has expired.'
            );
        END IF;
    END IF;

    -- 6. Authoritative reference / UTR.
    v_clean_utr := trim(COALESCE(p_utr, v_attempt.buyer_submitted_utr, ''));
    v_verified_ref := COALESCE(NULLIF(v_clean_utr, ''), v_attempt.transaction_reference);

    -- 7. Cross-order reference reuse protection.
    IF v_verified_ref IS NOT NULL THEN
        SELECT order_id INTO v_existing_order_id
          FROM order_payments
         WHERE reference_id = v_verified_ref AND status = 'verified'
         LIMIT 1;

        IF FOUND THEN
            IF v_existing_order_id = v_order.id THEN
                RETURN public.upi_verification_response(v_order.id, v_attempt.id, NULL, true, NULL, NULL,
                                                        'Payment reference already verified for this order.');
            ELSE
                RETURN jsonb_build_object(
                    'success', false,
                    'error', 'REFERENCE_USED_ON_ANOTHER_ORDER',
                    'message', 'This payment reference or UTR has already been verified on another order.'
                );
            END IF;
        END IF;
    END IF;

    -- 8. Per-type transition (shared by on-time and late claims).
    RETURN public.apply_upi_payment_transition(v_order.id, v_attempt.id, v_verified_ref, v_clean_utr, auth.uid());
END;
$$;

-- ============================================================================
-- 7. RPC: reject_manual_upi_payment (signature unchanged; lock order fixed)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.reject_manual_upi_payment(
    p_payment_attempt_id UUID,
    p_rejection_reason TEXT DEFAULT 'payment_not_found',
    p_release_hold BOOLEAN DEFAULT true
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order_id UUID;
    v_attempt payment_attempts%ROWTYPE;
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_reason TEXT;
    v_is_service BOOLEAN;
    v_release BOOLEAN;
BEGIN
    -- 1. Find the attempt's order without a lock; lock order, then attempt.
    SELECT order_id INTO v_order_id FROM payment_attempts WHERE id = p_payment_attempt_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt does not exist.'
        );
    END IF;

    SELECT * INTO v_order FROM orders WHERE id = v_order_id FOR UPDATE;
    SELECT * INTO v_attempt
      FROM payment_attempts
     WHERE id = p_payment_attempt_id AND order_id = v_order_id
     FOR UPDATE;
    IF v_order.id IS NULL OR v_attempt.id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_ATTEMPT_NOT_FOUND',
            'message', 'Payment attempt does not exist.'
        );
    END IF;

    -- 2. Ownership.
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id;
    v_is_service := COALESCE(current_setting('role', true), '') = 'service_role'
                 OR COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                             NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                             '') = 'service_role';
    IF NOT v_is_service AND (auth.uid() IS NULL OR auth.uid() <> v_drop.seller_id) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Only the drop-owning seller can reject this payment claim.'
        );
    END IF;

    IF v_attempt.status = 'verified' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'CANNOT_REJECT_VERIFIED',
            'message', 'A verified payment attempt cannot be rejected.'
        );
    END IF;

    v_reason := trim(COALESCE(p_rejection_reason, 'payment_not_found'));

    -- 3. Mark attempt as rejected.
    UPDATE payment_attempts
       SET status = 'rejected',
           rejection_reason = v_reason,
           updated_at = NOW()
     WHERE id = v_attempt.id;

    -- 4. Immediate inventory release, unless another payment claim on this order is still in flight.
    v_release := COALESCE(p_release_hold, false) AND v_order.status = 'pending' AND v_order.payment_status = 'unpaid';
    IF v_release THEN
        PERFORM 1 FROM payment_attempts WHERE order_id = v_order.id ORDER BY id FOR UPDATE;
        IF EXISTS (
            SELECT 1 FROM payment_attempts
             WHERE order_id = v_order.id
               AND id <> v_attempt.id
               AND status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
        ) THEN
            v_release := false;
        END IF;
    END IF;

    IF v_release THEN
        PERFORM 1 FROM products
         WHERE reserved_by_order_id = v_order.id AND status = 'reserved'
         ORDER BY id
         FOR UPDATE;

        UPDATE products
           SET status = 'available',
               reserved_at = NULL,
               reserved_by_order_id = NULL,
               version = version + 1,
               updated_at = NOW()
         WHERE reserved_by_order_id = v_order.id AND status = 'reserved';

        UPDATE orders
           SET status = 'cancelled',
               hold_expires_at = NOW(),
               updated_at = NOW()
         WHERE id = v_order.id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'payment_attempt_id', v_attempt.id,
        'status', 'rejected',
        'rejection_reason', v_reason,
        'hold_released', v_release
    );
END;
$$;

-- ============================================================================
-- 8. Internal: release one stale, unclaimed hold without ever waiting for a lock (SA-OPS-001)
-- ============================================================================
-- Returns true when the order was cancelled and its pieces returned to sale; false (and changes
-- nothing) when the order is not a pending unpaid hold past hold_expires_at, has a claimed payment
-- attempt, or any of its rows is locked by another transaction.
CREATE OR REPLACE FUNCTION public.release_stale_hold(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_locked INT;
    v_total INT;
BEGIN
    SELECT * INTO v_order
      FROM orders
     WHERE id = p_order_id
       AND status = 'pending'
       AND payment_status = 'unpaid'
       AND hold_expires_at < clock_timestamp()
     FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Payment attempts: never wait; any claim keeps the hold.
    SELECT count(*) INTO v_locked
      FROM (SELECT 1 FROM payment_attempts WHERE order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
    SELECT count(*) INTO v_total FROM payment_attempts WHERE order_id = v_order.id;
    IF v_locked < v_total THEN
        RETURN false;
    END IF;

    IF EXISTS (
        SELECT 1 FROM payment_attempts
         WHERE order_id = v_order.id
           AND status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
    ) THEN
        RETURN false;
    END IF;

    -- Pieces: never wait (the caller may already hold some of them; own locks are re-acquired).
    SELECT count(*) INTO v_locked
      FROM (SELECT 1 FROM products WHERE reserved_by_order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
    SELECT count(*) INTO v_total FROM products WHERE reserved_by_order_id = v_order.id;
    IF v_locked < v_total THEN
        RETURN false;
    END IF;

    UPDATE products
       SET status = 'available',
           reserved_at = NULL,
           reserved_by_order_id = NULL,
           version = version + 1,
           updated_at = NOW()
     WHERE reserved_by_order_id = v_order.id
       AND status = 'reserved';

    UPDATE payment_attempts
       SET status = 'expired',
           updated_at = NOW()
     WHERE order_id = v_order.id
       AND status IN ('created', 'awaiting_payment');

    UPDATE orders
       SET status = 'cancelled',
           fulfilment_status = 'not_ready',
           updated_at = NOW()
     WHERE id = v_order.id;

    RETURN true;
END;
$$;

-- ============================================================================
-- 9. Reaper: release_expired_holds() (signature unchanged; scripts/run-reaper.mjs and pg_cron)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.release_expired_holds()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_candidate RECORD;
    v_order orders%ROWTYPE;
    v_locked INT;
    v_total INT;
BEGIN
    FOR v_candidate IN
        SELECT o.id, o.status
          FROM orders o
         WHERE o.status IN ('pending', 'confirmed')
           AND o.hold_expires_at < clock_timestamp()
           AND NOT EXISTS (
               SELECT 1 FROM payment_attempts pa
                WHERE pa.order_id = o.id
                  AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
           )
         ORDER BY o.id
         FOR UPDATE OF o SKIP LOCKED
    LOOP
        IF v_candidate.status = 'pending' THEN
            -- Unpaid hold: cancel, release pieces, expire unclaimed attempts (shared with lazy expiry).
            PERFORM public.release_stale_hold(v_candidate.id);
            CONTINUE;
        END IF;

        -- Advance-paid hold that lapsed: order expires, the advance is retained (existing rule).
        SELECT * INTO v_order FROM orders WHERE id = v_candidate.id;
        IF v_order.status <> 'confirmed' OR v_order.hold_expires_at >= clock_timestamp() THEN
            CONTINUE;
        END IF;

        SELECT count(*) INTO v_locked
          FROM (SELECT 1 FROM payment_attempts WHERE order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
        SELECT count(*) INTO v_total FROM payment_attempts WHERE order_id = v_order.id;
        IF v_locked < v_total THEN
            CONTINUE;
        END IF;

        IF EXISTS (
            SELECT 1 FROM payment_attempts
             WHERE order_id = v_order.id
               AND status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
        ) THEN
            CONTINUE;
        END IF;

        SELECT count(*) INTO v_locked
          FROM (SELECT 1 FROM products WHERE reserved_by_order_id = v_order.id ORDER BY id FOR UPDATE SKIP LOCKED) s;
        SELECT count(*) INTO v_total FROM products WHERE reserved_by_order_id = v_order.id;
        IF v_locked < v_total THEN
            CONTINUE;
        END IF;

        UPDATE products
           SET status = 'available',
               reserved_at = NULL,
               reserved_by_order_id = NULL,
               version = version + 1,
               updated_at = NOW()
         WHERE reserved_by_order_id = v_order.id
           AND status = 'reserved';

        UPDATE payment_attempts
           SET status = 'expired',
               updated_at = NOW()
         WHERE order_id = v_order.id
           AND status IN ('created', 'awaiting_payment');

        UPDATE orders
           SET status = 'expired',
               fulfilment_status = 'not_ready',
               updated_at = NOW()
         WHERE id = v_order.id;
    END LOOP;
END;
$$;

-- ============================================================================
-- 10. RPC: force_release_hold (SA-PAY-005)
-- ============================================================================
-- Authenticated seller override to cancel a pending order and return its pieces to sale.
-- Refused while the buyer has a payment claim in flight; confirmed (advance-paid) orders remain
-- excluded (F-02 audit note in migration 009).
CREATE OR REPLACE FUNCTION public.force_release_hold(
    p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_claim payment_attempts%ROWTYPE;
    v_released INT := 0;
    v_expired INT := 0;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    SELECT o.* INTO v_order
      FROM orders o
      JOIN drops d ON d.id = o.drop_id
     WHERE o.id = p_order_id AND d.seller_id = auth.uid()
     FOR UPDATE OF o;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    IF v_order.status <> 'pending' THEN
        RETURN jsonb_build_object('success', false, 'error', 'ONLY_PENDING_CAN_BE_RELEASED');
    END IF;

    -- Lock order: orders -> payment_attempts -> products.
    PERFORM 1 FROM payment_attempts WHERE order_id = p_order_id ORDER BY id FOR UPDATE;

    SELECT * INTO v_claim
      FROM payment_attempts
     WHERE order_id = p_order_id
       AND status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
     ORDER BY buyer_claimed_at DESC NULLS LAST, updated_at DESC
     LIMIT 1;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'PAYMENT_CLAIM_PENDING',
            'message', 'The buyer has already submitted a payment for this order. Verify or reject it in Payments before releasing the piece.',
            'payment_attempt_id', v_claim.id,
            'buyer_submitted_utr', v_claim.buyer_submitted_utr
        );
    END IF;

    PERFORM 1 FROM products
     WHERE reserved_by_order_id = p_order_id AND status = 'reserved'
     ORDER BY id
     FOR UPDATE;

    UPDATE products
       SET status = 'available',
           reserved_at = NULL,
           reserved_by_order_id = NULL,
           version = version + 1,
           updated_at = NOW()
     WHERE reserved_by_order_id = p_order_id AND status = 'reserved';
    GET DIAGNOSTICS v_released = ROW_COUNT;

    UPDATE payment_attempts
       SET status = 'expired',
           updated_at = NOW()
     WHERE order_id = p_order_id
       AND status IN ('created', 'awaiting_payment');
    GET DIAGNOSTICS v_expired = ROW_COUNT;

    UPDATE orders
       SET status = 'cancelled',
           updated_at = NOW()
     WHERE id = p_order_id;

    RETURN jsonb_build_object(
        'success', true,
        'order_id', p_order_id,
        'status', 'cancelled',
        'released_products_count', v_released,
        'expired_attempts_count', v_expired
    );
END;
$$;

-- ============================================================================
-- 11. RPC: create_order_with_reservation with lazy expiry (SA-OPS-001)
-- ============================================================================
-- Identical to migration 022 except step 9.1: after the cart's pieces are locked, a piece held by
-- a pending order whose hold has expired and that has no payment claim is released (through
-- release_stale_hold, which never waits) before availability is asserted.
CREATE OR REPLACE FUNCTION public.create_order_with_reservation(
    p_drop_id UUID,
    p_product_ids UUID[],
    p_buyer_name TEXT,
    p_buyer_phone TEXT,
    p_shipping_address TEXT,
    p_pincode TEXT,
    p_confirmation_mode TEXT DEFAULT 'advance',
    p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
    v_clean_name TEXT;
    v_clean_phone TEXT;
    v_clean_address TEXT;
    v_clean_pincode TEXT;
    v_clean_idempotency TEXT;
    v_confirmation_mode TEXT;
    v_clean_product_ids UUID[];
    v_existing_product_ids UUID[];
    v_sorted_clean_pids UUID[];
    v_drop drops%ROWTYPE;
    v_seller profiles%ROWTYPE;
    v_subtotal_paisa INT := 0;
    v_shipping_paisa INT := 0;
    v_total_paisa INT := 0;
    v_advance_required_paisa INT := 0;
    v_advance_enabled BOOLEAN;
    v_hold_expires_at TIMESTAMPTZ;
    v_order_code TEXT;
    v_order_token UUID := gen_random_uuid();
    v_order orders%ROWTYPE;
    v_existing_order orders%ROWTYPE;
    v_random_suffix TEXT;
    v_stale_order_id UUID;
BEGIN
    -- 0. Clean and Deduplicate Product IDs Array early
    SELECT coalesce(array_agg(DISTINCT pid), '{}') INTO v_clean_product_ids
    FROM unnest(p_product_ids) AS pid
    WHERE pid IS NOT NULL;

    -- 0.1 Check Idempotency Token & Conflict Detection
    v_clean_idempotency := trim(COALESCE(p_idempotency_key, ''));
    IF v_clean_idempotency <> '' THEN
        SELECT * INTO v_existing_order
        FROM orders
        WHERE drop_id = p_drop_id AND idempotency_key = v_clean_idempotency;

        IF FOUND THEN
            -- Check if requested product items match existing order items
            SELECT coalesce(array_agg(product_id ORDER BY product_id ASC), '{}') INTO v_existing_product_ids
            FROM order_items
            WHERE order_id = v_existing_order.id;

            SELECT coalesce(array_agg(pid ORDER BY pid ASC), '{}') INTO v_sorted_clean_pids
            FROM unnest(v_clean_product_ids) AS pid;

            IF v_existing_product_ids IS DISTINCT FROM v_sorted_clean_pids THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'error', 'CHECKOUT_IDEMPOTENCY_CONFLICT',
                    'message', 'The provided idempotency key has already been used for an order with different cart items.'
                );
            END IF;

            -- Return existing committed order receipt idempotently
            RETURN jsonb_build_object(
                'success', true,
                'order_id', v_existing_order.id,
                'order_code', v_existing_order.order_code,
                'order_token', v_existing_order.order_token,
                'subtotal_paisa', v_existing_order.subtotal_paisa,
                'shipping_paisa', v_existing_order.shipping_paisa,
                'total_paisa', v_existing_order.total_paisa,
                'confirmation_mode', v_existing_order.confirmation_mode,
                'advance_required_paisa', v_existing_order.advance_required_paisa,
                'advance_paid_paisa', v_existing_order.advance_paid_paisa,
                'balance_due_paisa', v_existing_order.balance_due_paisa,
                'total_paid_paisa', v_existing_order.total_paid_paisa,
                'payment_status', v_existing_order.payment_status,
                'fulfilment_status', v_existing_order.fulfilment_status,
                'hold_expires_at', v_existing_order.hold_expires_at,
                'idempotent_replay', true
            );
        END IF;
    END IF;

    -- 1. Validate Drop Existence & Status
    SELECT * INTO v_drop FROM drops WHERE id = p_drop_id FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'DROP_NOT_FOUND',
            'message', 'The specified drop does not exist.'
        );
    END IF;

    IF v_drop.status != 'live' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'DROP_NOT_LIVE',
            'message', 'Orders can only be placed on drops that are currently live.'
        );
    END IF;

    -- 2. Fetch Seller Profile
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'SELLER_NOT_FOUND',
            'message', 'The seller for this drop could not be found.'
        );
    END IF;

    -- 3. Sanitize and Validate Buyer Name
    v_clean_name := trim(p_buyer_name);
    IF char_length(v_clean_name) < 3 OR char_length(v_clean_name) > 100 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_BUYER_NAME',
            'message', 'Buyer name must be between 3 and 100 characters.'
        );
    END IF;

    -- 4. Sanitize and Validate Indian Phone Number
    v_clean_phone := trim(p_buyer_phone);
    IF v_clean_phone ~ '^91[6-9][0-9]{9}$' THEN
        v_clean_phone := substr(v_clean_phone, 3);
    END IF;
    IF v_clean_phone !~ '^[6-9][0-9]{9}$' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_BUYER_PHONE',
            'message', 'Buyer phone must be a valid 10-digit Indian mobile number starting with 6-9.'
        );
    END IF;

    -- 5. Sanitize and Validate Shipping Address
    v_clean_address := trim(p_shipping_address);
    IF char_length(v_clean_address) < 10 OR char_length(v_clean_address) > 500 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_SHIPPING_ADDRESS',
            'message', 'Shipping address must be between 10 and 500 characters.'
        );
    END IF;

    -- 6. Sanitize and Validate Indian Pincode
    v_clean_pincode := trim(p_pincode);
    IF v_clean_pincode !~ '^[1-9][0-9]{5}$' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_PINCODE',
            'message', 'Pincode must be a valid 6-digit Indian postal code not starting with 0.'
        );
    END IF;

    -- 7. Validate Confirmation Mode
    v_confirmation_mode := lower(trim(coalesce(p_confirmation_mode, 'advance')));
    IF v_confirmation_mode NOT IN ('advance', 'full_payment') THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_CONFIRMATION_MODE',
            'message', 'Confirmation mode must be either "advance" or "full_payment".'
        );
    END IF;

    -- 8. Deduplicate and Validate Product IDs Array
    IF array_length(v_clean_product_ids, 1) IS NULL OR array_length(v_clean_product_ids, 1) = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'EMPTY_CART',
            'message', 'At least one product must be selected to checkout.'
        );
    END IF;

    IF array_length(v_clean_product_ids, 1) > 10 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'EXCEEDS_CART_LIMIT',
            'message', 'Cart cannot exceed 10 items.'
        );
    END IF;

    -- 9. Deterministic Product Locking & Availability Assertion
    PERFORM id FROM products
    WHERE id = ANY(v_clean_product_ids)
    ORDER BY id ASC
    FOR UPDATE;

    -- 9.1 Lazy expiry (SA-OPS-001): a requested piece held by a pending order whose hold has
    --     expired and that has no payment claim is released now instead of waiting for the reaper.
    --     release_stale_hold never waits for a lock; if it cannot lock everything it changes nothing
    --     and the piece simply counts as unavailable below.
    FOR v_stale_order_id IN
        SELECT DISTINCT p.reserved_by_order_id
          FROM products p
          JOIN orders o ON o.id = p.reserved_by_order_id
         WHERE p.id = ANY(v_clean_product_ids)
           AND p.drop_id = p_drop_id
           AND p.status = 'reserved'
           AND o.status = 'pending'
           AND o.hold_expires_at < clock_timestamp()
           AND NOT EXISTS (
               SELECT 1 FROM payment_attempts pa
                WHERE pa.order_id = o.id
                  AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
           )
    LOOP
        PERFORM public.release_stale_hold(v_stale_order_id);
    END LOOP;

    IF (
        SELECT COUNT(*) FROM products
        WHERE id = ANY(v_clean_product_ids)
          AND drop_id = p_drop_id
          AND status = 'available'
    ) != array_length(v_clean_product_ids, 1) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'STOCK_UNAVAILABLE',
            'message', 'One or more items in your cart are no longer available.'
        );
    END IF;

    -- 10. Compute Subtotal and Authoritative Shipping Fee
    SELECT SUM(price_paisa) INTO v_subtotal_paisa
    FROM products
    WHERE id = ANY(v_clean_product_ids);

    IF v_seller.free_shipping_threshold_paisa IS NOT NULL
       AND v_subtotal_paisa >= v_seller.free_shipping_threshold_paisa THEN
        v_shipping_paisa := 0;
    ELSE
        v_shipping_paisa := COALESCE(v_drop.shipping_fee_paisa, v_seller.default_shipping_fee_paisa, 8000);
    END IF;

    v_total_paisa := v_subtotal_paisa + v_shipping_paisa;

    -- 11. Resolve Seller Advance & Hold Policy
    IF v_confirmation_mode = 'advance' THEN
        v_advance_enabled := COALESCE(v_drop.advance_confirmation_enabled, v_seller.advance_confirmation_enabled, false);
        IF NOT v_advance_enabled THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'ADVANCE_CONFIRMATION_DISABLED',
                'message', 'This seller does not offer advance confirmation. Please choose Pay in Full.'
            );
        END IF;

        v_advance_required_paisa := COALESCE(v_drop.advance_amount_paisa, v_seller.advance_amount_paisa, 25000);
        IF v_advance_required_paisa > v_total_paisa THEN
            RETURN jsonb_build_object(
                'success', false,
                'error', 'ADVANCE_EXCEEDS_TOTAL',
                'message', 'Configured advance amount exceeds total order amount.'
            );
        END IF;

        v_hold_expires_at := NOW() + INTERVAL '15 minutes';
    ELSE
        v_advance_required_paisa := 0;
        v_hold_expires_at := NOW() + INTERVAL '15 minutes';
    END IF;

    -- 12. Generate Collision-Resistant 6-Char Order Code
    <<code_gen>>
    FOR _attempt IN 1..100 LOOP
        v_random_suffix := '';
        FOR _i IN 1..6 LOOP
            v_random_suffix := v_random_suffix ||
                substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ',
                       floor(random() * 36 + 1)::int, 1);
        END LOOP;
        v_order_code := 'LD-' || v_random_suffix;
        EXIT code_gen WHEN NOT EXISTS (SELECT 1 FROM orders WHERE order_code = v_order_code);
    END LOOP code_gen;

    IF EXISTS (SELECT 1 FROM orders WHERE order_code = v_order_code) THEN
        RAISE EXCEPTION 'Failed to generate unique order code after 100 attempts';
    END IF;

    -- 13. Insert Order Record with Snapshotted Financial Model & Idempotency Key
    INSERT INTO orders (
        drop_id, order_code, order_token, buyer_name, buyer_phone,
        shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa,
        confirmation_mode, advance_required_paisa, advance_paid_paisa,
        total_paid_paisa, balance_due_paisa, payment_status, fulfilment_status,
        status, hold_expires_at, idempotency_key
    ) VALUES (
        p_drop_id, v_order_code, v_order_token, v_clean_name, v_clean_phone,
        v_clean_address, v_clean_pincode, v_subtotal_paisa, v_shipping_paisa, v_total_paisa,
        v_confirmation_mode, v_advance_required_paisa, 0,
        0, v_total_paisa, 'unpaid', 'not_ready',
        'pending', v_hold_expires_at, NULLIF(v_clean_idempotency, '')
    ) RETURNING * INTO v_order;

    -- 14. Insert Order Line Items & Update Products to Reserved State
    INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
    SELECT v_order.id, p.id, p.price_paisa
    FROM products p
    WHERE p.id = ANY(v_clean_product_ids)
    ORDER BY p.id ASC;

    UPDATE products
    SET status = 'reserved',
        reserved_at = NOW(),
        reserved_by_order_id = v_order.id,
        version = version + 1,
        updated_at = NOW()
    WHERE id = ANY(v_clean_product_ids);

    -- 15. Return Authoritative Order Receipt
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'order_token', v_order.order_token,
        'subtotal_paisa', v_order.subtotal_paisa,
        'shipping_paisa', v_order.shipping_paisa,
        'total_paisa', v_order.total_paisa,
        'confirmation_mode', v_order.confirmation_mode,
        'advance_required_paisa', v_order.advance_required_paisa,
        'advance_paid_paisa', v_order.advance_paid_paisa,
        'balance_due_paisa', v_order.balance_due_paisa,
        'total_paid_paisa', v_order.total_paid_paisa,
        'payment_status', v_order.payment_status,
        'fulfilment_status', v_order.fulfilment_status,
        'hold_expires_at', v_order.hold_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- ============================================================================
-- 12. RPC: close_drop (lock order aligned; claims re-checked under the order lock)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.close_drop(
    p_drop_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_drop drops%ROWTYPE;
    v_order RECORD;
    v_released_orders_count INT := 0;
    v_is_service BOOLEAN;
BEGIN
    v_is_service := COALESCE(current_setting('role', true), '') = 'service_role'
                 OR COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                             NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                             '') = 'service_role';

    -- 1. Authentication Check
    IF NOT v_is_service AND auth.uid() IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to close a drop.'
        );
    END IF;

    -- 2. Fetch and Lock Drop
    SELECT * INTO v_drop
    FROM drops
    WHERE id = p_drop_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'DROP_NOT_FOUND',
            'message', 'The specified drop does not exist.'
        );
    END IF;

    -- 3. Verify Seller Ownership
    IF NOT v_is_service AND v_drop.seller_id IS DISTINCT FROM auth.uid() THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'FORBIDDEN',
            'message', 'You are not authorized to close drops for this boutique.'
        );
    END IF;

    -- 4. Idempotency Check
    IF v_drop.status = 'closed' THEN
        RETURN jsonb_build_object(
            'success', true,
            'drop_id', v_drop.id,
            'status', 'closed',
            'closed_at', v_drop.closed_at,
            'idempotent', true,
            'message', 'Drop is already closed.'
        );
    END IF;

    -- 5. Safe Closure Protocol (if drop is live):
    -- - Unpaid unclaimed reservations: released back to available & cancelled
    -- - Claims awaiting verification: preserved intact (buyer money in flight)
    -- - Advance-paid holds, fully paid and shipped orders: untouched
    IF v_drop.status = 'live' THEN
        FOR v_order IN
            SELECT o.id FROM orders o
            WHERE o.drop_id = p_drop_id
              AND o.status = 'pending'
              AND o.payment_status = 'unpaid'
              AND NOT EXISTS (
                  SELECT 1 FROM payment_attempts pa
                  WHERE pa.order_id = o.id
                    AND pa.status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
              )
            ORDER BY o.id ASC
            FOR UPDATE OF o
        LOOP
            -- Lock order: orders -> payment_attempts -> products. Re-check with a fresh snapshot
            -- now that the order is locked: a claim committed while we waited keeps the hold.
            PERFORM 1 FROM payment_attempts WHERE order_id = v_order.id ORDER BY id FOR UPDATE;

            IF EXISTS (
                SELECT 1 FROM payment_attempts
                 WHERE order_id = v_order.id
                   AND status IN ('buyer_claimed', 'awaiting_seller_verification', 'late_claim_pending_review')
            ) OR NOT EXISTS (
                SELECT 1 FROM orders
                 WHERE id = v_order.id AND status = 'pending' AND payment_status = 'unpaid'
            ) THEN
                CONTINUE;
            END IF;

            PERFORM id FROM products
            WHERE reserved_by_order_id = v_order.id
            ORDER BY id ASC
            FOR UPDATE;

            UPDATE products
            SET status = 'available',
                reserved_at = NULL,
                reserved_by_order_id = NULL,
                version = version + 1,
                updated_at = NOW()
            WHERE reserved_by_order_id = v_order.id
              AND status = 'reserved';

            -- Cancel the unpaid unclaimed order
            UPDATE orders
            SET status = 'cancelled',
                hold_expires_at = NOW(),
                updated_at = NOW()
            WHERE id = v_order.id;

            -- Expire associated open payment attempts
            UPDATE payment_attempts
            SET status = 'expired',
                updated_at = NOW()
            WHERE order_id = v_order.id
              AND status IN ('created', 'awaiting_payment');

            v_released_orders_count := v_released_orders_count + 1;
        END LOOP;
    END IF;

    -- 6. Transition Drop to Closed with Transaction-Local Exemption
    PERFORM set_config('livedrop.closing_drop', 'true', true);

    UPDATE drops
    SET status = 'closed',
        closed_at = NOW(),
        updated_at = NOW()
    WHERE id = p_drop_id;

    RETURN jsonb_build_object(
        'success', true,
        'drop_id', p_drop_id,
        'status', 'closed',
        'closed_at', NOW(),
        'released_orders_count', v_released_orders_count,
        'message', 'Drop successfully closed. Unclaimed reservations released.'
    );
END;
$$;

-- ============================================================================
-- 13. RPC: record_refund (SA-PAY-004)
-- ============================================================================
-- The owning seller (or the trusted backend) records that a refund owed to the buyer was paid.
CREATE OR REPLACE FUNCTION public.record_refund(
    p_order_id UUID,
    p_refund_reference TEXT,
    p_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_is_service BOOLEAN;
    v_order orders%ROWTYPE;
    v_reference TEXT;
    v_note TEXT;
BEGIN
    v_is_service := COALESCE(current_setting('role', true), '') = 'service_role'
                 OR COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''),
                             NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
                             '') = 'service_role';

    IF NOT v_is_service AND v_uid IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'UNAUTHORIZED',
            'message', 'Authentication required to record a refund.'
        );
    END IF;

    SELECT o.* INTO v_order
      FROM orders o
      JOIN drops d ON d.id = o.drop_id
     WHERE o.id = p_order_id
       AND (v_is_service OR d.seller_id = v_uid)
     FOR UPDATE OF o;

    IF NOT FOUND THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED',
            'message', 'Order not found.'
        );
    END IF;

    v_reference := trim(COALESCE(p_refund_reference, ''));
    IF char_length(v_reference) < 4 OR char_length(v_reference) > 64
       OR v_reference !~ '^[A-Za-z0-9_./ -]+$' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'INVALID_REFUND_REFERENCE',
            'message', 'Enter the refund UTR / reference: 4 to 64 letters, digits, spaces or . _ / -'
        );
    END IF;

    IF v_order.refund_status = 'refunded' THEN
        IF v_order.refund_reference = v_reference THEN
            RETURN jsonb_build_object(
                'success', true,
                'idempotent', true,
                'order_id', v_order.id,
                'order_code', v_order.order_code,
                'refund_status', v_order.refund_status,
                'refund_amount_paisa', v_order.refund_amount_paisa,
                'refund_reference', v_order.refund_reference,
                'refunded_at', v_order.refunded_at,
                'message', 'Refund already recorded with this reference.'
            );
        END IF;

        RETURN jsonb_build_object(
            'success', false,
            'error', 'NO_REFUND_DUE',
            'message', 'A refund for this order was already recorded with a different reference.'
        );
    END IF;

    IF v_order.refund_status <> 'required' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'NO_REFUND_DUE',
            'message', 'No refund is owed on this order.'
        );
    END IF;

    v_note := NULLIF(trim(COALESCE(p_note, '')), '');

    UPDATE orders
       SET refund_status = 'refunded',
           refund_reference = v_reference,
           refunded_at = NOW(),
           refund_recorded_by = v_uid,
           notes = CASE WHEN v_note IS NULL THEN notes ELSE COALESCE(notes || E'\n', '') || v_note END,
           updated_at = NOW()
     WHERE id = v_order.id
    RETURNING * INTO v_order;

    RETURN jsonb_build_object(
        'success', true,
        'idempotent', false,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'refund_status', v_order.refund_status,
        'refund_amount_paisa', v_order.refund_amount_paisa,
        'refund_reference', v_order.refund_reference,
        'refunded_at', v_order.refunded_at,
        'message', 'Refund recorded.'
    );
END;
$$;

-- ============================================================================
-- 14. Privileges
-- ============================================================================
-- Internal helpers: callable only from the SECURITY DEFINER RPCs above (function owner).
REVOKE ALL ON FUNCTION public.upi_verification_response(UUID, UUID, UUID, BOOLEAN, BOOLEAN, BOOLEAN, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.apply_upi_payment_transition(UUID, UUID, TEXT, TEXT, UUID)
    FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.release_stale_hold(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

-- Trigger function: firing does not need EXECUTE; nobody needs to call it directly.
REVOKE ALL ON FUNCTION public.prevent_finalized_order_deletion() FROM PUBLIC, anon, authenticated;

-- Redefined RPCs: same grants as before.
REVOKE ALL ON FUNCTION public.verify_manual_upi_payment(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_manual_upi_payment(UUID, TEXT) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.reject_manual_upi_payment(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reject_manual_upi_payment(UUID, TEXT, BOOLEAN) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.force_release_hold(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.force_release_hold(UUID) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.release_expired_holds() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_expired_holds() TO service_role;

REVOKE ALL ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.close_drop(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_drop(UUID) TO authenticated, service_role;

-- New RPC: sellers (RLS-scoped by ownership inside) and the trusted backend; never anon.
REVOKE ALL ON FUNCTION public.record_refund(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_refund(UUID, TEXT, TEXT) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
