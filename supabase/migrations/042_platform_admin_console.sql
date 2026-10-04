-- LiveDrop Migration: 042_platform_admin_console.sql
-- Description: SA-OPS-002 / SA-ONB-001 — operator console for approving sellers and recording
-- refunds without SQL (ADR-016).
--
--   Before this migration approving a seller (admin_approve_seller) and recording a refund for an
--   order whose seller cannot (record_refund) were possible only from the SQL editor, and the
--   onboarding-fee UTR a seller typed at sign-up was visible only in auth metadata.
--
--     platform_admins      the accounts allowed to use /admin on the website. Rows are added by
--                          the owner in the SQL editor; no client can read or write the table.
--     admin_actions        append-only log of every console action (who, what, when, why).
--     is_platform_admin()  true for the signed-in admin.
--     admin_whoami         lets the console decide what to show (any signed-in user; false
--                          unless admin).
--     admin_list_sellers   sellers with their sign-up details, onboarding-fee UTR and status
--                          (pending / approved / suspended, from the log).
--     admin_set_seller_approval
--                          approve or suspend; suspension needs a reason. Suspension closes the
--                          seller's live drops (trigger from 038).
--     admin_refunds_due / admin_find_order
--                          orders that owe a refund; one order by code. No buyer phone numbers
--                          or addresses.
--     admin_record_refund  records the refund through record_refund (same rules and checks).
--
--   Every write needs a password sign-in in the last 10 minutes (REAUTH_REQUIRED otherwise),
--   like the payee change guard in 039. No service-role key is involved: the console signs in
--   as a normal user with the anon key, and these RPCs decide.
--
-- Rules: SECURITY DEFINER functions pin search_path = public, pg_temp; RLS on every new table;
-- money in integer paisa. Idempotent.
--
-- Regression suite: audit/seller-app/tests/sql/24_admin_console.sql.

-- ============================================================================
-- 1. Tables
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.platform_admins (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    note TEXT,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.platform_admins ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.platform_admins FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS public.admin_actions (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_id UUID NOT NULL,
    action TEXT NOT NULL CHECK (action IN ('approve_seller', 'suspend_seller', 'record_refund')),
    target_id UUID NOT NULL,
    reason TEXT,
    detail JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.admin_actions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.admin_actions FROM PUBLIC, anon, authenticated;
CREATE INDEX IF NOT EXISTS idx_admin_actions_target ON public.admin_actions (target_id, created_at DESC);

-- ============================================================================
-- 2. Helpers
-- ============================================================================
CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT auth.uid() IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.platform_admins WHERE user_id = auth.uid());
$$;

-- Admin + password sign-in within 10 minutes. Returns NULL when allowed, else an error JSON.
CREATE OR REPLACE FUNCTION public.admin_write_denied()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_age BIGINT;
BEGIN
    IF NOT public.is_platform_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED',
                                  'message', 'Only LiveDrop administrators can do this.');
    END IF;
    v_age := public.seconds_since_password_sign_in();
    IF v_age IS NULL OR v_age > 600 THEN
        RETURN jsonb_build_object('success', false, 'error', 'REAUTH_REQUIRED',
                                  'message', 'Sign in again with your password to continue.');
    END IF;
    RETURN NULL;
END;
$$;

-- True only inside admin_record_refund (transaction-local flag set there) for an admin.
CREATE OR REPLACE FUNCTION public.admin_refund_in_progress()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT COALESCE(current_setting('livedrop.admin_refund', true), '') = 'on'
       AND public.is_platform_admin();
$$;

-- Status of a seller for the console: approved, or the latest approve/suspend action decides.
CREATE OR REPLACE FUNCTION public.admin_seller_status(p_seller_id UUID, p_is_approved BOOLEAN)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN p_is_approved THEN 'approved'
        WHEN (SELECT a.action FROM public.admin_actions a
               WHERE a.target_id = p_seller_id AND a.action IN ('approve_seller', 'suspend_seller')
               ORDER BY a.created_at DESC, a.id DESC LIMIT 1) = 'suspend_seller' THEN 'suspended'
        ELSE 'pending'
    END;
$$;

-- ============================================================================
-- 3. Read RPCs
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_whoami()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT jsonb_build_object('success', true, 'is_admin', public.is_platform_admin());
$$;

CREATE OR REPLACE FUNCTION public.admin_list_sellers(p_status TEXT DEFAULT 'pending')
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rows JSONB;
BEGIN
    IF NOT public.is_platform_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED',
                                  'message', 'Only LiveDrop administrators can do this.');
    END IF;
    IF p_status NOT IN ('pending', 'approved', 'suspended', 'all') THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_FILTER',
                                  'message', 'Filter must be pending, approved, suspended or all.');
    END IF;

    SELECT COALESCE(jsonb_agg(s ORDER BY s.created_at DESC), '[]'::jsonb) INTO v_rows
      FROM (
        SELECT p.id, p.store_name, p.store_slug, p.phone_number, p.upi_id, p.created_at,
               p.approved_at, u.email, (u.email_confirmed_at IS NOT NULL) AS email_confirmed,
               NULLIF(trim(u.raw_user_meta_data ->> 'utr_number'), '') AS onboarding_fee_utr,
               public.admin_seller_status(p.id, p.is_approved) AS status,
               (SELECT a.reason FROM public.admin_actions a
                 WHERE a.target_id = p.id AND a.action = 'suspend_seller'
                 ORDER BY a.created_at DESC, a.id DESC LIMIT 1) AS last_suspension_reason
          FROM public.profiles p
          LEFT JOIN auth.users u ON u.id = p.id
         WHERE NOT EXISTS (SELECT 1 FROM public.platform_admins pa WHERE pa.user_id = p.id)
      ) s
     WHERE p_status = 'all' OR s.status = p_status;

    RETURN jsonb_build_object('success', true, 'sellers', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_order_json(p_order public.orders)
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT jsonb_build_object(
        'id', p_order.id,
        'order_code', p_order.order_code,
        'status', p_order.status,
        'total_paisa', p_order.total_paisa,
        'total_paid_paisa', p_order.total_paid_paisa,
        'refund_status', p_order.refund_status,
        'refund_amount_paisa', p_order.refund_amount_paisa,
        'refund_reason', p_order.refund_reason,
        'refund_required_at', p_order.refund_required_at,
        'refund_reference', p_order.refund_reference,
        'refunded_at', p_order.refunded_at,
        'created_at', p_order.created_at,
        'store_name', (SELECT pr.store_name FROM public.drops d JOIN public.profiles pr ON pr.id = d.seller_id
                        WHERE d.id = p_order.drop_id)
    );
$$;

CREATE OR REPLACE FUNCTION public.admin_refunds_due()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_rows JSONB;
BEGIN
    IF NOT public.is_platform_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED',
                                  'message', 'Only LiveDrop administrators can do this.');
    END IF;
    SELECT COALESCE(jsonb_agg(public.admin_order_json(o) ORDER BY o.refund_required_at NULLS LAST, o.created_at),
                    '[]'::jsonb)
      INTO v_rows
      FROM public.orders o
     WHERE o.refund_status = 'required';
    RETURN jsonb_build_object('success', true, 'orders', v_rows);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_find_order(p_order_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_order public.orders%ROWTYPE;
BEGIN
    IF NOT public.is_platform_admin() THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED',
                                  'message', 'Only LiveDrop administrators can do this.');
    END IF;
    SELECT * INTO v_order FROM public.orders WHERE order_code = upper(trim(COALESCE(p_order_code, '')));
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND', 'message', 'No order with that code.');
    END IF;
    RETURN jsonb_build_object('success', true, 'order', public.admin_order_json(v_order));
END;
$$;

-- ============================================================================
-- 4. Write RPCs
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_set_seller_approval(
    p_seller_id UUID,
    p_approved BOOLEAN,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_denied JSONB := public.admin_write_denied();
    v_reason TEXT := NULLIF(trim(COALESCE(p_reason, '')), '');
    v_seller public.profiles%ROWTYPE;
BEGIN
    IF v_denied IS NOT NULL THEN
        RETURN v_denied;
    END IF;
    IF p_approved IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_INPUT', 'message', 'Choose approve or suspend.');
    END IF;
    IF NOT p_approved AND (v_reason IS NULL OR char_length(v_reason) < 3) THEN
        RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED',
                                  'message', 'Give a reason for suspending this seller.');
    END IF;
    IF v_reason IS NOT NULL AND char_length(v_reason) > 500 THEN
        RETURN jsonb_build_object('success', false, 'error', 'REASON_TOO_LONG',
                                  'message', 'Keep the reason under 500 characters.');
    END IF;
    IF EXISTS (SELECT 1 FROM public.platform_admins WHERE user_id = p_seller_id) THEN
        RETURN jsonb_build_object('success', false, 'error', 'SELLER_NOT_FOUND', 'message', 'Seller profile does not exist.');
    END IF;

    SELECT * INTO v_seller FROM public.profiles WHERE id = p_seller_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'SELLER_NOT_FOUND', 'message', 'Seller profile does not exist.');
    END IF;

    UPDATE public.profiles
       SET is_approved = p_approved,
           approved_at = CASE WHEN p_approved THEN COALESCE(v_seller.approved_at, NOW()) ELSE NULL END,
           approved_by = CASE WHEN p_approved THEN COALESCE(v_seller.approved_by, auth.uid()) ELSE NULL END,
           updated_at = NOW()
     WHERE id = p_seller_id;

    INSERT INTO public.admin_actions (admin_id, action, target_id, reason, detail)
    VALUES (auth.uid(), CASE WHEN p_approved THEN 'approve_seller' ELSE 'suspend_seller' END,
            p_seller_id, v_reason,
            jsonb_build_object('was_approved', v_seller.is_approved, 'store_slug', v_seller.store_slug));

    RETURN jsonb_build_object(
        'success', true,
        'seller_id', p_seller_id,
        'status', CASE WHEN p_approved THEN 'approved' ELSE 'suspended' END,
        'message', CASE WHEN p_approved THEN 'Seller approved.' ELSE 'Seller suspended. Their live drops were closed.' END
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_record_refund(
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
    v_denied JSONB := public.admin_write_denied();
    v_result JSONB;
BEGIN
    IF v_denied IS NOT NULL THEN
        RETURN v_denied;
    END IF;

    PERFORM set_config('livedrop.admin_refund', 'on', true);
    v_result := public.record_refund(p_order_id, p_refund_reference, p_note);
    PERFORM set_config('livedrop.admin_refund', '', true);

    IF (v_result ->> 'success')::boolean AND NOT COALESCE((v_result ->> 'idempotent')::boolean, false) THEN
        INSERT INTO public.admin_actions (admin_id, action, target_id, reason, detail)
        VALUES (auth.uid(), 'record_refund', p_order_id, NULLIF(trim(COALESCE(p_note, '')), ''),
                jsonb_build_object('order_code', v_result ->> 'order_code',
                                   'refund_reference', v_result ->> 'refund_reference',
                                   'refund_amount_paisa', (v_result ->> 'refund_amount_paisa')::int));
    END IF;
    RETURN v_result;
END;
$$;

-- ============================================================================
-- 5. record_refund: also accepts an admin acting through admin_record_refund
-- ============================================================================
-- Identical to 035 except that the privileged branch includes admin_refund_in_progress().
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
                             '') = 'service_role'
                 OR public.admin_refund_in_progress();

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
-- 6. Privileges
-- ============================================================================
-- Internal helpers: only the SECURITY DEFINER functions above (owner) call them.
REVOKE ALL ON FUNCTION public.admin_write_denied() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_refund_in_progress() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_seller_status(UUID, BOOLEAN) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.admin_order_json(public.orders) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated, service_role;

-- Console RPCs: signed-in users only; each one checks is_platform_admin() itself.
REVOKE ALL ON FUNCTION public.admin_whoami() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_whoami() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_list_sellers(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_sellers(TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_refunds_due() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_refunds_due() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_find_order(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_find_order(TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_set_seller_approval(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_seller_approval(UUID, BOOLEAN, TEXT) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_record_refund(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_record_refund(UUID, TEXT, TEXT) TO authenticated;

-- record_refund: same grants as 035.
REVOKE ALL ON FUNCTION public.record_refund(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_refund(UUID, TEXT, TEXT) TO authenticated, service_role;
