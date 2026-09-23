# 11 — Data Dictionary: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Database Design:** [`docs/12-database-design.md`](file:///c:/LiveDrop/docs/12-database-design.md)  

---

## 1. Entity Overview

The LiveDrop relational database consists of 5 core tables hosted on PostgreSQL:
1. `profiles` — Boutique seller metadata, contact, UPI details, and shipping policies.
2. `drops` — Discrete live-stream selling sessions and public slugs.
3. `products` — Garment catalog items, flash codes, images, and inventory hold states.
4. `orders` — Customer purchase orders, delivery details, amounts, and statuses.
5. `order_items` — Junction table recording products bundled in an order with purchase prices.

---

## 2. Table Specifications

### 2.1 Table: `profiles`
Stores boutique seller operational credentials and default fulfillment rules.

| Column | Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `id` | `UUID` | No | None | `PRIMARY KEY, REFERENCES auth.users(id) ON DELETE CASCADE` | Matches authenticated Supabase seller user ID. |
| `store_name` | `TEXT` | No | None | `CHECK (char_length(store_name) BETWEEN 2 AND 100)` | Public boutique brand name (e.g., "Mother's Boutique"). |
| `phone_number` | `TEXT` | No | None | `CHECK (phone_number ~ '^[6-9]\d{9}$' OR phone_number ~ '^91[6-9]\d{9}$')` | Business WhatsApp phone number normalized without `+`. |
| `upi_id` | `TEXT` | No | None | `CHECK (upi_id ~ '^[a-zA-Z0-9.\-_]{2,255}@[a-zA-Z]{2,64}$')` | Seller's Virtual Payment Address (e.g., `store@okaxis`). Note: PostgreSQL REG_MAX_REPEAT caps at 255. |
| `upi_qr_url` | `TEXT` | Yes | `NULL` | None | Public URL to seller's static UPI QR code image. |
| `return_address`| `TEXT` | No | None | `CHECK (char_length(return_address) BETWEEN 10 AND 500)` | Physical return address printed on 4×6 courier labels. |
| `default_shipping_fee_paisa` | `INT` | No | `8000` | `CHECK (default_shipping_fee_paisa >= 0)` | Standard flat shipping rate in Paisa (8000 = ₹80.00). |
| `free_shipping_threshold_paisa` | `INT` | Yes | `200000` | `CHECK (free_shipping_threshold_paisa >= 0)` | Subtotal order threshold in Paisa for free shipping (200000 = ₹2,000.00). |
| `is_approved` | `BOOLEAN` | No | `false` | None | Administrative approval flag for publishing live drops (SEC-01). |
| `created_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Record creation timestamp. |
| `updated_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Last modification timestamp. |

---

### 2.2 Table: `drops`
Represents an individual Facebook Live session.

| Column | Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `id` | `UUID` | No | `gen_random_uuid()` | `PRIMARY KEY` | Unique internal drop identifier. |
| `seller_id` | `UUID` | No | None | `REFERENCES profiles(id) ON DELETE RESTRICT` | Owning boutique seller reference. |
| `title` | `TEXT` | No | None | `CHECK (char_length(title) BETWEEN 3 AND 150)` | Public session title (e.g., "Friday Silk Special"). |
| `slug` | `TEXT` | No | None | `UNIQUE, CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' AND char_length(slug) BETWEEN 3 AND 60)` | URL-safe slug for web catalog: `/drop/[slug]`. |
| `status` | `TEXT` | No | `'draft'` | `CHECK (status IN ('draft', 'live', 'closed'))` | Lifecycle state of the live broadcast session. |
| `shipping_fee_paisa` | `INT` | No | `8000` | `CHECK (shipping_fee_paisa >= 0)` | Authoritative shipping fee in Paisa for orders in this drop. |
| `free_shipping_threshold_paisa` | `INT` | Yes | `200000` | `CHECK (free_shipping_threshold_paisa >= 0)` | Subtotal threshold in Paisa for free shipping in this drop. |
| `live_started_at` | `TIMESTAMPTZ` | Yes | `NULL` | None | Timestamp when seller toggled drop to `live`. |
| `closed_at` | `TIMESTAMPTZ` | Yes | `NULL` | None | Timestamp when seller closed the drop. |
| `created_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Record creation timestamp. |
| `updated_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Last modification timestamp. |

---

### 2.3 Table: `products`
Individual garment items displayed during a live drop.

| Column | Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `id` | `UUID` | No | `gen_random_uuid()` | `PRIMARY KEY` | Unique internal product identifier. |
| `drop_id` | `UUID` | No | None | `REFERENCES drops(id) ON DELETE RESTRICT` | Associated drop session. |
| `code` | `TEXT` | No | None | `CHECK (code ~ '^#[A-Z0-9]{1,6}$')` | Bold flash code shown on stream (e.g., `#A01`). |
| `title` | `TEXT` | Yes | `NULL` | `CHECK (char_length(title) <= 100)` | Optional fabric / garment descriptor (e.g., "Tussar Silk"). |
| `price_paisa` | `INT` | No | None | `CHECK (price_paisa > 0)` | Garment price in Paisa (185000 = ₹1,850.00). |
| `size` | `TEXT` | Yes | `NULL` | `CHECK (char_length(size) <= 30)` | Garment size descriptor (e.g., "Free Size", "XL"). |
| `image_url` | `TEXT` | No | None | `CHECK (char_length(image_url) BETWEEN 1 AND 2048)` | Public CDN URL to 1:1 square WebP thumbnail. |
| `status` | `TEXT` | No | `'available'` | `CHECK (status IN ('available', 'reserved', 'sold'))` | Real-time inventory reservation state. |
| `reserved_at` | `TIMESTAMPTZ` | Yes | `NULL` | None | Timestamp when item was locked by checkout RPC. |
| `reserved_by_order_id` | `UUID` | Yes | `NULL` | `REFERENCES orders(id) ON DELETE RESTRICT` | ID of the order holding the 15-minute reservation. |
| `version` | `INT` | No | `1` | `CHECK (version >= 1)` | Optimistic concurrency and realtime ordering sequence. |
| `created_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Record creation timestamp. |
| `updated_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Last modification timestamp. |

*Table Invariant:* `UNIQUE(drop_id, code)` guarantees flash codes cannot collide within the same drop.

---

### 2.4 Table: `orders`
Customer orders created during checkout.

| Column | Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `id` | `UUID` | No | `gen_random_uuid()` | `PRIMARY KEY` | Internal order identifier. |
| `drop_id` | `UUID` | No | None | `REFERENCES drops(id) ON DELETE RESTRICT` | Associated drop session. |
| `order_code` | `TEXT` | No | None | `UNIQUE, CHECK (order_code ~ '^LD-[A-Z0-9]{6}$')` | Non-sequential customer-facing reference (e.g. `LD-7K92MF`). |
| `order_token` | `UUID` | No | `gen_random_uuid()` | `UNIQUE` | Cryptographic secret for unauthenticated receipt access. |
| `buyer_name` | `TEXT` | No | None | `CHECK (char_length(trim(buyer_name)) BETWEEN 3 AND 100)` | Recipient full name. |
| `buyer_phone` | `TEXT` | No | None | `CHECK (buyer_phone ~ '^[6-9]\d{9}$' OR buyer_phone ~ '^91[6-9]\d{9}$')` | Buyer WhatsApp contact number. |
| `shipping_address`| `TEXT`| No | None | `CHECK (char_length(trim(shipping_address)) BETWEEN 10 AND 500)` | Full multiline delivery address. |
| `pincode` | `TEXT` | No | None | `CHECK (pincode ~ '^\d{6}$')` | 6-digit Indian postal code. |
| `subtotal_paisa`| `INT` | No | None | `CHECK (subtotal_paisa > 0)` | Authoritative sum of product prices in Paisa. |
| `shipping_paisa`| `INT` | No | `0` | `CHECK (shipping_paisa >= 0)` | Authoritative shipping fee applied in Paisa. |
| `total_paisa` | `INT` | No | None | `CHECK (total_paisa = subtotal_paisa + shipping_paisa)` | Authoritative total payable in Paisa. |
| `status` | `TEXT` | No | `'pending'` | `CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled'))` | Fulfillment lifecycle status. |
| `hold_expires_at`| `TIMESTAMPTZ`| No | `NOW() + INTERVAL '15 minutes'` | None | Absolute timestamp when 15-minute hold expires. |
| `idempotency_key`| `TEXT` | Yes | `NULL` | None | Client-generated UUID ensuring single-flight checkout idempotency. |
| `packed_at` | `TIMESTAMPTZ` | Yes | `NULL` | None | Timestamp when seller packed order and marked ready_to_ship. |
| `paid_at` | `TIMESTAMPTZ` | Yes | `NULL` | None | Timestamp when seller marked order paid. |
| `shipped_at` | `TIMESTAMPTZ` | Yes | `NULL` | None | Timestamp when seller marked order dispatched. |
| `tracking_number`| `TEXT` | Yes | `NULL` | None | Courier tracking / AWB number. |
| `courier_partner`| `TEXT` | Yes | `NULL` | None | Logistics partner name (e.g. "DTDC", "India Post"). |
| `created_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Order placement timestamp. |
| `updated_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Last status update timestamp. |

---

### 2.5 Table: `order_items`
Junction table linking orders to specific garments.

| Column | Type | Nullable | Default | Constraints | Description |
|---|---|---|---|---|---|
| `id` | `UUID` | No | `gen_random_uuid()` | `PRIMARY KEY` | Line item identifier. |
| `order_id` | `UUID` | No | None | `REFERENCES orders(id) ON DELETE CASCADE` | Associated order. |
| `product_id` | `UUID` | No | None | `REFERENCES products(id) ON DELETE RESTRICT` | Referenced garment piece. |
| `price_at_purchase_paisa` | `INT` | No | None | `CHECK (price_at_purchase_paisa > 0)` | Immutable snapshot of product price at purchase in Paisa. |
| `created_at` | `TIMESTAMPTZ` | No | `NOW()` | None | Line item creation timestamp. |

*Table Invariant:* `UNIQUE(order_id, product_id)` prevents the same product from being included twice in one order.

---

## 3. Database Indexes

| Index Name | Table | Type / Condition | Target Columns | Primary Query Supported |
|---|---|---|---|---|
| `idx_products_drop_status` | `products` | B-tree | `(drop_id, status)` | Public buyer catalog browsing & available filter |
| `idx_products_active_hold` | `products` | Partial B-tree | `(reserved_at) WHERE status = 'reserved'` | Background expired reservation cleanup cron |
| `idx_orders_drop_status` | `orders` | B-tree | `(drop_id, status)` | Seller dashboard Kanban pipeline by drop and status |
| `idx_orders_hold_expiry` | `orders` | Partial B-tree | `(hold_expires_at) WHERE status = 'pending'` | Background expired orders cancellation cron |
| `idx_orders_buyer_phone` | `orders` | B-tree | `(buyer_phone)` | Buyer customer support and WhatsApp order lookups |
| `idx_order_items_order` | `order_items` | B-tree | `(order_id)` | Receipt rendering and packing slip queries |
| `idx_order_items_product` | `order_items` | B-tree | `(product_id)` | Reverse integrity lookup & product deletion checks |
| `idx_drops_one_live_per_seller` | `drops` | Partial Unique B-tree | `(seller_id) WHERE status = 'live'` | Database-level enforcement of RULE-DRP-03 (one live drop per seller) |

---

## 4. Database Triggers

| Trigger Name | Target Table | Timing / Event | Function | Behavior |
|---|---|---|---|---|
| `trg_profiles_updated_at` | `profiles` | `BEFORE UPDATE` | `set_updated_at()` | Overwrites `updated_at = NOW()`, preserves `created_at` |
| `trg_drops_updated_at` | `drops` | `BEFORE UPDATE` | `set_updated_at()` | Overwrites `updated_at = NOW()`, preserves `created_at` |
| `trg_products_updated_at` | `products` | `BEFORE UPDATE` | `set_updated_at()` | Overwrites `updated_at = NOW()`, preserves `created_at` |
| `trg_orders_updated_at` | `orders` | `BEFORE UPDATE` | `set_updated_at()` | Overwrites `updated_at = NOW()`, preserves `created_at` |
| `trg_orders_no_delete_finalized` | `orders` | `BEFORE DELETE` | `prevent_finalized_order_deletion()` | Aborts deletion if `OLD.status IN ('paid', 'shipped')` for legal/GST retention |

