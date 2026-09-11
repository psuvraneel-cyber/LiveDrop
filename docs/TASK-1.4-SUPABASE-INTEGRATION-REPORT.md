# LiveDrop — TASK-1.4 Completion Report
## Supabase Integration, Realtime Foundation & Development Data/Environment Gate

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** COMPLETE / AUTHORITATIVE BASELINE  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  
**Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  
**API Contract:** [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md)  
**Realtime Specification:** [`docs/14-realtime-contract.md`](file:///c:/LiveDrop/docs/14-realtime-contract.md)  

---

## 1. Scope

TASK-1.4 establishes the application-facing Supabase integration boundary for both the Buyer Web application (`buyer-web`) and Seller Mobile application (`seller-app`). It bridges the database transactional core (TASK-1.1 through TASK-1.3.1) to the upcoming client vertical slices without implementing application screens or UI components.

Specifically delivered:
1. Browser-safe anonymous Supabase client and strict environment validation for `buyer-web`.
2. Mobile authenticated Supabase service and configuration reader for `seller-app`.
3. Strongly typed domain and database models in TypeScript and Dart with integer Paisa enforcement.
4. Typed application data-access layer abstractions separating data queries from presentation components.
5. Typed error classification and mapping layer translating database/RPC error responses to structured application exceptions.
6. Realtime foundation with drop-scoped channel subscription, monotonic entity version defense (`version`), and graceful unsubscription.
7. Deterministic, synthetic development seed fixtures (`supabase/seed.sql`) covering profiles, drops (draft, live, closed), products across statuses, and orders across lifecycle states.
8. Comprehensive automated test suites across web and mobile.

---

## 2. Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                        SUPABASE POSTGRESQL                             │
│       • PostgreSQL Tables (profiles, drops, products, orders)          │
│       • Row-Level Security (RLS) & Security Definer RPCs               │
│       • Realtime Engine (postgres_changes publication)                 │
└──────────────────┬─────────────────────────────────┬───────────────────┘
                   │                                 │
                   │ HTTPS / REST (Anon Key)         │ HTTPS / REST (Bearer JWT)
                   │ Realtime WS (Public Channel)    │ Realtime WS (Seller Channel)
                   ▼                                 ▼
┌──────────────────────────────────────┐ ┌───────────────────────────────┐
│          BUYER WEB FRONT             │ │       SELLER MOBILE APP       │
│      (Next.js 16+ App Router)        │ │        (Flutter Native)       │
├──────────────────────────────────────┤ ├───────────────────────────────┤
│ • src/lib/supabase/client.ts         │ │ • lib/core/services/          │
│ • src/lib/data/buyer-catalog.ts      │ │ • lib/data/repositories/      │
│ • src/lib/realtime/catalog-realtime  │ │ • lib/data/realtime/          │
│ • src/types/domain.ts                │ │ • lib/domain/models/          │
│ • src/lib/errors.ts                  │ │ • lib/core/errors/            │
└──────────────────────────────────────┘ └───────────────────────────────┘
```

Both clients communicate with Supabase via the official client SDKs (`@supabase/supabase-js` and `supabase_flutter`), strictly separated into dedicated data layers so that no UI components make raw database calls.

---

## 3. Client Credential & Environment Model

| Environment Property | Buyer Webfront (`buyer-web`) | Seller Mobile App (`seller-app`) | Backend Daemon / Scheduler (TASK-1.5) |
| :--- | :--- | :--- | :--- |
| **URL Variable** | `NEXT_PUBLIC_SUPABASE_URL` | `SUPABASE_URL` (`--dart-define`) | `SUPABASE_URL` |
| **Key Variable** | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `SUPABASE_ANON_KEY` (`--dart-define`) | `SUPABASE_SERVICE_ROLE_KEY` |
| **Credential Type** | Public Anon Key | Public Anon Key | Secret Service-Role Key |
| **Auth Requirement** | None (Anonymous) | Authenticated Seller JWT (`auth.uid()`) | Internal system authorization |
| **Service-Role Presence** | **STRICTLY PROHIBITED** | **STRICTLY PROHIBITED** | Required for maintenance only |

### Security Safeguards Implemented:
1. `validateBuyerEnv()` inspects the runtime environment and throws an immediate fatal error if any variable containing `SERVICE_ROLE` or `SERVICE_KEY` is detected.
2. `EnvConfig.validate()` in Flutter inspects `SUPABASE_ANON_KEY` and throws a `StateError` if a service-role key is mistakenly supplied.
3. Client configuration files and sample environment files (`.env.example`) contain explicit security headers prohibiting secret commits.

---

## 4. Data Access Matrix

| Entity / Routine | Buyer Webfront (`buyer-web`) | Seller Mobile App (`seller-app`) | Service Role (TASK-1.5) |
| :--- | :--- | :--- | :--- |
| `profiles` | Read-only (joined with active live drop) | Read/Write (`auth.uid() = id`) | Full Access |
| `drops` | Read-only (`status = 'live'` via slug) | Read/Write (`auth.uid() = seller_id`) | Full Access |
| `products` | Read-only (for live drop, code asc) | Read/Write (`auth.uid() = seller_id`) | Full Access |
| `orders` | Token-gated lookup (`get_order_by_token`) | Read/Update (`auth.uid() = seller_id`) | Full Access |
| `order_items` | Token-gated lookup (`get_order_by_token`) | Read-only (`auth.uid() = seller_id`) | Full Access |
| `create_order_with_reservation` | **Permitted** (Anon) | Prohibited (Client UI does not call) | N/A |
| `get_order_by_token` | **Permitted** (Anon with token) | Prohibited | N/A |
| `mark_order_paid` | Prohibited | **Permitted** (Authenticated Seller) | Permitted |
| `force_release_hold` | Prohibited | **Permitted** (Authenticated Seller) | Permitted |
| `mark_product_sold_offline` | Prohibited | **Permitted** (Authenticated Seller) | Permitted |
| `release_expired_holds` | **PROHIBITED (Not Exposed)** | **PROHIBITED (Not Exposed)** | **Permitted** |

---

## 5. RPC Mapping

All application-callable RPCs are mapped strictly to their authoritative database signatures:

1. **`create_order_with_reservation`**:
   - Mapped in `buyer-web/src/lib/data/buyer-catalog.ts` via `createOrderWithReservation(client, request)`.
   - Arguments: `p_drop_id`, `p_product_ids`, `p_buyer_name`, `p_buyer_phone`, `p_shipping_address`, `p_pincode`.
   - Returns: Authoritative integer Paisa totals (`subtotal_paisa`, `shipping_paisa`, `total_paisa`), `order_id`, `order_code`, `order_token`, `hold_expires_at`.
   - Price authority rule: The client NEVER calculates authoritative order totals.

2. **`get_order_by_token`**:
   - Mapped in `buyer-web/src/lib/data/buyer-catalog.ts` via `getOrderByToken(client, orderId, orderToken)`.
   - Arguments: `p_order_id`, `p_order_token`.
   - Returns: Sanitized `OrderReceipt` with `buyer_name`, totals in Paisa, order status, boutique UPI info, and line items. Sensitive fulfillment PII (`buyer_phone`, `shipping_address`, `pincode`) is omitted.

3. **`mark_order_paid`**:
   - Mapped in `seller-app/lib/data/repositories/seller_repository.dart` via `markOrderPaid(orderId)`.
   - Arguments: `p_order_id`.
   - Handles conflict: maps `PRODUCT_ALREADY_RECLAIMED` to `ProductReclaimedException`.

4. **`force_release_hold`**:
   - Mapped in `seller-app/lib/data/repositories/seller_repository.dart` via `forceReleaseHold(orderId)`.
   - Arguments: `p_order_id`.

5. **`mark_product_sold_offline`**:
   - Mapped in `seller-app/lib/data/repositories/seller_repository.dart` via `markProductSoldOffline(productId)`.
   - Arguments: `p_product_id`.

6. **`release_expired_holds`**:
   - **DELIBERATELY NOT EXPOSED** in any client application repository. Restricted to backend `service_role` execution.

---

## 6. Realtime Plan

| Channel | Target Table | Audience | Events | Defense Mechanism | Cleanup / Teardown |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `drop:{drop_id}:products` | `products` | Public buyers | `UPDATE`, `INSERT` | Monotonic `version` integer check; stale/older events discarded | `unsubscribe()` removes channel; tab sleep disconnect |
| `seller-orders-{dropId}` | `orders` | Authenticated seller | `INSERT`, `UPDATE` | Authenticated session + RLS drop ownership | `unsubscribe()` removes channel upon screen dispose |

### Out-of-Order Version Defense:
The `CatalogRealtimeSubscription` class tracks monotonic entity versions (`localVersions` map). When an incoming payload arrives with `version <= currentVersion`, the event is discarded to prevent stale network packet reversals.

---

## 7. Error Model

| Database / RPC Error | Application Error Class (TS) | Dart Exception (Flutter) | User Meaning |
| :--- | :--- | :--- | :--- |
| `EMPTY_CART` | `InvalidCartError` | `LiveDropException` | Cart is empty |
| `EXCEEDS_CART_LIMIT` | `InvalidCartError` | `LiveDropException` | Cart exceeds 10 items limit |
| `MIXED_DROP_PRODUCTS`| `InvalidCartError` | `LiveDropException` | Items belong to different drops |
| `STOCK_UNAVAILABLE` | `StockUnavailableError` | `StockUnavailableException` | Item claimed by another buyer |
| `INVALID_DROP` | `InvalidDropError` | `LiveDropException` | Drop not found or not live |
| `PRODUCT_ALREADY_RECLAIMED` | `ProductReclaimedError` | `ProductReclaimedException` | Hold expired and re-reserved |
| `INVALID_ORDER_TOKEN` | `InvalidOrderTokenError` | `OrderNotFoundException` | Receipt token invalid or missing |
| `UNAUTHORIZED` | `UnauthorizedError` | `UnauthorizedException` | Action forbidden by security rule |
| PostgREST / Network | `NetworkError` | `NetworkException` | Connection failure |

---

## 8. Development Seed Data

File: [`supabase/seed.sql`](file:///c:/LiveDrop/supabase/seed.sql)

Contains 100% synthetic, deterministic fixtures for local and staging development:
1. **Auth & Profile:**
   - Test Seller User: `8a329e71-4b10-4055-90d2-df8029d5b512` (`seller.mother@livedrop.test`)
   - Profile: "Mother's Boutique", `919830012345`, `mothersboutique@okaxis`, `8000` Paisa shipping, `200000` Paisa free shipping threshold.
2. **Drops:**
   - 1 Draft Drop: `c1f76d42-4f36-4d2b-9801-b5e1cf3e6800` (`festive-silk-drop`)
   - 1 Live Drop: `c1f76d42-4f36-4d2b-9801-b5e1cf3e6801` (`mothers-boutique`)
   - 1 Closed Drop: `c1f76d42-4f36-4d2b-9801-b5e1cf3e6802` (`past-clearance`)
3. **Products (on live drop):**
   - `#A01`: `available` (`185000` Paisa)
   - `#A02`: `reserved` (`75000` Paisa, held by pending order)
   - `#A03`: `sold` (`125000` Paisa, finalized by paid order)
   - `#A04`: `sold` (`95000` Paisa, offline sale representation)
4. **Orders:**
   - Pending Order: `4b724590-7811-419b-a311-6b2a091df012` (Token: `9a01f822...`)
   - Paid Order: `5c835601-8922-420c-b422-7c3b102ef023` (Token: `8b12e933...`)
   - Cancelled Order: `6d946712-9033-431d-c533-8d4c213fa034` (Token: `7c23f044...`)
5. **Order Items:**
   - Linked to orders and products with matching `price_at_purchase_paisa`.

Validated automatically against all schema check constraints in `scripts/verify-schema.mjs`.

---

## 9. Test Results

### Buyer Webfront Tests (`buyer-web`)
```powershell
npm --prefix buyer-web test -- --run
```
- **Result:** 6 test files passed, 132 tests passed (0 failed).
- Breakdown:
  - `src/test/realtime.test.ts`: 3 passed (monotonic version filter, subscription setup, cleanup)
  - `src/test/data-layer.test.ts`: 15 passed (env validation, client config, catalog ops, RPC mapping, error classification, PII minimization)
  - `src/test/rpcs.test.ts`: 45 passed (transactional RPCs, concurrency simulation, permissions)
  - `src/test/rls.test.ts`: 35 passed (RLS policies, tenant isolation)
  - `src/test/schema.test.ts`: 33 passed (tables, columns, indexes, triggers)
  - `src/test/smoke.test.tsx`: 1 passed (smoke render)

### TypeScript Typecheck & ESLint (`buyer-web`)
```powershell
npm --prefix buyer-web run typecheck
npm --prefix buyer-web run lint
```
- **Result:** Exit code 0 (0 type errors, 0 lint errors, 0 warnings).

### Production Build (`buyer-web`)
```powershell
npm --prefix buyer-web run build
```
- **Result:** Exit code 0 (Optimized production build generated successfully).

### Seller Mobile App Tests & Lints (`seller-app`)
```powershell
& "C:\flutter\bin\flutter.bat" analyze
& "C:\flutter\bin\flutter.bat" test
```
- **Result:**
  - `flutter analyze`: Exit code 0 ("No issues found!").
  - `flutter test`: Exit code 0 (10/10 tests passed across `seller_repository_test.dart`, `realtime_test.dart`, and `widget_test.dart`).

### Schema & Seed Verification (`scripts/verify-schema.mjs`)
```powershell
node scripts/verify-schema.mjs
```
- **Result:** Exit code 0.
- Output: All 9 migrations applied, 5 tables, 8 indexes, 9 Paisa columns, 5 triggers, 13 RLS policies, 6 RPCs, 19 routine privileges, and seed fixture executed cleanly.

---

## 10. Real Supabase Validation

> [!NOTE]
> **Environment Evidence Classification**:
> Automated tests and schema validations in this task executed against the repository's deterministic in-memory PostgreSQL engine (`PGlite`) and client mocks.
> 
> **Real Supabase Integration Validation**: Deferred to the pre-production staging deployment gate, in accordance with the repository's zero-cost development model and TASK-1.3.1 documentation.

---

## 11. Security & PII Review

1. **Secret & Key Isolation**:
   - A global repository search confirmed zero instances of `service_role` keys embedded in client code.
   - Client environments enforce immediate failure if a service-role key is detected.
2. **PII Minimization**:
   - `get_order_by_token` returns only `buyer_name` on order receipts.
   - `buyer_phone`, `shipping_address`, and `pincode` are excluded from the token-gated public response.
3. **No Unqualified Mutations**:
   - Client repositories perform zero direct `INSERT` operations on `orders` or `order_items`. All mutations remain strictly mediated by atomic database RPCs.
4. **Reaper Isolation**:
   - `release_expired_holds` is not exposed in any client data layer.

---

## 12. Deferred Work

The following items are intentionally **NOT** implemented in TASK-1.4, as mandated by the architectural boundaries:
1. **Background Reaper Scheduler (TASK-1.5):** Deployment of `pg_cron` or external Edge Function daemon.
2. **Application UI / Screens:** Buyer catalog grid, cart drawer, checkout screen, seller login, viewfinder, and Kanban dashboard (Phases 2 through 6).
3. **Request-Level Idempotency Keys:** Deferred per TASK-1.3.1 Model B decision.

---

## 13. Final Gate Status

**PASS — TASK-1.4 COMPLETE; READY FOR BUYER/SELLER VERTICAL SLICE**
