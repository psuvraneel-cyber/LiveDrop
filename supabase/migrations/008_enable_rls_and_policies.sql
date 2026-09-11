-- LiveDrop Migration: 008_enable_rls_and_policies.sql
-- Description: Enables Row-Level Security (RLS) on all core tables and applies hardened
--              access-control policies for public anonymous buyers and authenticated boutique sellers.
-- Parent Documentation: docs/16-security-architecture.md, docs/RLS-ACCESS-MATRIX.md, docs/TASK-1.2-RLS-SECURITY-MATRIX.md
-- Governing Rules: AGENTS.md, ADR-003, ADR-009

-- Ensure standard Supabase roles exist for local/WASM testing engines
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
END
$$;

-- Grant schema usage to standard roles
GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- ============================================================================
-- 1. TABLE: profiles
-- ============================================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 1.1 Public read: Anyone can read public boutique seller profiles (store branding, UPI ID, business WhatsApp)
CREATE POLICY profiles_public_read ON profiles
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- 1.2 Seller insert: Authenticated sellers can only create their own profile matching auth.uid()
CREATE POLICY profiles_seller_insert ON profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (id = auth.uid());

-- 1.3 Seller update: Authenticated sellers can only update their own profile matching auth.uid()
CREATE POLICY profiles_seller_update ON profiles
    FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- Direct DELETE on profiles is strictly blocked (no policy defined).

-- ============================================================================
-- 2. TABLE: drops
-- ============================================================================
ALTER TABLE drops ENABLE ROW LEVEL SECURITY;

-- 2.1 Public read: Anonymous buyers can only view active 'live' drops
CREATE POLICY drops_public_read_live ON drops
    FOR SELECT
    TO anon
    USING (status = 'live');

-- 2.2 Seller manage: Authenticated sellers can view, insert, update, and delete their own drops (draft, live, closed)
CREATE POLICY drops_seller_manage ON drops
    FOR ALL
    TO authenticated
    USING (seller_id = auth.uid())
    WITH CHECK (seller_id = auth.uid());

-- ============================================================================
-- 3. TABLE: products
-- ============================================================================
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- 3.1 Public read: Anonymous buyers can only view products belonging to active 'live' drops
CREATE POLICY products_public_read_live ON products
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = products.drop_id
              AND drops.status = 'live'
        )
    );

-- 3.2 Seller manage: Authenticated sellers can manage products for drops they own
CREATE POLICY products_seller_manage ON products
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = products.drop_id
              AND drops.seller_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = products.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- Direct anonymous mutation of products is strictly blocked (state updates occur via RPC).

-- ============================================================================
-- 4. TABLE: orders
-- ============================================================================
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 4.1 Token-gated read: Anonymous buyers can read their order ONLY if they supply the exact secret x-order-token
CREATE POLICY orders_buyer_read_with_token ON orders
    FOR SELECT
    TO anon
    USING (
        order_token::text = (
            CASE 
                WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> ''
                THEN current_setting('request.headers', true)::json->>'x-order-token'
                ELSE NULL
            END
        )
    );

-- 4.2 Seller SELECT: Authenticated sellers can read orders for their own drops
CREATE POLICY orders_seller_select ON orders
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- 4.3 Seller UPDATE: Authenticated sellers can update orders (e.g. status, tracking) for their own drops
CREATE POLICY orders_seller_update ON orders
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- 4.4 Seller DELETE: Authenticated sellers can delete unfinalized orders for their own drops (finalized deletion guarded by trigger)
CREATE POLICY orders_seller_delete ON orders
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- Direct REST INSERT on orders is strictly blocked for all roles (order creation occurs exclusively via atomic RPC).

-- ============================================================================
-- 5. TABLE: order_items
-- ============================================================================
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- 5.1 Token-gated read: Anonymous buyers can view order items ONLY for their token-verified order
CREATE POLICY order_items_buyer_read_with_token ON order_items
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_items.order_id
              AND orders.order_token::text = (
                  CASE 
                      WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> ''
                      THEN current_setting('request.headers', true)::json->>'x-order-token'
                      ELSE NULL
                  END
              )
        )
    );

-- 5.2 Seller read: Authenticated sellers can view line items for orders under their drops
CREATE POLICY order_items_seller_select ON order_items
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders
            JOIN drops ON drops.id = orders.drop_id
            WHERE orders.id = order_items.order_id
              AND drops.seller_id = auth.uid()
        )
    );

-- Direct mutation (INSERT/UPDATE/DELETE) on order_items is strictly blocked for all roles (line items are immutable financial records).

-- ============================================================================
-- 6. GRANT TABLE PERMISSIONS TO ROLES
-- ============================================================================
-- Revoke all default public permissions
REVOKE ALL ON profiles FROM PUBLIC;
REVOKE ALL ON drops FROM PUBLIC;
REVOKE ALL ON products FROM PUBLIC;
REVOKE ALL ON orders FROM PUBLIC;
REVOKE ALL ON order_items FROM PUBLIC;

-- Anon permissions (Read-only on public/token-scoped surfaces)
GRANT SELECT ON profiles TO anon;
GRANT SELECT ON drops TO anon;
GRANT SELECT ON products TO anon;
GRANT SELECT ON orders TO anon;
GRANT SELECT ON order_items TO anon;

-- Authenticated permissions (Management permissions on seller-owned surfaces)
GRANT SELECT, INSERT, UPDATE ON profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON drops TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON products TO authenticated;
GRANT SELECT, UPDATE, DELETE ON orders TO authenticated;
GRANT SELECT ON order_items TO authenticated;

