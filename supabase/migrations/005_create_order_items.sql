-- LiveDrop Migration: 005_create_order_items.sql
-- Description: Creates order line items junction table with immutable purchase price and delete restrictions.
-- Parent Documentation: docs/12-database-design.md, docs/11-data-dictionary.md

CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    price_at_purchase_paisa INT NOT NULL CHECK (price_at_purchase_paisa > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(order_id, product_id)
);
