# TASK-1.3 — Core Business RPC Contract Specification

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Task Scope:** Phase 1 / TASK-1.3 (Atomic Order Creation, Reservation & Payment Transition RPCs)  
**Governing Documents:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md), [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md), [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md), [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)  
**Migration File:** [`supabase/migrations/009_create_core_business_rpcs.sql`](file:///c:/LiveDrop/supabase/migrations/009_create_core_business_rpcs.sql)

---

## 1. Executive Architecture Summary

In LiveDrop, direct client table mutations (`INSERT`, `UPDATE`, `DELETE`) on orders and inventory state are strictly prohibited by Row-Level Security (RLS). All transactional state transitions—order creation, inventory reservation, hold expiration/release, payment confirmation, and manual sales—are executed through **atomic PostgreSQL Stored Procedures (RPCs)** running with `SECURITY DEFINER` privileges and hardened search paths.

### Core Architectural Guardrails
1. **Integer Paisa Only (ADR-009):** All pricing, subtotals, shipping calculations, and order totals are computed strictly using integer Paisa (`150000` = ₹1,500.00). No floating-point or client-supplied amounts are ever trusted.
2. **Deterministic Lock Ordering:** Multi-product row locks are strictly acquired via `ORDER BY id ASC` to mathematically eliminate transaction deadlocks (formal proof in [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md)).
3. **Reservation Owned by Order:** Inventory holds are explicitly associated with an authoritative `orders.id` foreign key (`products.reserved_by_order_id`). Ephemeral browser sessions are never used as reservation owners.
4. **Hardened Execution Context:** All RPCs are defined with `SECURITY DEFINER SET search_path = public, pg_temp;`. Default `PUBLIC` execute privileges are revoked; execution is granted on a strict least-privilege basis to `anon`, `authenticated`, or `service_role`.

---

## 2. Comprehensive Routine Interface Directory

| Routine Name | Primary Role / Actor | Security | Granted Roles | Purpose |
|---|---|---|---|---|
| `create_order_with_reservation` | Public Buyer (`anon`) | `SECURITY DEFINER` | `anon`, `authenticated`, `service_role` | Atomic cart validation, deterministic locking, price calculation, order creation, and 15-minute inventory hold |
| `mark_order_paid` | Boutique Seller (`authenticated`) | `SECURITY DEFINER` | `authenticated`, `service_role` | Payment confirmation, seller ownership verification, contested hold reclamation check, transition to `paid` and `sold` |
| `release_expired_holds` | Background System / Maintenance | `SECURITY DEFINER` | `service_role` | Reaper routine releasing genuine expired holds (`hold_expires_at < clock_timestamp()`) and cancelling stale pending orders. Execution restricted strictly to backend `service_role` |
| `force_release_hold` | Boutique Seller (`authenticated`) | `SECURITY DEFINER` | `authenticated`, `service_role` | Seller manual cancellation of a pending buyer hold, freeing garments back to `available` |
| `mark_product_sold_offline` | Boutique Seller (`authenticated`) | `SECURITY DEFINER` | `authenticated`, `service_role` | Manual walk-in / off-platform sale override, transitioning available item directly to `sold` |
| `get_order_by_token` | Public Buyer (`anon`) | `SECURITY DEFINER` | `anon`, `authenticated`, `service_role` | Secret token-gated order retrieval designed to reduce unauthorized disclosure risk |


---

## 3. Routine Specifications & Contracts

### 3.1 `create_order_with_reservation`

#### Signature
```sql
CREATE OR REPLACE FUNCTION public.create_order_with_reservation(
    p_drop_id UUID,
    p_product_ids UUID[],
    p_buyer_name TEXT,
    p_buyer_phone TEXT,
    p_shipping_address TEXT,
    p_pincode TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
```

#### Inputs
* `p_drop_id` (`UUID`): ID of the drop session.
* `p_product_ids` (`UUID[]`): Array of requested product IDs.
* `p_buyer_name` (`TEXT`): Full name of buyer (1 to 255 characters).
* `p_buyer_phone` (`TEXT`): 10-digit Indian mobile number (`^[6-9]\d{9}$`).
* `p_shipping_address` (`TEXT`): Physical delivery address (10 to 1000 characters).
* `p_pincode` (`TEXT`): 6-digit Indian postal code (`^\d{6}$`).

#### Execution Logic & Transaction Boundaries
1. **Input Validation:**
   - Validates buyer name, address, phone format (`^[6-9]\d{9}$`), and pincode format (`^\d{6}$`).
   - Normalizes input arrays: canonicalizes and deduplicates `p_product_ids` deterministically via `SELECT ARRAY(SELECT DISTINCT unnest(p_product_ids))`.
   - Rejects empty cart (`EMPTY_CART`).
   - Enforces cart size limit: cart must contain $\le 10$ distinct items (`EXCEEDS_CART_LIMIT`).
2. **Drop Verification:**
   - Locks drop record (`SELECT ... FOR SHARE`) and verifies it exists and is currently in status `'live'` (`DROP_NOT_FOUND`, `DROP_NOT_ACTIVE`).
3. **Deterministic Row Locking:**
   - Queries and locks candidate products in strictly ascending UUID order:
     ```sql
     SELECT id, price_paisa, drop_id, status
     FROM public.products
     WHERE id = ANY(v_unique_ids)
     ORDER BY id ASC
     FOR UPDATE;
     ```
4. **Inventory & Integrity Verification:**
   - Asserts all requested products were found (`STOCK_UNAVAILABLE`).
   - Asserts all products belong to the specified `p_drop_id` (`CROSS_DROP_ITEMS_NOT_ALLOWED`).
   - Asserts all products have `status = 'available'` (`STOCK_UNAVAILABLE`). If any item is reserved or sold, returns array of `unavailable_product_ids` and transaction makes zero mutations.
5. **Authoritative Price Computation:**
   - Sums database `price_paisa` for subtotal. Never trusts client prices.
   - Calculates `shipping_paisa`: if `subtotal_paisa >= drop.free_shipping_threshold_paisa`, shipping is `0`; otherwise, applies `drop.shipping_fee_paisa`.
   - Computes integer sum `total_paisa = subtotal_paisa + shipping_paisa`.
6. **Order & Hold Creation:**
   - Generates unique order code: `'LD-' || UPPER(SUBSTRING(MD5(gen_random_uuid()::text) FROM 1 FOR 6))`.
   - Generates cryptographically secure `order_token = gen_random_uuid()`.
   - Sets 15-minute hold timestamp: `v_hold_expires_at := clock_timestamp() + INTERVAL '15 minutes'`.
   - Inserts into `orders` with `status = 'pending'`.
   - Inserts snapshot records into `order_items` with `price_at_purchase_paisa`.
   - Updates `products`:
     ```sql
     UPDATE public.products
     SET status = 'reserved',
         reserved_at = clock_timestamp(),
         reserved_by_order_id = v_order_id,
         version = version + 1
     WHERE id = ANY(v_unique_ids);
     ```
7. **Atomic Return:**
   ```json
   {
     "success": true,
     "order_id": "UUID",
     "order_code": "LD-XXXXXX",
     "order_token": "UUID",
     "subtotal_paisa": 260000,
     "shipping_paisa": 8000,
     "total_paisa": 268000,
     "hold_expires_at": "ISO-TIMESTAMP"
   }
   ```
8. **Duplicate Request & Idempotency Semantics (Model B):**
   - **Classification:** Inventory-level duplicate protection without request-level idempotency.
   - **Behavior:** The function does not accept an idempotency key or coalesce duplicate requests. Instead, mutual exclusion is enforced via deterministic row locking (`ORDER BY id ASC FOR UPDATE`) and stock validation (`status = 'available'`).
   - **Concurrent Submissions:** If two identical checkout requests for the same single-piece garment arrive simultaneously, PostgreSQL serializes them across the product lock. Exactly 1 request succeeds and acquires the hold; competing concurrent requests receive `STOCK_UNAVAILABLE` with zero database modifications.
   - **Sequential Retries:** A sequential duplicate submission for an already-reserved item is rejected with `STOCK_UNAVAILABLE`.
   - **Independent Orders:** Submissions for distinct available inventory items succeed independently and generate separate orders.
   - **Client Contract:** Clients must disable the submit button upon initial tap to prevent accidental multiple submissions; the database guarantees zero over-selling if duplicate requests occur.

---

### 3.2 `mark_order_paid`

#### Signature
```sql
CREATE OR REPLACE FUNCTION public.mark_order_paid(
    p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
```

#### Seller Ownership & Contested Expiry Resolution
1. **Caller Verification:**
   - Extracts authenticated seller `v_seller_id := auth.uid()`.
   - Rejects unauthenticated calls with `UNAUTHORIZED`.
2. **Order & Drop Ownership Lock:**
   - Locks order row (`FOR UPDATE`) and joins drop row (`FOR UPDATE`).
   - Asserts `drop.seller_id = v_seller_id`. Returns `FORBIDDEN` if caller attempts to confirm another seller's order.
3. **Idempotency:**
   - If order is already `paid` or `shipped`, immediately returns `{"success": true, "already_paid": true}` without re-mutating rows.
4. **Order State Validation:**
   - Rejects orders that are not in `pending` or `cancelled` with `INVALID_ORDER_STATE`.
5. **Deterministic Product Lock & Contested Hold Check:**
   - Locks all products associated with the order via `order_items`:
     ```sql
     SELECT id, status, reserved_by_order_id
     FROM public.products
     WHERE id = ANY(v_product_ids)
     ORDER BY id ASC
     FOR UPDATE;
     ```
   - **Contested Collision Check:** If the hold expired and any product has since been claimed by another buyer (`status = 'sold'` OR `(status = 'reserved' AND reserved_by_order_id != p_order_id)`), the confirmation strictly aborts and returns:
     ```json
     {
       "success": false,
       "error": "PRODUCT_ALREADY_RECLAIMED",
       "message": "One or more items in this order were claimed by another buyer after the hold expired."
     }
     ```
   - **Uncontested Re-acquisition:** If the hold expired but all items remain unreserved (`status = 'available'`), the seller's payment confirmation successfully re-acquires the items.
6. **State Transitions:**
   - Updates `orders`: `status = 'paid'`, `paid_at = clock_timestamp()`.
   - Updates `products`: `status = 'sold'`, `reserved_at = NULL`, `reserved_by_order_id = NULL`, `version = version + 1`.
7. **Return:**
   ```json
   {
     "success": true
   }
   ```

---

### 3.3 `release_expired_holds`

#### Signature
```sql
CREATE OR REPLACE FUNCTION public.release_expired_holds()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
```

#### Execution Logic
1. **Find Genuine Expired Orders:**
   - Selects IDs of orders where `status = 'pending'` AND `hold_expires_at < clock_timestamp()`.
   - Locks affected order rows `FOR UPDATE SKIP LOCKED` to allow safe, concurrent execution across distributed workers without contention.
2. **Atomic Inventory Reversion:**
   - Selects and locks associated products in `ORDER BY id ASC FOR UPDATE`.
   - Reverts products that are currently reserved by these expired orders:
     ```sql
     UPDATE public.products
     SET status = 'available',
         reserved_at = NULL,
         reserved_by_order_id = NULL,
         version = version + 1
     WHERE id = ANY(v_product_ids)
       AND status = 'reserved'
       AND reserved_by_order_id = ANY(v_order_ids);
     ```
3. **Order Status Update:**
   - Transitions orders to `status = 'cancelled'`.
4. **Safety Invariants:**
   - Never modifies orders in `paid` or `shipped` status.
   - Idempotent and safe to invoke repeatedly.

---

### 3.4 `get_order_by_token`

#### Signature
```sql
CREATE OR REPLACE FUNCTION public.get_order_by_token(
    p_order_id UUID,
    p_order_token UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
```

#### Execution Logic & Data Protection
1. **Token Validation:**
   - Queries `orders` where `id = p_order_id AND order_token = p_order_token`.
   - If no record matches, returns `{"success": false, "error": "ORDER_NOT_FOUND_OR_UNAUTHORIZED"}`.
2. **Payload Construction:**
   - Joins `drops` and `profiles` to extract boutique branding (`store_name`, `upi_id`, `upi_qr_url`).
   - Aggregates `order_items` joined with `products` to produce a complete line-item breakdown.
3. **Return:**
   ```json
   {
     "success": true,
     "order": {
       "id": "UUID",
       "order_code": "LD-XXXXXX",
       "buyer_name": "Sangeeta Mukherjee",
       "subtotal_paisa": 260000,
       "shipping_paisa": 8000,
       "total_paisa": 268000,
       "status": "pending",
       "hold_expires_at": "ISO-TIMESTAMP",
       "store_name": "Mother's Boutique",
       "upi_id": "mothersboutique@okaxis",
       "upi_qr_url": "https://storage.livedrop.store/qrs/mb.webp",
       "items": [
         {
           "product_id": "UUID",
           "code": "#A01",
           "title": "Tussar Silk Saree",
           "image_url": "https://...",
           "price_at_purchase_paisa": 185000
         }
       ]
     }
   }
   ```

4. **Data Protection & PII Minimization Decision:**
   - **Returned PII:** `buyer_name` ONLY (e.g., "Sangeeta Mukherjee").
   - **Fulfillment Justification:** Displayed on the receipt screen (`/order/[id]`) to personalize the order confirmation greeting and assure the buyer of receipt authenticity.
   - **Protection Control:** Token-gated access requiring knowledge of both the order ID (UUIDv4) and the cryptographically random 128-bit `order_token` (UUIDv4).
   - **Enumeration Defense:** Guessing 128-bit tokens is computationally infeasible ($> 5.3 \times 10^{36}$ keyspace). Without the exact token issued in the checkout response, querying an order ID returns `ORDER_NOT_FOUND_OR_UNAUTHORIZED`.
   - **Deliberately Excluded Fields:** `buyer_phone`, `shipping_address`, and `pincode` are **strictly excluded** from the response payload. Although stored in `orders` for courier dispatch, they are never exposed on the public token receipt surface, mitigating unauthorized disclosure risk if a receipt URL is forwarded or opened on a shared device.

---

### 3.5 `force_release_hold`

#### Signature
```sql
CREATE OR REPLACE FUNCTION public.force_release_hold(
    p_order_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
```

#### Seller Manual Cancellation Logic
1. **Caller Verification:** Asserts `auth.uid()` matches the order's drop `seller_id`.
2. **Order State Check:** Asserts `order.status = 'pending'`. Cannot force-release `paid` or `shipped` orders.
3. **Lock & Release:** Locks products via `ORDER BY id ASC FOR UPDATE`, resets `status = 'available'`, clears `reserved_at` and `reserved_by_order_id`. Sets order `status = 'cancelled'`.

---

### 3.6 `mark_product_sold_offline`

#### Signature
```sql
CREATE OR REPLACE FUNCTION public.mark_product_sold_offline(
    p_product_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
```

#### Walk-in / Off-Platform Sale Logic
1. **Caller Verification:** Asserts `auth.uid()` matches `drops.seller_id` for the product's drop.
2. **Product State Verification:**
   - Locks product row `FOR UPDATE`.
   - If `status = 'sold'`, returns `{"success": false, "error": "ALREADY_SOLD"}`.
   - If `status = 'reserved'`, returns `{"success": false, "error": "PRODUCT_RESERVED"}`.
   - If `status = 'available'`, updates `status = 'sold'`, `version = version + 1`.

---

## 4. Routine Privilege & Security Enforcement Matrix

PostgreSQL automatically grants `EXECUTE` on new functions to pseudo-role `PUBLIC`. Migration `009_create_core_business_rpcs.sql` explicitly revokes this default and assigns privileges on a strict least-privilege boundary:

```sql
REVOKE ALL ON FUNCTION public.create_order_with_reservation(UUID, UUID[], TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_order_paid(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.release_expired_holds() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.force_release_hold(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_product_sold_offline(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_order_by_token(UUID, UUID) FROM PUBLIC;
```

### Privilege Grid

| Routine | PUBLIC | anon | authenticated | service_role | Enforced Access Control |
|---|---|---|---|---|---|
| `create_order_with_reservation` | **REVOKED** | **EXECUTE** | **EXECUTE** | **EXECUTE** | Open to public buyers; row-level locks prevent stock over-allocation |
| `get_order_by_token` | **REVOKED** | **EXECUTE** | **EXECUTE** | **EXECUTE** | Open to public buyers; access strictly gated by knowledge of secret `order_token` |
| `mark_order_paid` | **REVOKED** | **REVOKED** | **EXECUTE** | **EXECUTE** | Blocked for anonymous buyers; checks `auth.uid() = drop.seller_id` |
| `force_release_hold` | **REVOKED** | **REVOKED** | **EXECUTE** | **EXECUTE** | Blocked for anonymous buyers; checks `auth.uid() = drop.seller_id` |
| `mark_product_sold_offline` | **REVOKED** | **REVOKED** | **EXECUTE** | **EXECUTE** | Blocked for anonymous buyers; checks `auth.uid() = drop.seller_id` |
| `release_expired_holds` | **REVOKED** | **REVOKED** | **REVOKED** | **EXECUTE** | Blocked for anonymous buyers and authenticated sellers; executable strictly by trusted backend `service_role` worker |

---

## 5. Error Contract Directory

All client RPC invocations return structured JSON error payloads conforming to the following taxonomy:

| Error Code | HTTP Status | Description | Trigger Condition |
|---|---|---|---|
| `EMPTY_CART` | 200 OK | Cart is empty | Array `p_product_ids` is empty or null |
| `EXCEEDS_CART_LIMIT` | 200 OK | Too many items | Array contains $> 10$ distinct items |
| `INVALID_BUYER_NAME` | 200 OK | Malformed name | Name is null or empty |
| `INVALID_PHONE` | 200 OK | Invalid Indian mobile | Phone does not match `^[6-9]\d{9}$` |
| `INVALID_SHIPPING_ADDRESS` | 200 OK | Malformed address | Address is shorter than 10 characters |
| `INVALID_PINCODE` | 200 OK | Invalid Indian postal code | Pincode does not match `^\d{6}$` |
| `DROP_NOT_FOUND` | 200 OK | Drop does not exist | Invalid `p_drop_id` supplied |
| `DROP_NOT_ACTIVE` | 200 OK | Drop not currently live | Drop is in `draft` or `closed` status |
| `CROSS_DROP_ITEMS_NOT_ALLOWED`| 200 OK | Cross-drop cart | Products belong to multiple distinct drops |
| `STOCK_UNAVAILABLE` | 200 OK | One or more items unavailable | Product already reserved or sold (returns `unavailable_product_ids`) |
| `UNAUTHORIZED` | 200 OK | Unauthenticated caller | Caller lacks valid JWT session (`auth.uid() IS NULL`) |
| `ORDER_NOT_FOUND` | 200 OK | Order does not exist | Specified `p_order_id` not found |
| `FORBIDDEN` | 200 OK | Cross-seller mutation | Caller is authenticated but does not own the drop |
| `PRODUCT_ALREADY_RECLAIMED` | 200 OK | Contested hold collision | Hold expired and item was reserved/sold to another buyer |
| `INVALID_ORDER_STATE` | 200 OK | Order not in valid state | Order is not in `pending` or `cancelled` |
| `ALREADY_SOLD` | 200 OK | Offline sale collision | Product is already marked `sold` |
| `PRODUCT_RESERVED` | 200 OK | Offline sale collision | Product is currently held by an active buyer |
| `ORDER_NOT_FOUND_OR_UNAUTHORIZED` | 200 OK | Secret token mismatch | Invalid `p_order_id` or `p_order_token` |
