-- LiveDrop Migration: 019_enable_realtime_publication.sql
-- Description: Enables Supabase Realtime publication on products, orders, and payment_attempts.
-- Restores sanitized column-level SELECT on products to anon role guarded by drops.status = 'live'
-- so real-time WAL replication reaches the public buyer webfront without leaking reserved_by_order_id.

DO $$
BEGIN
    -- Ensure standard Supabase publication exists
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    -- Add products to publication if not already added
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_rel pr
        JOIN pg_publication p ON p.oid = pr.prpubid
        JOIN pg_class c ON c.oid = pr.prrelid
        WHERE p.pubname = 'supabase_realtime' AND c.relname = 'products'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE products;
    END IF;

    -- Add orders to publication if not already added
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_rel pr
        JOIN pg_publication p ON p.oid = pr.prpubid
        JOIN pg_class c ON c.oid = pr.prrelid
        WHERE p.pubname = 'supabase_realtime' AND c.relname = 'orders'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE orders;
    END IF;

    -- Add payment_attempts to publication if not already added
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_rel pr
        JOIN pg_publication p ON p.oid = pr.prpubid
        JOIN pg_class c ON c.oid = pr.prrelid
        WHERE p.pubname = 'supabase_realtime' AND c.relname = 'payment_attempts'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE payment_attempts;
    END IF;
END $$;

-- Grant sanitized column-level SELECT on products to anon role
-- Excludes reserved_by_order_id to protect buyer privacy
GRANT SELECT (id, drop_id, code, title, price_paisa, size, image_url, status, reserved_at, version, created_at, updated_at) 
ON products TO anon;

-- Reinstate RLS policy on products for anon role guarded by active live drops
DROP POLICY IF EXISTS products_public_read_live ON products;
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
