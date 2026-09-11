-- LiveDrop Migration: 003_create_products.sql
-- Description: Creates the products (catalog garments) table with flash codes and integer paisa pricing.
-- Parent Documentation: docs/12-database-design.md, docs/11-data-dictionary.md

CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drop_id UUID NOT NULL REFERENCES drops(id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^#[A-Z0-9]{1,6}$'),
    title TEXT CHECK (char_length(title) <= 100),
    price_paisa INT NOT NULL CHECK (price_paisa > 0),
    size TEXT CHECK (char_length(size) <= 30),
    image_url TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('available', 'reserved', 'sold')) DEFAULT 'available',
    reserved_at TIMESTAMPTZ,
    reserved_by_order_id UUID,
    version INT NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(drop_id, code)
);
