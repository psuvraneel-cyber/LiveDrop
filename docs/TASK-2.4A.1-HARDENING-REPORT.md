# LiveDrop — TASK-2.4A.1 Completion Report
## Domain Consistency & Payment Authority Hardening

**Document Version:** 1.0.0  
**Date:** 2026-09-13  
**Author:** Principal Backend & Database Architect  
**Task Ref:** `TASK-2.4A.1`  
**Status:** **PASS — TASK-2.4A.1 COMPLETE; READY FOR ADVERSARIAL AUDIT**

---

## 1. Executive Summary

TASK-2.4A.1 executes a rigorous architectural hardening pass on the LiveDrop multi-seller domain model, order state machine, and payment authority boundaries. 

The preceding milestone (TASK-2.4A) established the multi-seller storefront model, order snapshots, and lifecycle foundations. However, audit analysis identified critical domain consistency gaps and an incorrect authority boundary: `confirm_order_advance` was designed as a seller-authenticated RPC, permitting sellers to self-assert that customer payments were received without independent verification. Furthermore, newly created sellers defaulted to having advance confirmation enabled, contradicting the business rule that advance confirmation is an optional feature.

Under TASK-2.4A.1:
1. **Advance Feature Default Fixed:** `profiles.advance_confirmation_enabled` now defaults to `false` (strictly opt-in). Default advance amount remains ₹250 (`25000` Paisa) and default hold duration is 30 days. Existing/demo sellers with active configurations are preserved explicitly in `seed.sql`.
2. **Payment Authority Corrected:** `confirm_order_advance` has been **completely dropped**. The authoritative payment-transition boundary is now encapsulated in a trusted, backend-only `SECURITY DEFINER` RPC: `record_verified_payment(order_id, payment_type, amount_paisa, reference_id, metadata)`.
3. **Least Privilege Enforced:** `PUBLIC`, `anon`, and `authenticated` privileges on `record_verified_payment` have been revoked. Only `service_role` can execute it. Direct table writes (`INSERT`, `UPDATE`, `DELETE`) on `order_payments` are revoked from `anon` and `authenticated`.
4. **Idempotency Hardened:** A partial unique index `uq_order_payments_reference_verified` on `order_payments(reference_id)` (`WHERE status = 'verified' AND reference_id IS NOT NULL`) ensures duplicate payment provider webhooks cannot double-credit an order or record multiple verified payment entries. Replays return idempotent success without altering financial totals.
5. **State Machine & Financial Invariants Enforced:** Enforced database constraints ensuring `ready_to_ship` and `shipped` require `payment_status = 'paid'` and `balance_due_paisa = 0`. Full payment transitions atomically mark orders paid, zero balance, and products sold. Holds expiring after advance payment release inventory to `available` while keeping the order `expired` and non-shippable, retaining the advance as non-refundable.

---

## 2. Files Changed

### Database Migrations
* **Created:** [`supabase/migrations/011_domain_consistency_and_payment_authority_hardening.sql`](file:///c:/LiveDrop/supabase/migrations/011_domain_consistency_and_payment_authority_hardening.sql)
  * Sets `profiles.advance_confirmation_enabled DEFAULT false`.
  * Adds check constraint `chk_profiles_hold_duration_max` (1 to 30 days) and `chk_profiles_advance_non_negative`.
  * Creates partial unique index `uq_order_payments_reference_verified` on `order_payments(reference_id)`.
  * Revokes `INSERT`, `UPDATE`, `DELETE` on `order_payments` from `PUBLIC`, `anon`, `authenticated`; grants only to `service_role`.
  * Drops obsolete function `confirm_order_advance(UUID, TEXT)`.
  * Creates `record_verified_payment(UUID, TEXT, INT, TEXT, JSONB)` with `SECURITY DEFINER`, `search_path = public, pg_temp`, and grants `EXECUTE` strictly to `service_role`.
  * Hardens `create_order_with_reservation` to fallback `advance_confirmation_enabled` to `false` and initial unpaid hold to 15 minutes.
  * Hardens `mark_order_paid` to reject orders with `status IN ('cancelled', 'expired')`.
  * Adds database check constraints `chk_orders_shipment_requires_full_payment`, `chk_orders_confirmed_lifecycle`, `chk_orders_paid_lifecycle`, and `chk_orders_adv_req_positive`.

### TypeScript Domain Models & Application Layer
* **Modified:** [`buyer-web/src/types/domain.ts`](file:///c:/LiveDrop/buyer-web/src/types/domain.ts)
  * Added typed interfaces for backend payment verification: `RecordVerifiedPaymentRequest`, `RecordVerifiedPaymentSuccessResponse`, `RecordVerifiedPaymentErrorResponse`, and union `RecordVerifiedPaymentResponse`.
* **Modified:** [`scripts/dev-mock-supabase.mjs`](file:///c:/LiveDrop/scripts/dev-mock-supabase.mjs)
  * Updated initial checkout hold duration to 15 minutes.

### Mobile Application Layer (Flutter/Dart)
* **Modified:** [`seller-app/lib/domain/models/models.dart`](file:///c:/LiveDrop/seller-app/lib/domain/models/models.dart)
  * Updated `SellerProfile.fromJson` to default `advanceConfirmationEnabled` to `false` when omitted or null.
  * Added safe default fallback for `defaultShippingFeePaisa` (`8000`).

### Seed Fixtures
* **Modified:** [`supabase/seed.sql`](file:///c:/LiveDrop/supabase/seed.sql)
  * Explicitly configured Seller A (Sonali's Boutique: advance enabled, ₹250, 30-day hold), Seller B (Artisan Silks: advance enabled, ₹500, 14-day hold), and Seller C (Bengal Handlooms: advance disabled).
  * Seeded 6 representative orders covering: pending advance, advance-paid balance due, paid/full payment, shipped, expired, and cancelled.
  * Seeded coherent `order_payments` rows with unique verified references.

### Automated Test Suites & Verification Scripts
* **Modified:** [`buyer-web/src/test/storefront-and-state-machine.test.ts`](file:///c:/LiveDrop/buyer-web/src/test/storefront-and-state-machine.test.ts)
  * Applied migration 011 in test harness.
  * Added test 1.5 proving new sellers default to advance disabled.
  * Updated Section 3 with 6 comprehensive test cases testing `record_verified_payment`, payment authority, idempotency, and full-payment flows.
  * Hardened Section 4 hold expiration tests for 15-minute unpaid hold and non-refundable advance retention.
  * Hardened Section 5 financial invariant check tests.
  * Added Section 6: a 25-vector adversarial attack suite (V01–V25) verifying permission denials, fake amounts, replayed webhooks, SQL injection safety, RLS isolation, and race resilience.
* **Modified:** [`seller-app/test/seller_repository_test.dart`](file:///c:/LiveDrop/seller-app/test/seller_repository_test.dart)
  * Added unit test verifying `SellerProfile` defaults `advanceConfirmationEnabled` to `false` when omitted from JSON.
* **Modified:** [`scripts/verify-schema.mjs`](file:///c:/LiveDrop/scripts/verify-schema.mjs)
  * Added migration 011 to sequential execution list.
  * Verified `confirm_order_advance` is dropped.
  * Verified `record_verified_payment` is `SECURITY DEFINER` and restricted to `service_role`.
  * Verified `profiles.advance_confirmation_enabled` default is `false`.
  * Verified `uq_order_payments_reference_verified` partial index.
  * Validated seed execution against in-memory PostgreSQL engine.

### Documentation
* **Created:** [`docs/TASK-2.4A.1-HARDENING-REPORT.md`](file:///c:/LiveDrop/docs/TASK-2.4A.1-HARDENING-REPORT.md)
* **Modified:** [`docs/00-project-status.md`](file:///c:/LiveDrop/docs/00-project-status.md)
* **Modified:** [`docs/06-requirements-traceability-matrix.md`](file:///c:/LiveDrop/docs/06-requirements-traceability-matrix.md)
* **Modified:** [`walkthrough.md`](file:///c:/LiveDrop/walkthrough.md)

---

## 3. Domain Changes

1. **Advance Feature Default Disabled:**
   - Database column definition: `advance_confirmation_enabled BOOLEAN NOT NULL DEFAULT false`.
   - New sellers are strictly opt-in. Sellers must explicitly toggle advance confirmation in their settings.
   - Platform maximum hold duration enforced by check constraint: `hold_duration_days BETWEEN 1 AND 30`.
   - Default advance amount remains ₹250 (`25000` Paisa) and default hold duration remains 30 days when opted in.
2. **Advance Treated as Part of Purchase Price:**
   - The advance payment is NOT a platform fee or reservation surcharge. It is an initial payment towards the total order purchase price.
   - Accounting invariant: `total_paisa = advance_paid_paisa + balance_due_paisa` (when advance is paid).
   - Balance due calculation: `balance_due_paisa = total_paisa - total_paid_paisa`.
3. **Seller / Drop Policy Immutability Snapshot:**
   - `create_order_with_reservation` snapshots the seller's active configuration (`advance_required_paisa`, `hold_expires_at`, `confirmation_mode`) at order creation time.
   - Subsequent changes made by the seller to storefront settings do not mutate existing orders.
4. **Buyer Web Zero Control Over Policy:**
   - The buyer web client passes only `confirmation_mode` ('advance' or 'full_payment'), contact details, and item identifiers.
   - Authoritative amounts (`subtotal_paisa`, `shipping_paisa`, `total_paisa`, `advance_required_paisa`) are calculated server-side from active database records.

---

## 4. Payment Authority Changes

The authoritative payment confirmation flow is decoupled from seller app self-assertion:

```
[ BUYER WEB ] 
      │ Initiates checkout / payment
      ▼
[ PAYMENT PROVIDER (Gateway / UPI) ]
      │ Webhook / Server Notification
      ▼
[ TRUSTED BACKEND SERVICE (service_role) ]
      │ Validates signature, provider transaction status & amount
      ▼
[ record_verified_payment() RPC (SECURITY DEFINER) ]
      │ 1. Checks order exists and is in payable state
      │ 2. Acquires row locks (deterministic order)
      │ 3. Verifies amount matches database expectation
      │ 4. Checks reference_id idempotency
      │ 5. Inserts verified ledger row into order_payments
      │ 6. Updates order financial state & lifecycle atomically
      │ 7. Transitions inventory (reserved -> sold on full payment)
      ▼
[ DB STATE COMMITTED ]
```

* **Removal of `confirm_order_advance`:** Dropped from the database to eliminate the risk of sellers marking unverified payments as confirmed.
* **Backend RPC Boundary:** `record_verified_payment(order_id, payment_type, amount_paisa, reference_id, metadata)` is executable **exclusively by `service_role`**. Any invocation by `anon` or standard `authenticated` users is denied by PostgreSQL grant permissions.
* **Zero Trust on Amounts:** The RPC checks that the incoming payment amount matches the order's exact requirement (`advance_required_paisa` for advance, `balance_due_paisa` for balance, `total_paisa` for full). Mismatched amounts are rejected with error `AMOUNT_MISMATCH`.

---

## 5. State-Machine Changes

### Valid Transitions

1. **Advance Confirmation Mode:**
   ```
   [create_order_with_reservation]
         │
         ▼
     (pending / unpaid / reserved / balance_due = total)
         │
         │ record_verified_payment('advance')
         ▼
     (confirmed / advance_paid / reserved / balance_due = total - advance)
         │
         │ record_verified_payment('balance')
         ▼
     (paid / paid / sold / balance_due = 0 / ready_to_ship)
         │
         │ seller dispatches shipment
         ▼
     (shipped / paid / sold / balance_due = 0 / shipped)
   ```

2. **Full Payment Mode:**
   ```
   [create_order_with_reservation]
         │
         ▼
     (pending / unpaid / reserved / advance_required = 0)
         │
         │ record_verified_payment('full')
         ▼
     (paid / paid / sold / balance_due = 0 / ready_to_ship)
         │
         │ seller dispatches shipment
         ▼
     (shipped / paid / sold / balance_due = 0 / shipped)
   ```

3. **Hold Expiry Lifecycle:**
   - **Pending Unpaid Order Expiry (15-min initial window):** `status -> cancelled`, `products.status -> available`, `reserved_by_order_id -> null`.
   - **Advance-Confirmed Order Expiry (hold duration days elapsed):** `status -> expired`, `products.status -> available`, `reserved_by_order_id -> null`, `advance_paid_paisa` retained, order remains non-shippable forever.

### Disallowed / Blocked Transitions
- `unpaid` -> `shipped` (Blocked by constraint `chk_orders_shipment_requires_full_payment`).
- `advance_paid` -> `ready_to_ship` or `shipped` (Blocked by constraints).
- `balance_due_paisa > 0` with `fulfilment_status = 'ready_to_ship'` or `'shipped'` (Blocked).
- `cancelled` or `expired` -> `paid` or `advance_paid` (Blocked by RPC state checks).
- `paid` -> `advance_paid` or `unpaid` (Blocked).
- `sold` -> `available` through normal checkout (Blocked).

---

## 6. Payment Ledger & Idempotency Changes

1. **Separation of Ledger & Aggregate State:**
   - `orders`: Stores the current materialized financial state (`advance_required_paisa`, `advance_paid_paisa`, `total_paid_paisa`, `balance_due_paisa`, `payment_status`).
   - `order_payments`: Stores the append-only ledger of discrete payment transactions (`payment_type`, `amount_paisa`, `status`, `reference_id`, `created_at`).
2. **Webhook Idempotency Enforcement:**
   - Partial unique index: `CREATE UNIQUE INDEX uq_order_payments_reference_verified ON order_payments(reference_id) WHERE status = 'verified' AND reference_id IS NOT NULL;`.
   - If a payment provider resends a webhook with an identical `reference_id`, `record_verified_payment` detects the existing verified record and returns `{"success": true, "idempotent": true, ...}` without double-crediting `total_paid_paisa` or inserting duplicate payments.
3. **Table Direct Write Immunization:**
   - `REVOKE INSERT, UPDATE, DELETE ON order_payments FROM PUBLIC, anon, authenticated;`
   - Prevents malicious or erroneous clients from tampering with payment logs.

---

## 7. Security, RLS, and RPC Changes

| Surface | Previous State (TASK-2.4A) | Hardened State (TASK-2.4A.1) | Security Rationale |
|---|---|---|---|
| `profiles.advance_confirmation_enabled` | `DEFAULT true` | `DEFAULT false` | Safe default; prevents unintended advance requirements for new sellers. |
| `confirm_order_advance` | Granted to `authenticated` (seller) | **DROPPED** | Sellers cannot self-assert customer payments without provider verification. |
| `record_verified_payment` | Non-existent | Granted strictly to `service_role` | Trusted backend webhook receiver boundary with least privilege. |
| `order_payments` Writes | Authenticated insert policy | Revoked from all except `service_role` | Ledger immutability; prevents payment forgery. |
| `release_expired_holds` | `SECURITY DEFINER` | `SECURITY DEFINER`, pinned search path | System cron/reaper only; unaffected by client sessions. |
| `get_order_by_token` | Token-gated | Token-gated, PII minimized | Excludes buyer phone, address, and pincode from receipt. |

---

## 8. Concurrency & Locking Changes

* **Deterministic Row Locking:** In `record_verified_payment`, orders are locked with `SELECT ... FOR UPDATE` before inspecting state and updating ledger. Products are updated atomically in the same database transaction.
* **Deadlock Prevention:** All multi-row updates maintain deterministic `ORDER BY id ASC` locking semantics as established in ADR-002.
* **Race Between Payment and Expiry:** Handled deterministically by `FOR UPDATE` transaction locks. If the reaper executes first, the order status becomes `expired`, and subsequent `record_verified_payment` attempts are rejected with `INVALID_ORDER_STATE`. If payment executes first, `hold_expires_at` is updated or cleared, and the reaper ignores the order.

---

## 9. Test Coverage Summary

### Automated Test Suites Executed

| Component / Suite | Test File | Tests Run | Result | Notes |
|---|---|---|---|---|
| **Database & Domain State Machine** | `buyer-web/src/test/storefront-and-state-machine.test.ts` | 53 | **53 PASSED** | Covers migrations 001-011, invariants, reaper, and 25-vector adversarial suite. |
| **Buyer Web Full Test Suite** | 12 test files across `buyer-web/src/test/` | 255 | **255 PASSED** | All cart, checkout, catalog, schema, rls, and rpc suites pass. |
| **Schema Verifier** | `scripts/verify-schema.mjs` | 1 | **PASSED** | 11 migrations, 6 tables, 10 indexes, 16 Paisa columns, 6 triggers, 15 RLS policies, 7 RPCs, 21 privileges, seed data verified. |
| **Buyer Web Strict Typecheck** | `npm run typecheck` (`tsc --noEmit`) | N/A | **PASSED** | 0 TypeScript compilation errors in strict mode. |
| **Buyer Web Linter** | `npm run lint` (`eslint`) | N/A | **PASSED** | 0 warnings, 0 errors. |
| **Buyer Web Production Build** | `npm run build` (`next build`) | N/A | **PASSED** | Optimized Next.js 16.3.4 production bundle built successfully. |
| **Seller App Static Analyzer** | `flutter analyze` | N/A | **PASSED** | "No issues found!" across all Dart domain models, repos, and tests. |
| **Seller App Unit Tests** | `flutter test` | 11 | **11 PASSED** | All domain, realtime deserialization, exception, and default config tests pass. |

**Total Automated Test Count:** 266 tests across web and mobile suites (255 in `buyer-web` + 11 in `seller-app`), all passing with exit code 0.

### 25-Vector Adversarial Verification Suite (V01–V25)

The dedicated adversarial test suite in `storefront-and-state-machine.test.ts` executes and proves the following 25 vectors:

1. **V01:** Anonymous client attempts to invoke `record_verified_payment` ➔ `Permission denied` (Exit code failure / rejected).
2. **V02:** Authenticated normal buyer attempts to invoke `record_verified_payment` ➔ `Permission denied`.
3. **V03:** Unrelated authenticated seller attempts to invoke `record_verified_payment` ➔ `Permission denied`.
4. **V04:** Submit fake advance amount (e.g. ₹1) ➔ Rejected with `AMOUNT_MISMATCH`.
5. **V05:** Submit fake paid amount (e.g. ₹99,999) ➔ Rejected with `AMOUNT_MISMATCH`.
6. **V06:** Replay identical payment reference ➔ Idempotent success returned; exactly one ledger entry created.
7. **V07:** Concurrent / repeated payment verification ➔ Total paid strictly matches required amount; no excess credit.
8. **V08:** Pay balance twice ➔ Idempotent success; order remains paid with balance = 0; no double credit.
9. **V09:** Pay full amount after advance is already paid ➔ Rejected with `INVALID_OPERATION`.
10. **V10:** Pay after order hold expires ➔ Rejected with `INVALID_ORDER_STATE`.
11. **V11:** Pay after order cancellation ➔ Rejected with `INVALID_ORDER_STATE`.
12. **V12:** Seller mutates advance policy after order creation ➔ Order snapshot remains unchanged.
13. **V13:** Seller modifies hold duration after order creation ➔ Existing order hold expiry remains unchanged.
14. **V14:** Force balance below zero via raw update ➔ Rejected by database check constraint.
15. **V15:** Force total paid above total via raw update ➔ Rejected by database check constraint.
16. **V16:** Transition order to `ready_to_ship` while balance remains due ➔ Rejected by database check constraint.
17. **V17:** Transition order to `shipped` while unpaid ➔ Rejected by database check constraint.
18. **V18:** Attempt to restore expired product through buyer RPC ➔ Rejected with `STOCK_UNAVAILABLE`.
19. **V19:** Unrelated seller attempts cross-seller order/payment access ➔ 0 rows returned under RLS.
20. **V20:** Attempt token substitution on `get_order_by_token` ➔ Fake token rejected with `ORDER_NOT_FOUND_OR_UNAUTHORIZED`; authentic token succeeds.
21. **V21:** Seller attempts direct `INSERT` into `order_payments` ➔ `Permission denied`.
22. **V22:** Seller attempts direct `UPDATE` into `order_payments` ➔ `Permission denied`.
23. **V23:** Attempt SQL injection / privilege escalation through SECURITY DEFINER inputs ➔ Handled as literal string parameters; rejected with `INVALID_PAYMENT_TYPE`; table structure intact.
24. **V24:** Attempt malformed / invalid payment type (e.g. `crypto_token`) ➔ Rejected with `INVALID_PAYMENT_TYPE`.
25. **V25:** Attempt duplicate provider references with different amounts ➔ Blocked by partial unique index `uq_order_payments_reference_verified`.

---

## 10. Verification Results

All required verification commands executed on the actual codebase:

```powershell
# 1. Schema and migration integrity
node scripts/verify-schema.mjs
# Output: ALL RELATIONAL DATABASE SCHEMA, STOREFRONT INVARIANTS, RLS POLICIES, BUSINESS RPCS & MULTI-SELLER SEED DATA VERIFIED. (Exit code 0)

# 2. Buyer Web Full Test Suite
npm --prefix buyer-web test
# Output: 12 test files passed, 255 tests passed. (Exit code 0)

# 3. Buyer Web TypeScript Typecheck
npm --prefix buyer-web run typecheck
# Output: tsc --noEmit passed with 0 errors. (Exit code 0)

# 4. Buyer Web ESLint
npm --prefix buyer-web run lint
# Output: eslint passed with 0 warnings, 0 errors. (Exit code 0)

# 5. Buyer Web Next.js Build
npm --prefix buyer-web run build
# Output: Compiled successfully, optimized production build generated. (Exit code 0)

# 6. Seller App Flutter Analyze
C:\flutter\bin\flutter.bat analyze
# Output: Analyzing seller-app... No issues found! (Exit code 0)

# 7. Seller App Flutter Test
C:\flutter\bin\flutter.bat test
# Output: All 11 tests passed! (Exit code 0)
```

---

## 11. Remaining Limitations

1. **Payment Gateway Integration (TASK-2.4B):** No live payment gateway (Razorpay / Cashfree / UPI intent deep-linking) is implemented in this task. Payment transitions are modeled and verified through the authoritative `record_verified_payment` RPC boundary.
2. **Seller Payment Reconciliation UI:** No seller payment proof review UI or payment settlement dashboard is built in this task.
3. **Hosted Concurrency Environment:** Concurrency tests were executed using the local in-memory PostgreSQL engine (PGlite WASM) simulating serialized database transactions. Hosted multi-connection stress testing against physical Supabase instances remains a staging verification gate for Phase 8.

---

## 12. Final Status

**PASS — TASK-2.4A.1 COMPLETE; READY FOR ADVERSARIAL AUDIT**
