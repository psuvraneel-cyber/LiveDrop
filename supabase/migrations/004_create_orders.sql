-- LiveDrop Migration: 004_create_orders.sql
-- Description: Creates customer orders table with integer paisa totals, validation regexes, and reservation FK.
-- Parent Documentation: docs/12-database-design.md, docs/11-data-dictionary.md

CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drop_id UUID NOT NULL REFERENCES drops(id) ON DELETE RESTRICT,
    order_code TEXT UNIQUE NOT NULL CHECK (order_code ~ '^LD-[A-Z0-9]{6}$'),
    order_token UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(),
    buyer_name TEXT NOT NULL CHECK (char_length(trim(buyer_name)) BETWEEN 3 AND 100),
    buyer_phone TEXT NOT NULL CHECK (buyer_phone ~ '^[6-9]\d{9}$' OR buyer_phone ~ '^91[6-9]\d{9}$'),
    shipping_address TEXT NOT NULL CHECK (char_length(trim(shipping_address)) BETWEEN 10 AND 500),
    pincode TEXT NOT NULL CHECK (pincode ~ '^\d{6}$'),
    subtotal_paisa INT NOT NULL CHECK (subtotal_paisa > 0),
    shipping_paisa INT NOT NULL DEFAULT 0 CHECK (shipping_paisa >= 0),
    total_paisa INT NOT NULL CHECK (total_paisa = subtotal_paisa + shipping_paisa),
    status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')) DEFAULT 'pending',
    hold_expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
    paid_at TIMESTAMPTZ,
    shipped_at TIMESTAMPTZ,
    tracking_number TEXT,
    courier_partner TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Establish foreign key from products to orders for reservation tracking
ALTER TABLE products 
ADD CONSTRAINT fk_products_reserved_by_order 
FOREIGN KEY (reserved_by_order_id) REFERENCES orders(id) ON DELETE RESTRICT;
