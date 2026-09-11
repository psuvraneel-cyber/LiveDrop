-- LiveDrop Migration: 002_create_drops.sql
-- Description: Creates the drops (live session) table owned by a seller profile.
-- Parent Documentation: docs/12-database-design.md, docs/11-data-dictionary.md

CREATE TABLE drops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 150),
    slug TEXT UNIQUE NOT NULL CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
    status TEXT NOT NULL CHECK (status IN ('draft', 'live', 'closed')) DEFAULT 'draft',
    shipping_fee_paisa INT NOT NULL DEFAULT 8000 CHECK (shipping_fee_paisa >= 0),
    free_shipping_threshold_paisa INT DEFAULT 200000 CHECK (free_shipping_threshold_paisa >= 0),
    live_started_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
