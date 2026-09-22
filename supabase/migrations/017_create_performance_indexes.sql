-- LiveDrop Migration: 017_create_performance_indexes.sql
-- Description: SPRINT 1 (P0) — Performance Indexes for Reaper Optimization, Foreign Keys & Seller Operations.
-- Standards: ADR-009, Performance Budget & 1,000-User Capacity Design
-- Objectives: Eliminate unindexed sequential scans during reaper runs and seller Kanban loading.

-- ============================================================================
-- 1. REAPER & HOLD EXPIRATION INDEXES
-- ============================================================================

-- 1.1 Index for release_expired_holds() matching WHERE status IN ('pending', 'confirmed')
CREATE INDEX IF NOT EXISTS idx_orders_hold_expiry_reaper 
ON orders (hold_expires_at) 
WHERE status IN ('pending', 'confirmed');

-- 1.2 Foreign key index on products(reserved_by_order_id) to eliminate product table sequential scans in reaper loop
CREATE INDEX IF NOT EXISTS idx_products_reserved_by_order 
ON products (reserved_by_order_id) 
WHERE reserved_by_order_id IS NOT NULL;


-- ============================================================================
-- 2. SELLER QUEUE & OPERATIONAL INDEXES
-- ============================================================================

-- 2.1 Index for seller verification queue sorting by claim timestamp
CREATE INDEX IF NOT EXISTS idx_payment_attempts_queue 
ON payment_attempts (status, buyer_claimed_at DESC);

-- 2.2 Index for seller drop order list chronological pagination
CREATE INDEX IF NOT EXISTS idx_orders_drop_created 
ON orders (drop_id, created_at DESC);
