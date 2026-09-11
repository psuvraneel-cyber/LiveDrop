-- LiveDrop Migration: 001_create_profiles.sql
-- Description: Creates the boutique seller profiles table linking to auth.users.
-- Parent Documentation: docs/12-database-design.md, docs/11-data-dictionary.md
-- Note: upi_id regex repetition count is bounded to 255 (PostgreSQL REG_MAX_REPEAT limit is 255).

DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EXCEPTION
    WHEN undefined_file THEN
        NULL;
    WHEN feature_not_supported THEN
        NULL;
END
$$;

CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    store_name TEXT NOT NULL CHECK (char_length(store_name) BETWEEN 2 AND 100),
    phone_number TEXT NOT NULL CHECK (phone_number ~ '^[6-9]\d{9}$' OR phone_number ~ '^91[6-9]\d{9}$'),
    upi_id TEXT NOT NULL CHECK (upi_id ~ '^[a-zA-Z0-9.\-_]{2,255}@[a-zA-Z]{2,64}$'),
    upi_qr_url TEXT,
    return_address TEXT NOT NULL CHECK (char_length(return_address) BETWEEN 10 AND 500),
    default_shipping_fee_paisa INT NOT NULL DEFAULT 8000 CHECK (default_shipping_fee_paisa >= 0),
    free_shipping_threshold_paisa INT DEFAULT 200000 CHECK (free_shipping_threshold_paisa >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
