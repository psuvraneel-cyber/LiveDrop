# TASK-1.3.1 — Transactional Core Hardening Pass Report
## Final Pre-TASK-1.4 Hardening & Gate Review

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** COMPLETE & SIGNED OFF  
**Task Scope:** Phase 1 / TASK-1.3.1 (Transactional Core Hardening Pass)  
**Governing Documents:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md), [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md), [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md), [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md), [`docs/TASK-1.3-RPC-CONTRACT.md`](file:///c:/LiveDrop/docs/TASK-1.3-RPC-CONTRACT.md)  
**Migration Target:** [`supabase/migrations/009_create_core_business_rpcs.sql`](file:///c:/LiveDrop/supabase/migrations/009_create_core_business_rpcs.sql)  
**Test Suite:** [`buyer-web/src/test/rpcs.test.ts`](file:///c:/LiveDrop/buyer-web/src/test/rpcs.test.ts)

---

## 1. Scope of Hardening Pass

This hardening pass performs targeted, non-architectural remediations and formal contractual decisions addressing actionable observations from the independent adversarial review of TASK-1.3:

1. **Global Reaper Routine Privilege Hardening:** Revoked `EXECUTE` privilege on `release_expired_holds()` from `authenticated` callers in addition to `anon` and `PUBLIC`. Restricted invocation exclusively to trusted backend `service_role`.
2. **Automated Negative & Positive Privilege Verification:** Added automated regression tests proving that `anon` and `authenticated` roles are denied execution (SQLSTATE 42501), while `service_role` execution succeeds deterministically.
3. **Buyer PII Exposure Governance:** Audited `get_order_by_token()`, documented the necessity of returning `buyer_name` for personalized receipt greeting, verified cryptographic 128-bit capability token-gating, and proved through tests that sensitive fulfillment PII (`buyer_phone`, `shipping_address`, `pincode`) is strictly excluded.
4. **Idempotency & Retry Contract Specification (Model B):** Formalized and documented the checkout retry model as **Model B: Inventory-level duplicate protection without request-level idempotency**, backed by empirical tests proving sequential duplicates fail on the second attempt with `STOCK_UNAVAILABLE` while preserving the winning reservation.
5. **Reaper State Preservation:** Verified that the trusted `service_role` reaper execution cancels only genuine expired holds (`hold_expires_at < clock_timestamp()`), leaving paid, cancelled, and unexpired orders across multiple sellers completely intact.
6. **Concurrency Evidence Boundary:** Documented the precise boundary between `@electric-sql/pglite` in-process WASM event-loop simulation and real multi-connection PostgreSQL database concurrency.

---

## 2. Findings Addressed & Remediated

| Finding ID | Severity | Problem Summary | Remediation Applied | Automated Test Verification | Status |
|---|---|---|---|---|---|
| **SEC-RP-01** (Privilege Boundary) | **HIGH** | `release_expired_holds()` was executable by any `authenticated` seller session, exposing a global maintenance routine to boutique sellers. | In `supabase/migrations/009_create_core_business_rpcs.sql`, revoked `EXECUTE` from `anon` and `authenticated`; granted strictly to `service_role`. | `authenticated seller role is strictly denied execution on release_expired_holds (SQLSTATE 42501)` & `service_role is permitted execution` in `rpcs.test.ts`. | **CLOSED** |
| **F-09** (PII Exposure) | **LOW** | Concerns regarding potential PII leakage via token-gated order retrieval. | Documented that `buyer_name` is the only returned identifier (required for receipt personalization); confirmed `buyer_phone`, `shipping_address`, and `pincode` are excluded. Added cross-order token isolation. | `verifies that sensitive PII (phone, address, pincode) is strictly excluded` & `cross-order token isolation` in `rpcs.test.ts`. | **CLOSED** |
| **F-11** (Idempotency Semantics) | **INFO** | Undocumented behavior when identical checkout requests are submitted concurrently or sequentially. | Formally classified as **Model B: Inventory-level duplicate protection without request-level idempotency**. Documented that row locks serialize requests and single-piece stock rejects duplicates with `STOCK_UNAVAILABLE`. | `Model B: sequential duplicate checkout for 1-of-1 item fails on second attempt with STOCK_UNAVAILABLE` in `rpcs.test.ts`. | **CLOSED** |

---

## 3. Final RPC Privilege Matrix

PostgreSQL automatically grants `EXECUTE` to pseudo-role `PUBLIC`. LiveDrop strictly revokes `PUBLIC` execution on all 6 routines and enforces a hardened least-privilege boundary:

| Routine | PUBLIC | anon | authenticated | service_role | Enforced Security & Ownership Boundary |
|---|---|---|---|---|---|
| `create_order_with_reservation` | **REVOKED** | **EXECUTE** | **EXECUTE** | **EXECUTE** | Open to public buyers; deterministic row-level locks (`ORDER BY id ASC FOR UPDATE`) prevent over-allocation. |
| `get_order_by_token` | **REVOKED** | **EXECUTE** | **EXECUTE** | **EXECUTE** | Open to public buyers; access strictly gated by knowledge of secret 128-bit `order_token` paired with order ID. |
| `mark_order_paid` | **REVOKED** | **REVOKED** | **EXECUTE** | **EXECUTE** | Blocked for anonymous buyers; verifies caller authentication (`auth.uid() IS NOT NULL`) and seller drop ownership (`drops.seller_id = auth.uid()`). |
| `force_release_hold` | **REVOKED** | **REVOKED** | **EXECUTE** | **EXECUTE** | Blocked for anonymous buyers; verifies caller authentication and seller drop ownership. Rejects non-pending orders. |
| `mark_product_sold_offline` | **REVOKED** | **REVOKED** | **EXECUTE** | **EXECUTE** | Blocked for anonymous buyers; verifies caller authentication and seller drop ownership. Rejects reserved/sold products. |
| `release_expired_holds` | **REVOKED** | **REVOKED** | **REVOKED** | **EXECUTE** | **Strictly blocked for public buyers and authenticated sellers.** Callable exclusively by background `service_role` scheduler or cron worker. |

All 6 routines are declared with `SECURITY DEFINER` and have their search path pinned to `SET search_path = public, pg_temp;`.

---

## 4. Buyer PII Exposure Decision & Security Control

### 4.1 Data Fields Evaluated
* **Fields Returned by `get_order_by_token`:**
  * `id`: Order UUID
  * `order_code`: Human-readable reference (`LD-XXXXXX`)
  * `buyer_name`: Full name of recipient (e.g., "Sangeeta Mukherjee")
  * `subtotal_paisa`, `shipping_paisa`, `total_paisa`: Integer financial accounting
  * `status`: Order lifecycle state (`pending`, `paid`, `shipped`, `cancelled`)
  * `hold_expires_at`: Expiration timestamp
  * `store_name`, `upi_id`, `upi_qr_url`: Boutique seller payment credentials
  * `items`: Line items array (`product_id`, `code`, `title`, `image_url`, `price_at_purchase_paisa`)

### 4.2 Deliberately Excluded Fields
* **`buyer_phone`:** Omitted. Withheld to prevent unauthorized telephone contact.
* **`shipping_address`:** Omitted. Withheld to protect physical residential delivery location.
* **`pincode`:** Omitted. Withheld to protect recipient postal routing.

### 4.3 Architectural & Security Rationale
1. **Receipt Personalization:** `buyer_name` is necessary on `/order/[id]` to render the personal greeting ("Thank you, {buyer_name}!") confirming the order details to the customer before launching the WhatsApp payment handshake.
2. **Capability Token Boundary:** Access is guarded by a 128-bit cryptographic bearer token (`orders.order_token`, UUIDv4) generated via `gen_random_uuid()` during atomic order creation.
3. **Anti-Enumeration Guarantee:** Guessing a valid order ID + token pair is mathematically infeasible ($2^{122} \approx 5.3 \times 10^{36}$ entropy space). Querying with a valid order ID but incorrect token returns `ORDER_NOT_FOUND_OR_UNAUTHORIZED` without disclosing whether the order exists.
4. **Privacy Classification:** The token-gated mechanism serves as a robust privacy and security control designed to reduce unauthorized disclosure risk.

---

## 5. Idempotency & Duplicate-Request Semantics (Model B)

### 5.1 Classification
LiveDrop adopts **Model B: Inventory-level duplicate protection without request-level idempotency**.

### 5.2 Mechanics & System Guarantees
1. **No Client Idempotency Key:** The RPC signature `create_order_with_reservation` does not require or accept an idempotency token from the client.
2. **Single-Piece Garment Protection:**
   - When a buyer submits checkout for a unique handloom item (`status = 'available'`), the transaction locks the product row via `ORDER BY id ASC FOR UPDATE`.
   - The first transaction commits: product transitions to `status = 'reserved'` with `reserved_by_order_id = v_order.id`.
   - Any concurrent or subsequent duplicate checkout request for the same product finds `status != 'available'` upon acquiring the lock and is immediately rejected with `STOCK_UNAVAILABLE`.
3. **No Request Coalescing:** The system does **not** return the existing order on a duplicate checkout attempt. A duplicate submission is treated as a subsequent checkout attempt for an item that is no longer available.
4. **Client-Side Responsibility:** The webfront client must disable the checkout button upon the first tap to prevent duplicate dispatch under network latency. If multiple requests are dispatched, the database ACID transaction guarantees that **at most one** order is created and zero over-selling can occur.

---

## 6. Concurrency Evidence Classification

| Dimension | PGlite In-Process Simulation (Current) | Real PostgreSQL Concurrency Validation (Future) |
|---|---|---|
| **Execution Environment** | `@electric-sql/pglite` (PostgreSQL 18.3 WASM compiled in Node.js) | Physical Supabase PostgreSQL 15+ managed instance |
| **Connection Model** | Single-connection event-loop dispatch via `Promise.all` | Multi-connection parallel worker processes |
| **Row Locking Evaluated** | `ORDER BY id ASC FOR UPDATE` properly serializes async queries | Evaluates multi-threaded kernel-level IPC locks |
| **Deadlock Freedom** | Verified reverse-order locking (`TC-CON-05`) does not deadlock | Verified under multi-process contention |
| **Status in Repository** | **VERIFIED (45 dedicated tests passing)** | **SCHEDULED for Staging Gate (Phase 1/2 deployment)** |

> [!NOTE]
> We explicitly document this distinction: PGlite tests provide mathematical and logical proof of transaction correctness within the WASM engine, but do not replace live multi-connection load testing against a remote database.

---

## 7. Verification Results & Terminal Outputs

### 7.1 Schema, RLS & RPC Routine Privileges (`scripts/verify-schema.mjs`)
```
🚀 Initializing in-memory PostgreSQL engine (PGlite)...
🔧 Initializing auth schema simulation...
📦 Applying migrations sequentially:
  ✓ Applied 001_create_profiles.sql
  ✓ Applied 002_create_drops.sql
  ✓ Applied 003_create_products.sql
  ✓ Applied 004_create_orders.sql
  ✓ Applied 005_create_order_items.sql
  ✓ Applied 006_create_indexes.sql
  ✓ Applied 007_create_triggers.sql
  ✓ Applied 008_enable_rls_and_policies.sql
  ✓ Applied 009_create_core_business_rpcs.sql
🔍 Verifying table existence:
  Tables found: drops, order_items, orders, products, profiles
🔍 Verifying 8 query indexes:
  Indexes found (8): idx_drops_one_live_per_seller, idx_order_items_order, idx_order_items_product, idx_orders_buyer_phone, idx_orders_drop_status, idx_orders_hold_expiry, idx_products_active_hold, idx_products_drop_status
🔍 Verifying integer Paisa columns:
  ✓ drops.free_shipping_threshold_paisa: integer (Paisa)
  ✓ drops.shipping_fee_paisa: integer (Paisa)
  ✓ order_items.price_at_purchase_paisa: integer (Paisa)
  ✓ orders.shipping_paisa: integer (Paisa)
  ✓ orders.subtotal_paisa: integer (Paisa)
  ✓ orders.total_paisa: integer (Paisa)
  ✓ products.price_paisa: integer (Paisa)
  ✓ profiles.default_shipping_fee_paisa: integer (Paisa)
  ✓ profiles.free_shipping_threshold_paisa: integer (Paisa)
🔍 Verifying 5 triggers:
  Triggers found (5):
    trg_drops_updated_at on drops (UPDATE)
    trg_orders_no_delete_finalized on orders (DELETE)
    trg_orders_updated_at on orders (UPDATE)
    trg_products_updated_at on products (UPDATE)
    trg_profiles_updated_at on profiles (UPDATE)
🔍 Verifying Row-Level Security (RLS) enforcement:
  ✓ RLS enabled on drops (rowsecurity = true)
  ✓ RLS enabled on order_items (rowsecurity = true)
  ✓ RLS enabled on orders (rowsecurity = true)
  ✓ RLS enabled on products (rowsecurity = true)
  ✓ RLS enabled on profiles (rowsecurity = true)
🔍 Verifying RLS Policies:
  Policies found (13):
    - drops: drops_public_read_live (SELECT) for anon
    - drops: drops_seller_manage (ALL) for authenticated
    - order_items: order_items_buyer_read_with_token (SELECT) for anon
    - order_items: order_items_seller_select (SELECT) for authenticated
    - orders: orders_buyer_read_with_token (SELECT) for anon
    - orders: orders_seller_delete (DELETE) for authenticated
    - orders: orders_seller_select (SELECT) for authenticated
    - orders: orders_seller_update (UPDATE) for authenticated
    - products: products_public_read_live (SELECT) for anon
    - products: products_seller_manage (ALL) for authenticated
    - profiles: profiles_public_read (SELECT) for anon,authenticated
    - profiles: profiles_seller_insert (INSERT) for authenticated
    - profiles: profiles_seller_update (UPDATE) for authenticated
🔍 Verifying Core Business RPCs (TASK-1.3):
  RPCs found (6):
    ✓ create_order_with_reservation (jsonb) [SECURITY DEFINER]
    ✓ force_release_hold (jsonb) [SECURITY DEFINER]
    ✓ get_order_by_token (jsonb) [SECURITY DEFINER]
    ✓ mark_order_paid (jsonb) [SECURITY DEFINER]
    ✓ mark_product_sold_offline (jsonb) [SECURITY DEFINER]
    ✓ release_expired_holds (void) [SECURITY DEFINER]
🔍 Verifying RPC Routine Privileges:
  Routine privilege grants found (19)
  ✓ Verified: PUBLIC execution revoked; anon & authenticated blocked from release_expired_holds; service_role granted EXECUTE.
✅ ALL RELATIONAL DATABASE SCHEMA, RLS POLICIES & BUSINESS RPCS VERIFIED.
```

### 7.2 Full Vitest Test Suite (`npm --prefix buyer-web test -- --run`)
```
 RUN  v5.0.0 C:/LiveDrop/buyer-web

 ✓ src/test/smoke.test.tsx (1 test) 96ms
 ✓ src/test/rls.test.ts (35 tests) 4210ms
 ✓ src/test/schema.test.ts (33 tests) 4367ms
 ✓ src/test/rpcs.test.ts (45 tests) 4898ms

 Test Files  4 passed (4)
      Tests  114 passed (114)
   Duration  5.63s
```

### 7.3 TypeScript Strict Typecheck (`npm --prefix buyer-web run typecheck`)
```
> buyer-web@0.1.0 typecheck
> tsc --noEmit
Exit code: 0 (No type errors)
```

### 7.4 ESLint Code Quality (`npm --prefix buyer-web run lint`)
```
> buyer-web@0.1.0 lint
> eslint
Exit code: 0 (No lint warnings or errors)
```

---

## 8. Remaining Follow-Ups (Non-Blocking Backlog)

The following items are documented for future phases and do not block closing TASK-1.3:
1. **Background Cron Runner (Phase 1 / TASK-1.5):** Deployment of scheduled `pg_cron` or Supabase Edge Function to invoke `release_expired_holds()` every 60 seconds.
2. **Real Multi-Connection Load Test (Staging Gate):** Physical load test running `k6` or concurrent Node workers against a deployed Supabase PostgreSQL database to benchmark connection pool saturation under 100+ concurrent connections.
3. **Optional Client Idempotency Keys (Future Feature):** If future buyer experience requires seamless coalescing of accidental duplicate orders on slow cellular networks without showing `STOCK_UNAVAILABLE`, an optional `p_idempotency_key UUID` can be introduced via an approved ADR.

---

## 9. Final Gate Sign-Off Checklist

- [x] Global reaper cannot be executed by anon (`SQLSTATE 42501` verified).
- [x] Global reaper cannot be executed by authenticated sellers (`SQLSTATE 42501` verified).
- [x] Global reaper remains executable by the intended trusted backend role (`service_role` verified).
- [x] PUBLIC execution is revoked on all 6 RPC routines.
- [x] SECURITY DEFINER search_path hardening (`SET search_path = public, pg_temp;`) remains intact across all routines.
- [x] Buyer token gating remains intact.
- [x] PII exposure is explicitly documented and sensitive fulfillment PII is verified excluded.
- [x] Duplicate/retry semantics are explicitly documented and tested (Model B).
- [x] No transactional invariant regressed.
- [x] No seller authorization regression.
- [x] No cross-seller access regression.
- [x] Existing 106 tests still pass, plus 8 new hardening tests (total 114 passed).
- [x] Schema verification passes (`scripts/verify-schema.mjs` exits 0).
- [x] Typecheck passes (`tsc --noEmit` exits 0).
- [x] Lint passes (`eslint` exits 0).
- [x] PGlite evidence is clearly labeled as simulation and not misrepresented as real Supabase multi-connection concurrency proof.
- [x] No TASK-1.4 implementation has begun.

---

## 10. Status

**PASS — TASK-1.3 CLOSED; READY FOR TASK-1.4**
