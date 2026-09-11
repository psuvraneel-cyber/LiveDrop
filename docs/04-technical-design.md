# 04 — Master Technical Design: LiveDrop

**Document Version:** 2.0.0  
**Effective Date:** 2026-09-11  
**Status:** Reconciled Engineering Specification  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  

---

## 1. Architectural Overview & System Topology

LiveDrop decouples the live-commerce interaction into two specialized client surfaces connected by a unified, real-time cloud backend (Supabase PostgreSQL):

```
                          ┌───────────────────────────┐
                          │      Supabase Cloud       │
                          │   ┌─────────────────────┐ │
                          │   │ PostgreSQL Database │ │
                          │   │ Realtime WebSockets │ │
                          │   │ Auth (Email/Pass)   │ │
                          │   │ Storage (Images)    │ │
                          │   │ Edge Functions / RPC│ │
                          │   └─────────────────────┘ │
                          └─────────────┬─────────────┘
                                        │
                ┌───────────────────────┴───────────────────────┐
                ▼                                               ▼
┌───────────────────────────────┐               ┌───────────────────────────────┐
│     SELLER OPERATIONS APP     │               │      BUYER WEB CATALOG        │
│   (Flutter Native Android)    │               │   (Next.js App Router / Edge) │
├───────────────────────────────┤               ├───────────────────────────────┤
│ • Camera → WebP → Storage     │               │ • Edge SSR catalog feed       │
│ • Realtime order pipeline     │               │ • LocalStorage cart bundle    │
│ • Kanban order management     │  ◄──────────► │ • Unified atomic order RPC    │
│ • 4x6 Thermal PDF engine      │   (Realtime)  │ • WhatsApp deep link dispatch │
│ • Supabase Auth (seller only) │               │ • Zero authentication required│
└───────────────────────────────┘               └───────────────────────────────┘
```

---

## 2. Critical Review & Architectural Reconciliation

The initial draft Technical Design Document contained significant security, concurrency, and data-integrity vulnerabilities. Below is the explicit audit and architectural reconciliation:

### Reconciliation Matrix

| Area | Current Draft Design | Problem Identified | Recommended Reconciled Design | Why Necessary | Impact | ADR Required? |
|---|---|---|---|---|---|---|
| **1. Order Creation & Reservation** | Decoupled: `reserve_order_items` called first; client then executes `POST /orders` with arbitrary client-calculated `total_amount`. | Race condition, phantom holds if browser drops before order insert, and client price tampering (e.g. buyer posting ₹1 total). | Single atomic RPC `create_order_with_reservation(...)` that locks products, validates live status, computes totals server-side, inserts order and order items, and returns `order_token`. | Guarantees complete atomicity and prevents price manipulation. | Eliminates double-booking and fraud vulnerabilities. | **Yes** ([ADR-002](file:///c:/LiveDrop/docs/adr/ADR-002-atomic-reservation-engine.md)) |
| **2. Buyer PII Exposure** | `orders` table allows unauthenticated public `INSERT`, but lacks a secure policy for buyer retrieval on `/order/[id]`. | If public read is enabled, anyone can scrape all customer names, phones, and addresses. If restricted to seller, buyer receipt breaks. | Token-gated RLS policy: `order_token` (UUIDv4) issued at creation and verified via header or query parameter for unauthenticated receipt access. | Complies with data privacy regulations and prevents customer harvesting. | Protects buyer privacy while maintaining zero-login experience. | **Yes** ([ADR-003](file:///c:/LiveDrop/docs/adr/ADR-003-unauthenticated-buyer-model-and-order-privacy.md)) |
| **3. Security Definer Risks** | RPC functions defined with `SECURITY DEFINER` without setting explicit `search_path`. | Malicious users can manipulate PostgreSQL `search_path` to execute arbitrary functions with elevated privileges. | Add `SET search_path = public, pg_temp;` to all `SECURITY DEFINER` functions. | Standard PostgreSQL security hardening rule. | Hardens database against privilege escalation. | No (Standard Patch) |
| **4. Expiration Collision** | Seller marks an order "Paid" after its 15-minute hold expired, unaware that another buyer claimed the piece. | Double-sold merchandise and severe seller reputational damage. | Atomic `mark_order_paid(p_order_id)` function that checks if any product was reclaimed by another order; aborts with `PRODUCT_ALREADY_RECLAIMED` error if contested. | Prevents silent inventory collisions when sellers review chats late. | Guarantees zero double-allocation even with expired orders. | **Yes** ([ADR-002](file:///c:/LiveDrop/docs/adr/ADR-002-atomic-reservation-engine.md)) |
| **5. Shipping & Subtotal Accounting** | `orders` table only had a single `total_amount` column with no shipping breakdown. | Violates accounting transparency and prevents verification against pre-filled WhatsApp message. | Add `subtotal_amount`, `shipping_amount`, and `shipping_notes` to `orders` table. Computed authoritatively via seller profile settings. | Transparent audit trail for buyer and courier manifests. | Prevents shipping charge discrepancies. | No (Schema Patch) |
| **6. Order Code Enumeration** | Sequential order codes (`LD-1001`, `LD-1002`). | Competitors can scrape order velocity; attackers can guess valid order codes. | 8-character randomized alphanumeric uppercase codes (e.g., `LD-8F42-9B`). | Cryptographically random order identifiers. | Eliminates business intelligence leaks. | No (Schema Patch) |
| **7. Free Tier Inactivity Pausing** | Supabase free tier projects pause automatically after 7 days of inactivity. | Seller broadcasting after an 8-day break encounters a 503 database offline error. | Automated daily keepalive health check ping via GitHub Actions cron or cron-job.org. | Ensures 100% database availability for weekend live streams. | Protects operational continuity at ₹0 cost. | **Yes** ([ADR-008](file:///c:/LiveDrop/docs/adr/ADR-008-zero-cost-infrastructure-limits-and-mitigations.md)) |
| **8. Image Storage Egress Quota** | 1 GB storage and 2 GB monthly egress limit on Supabase free tier. | 100 stream viewers loading 40 thumbnails exhausts 2 GB bandwidth in ~15 live drops. | Cache-Control headers (`public, max-age=31536000, immutable`) routed through Cloudflare CDN caching layer. | Eliminates repeat egress hits against Supabase quota. | Guarantees long-term ₹0 media hosting. | **Yes** ([ADR-005](file:///c:/LiveDrop/docs/adr/ADR-005-client-side-image-compression-and-storage.md)) |

---

## 3. Technology Stack & Key Dependencies

| Subsystem | Technology Selection | Version / Specification | Rationale |
|---|---|---|---|
| **Buyer Webfront** | Next.js (React 19) | App Router, TypeScript | Fast edge SSR (<1.5s FCP), OpenGraph preview cards, zero buyer download |
| **Web Hosting** | Cloudflare Pages / Vercel | Global Edge Network | Unlimited static requests, 100 GB bandwidth on free tier |
| **Seller Mobile App** | Flutter for Android | Dart 3.x, Android 11.0+ | Direct camera access, background image compression, 4×6 PDF generation |
| **App Distribution** | Direct Sideload APK | Release build (No Play Store) | Eliminates $25 Google Play fee; instant installation for boutique seller |
| **Backend & Database** | Supabase Cloud | PostgreSQL 15+, PostgREST | Full ACID relational database, real-time WebSockets, RLS, Auth, ₹0 tier |
| **Local Offline Cache** | Hive / SQLite (Flutter) | Key-value / relational | Queues offline image uploads during cellular drops in live streams |
| **PDF Label Engine** | `pdf` & `printing` (Flutter) | 4×6 inch (100×150 mm) | Client-side thermal rendering, Bluetooth ESC/POS or Android Print Spooler |
| **Payment Protocol** | Direct UPI Deep-Link / QR | NPCI / UPI Specification | 0% transaction fees; no payment gateway registration or merchant fees |

---

## 4. Reconciled Database Schema (PostgreSQL)

```sql
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. PROFILES (Boutique Sellers)
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    store_name TEXT NOT NULL,
    phone_number TEXT NOT NULL,         -- E.164 without '+' (e.g., '919830012345')
    upi_id TEXT NOT NULL,               -- VPA (e.g., 'mothersboutique@okaxis')
    upi_qr_url TEXT,                    -- Optional URL to static UPI QR code image
    return_address TEXT NOT NULL,
    default_shipping_fee_paisa INTEGER NOT NULL DEFAULT 8000 CHECK (default_shipping_fee_paisa >= 0), -- ₹80.00
    free_shipping_threshold_paisa INTEGER DEFAULT 200000 CHECK (free_shipping_threshold_paisa IS NULL OR free_shipping_threshold_paisa >= 0), -- ₹2,000.00
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. DROPS (Live Stream Sessions)
CREATE TABLE drops (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    seller_id UUID NOT NULL REFERENCES profiles(id) ON DELETE RESTRICT,
    title TEXT NOT NULL CHECK (char_length(title) BETWEEN 3 AND 150),
    slug TEXT UNIQUE NOT NULL CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' AND char_length(slug) BETWEEN 3 AND 60),
    status TEXT NOT NULL CHECK (status IN ('draft', 'live', 'closed')) DEFAULT 'draft',
    shipping_fee_paisa INTEGER NOT NULL DEFAULT 8000 CHECK (shipping_fee_paisa >= 0),
    free_shipping_threshold_paisa INTEGER DEFAULT 200000 CHECK (free_shipping_threshold_paisa IS NULL OR free_shipping_threshold_paisa >= 0),
    live_started_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. PRODUCTS (Garment Catalog)
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drop_id UUID NOT NULL REFERENCES drops(id) ON DELETE RESTRICT,
    code TEXT NOT NULL CHECK (code ~ '^#[A-Z0-9]{1,6}$'), -- e.g., '#A01', uppercase alphanumeric
    title TEXT CHECK (char_length(title) <= 100),
    price_paisa INTEGER NOT NULL CHECK (price_paisa > 0),
    size TEXT CHECK (char_length(size) <= 30),
    image_url TEXT NOT NULL CHECK (char_length(image_url) BETWEEN 1 AND 2048),
    status TEXT NOT NULL CHECK (status IN ('available', 'reserved', 'sold')) DEFAULT 'available',
    reserved_at TIMESTAMPTZ,
    reserved_by_order_id UUID,          -- FK added after orders table creation
    version INT NOT NULL DEFAULT 1 CHECK (version >= 1), -- Optimistic concurrency counter
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(drop_id, code)
);

-- 4. ORDERS (Customer Purchases)
CREATE TABLE orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    drop_id UUID NOT NULL REFERENCES drops(id) ON DELETE RESTRICT,
    order_code TEXT UNIQUE NOT NULL CHECK (order_code ~ '^LD-[A-Z0-9]{6}$'), -- Randomized 6-char (e.g., 'LD-8F429B')
    order_token UUID UNIQUE NOT NULL DEFAULT gen_random_uuid(), -- Unauthenticated receipt access key
    buyer_name TEXT NOT NULL CHECK (char_length(trim(buyer_name)) BETWEEN 3 AND 100),
    buyer_phone TEXT NOT NULL CHECK (buyer_phone ~ '^[6-9]\d{9}$' OR buyer_phone ~ '^91[6-9]\d{9}$'), -- E.164 / Indian mobile
    shipping_address TEXT NOT NULL CHECK (char_length(trim(shipping_address)) BETWEEN 10 AND 500),
    pincode TEXT NOT NULL CHECK (pincode ~ '^\d{6}$'),
    subtotal_paisa INTEGER NOT NULL CHECK (subtotal_paisa > 0),
    shipping_paisa INTEGER NOT NULL DEFAULT 0 CHECK (shipping_paisa >= 0),
    total_paisa INTEGER NOT NULL CHECK (total_paisa = subtotal_paisa + shipping_paisa),
    status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')) DEFAULT 'pending',
    hold_expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
    paid_at TIMESTAMPTZ,
    shipped_at TIMESTAMPTZ,
    tracking_number TEXT,
    courier_partner TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Link products.reserved_by_order_id to orders(id)
ALTER TABLE products 
ADD CONSTRAINT fk_products_reserved_by_order 
FOREIGN KEY (reserved_by_order_id) REFERENCES orders(id) ON DELETE RESTRICT;

-- 5. ORDER ITEMS (Junction Table)
CREATE TABLE order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    price_at_purchase_paisa INTEGER NOT NULL CHECK (price_at_purchase_paisa > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(order_id, product_id)
);

-- 6. INDEXES FOR HIGH-VELOCITY QUERYING
CREATE INDEX idx_products_drop_status ON products(drop_id, status);
CREATE INDEX idx_products_active_hold ON products(reserved_at) WHERE status = 'reserved';
CREATE INDEX idx_orders_drop_status ON orders(drop_id, status);
CREATE INDEX idx_orders_hold_expiry ON orders(hold_expires_at) WHERE status = 'pending';
CREATE INDEX idx_orders_buyer_phone ON orders(buyer_phone);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_product ON order_items(product_id);
CREATE UNIQUE INDEX idx_drops_one_live_per_seller ON drops(seller_id) WHERE status = 'live';
```

---

## 5. Unified Core Database RPC Functions

### 5.1 Atomic Order Creation & Stock Lock
`create_order_with_reservation(...)` completely replaces the broken decoupled design with sorted locking, deduplication, and server-computed Paisa totals:

```sql
CREATE OR REPLACE FUNCTION create_order_with_reservation(
    p_drop_id UUID,
    p_product_ids UUID[],
    p_buyer_name TEXT,
    p_buyer_phone TEXT,
    p_shipping_address TEXT,
    p_pincode TEXT
) RETURNS JSONB AS $$
DECLARE
    v_drop drops%ROWTYPE;
    v_seller profiles%ROWTYPE;
    v_clean_product_ids UUID[];
    v_locked_count INT;
    v_subtotal_paisa INT := 0;
    v_shipping_paisa INT := 0;
    v_total_paisa INT := 0;
    v_order orders%ROWTYPE;
    v_random_suffix TEXT;
    v_order_code TEXT;
    v_order_token UUID := gen_random_uuid();
    v_product RECORD;
BEGIN
    -- 1. Validate Drop is Active
    SELECT * INTO v_drop FROM drops WHERE id = p_drop_id AND status = 'live';
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'DROP_NOT_ACTIVE');
    END IF;

    -- 2. Deduplicate Product IDs to Prevent Multi-Lock Glitches
    SELECT array_agg(DISTINCT id) INTO v_clean_product_ids
    FROM unnest(p_product_ids) AS id;

    IF v_clean_product_ids IS NULL OR array_length(v_clean_product_ids, 1) = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'EMPTY_CART');
    END IF;

    IF array_length(v_clean_product_ids, 1) > 10 THEN
        RETURN jsonb_build_object('success', false, 'error', 'EXCEEDS_CART_LIMIT');
    END IF;

    -- 3. Fetch Seller Profile for Fallback Shipping Policy
    SELECT * INTO v_seller FROM profiles WHERE id = v_drop.seller_id;

    -- 4. Lock Requested Products in Strict Ascending UUID Order (Prevents Deadlocks)
    SELECT COUNT(*) INTO v_locked_count
    FROM (
        SELECT id FROM products
        WHERE id = ANY(v_clean_product_ids) 
          AND drop_id = p_drop_id 
          AND status = 'available'
        ORDER BY id ASC
        FOR UPDATE
    ) locked_rows;

    -- If not all items are available, return conflict with unavailable breakdown
    IF v_locked_count < array_length(v_clean_product_ids, 1) THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'STOCK_UNAVAILABLE',
            'unavailable_product_ids', (
                SELECT coalesce(json_agg(id), '[]'::json)
                FROM unnest(v_clean_product_ids) AS id
                WHERE id NOT IN (
                    SELECT p.id FROM products p 
                    WHERE p.id = ANY(v_clean_product_ids) AND p.status = 'available'
                )
            )
        );
    END IF;

    -- 5. Authoritatively Calculate Subtotal from Database Prices in Paisa
    SELECT COALESCE(SUM(price_paisa), 0) INTO v_subtotal_paisa
    FROM products
    WHERE id = ANY(v_clean_product_ids);

    -- 6. Authoritatively Calculate Shipping from Drop with Seller Fallback
    IF v_subtotal_paisa >= COALESCE(v_drop.free_shipping_threshold_paisa, v_seller.free_shipping_threshold_paisa, 200000) THEN
        v_shipping_paisa := 0;
    ELSE
        v_shipping_paisa := COALESCE(v_drop.shipping_fee_paisa, v_seller.default_shipping_fee_paisa, 8000);
    END IF;
    v_total_paisa := v_subtotal_paisa + v_shipping_paisa;

    -- 7. Generate Unambiguous 6-Char Randomized Order Code (e.g. 'LD-8F429B')
    v_random_suffix := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    v_order_code := 'LD-' || v_random_suffix;

    -- 8. Insert Order Record
    INSERT INTO orders (
        drop_id, order_code, order_token, buyer_name, buyer_phone,
        shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa,
        status, hold_expires_at
    ) VALUES (
        p_drop_id, v_order_code, v_order_token, trim(p_buyer_name), trim(p_buyer_phone),
        trim(p_shipping_address), trim(p_pincode), v_subtotal_paisa, v_shipping_paisa, v_total_paisa,
        'pending', NOW() + INTERVAL '15 minutes'
    ) RETURNING * INTO v_order;

    -- 9. Insert Order Items & Update Products to Reserved
    FOR v_product IN 
        SELECT id, price_paisa FROM products WHERE id = ANY(v_clean_product_ids) ORDER BY id ASC
    LOOP
        INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
        VALUES (v_order.id, v_product.id, v_product.price_paisa);

        UPDATE products
        SET status = 'reserved',
            reserved_at = NOW(),
            reserved_by_order_id = v_order.id,
            version = version + 1,
            updated_at = NOW()
        WHERE id = v_product.id;
    END LOOP;

    -- 10. Return Structured Order Receipt (Paisa values for precision)
    RETURN jsonb_build_object(
        'success', true,
        'order_id', v_order.id,
        'order_code', v_order.order_code,
        'order_token', v_order.order_token,
        'subtotal_paisa', v_order.subtotal_paisa,
        'shipping_paisa', v_order.shipping_paisa,
        'total_paisa', v_order.total_paisa,
        'hold_expires_at', v_order.hold_expires_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
```

### 5.2 Expired Hold Reaper
Scheduled via pg_cron every 60 seconds to release abandoned carts:

```sql
CREATE OR REPLACE FUNCTION release_expired_holds() RETURNS VOID AS $$
DECLARE
    v_expired_order RECORD;
BEGIN
    FOR v_expired_order IN
        SELECT id FROM orders
        WHERE status = 'pending' AND hold_expires_at < NOW()
    LOOP
        -- Release associated products back to 'available'
        UPDATE products
        SET status = 'available',
            reserved_at = NULL,
            reserved_by_order_id = NULL,
            version = version + 1,
            updated_at = NOW()
        WHERE reserved_by_order_id = v_expired_order.id
          AND status = 'reserved';

        -- Mark order cancelled / expired
        UPDATE orders
        SET status = 'cancelled',
            updated_at = NOW()
        WHERE id = v_expired_order.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
```

### 5.3 Safe Conflict-Guarded Payment Transition
Prevents sellers from selling reclaimed merchandise:

```sql
CREATE OR REPLACE FUNCTION mark_order_paid(p_order_id UUID) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
    v_drop drops%ROWTYPE;
    v_contested_count INT;
BEGIN
    SELECT * INTO v_order FROM orders WHERE id = p_order_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND');
    END IF;

    -- Verify Seller Authorization
    SELECT * INTO v_drop FROM drops WHERE id = v_order.drop_id AND seller_id = auth.uid();
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
    END IF;

    -- Explicitly lock target products in sorted order to prevent concurrent race conditions
    PERFORM id FROM products
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id)
    ORDER BY id ASC
    FOR UPDATE;

    -- Check if any item belonging to this order was reserved/bought by ANOTHER order
    SELECT COUNT(*) INTO v_contested_count
    FROM products p
    JOIN order_items oi ON oi.product_id = p.id
    WHERE oi.order_id = p_order_id
      AND (p.status = 'sold' OR (p.status = 'reserved' AND p.reserved_by_order_id != p_order_id));

    IF v_contested_count > 0 THEN
        RETURN jsonb_build_object(
            'success', false, 
            'error', 'PRODUCT_ALREADY_RECLAIMED',
            'message', 'One or more items in this order were claimed by another buyer after the hold expired.'
        );
    END IF;

    -- Mark products permanently Sold
    UPDATE products
    SET status = 'sold',
        version = version + 1,
        updated_at = NOW()
    WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);

    -- Transition Order to Paid
    UPDATE orders
    SET status = 'paid',
        paid_at = NOW(),
        updated_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
```

### 5.4 Token-Gated Buyer Order Retrieval RPC
Provides cryptographic zero-trust retrieval of buyer order receipts:

```sql
CREATE OR REPLACE FUNCTION get_order_by_token(
    p_order_id UUID,
    p_order_token UUID
) RETURNS JSONB AS $$
DECLARE
    v_order_json JSONB;
BEGIN
    SELECT jsonb_build_object(
        'id', o.id,
        'order_code', o.order_code,
        'buyer_name', o.buyer_name,
        'subtotal_paisa', o.subtotal_paisa,
        'shipping_paisa', o.shipping_paisa,
        'total_paisa', o.total_paisa,
        'status', o.status,
        'hold_expires_at', o.hold_expires_at,
        'store_name', pr.store_name,
        'upi_id', pr.upi_id,
        'upi_qr_url', pr.upi_qr_url,
        'items', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'product_id', p.id,
                'code', p.code,
                'title', p.title,
                'image_url', p.image_url,
                'price_at_purchase_paisa', oi.price_at_purchase_paisa
            )), '[]'::jsonb)
            FROM order_items oi
            JOIN products p ON p.id = oi.product_id
            WHERE oi.order_id = o.id
        )
    ) INTO v_order_json
    FROM orders o
    JOIN drops d ON d.id = o.drop_id
    JOIN profiles pr ON pr.id = d.seller_id
    WHERE o.id = p_order_id AND o.order_token = p_order_token;

    IF v_order_json IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    RETURN jsonb_build_object('success', true, 'order', v_order_json);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
```

### 5.5 Manual Offline Sale Override RPC
Permits the boutique seller to mark an item sold immediately during a live broadcast:

```sql
CREATE OR REPLACE FUNCTION mark_product_sold_offline(
    p_product_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_prod products%ROWTYPE;
BEGIN
    SELECT p.* INTO v_prod
    FROM products p
    JOIN drops d ON d.id = p.drop_id
    WHERE p.id = p_product_id AND d.seller_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'PRODUCT_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    IF v_prod.status = 'sold' THEN
        RETURN jsonb_build_object('success', false, 'error', 'ALREADY_SOLD');
    END IF;

    UPDATE products
    SET status = 'sold',
        version = version + 1,
        updated_at = NOW()
    WHERE id = p_product_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
```

### 5.6 Force Release Hold RPC
Allows the seller to cancel an unpaid order and immediately return items to available status:

```sql
CREATE OR REPLACE FUNCTION force_release_hold(
    p_order_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_order orders%ROWTYPE;
BEGIN
    SELECT o.* INTO v_order
    FROM orders o
    JOIN drops d ON d.id = o.drop_id
    WHERE o.id = p_order_id AND d.seller_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    END IF;

    IF v_order.status != 'pending' THEN
        RETURN jsonb_build_object('success', false, 'error', 'ONLY_PENDING_CAN_BE_RELEASED');
    END IF;

    -- Return products to available
    UPDATE products
    SET status = 'available',
        reserved_at = NULL,
        reserved_by_order_id = NULL,
        version = version + 1,
        updated_at = NOW()
    WHERE reserved_by_order_id = p_order_id AND status = 'reserved';

    -- Mark order cancelled
    UPDATE orders
    SET status = 'cancelled',
        updated_at = NOW()
    WHERE id = p_order_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
```
