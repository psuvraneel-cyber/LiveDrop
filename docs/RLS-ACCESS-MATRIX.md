# LiveDrop — Row-Level Security (RLS) Access Control Matrix
# Governing Security Specification for Database Authorization

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Task Authority:** Phase 1 / TASK-1.2  
**Governing Documents:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md), [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md), [`docs/adr/ADR-003-unauthenticated-buyer-model-and-order-privacy.md`](file:///c:/LiveDrop/docs/adr/ADR-003-unauthenticated-buyer-model-and-order-privacy.md)  

---

## 1. Security Architecture & Role Model

LiveDrop strictly enforces authorization at the PostgreSQL engine level using Row-Level Security (RLS). All direct table access without an explicit matching policy is denied by default.

### Role Definitions
1. **`anon` (Anonymous Buyer):** Unauthenticated public browser visitor. No Supabase JWT. Has zero direct write access to database tables. Reads are strictly scoped to public live catalog data and token-gated order receipts.
2. **`authenticated` (Boutique Seller):** Authenticated seller session with a verified Supabase GoTrue JWT. The seller's identity is derived strictly from `auth.uid()`. Can manage only their own store profile, drops, products, and orders.
3. **`service_role` (Privileged Backend / Cron):** Internal Supabase service role key. Bypasses RLS for trusted maintenance routines (e.g., releasing expired holds). Strictly prohibited from client bundles.

---

## 2. Master Access Control Matrix

| Table | Operation | Role | Allowed? | Exact Ownership Rule | Additional Predicates / Conditions | Sensitive Columns | Enforced Via |
|---|---|---|---|---|---|---|---|
| **`profiles`** | `SELECT` | `anon` | **YES** | Public store branding | None (public boutique identity) | Phone & UPI are public business details | Direct PostgREST SELECT |
| **`profiles`** | `SELECT` | `authenticated` | **YES** | Public store branding | None (sellers can read boutique profiles) | None | Direct PostgREST SELECT |
| **`profiles`** | `INSERT` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`profiles`** | `INSERT` | `authenticated` | **YES** | `id = auth.uid()` | Matches authenticated user ID | `id` | Direct PostgREST INSERT |
| **`profiles`** | `UPDATE` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`profiles`** | `UPDATE` | `authenticated` | **YES** | `id = auth.uid()` | Cannot update another seller's profile | `store_name`, `upi_id`, `phone_number` | Direct PostgREST UPDATE |
| **`profiles`** | `DELETE` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`profiles`** | `DELETE` | `authenticated` | **NO** | Profile deletion guard | Guarded by `drops.seller_id ON DELETE RESTRICT` | All | Blocked via FK / No DELETE policy |
|---|---|---|---|---|---|---|---|
| **`drops`** | `SELECT` | `anon` | **YES** | Live drops only | `status = 'live'` (draft/closed drops hidden) | None | Direct PostgREST SELECT |
| **`drops`** | `SELECT` | `authenticated` | **YES** | `seller_id = auth.uid()` | Can read all own drops (`draft`, `live`, `closed`) | None | Direct PostgREST SELECT |
| **`drops`** | `INSERT` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`drops`** | `INSERT` | `authenticated` | **YES** | `seller_id = auth.uid()` | Enforced via `WITH CHECK (seller_id = auth.uid())` | `seller_id` | Direct PostgREST INSERT |
| **`drops`** | `UPDATE` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`drops`** | `UPDATE` | `authenticated` | **YES** | `seller_id = auth.uid()` | Enforced via `USING / WITH CHECK (seller_id = auth.uid())` | `status`, `shipping_fee_paisa` | Direct PostgREST UPDATE |
| **`drops`** | `DELETE` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`drops`** | `DELETE` | `authenticated` | **YES** | `seller_id = auth.uid()` | Blocked by FK if products or orders exist | All | Direct PostgREST DELETE |
|---|---|---|---|---|---|---|---|
| **`products`** | `SELECT` | `anon` | **YES** | Live drops only | `EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.status = 'live')` | None | Direct PostgREST SELECT |
| **`products`** | `SELECT` | `authenticated` | **YES** | Seller's own drops | `EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.seller_id = auth.uid())` | None | Direct PostgREST SELECT |
| **`products`** | `INSERT` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`products`** | `INSERT` | `authenticated` | **YES** | Seller's own drops | `WITH CHECK (EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.seller_id = auth.uid()))` | `drop_id`, `price_paisa` | Direct PostgREST INSERT |
| **`products`** | `UPDATE` | `anon` | **NO** | N/A | Direct mutation forbidden (state changes must traverse RPC) | `status`, `reserved_at`, `price_paisa` | Denied by default RLS (RPC only) |
| **`products`** | `UPDATE` | `authenticated` | **YES** | Seller's own drops | `USING / WITH CHECK (EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.seller_id = auth.uid()))` | `title`, `size`, `price_paisa` | Direct PostgREST UPDATE |
| **`products`** | `DELETE` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`products`** | `DELETE` | `authenticated` | **YES** | Seller's own drops | Blocked by FK if referenced in `order_items` (`RESTRICT`) | All | Direct PostgREST DELETE |
|---|---|---|---|---|---|---|---|
| **`orders`** | `SELECT` | `anon` | **CONDITIONAL** | Token-gated receipt read | `order_token::text = (header 'x-order-token')` (arbitrary reads denied) | `buyer_name`, `buyer_phone`, `shipping_address` | Direct PostgREST with header / RPC |
| **`orders`** | `SELECT` | `authenticated` | **YES** | Seller's own drops | `EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid())` | Customer PII | Direct PostgREST SELECT |
| **`orders`** | `INSERT` | `anon` | **NO** | N/A | Direct REST INSERT blocked; must traverse `create_order_with_reservation` RPC | `subtotal_paisa`, `total_paisa`, `status` | Atomic RPC Only |
| **`orders`** | `INSERT` | `authenticated` | **NO** | N/A | Orders created exclusively via atomic reservation engine | All | Atomic RPC Only |
| **`orders`** | `UPDATE` | `anon` | **NO** | N/A | Buyers cannot alter totals, status, or delivery | All | Denied by default RLS |
| **`orders`** | `UPDATE` | `authenticated` | **YES** | Seller's own drops | `USING / WITH CHECK (EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid()))` | `status`, `tracking_number` | Direct PostgREST UPDATE / RPC |
| **`orders`** | `DELETE` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`orders`** | `DELETE` | `authenticated` | **CONDITIONAL** | Seller's own drops | Denied if `status IN ('paid', 'shipped')` (trigger); denied if referenced by active product holds | Financial & legal records | Guarded by trigger & FK |
|---|---|---|---|---|---|---|---|
| **`order_items`** | `SELECT` | `anon` | **CONDITIONAL** | Token-gated receipt read | `EXISTS (SELECT 1 FROM orders WHERE orders.id = order_items.order_id AND orders.order_token::text = (header 'x-order-token'))` | Purchase history | Direct PostgREST with header / RPC |
| **`order_items`** | `SELECT` | `authenticated` | **YES** | Seller's own drops | `EXISTS (SELECT 1 FROM orders JOIN drops ON drops.id = orders.drop_id WHERE orders.id = order_items.order_id AND drops.seller_id = auth.uid())` | None | Direct PostgREST SELECT |
| **`order_items`** | `INSERT` | `anon` | **NO** | N/A | Direct REST INSERT blocked; line items inserted via atomic RPC | `price_at_purchase_paisa` | Atomic RPC Only |
| **`order_items`** | `INSERT` | `authenticated` | **NO** | N/A | Line items inserted via atomic checkout RPC | All | Atomic RPC Only |
| **`order_items`** | `UPDATE` | `anon` | **NO** | N/A | Immutable financial line items | All | Denied by default RLS |
| **`order_items`** | `UPDATE` | `authenticated` | **NO** | N/A | Immutable financial line items | All | Denied by default RLS |
| **`order_items`** | `DELETE` | `anon` | **NO** | N/A | Blocked by default | All | Denied by default RLS |
| **`order_items`** | `DELETE` | `authenticated` | **NO** | N/A | Direct line-item deletion blocked; cascades when parent order is deleted | All | Denied by default RLS |

---

## 3. Critical Security Boundaries & Invariants

### 3.1 Seller Isolation Invariant
* **Rule:** Seller A must NEVER read, update, or delete Seller B's data across any table (`profiles`, `drops`, `products`, `orders`, `order_items`).
* **Derivation Chain:**
  * `profiles`: `id = auth.uid()`
  * `drops`: `seller_id = auth.uid()`
  * `products`: `products.drop_id = drops.id AND drops.seller_id = auth.uid()`
  * `orders`: `orders.drop_id = drops.id AND drops.seller_id = auth.uid()`
  * `order_items`: `order_items.order_id = orders.id AND orders.drop_id = drops.id AND drops.seller_id = auth.uid()`

### 3.2 Order Privacy & Data Minimization (India DPDP Act 2023 Compliance)
* **Rule:** Unauthenticated buyers MUST NOT have open `SELECT` on `orders`. An attacker querying `/rest/v1/orders` must receive zero rows.
* **Token-Scoped Access:** Buyers can read order details and line items ONLY when supplying the cryptographically unguessable UUIDv4 `order_token` via the `x-order-token` request header.
* **Direct INSERT Prohibition:** Anonymous users CANNOT execute direct REST `INSERT` into `orders` or `order_items`. Bypassing this would allow client-side price tampering or unheld inventory creation. All order placement is delegated to the atomic `create_order_with_reservation` RPC.

### 3.3 Inventory Leakage Prevention
* **Rule:** Products belonging to `draft` or `closed` drops MUST NOT be visible to anonymous buyers.
* **Predicate:** `drops.status = 'live'` required for public product read.
