-- LiveDrop Migration: 006_create_indexes.sql
-- Description: Deploys the 8 justified query performance and constraint indexes.
-- Parent Documentation: docs/12-database-design.md, Section 2 & Section 8

-- 1. Buyer catalog grid query: filtering active garments by drop
CREATE INDEX idx_products_drop_status ON products(drop_id, status);

-- 2. Concurrency cleanup: partial index for expired holds reclamation
CREATE INDEX idx_products_active_hold ON products(reserved_at) WHERE status = 'reserved';

-- 3. Seller dashboard kanban pipeline: querying orders by drop and lifecycle status
CREATE INDEX idx_orders_drop_status ON orders(drop_id, status);

-- 4. Receipt token verification: looking up orders by unguessable cryptographic token
CREATE INDEX idx_orders_order_token ON orders(order_token);

-- 5. Order hold expiration: partial index for background cancellation of unpaid orders
CREATE INDEX idx_orders_hold_expiry ON orders(hold_expires_at) WHERE status = 'pending';

-- 6. Customer support and order history: looking up orders by buyer WhatsApp phone
CREATE INDEX idx_orders_buyer_phone ON orders(buyer_phone);

-- 7. Receipt and packing slip generation: fetching line items for an order
CREATE INDEX idx_order_items_order ON order_items(order_id);

-- 8. Reverse integrity lookup & cascade protection: checking if garment is in orders
CREATE INDEX idx_order_items_product ON order_items(product_id);
