# 16 — Security Architecture & Access Control Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Threat Model Reference:** [`docs/17-threat-model.md`](file:///c:/LiveDrop/docs/17-threat-model.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Security Architecture Principles

1. **Principle of Least Privilege:** Public unauthenticated buyers have zero direct write access to database tables. All mutating interactions must traverse hardened PostgreSQL RPC functions.
2. **Cryptographic Receipt Isolation:** Unauthenticated buyers access order confirmations exclusively through high-entropy UUIDv4 `order_token` credentials.
3. **No Privileged Client Secrets:** The Supabase `service_role` key is strictly prohibited from client bundles (Next.js client code, Flutter APK binaries). Only the public `anon` key is distributed.
4. **Authoritative Server Calculation:** Financial totals and inventory state transitions are calculated strictly within database transactions, completely ignoring client-side price or state parameters.

---

## 2. Authentication & Session Management

### 2.1 Seller Authentication
* **Provider:** Supabase Auth (GoTrue).
* **Strategy:** Email and Password authentication restricted strictly to the boutique owner. Self-service registration is disabled; seller accounts are provisioned via administrative invite.
* **Token Lifecycle:**
  * JWT Access Token: 1-hour expiration.
  * Refresh Token: 30-day sliding expiration stored in Android EncryptedSharedPreferences (via `flutter_secure_storage`).
* **Session Termination:** Tapping "Logout" in the mobile app immediately revokes the active session token and purges local encryption keys.

### 2.2 Buyer Identity Model
* **Zero-Login Mandate:** Buyers are unauthenticated. No passwords, SMS OTPs, or social logins.
* **Session Verification:** Order creation issues a client-stored `order_token` (UUIDv4) that acts as an unforgeable bearer credential for accessing `/order/[id]`.

---

## 3. Authorization & Row-Level Security (RLS) Policies

All PostgreSQL tables have Row-Level Security explicitly enabled (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`). Direct table access without an explicit policy is denied by default.

```sql
-- ============================================================================
-- 1. TABLE: profiles
-- ============================================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Public can read store branding and UPI details
CREATE POLICY profiles_public_read ON profiles
    FOR SELECT
    USING (true);

-- Only authenticated seller can update their own profile
CREATE POLICY profiles_seller_update ON profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ============================================================================
-- 2. TABLE: drops
-- ============================================================================
ALTER TABLE drops ENABLE ROW LEVEL SECURITY;

-- Public can only see active 'live' drops
CREATE POLICY drops_public_read_live ON drops
    FOR SELECT
    USING (status = 'live');

-- Seller can view all their drops (draft, live, closed)
CREATE POLICY drops_seller_all ON drops
    FOR ALL
    TO authenticated
    USING (seller_id = auth.uid())
    WITH CHECK (seller_id = auth.uid());

-- ============================================================================
-- 3. TABLE: products
-- ============================================================================
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Public can read products belonging to active live drops
CREATE POLICY products_public_read_live ON products
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM drops 
            WHERE drops.id = products.drop_id 
              AND drops.status = 'live'
        )
    );

-- Seller can manage products for their drops
CREATE POLICY products_seller_manage ON products
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops 
            WHERE drops.id = products.drop_id 
              AND drops.seller_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM drops 
            WHERE drops.id = products.drop_id 
              AND drops.seller_id = auth.uid()
        )
    );

-- ============================================================================
-- 4. TABLE: orders
-- ============================================================================
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Direct public INSERT is BLOCKED. Inserts must occur via create_order_with_reservation() RPC!
-- This policy allows unauthenticated receipt viewing ONLY with valid order_token
CREATE POLICY orders_buyer_read_with_token ON orders
    FOR SELECT
    USING (
        order_token::text = current_setting('request.headers', true)::json->>'x-order-token'
    );

-- Seller can read and update orders for their own drops
CREATE POLICY orders_seller_manage ON orders
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops 
            WHERE drops.id = orders.drop_id 
              AND drops.seller_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM drops 
            WHERE drops.id = orders.drop_id 
              AND drops.seller_id = auth.uid()
        )
    );

-- ============================================================================
-- 5. TABLE: order_items
-- ============================================================================
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- Buyer can read line items for their token-verified order
CREATE POLICY order_items_buyer_read ON order_items
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM orders 
            WHERE orders.id = order_items.order_id 
              AND orders.order_token::text = current_setting('request.headers', true)::json->>'x-order-token'
        )
    );

-- Seller can view line items for their orders
CREATE POLICY order_items_seller_manage ON order_items
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders 
            JOIN drops ON drops.id = orders.drop_id
            WHERE orders.id = order_items.order_id 
              AND drops.seller_id = auth.uid()
        )
    );
```

---

## 4. Database Security Definer Hardening

PostgreSQL functions declared with `SECURITY DEFINER` execute with the privileges of the database owner.
* **Privilege Escalation Vulnerability:** If `search_path` is not explicitly pinned, an attacker can manipulate temporary schema search paths to execute malicious functions under superuser privileges.
* **Mandatory Hardening Standard:** Every `SECURITY DEFINER` function in LiveDrop must include:
  ```sql
  SECURITY DEFINER SET search_path = public, pg_temp;
  ```
* **Revocation of Public Execution:** Functions intended exclusively for authenticated sellers must revoke execution permissions from the `anon` and `public` roles:
  ```sql
  REVOKE EXECUTE ON FUNCTION mark_order_paid(UUID) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION mark_order_paid(UUID) TO authenticated;
  ```

---

## 5. URL & WhatsApp Deep-Link Security

The checkout handshake relies on generating standard `https://wa.me/{seller_phone}?text={encoded_message}` links.

### 5.1 Injection & Malformed Payload Defenses
1. **Phone Number Normalization:**
   * Raw input is cleaned to strictly retain digits: `phone.replace(/[^0-9]/g, '')`.
   * Strips leading `0` or `+`. If exactly 10 digits starting with `6–9`, prepends Indian country code `91`.
   * Prevents protocol injection or dialer exploits.
2. **Text Payload Sanitization:**
   * Line breaks normalized strictly to `%0A`.
   * Characters `#`, `&`, `+`, `=`, and unicode emojis are encoded using `encodeURIComponent`.
   * Payload length capped at **2,000 characters** to prevent browser address-bar truncation crashes in embedded webviews.

---

## 6. Secrets & Environment Classification

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SECRETS CLASSIFICATION                           │
├────────────────────┬──────────────────┬─────────────────────────────────────┤
│ Credential         │ Permitted Scope  │ Forbidden Deployment Locations      │
├────────────────────┼──────────────────┼─────────────────────────────────────┤
│ `SUPABASE_ANON_KEY`│ Public (Web/APK) │ Never use for administrative tasks  │
│ `SUPABASE_URL`     │ Public (Web/APK) │ N/A                                 │
│ `SERVICE_ROLE_KEY` │ Backend / CI Only│ NEVER in Next.js Client, NEVER in   │
│                    │                  │ Flutter APK, NEVER in public repos  │
│ `DATABASE_URL`     │ CI / Migrations  │ NEVER in client source or build APK │
└────────────────────┴──────────────────┴─────────────────────────────────────┘
```

* **Git Secret Defense:** Pre-commit hooks (`git-secrets` / `trufflehog`) scan for Supabase service role tokens and private keys prior to any commit.
