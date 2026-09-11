# LiveDrop — Engineering Implementation Log

This document serves as the permanent, immutable engineering audit trail for all implementation tasks executed in the LiveDrop repository.

---

## Task Execution Log

### `TASK-0.1: Initialize Antigravity Monorepo Workspace`
* **Phase:** Phase 0 — Workspace & Repository Foundation
* **Date:** 2026-09-11
* **Requirement IDs:** `NFR-SYS-01`
* **Status:** **COMPLETED**
* **Change Summary:**
  1. Initialized empty Git repository and established root `.gitignore` protecting secrets, local `.env*` files, build outputs, keystores, and OS metadata.
  2. Created `.editorconfig` setting unified indentation (2 spaces) across TypeScript, Dart, SQL, and Markdown.
  3. Updated root `README.md` to document repository layout, local toolchains, and Phase 0 status.
  4. Scaffolded `buyer-web` using Next.js 16 (App Router), TypeScript in strict mode (`strict: true`, `noImplicitAny: true`), ESLint, Vitest component test foundation, and `.env.example` contract.
  5. Scaffolded `seller-app` using Flutter 3.41.6 (Dart 3.11.4), configured strict analyzer options (`analysis_options.yaml`), Clean Architecture folder skeleton (`core/`, `data/`, `domain/`, `presentation/`), and `.env.example` contract.
  6. Initialized Supabase project structure via `npx supabase init` with `migrations/`, `functions/`, and `seed/` placeholders.
  7. Created operational utility `scripts/keepalive-ping.js` for free-tier dormancy prevention (ADR-008).
  8. Authored GitHub Actions CI workflows (`buyer-web-ci.yml`, `seller-app-ci.yml`, `supabase-keepalive.yml`).
  9. Verified 100% of toolchains and commands locally with zero failures.

* **Files Created / Modified:**
  * Created: `.gitignore`, `.editorconfig`
  * Modified: `README.md`, `docs/32-implementation-plan.md`
  * Created: `buyer-web/` (Next.js app, `vitest.config.ts`, `src/test/setup.ts`, `src/test/smoke.test.tsx`, `.env.example`, `.gitkeep` files)
  * Created: `seller-app/` (Flutter Android app, `analysis_options.yaml`, `.env.example`, Clean Architecture `.gitkeep` files)
  * Created: `supabase/` (`config.toml`, `.gitignore`, `migrations/.gitkeep`, `functions/.gitkeep`, `seed/.gitkeep`)
  * Created: `scripts/` (`README.md`, `keepalive-ping.js`)
  * Created: `.github/workflows/` (`buyer-web-ci.yml`, `seller-app-ci.yml`, `supabase-keepalive.yml`)

* **Verification Commands Executed & Results:**
  1. `git init` ➔ Initialized empty Git repository (Exit code 0).
  2. `npm --prefix buyer-web run typecheck` (`tsc --noEmit`) ➔ Passed with 0 errors (Exit code 0).
  3. `npm --prefix buyer-web run lint` (`eslint`) ➔ Passed with 0 warnings/errors (Exit code 0).
  4. `npm --prefix buyer-web test` (`vitest run`) ➔ 1/1 test passed (Exit code 0).
  5. `npm --prefix buyer-web run build` (`next build`) ➔ Optimized production build generated (Exit code 0).
  6. `& "C:\flutter\bin\flutter.bat" pub get` ➔ Resolved dependencies cleanly (Exit code 0).
  7. `& "C:\flutter\bin\flutter.bat" analyze` ➔ "No issues found!" (Exit code 0).
  8. `& "C:\flutter\bin\flutter.bat" test` ➔ 1/1 test passed (Exit code 0).
  9. `& "C:\flutter\bin\flutter.bat" build apk --debug` ➔ Built `app-debug.apk` in 157s (Exit code 0).
  10. `git status` ➔ Clean working tree, zero secrets, zero build artifacts leaked.

---

### `TASK-1.1: Deploy Relational Tables & Indexes`
* **Phase:** Phase 1 — Database & Security Foundation
* **Date:** 2026-09-11
* **Requirement IDs:** `REQ-DB-01..05`
* **Status:** **COMPLETED**
* **Change Summary:**
  1. Deployed 6 sequential PostgreSQL migrations under `supabase/migrations/` covering the complete relational schema.
  2. Enforced integer Paisa currency across all 9 monetary columns (`default_shipping_fee_paisa`, `free_shipping_threshold_paisa`, `shipping_fee_paisa`, `price_paisa`, `subtotal_paisa`, `shipping_paisa`, `total_paisa`, `price_at_purchase_paisa`).
  3. Deployed hardened check constraints: `total_paisa = subtotal_paisa + shipping_paisa`, phone regex (`^[6-9]\d{9}$`), pincode regex (`^\d{6}$`), flash code regex (`^#[A-Z0-9]{1,6}$`), order code regex (`^LD-[A-Z0-9]{6}$`).
  4. Deployed cascade & restrict delete semantics: `orders.drop_id ON DELETE RESTRICT`, `order_items.product_id ON DELETE RESTRICT`, `order_items.order_id ON DELETE CASCADE`, `products.reserved_by_order_id ON DELETE SET NULL`.
  5. Created 8 justified query performance indexes.
  6. Implemented and executed automated PostgreSQL test harness with 25 test assertions using `@electric-sql/pglite` (PostgreSQL 18.3 WASM).
  7. Created standalone script `scripts/verify-schema.mjs` for root-level CI migration verification.

* **Migration Files Created:**
  * `supabase/migrations/001_create_profiles.sql`
  * `supabase/migrations/002_create_drops.sql`
  * `supabase/migrations/003_create_products.sql`
  * `supabase/migrations/004_create_orders.sql`
  * `supabase/migrations/005_create_order_items.sql`
  * `supabase/migrations/006_create_indexes.sql`

* **Test & Verification Files Created:**
  * `buyer-web/src/test/schema.test.ts`
  * `scripts/verify-schema.mjs`

* **Commands Executed & Validation Results:**
  1. `npm --prefix buyer-web test` ➔ 26/26 tests passed across smoke test and schema test suite (Exit code 0).
  2. `node scripts/verify-schema.mjs` ➔ 6 migrations applied, 5 tables verified, 8 indexes verified, 9 Paisa columns verified (Exit code 0).
  3. `npm --prefix buyer-web run typecheck` ➔ TypeScript strict mode passed with 0 errors (Exit code 0).
  4. `npm --prefix buyer-web run lint` ➔ ESLint passed with 0 warnings/errors (Exit code 0).

* **Failures & Corrections During Development:**
  * Failure 1: Extension `uuid-ossp` not bundled in minimal WASM/embedded PostgreSQL engines. Resolved by using resilient anonymous block `EXCEPTION WHEN undefined_file THEN NULL; WHEN feature_not_supported THEN NULL;` and relying on native PostgreSQL 13+ `gen_random_uuid()`.
  * Failure 2: Regex repetition quantifier `{2,256}` in `upi_id` triggered PostgreSQL `invalid repetition count(s)` because POSIX regex limit `REG_MAX_REPEAT` in PostgreSQL engine is 255. Corrected to `{2,255}` matching UPI specification.
  * Failure 3: ESLint flagged 15 `@typescript-eslint/no-explicit-any` warnings in `schema.test.ts`. Corrected by declaring explicit typed row interfaces (`ProfileRow`, `DropRow`, `ProductRow`, `OrderRow`, `OrderItemRow`, `ColumnMetaRow`, `IndexMetaRow`).

* **Deviations:**
  * None. Schema strictly complies with `docs/12-database-design.md`, `docs/11-data-dictionary.md`, and ADR-009.

---

### `TASK-1.1-VERIFY: Post-Remediation Database Foundation Verification`
* **Phase:** Phase 1 — Database & Security Foundation
* **Date:** 2026-09-11
* **Requirement IDs:** `REQ-DB-01..05`, `RULE-DRP-03`, `RULE-ORD-01`, `ADR-009`
* **Status:** **VERIFIED & SIGNED OFF**
* **Event Summary:**
  1. Completed rigorous post-remediation verification following principal-level PostgreSQL review.
  2. Verified all 12 remediation items:
     - F1: `drops.seller_id` changed to `ON DELETE RESTRICT` (protects seller history).
     - F2: `products.drop_id` changed to `ON DELETE RESTRICT` (protects catalog).
     - F3: Added `set_updated_at()` trigger function & triggers on `profiles`, `drops`, `products`, and `orders`.
     - F4: `fk_products_reserved_by_order` changed to `ON DELETE RESTRICT` (protects order reservation holds).
     - F5: `upi_id` repetition quantifier bounded to `{2,255}` matching PostgreSQL `REG_MAX_REPEAT`.
     - F6: `slug` length constraint bounded to `BETWEEN 3 AND 60`.
     - F7: Added `prevent_finalized_order_deletion()` trigger preventing deletion of `paid` or `shipped` orders.
     - F8: `image_url` length constraint bounded to `BETWEEN 1 AND 2048`.
     - F9: Derived seller ownership path reconciled (`orders.drop_id → drops.seller_id`) and documented mandatory RPC lock constraint.
     - F10: `subtotal_paisa` constrained to `> 0` and default removed.
     - F11: Partial unique index `idx_drops_one_live_per_seller` deployed on `drops(seller_id) WHERE status = 'live'`.
     - F12: Redundant B-tree index on `orders(order_token)` removed.
  3. Expanded automated test suite in `buyer-web/src/test/schema.test.ts` to 34 tests (33 schema tests + 1 smoke test) covering one-live-drop invariant across sellers and status transitions, deletion restrictions, updated_at triggers, finalized order deletion guards, monetary integrity, and string bounds.
  4. Updated standalone migration verification script `scripts/verify-schema.mjs` to execute all 7 migrations and assert triggers.
  5. Reconciled and synchronized all documentation (`12-database-design.md`, `11-data-dictionary.md`, `19-validation-and-business-rules.md`, `04-technical-design.md`).
  6. Generated formal sign-off report: `docs/TASK-1.1-POST-REMEDIATION-SIGNOFF.md`.

* **Files Created / Modified:**
  * Created: `docs/TASK-1.1-POST-REMEDIATION-SIGNOFF.md`
  * Modified: `docs/IMPLEMENTATION-LOG.md`
  * Modified: `docs/11-data-dictionary.md`
  * Modified: `docs/19-validation-and-business-rules.md`
  * Modified: `docs/04-technical-design.md`
  * Modified: `scripts/verify-schema.mjs`
  * Modified: `buyer-web/src/test/schema.test.ts`

* **Commands Executed & Validation Results:**
  1. `npx vitest run --reporter verbose` ➔ 34/34 tests passed (Exit code 0).
  2. `node scripts/verify-schema.mjs` ➔ 7 migrations applied, 5 tables, 8 indexes, 9 Paisa columns, 5 triggers verified (Exit code 0).
  3. `npm --prefix buyer-web run typecheck` ➔ TypeScript strict mode passed with 0 errors (Exit code 0).
  4. `npm --prefix buyer-web run lint` ➔ ESLint passed with 0 warnings/errors (Exit code 0).

* **Verdict:**
  * **READY FOR RLS** (Authorized to proceed to TASK-1.2).

---

### `TASK-1.2: Row-Level Security & Database Access Control`
* **Phase:** Phase 1 — Database & Security Foundation
* **Date:** 2026-09-11
* **Requirement IDs:** `REQ-SEC-01..04`, `REQ-PRV-01..02`, `ADR-003`, `ADR-009`
* **Status:** **COMPLETED**
* **Change Summary:**
  1. Built comprehensive access control matrix in `docs/RLS-ACCESS-MATRIX.md` defining permissions for `anon`, `authenticated`, and `service_role` across all 5 tables and CRUD actions.
  2. Built detailed policy verification matrix in `docs/TASK-1.2-RLS-SECURITY-MATRIX.md` specifying exact `USING` and `WITH CHECK` expressions and test mappings.
  3. Created migration `supabase/migrations/008_enable_rls_and_policies.sql` which:
     - Enables RLS on all 5 core tables (`profiles`, `drops`, `products`, `orders`, `order_items`).
     - Revokes all default public schema permissions on tables (`REVOKE ALL ON ... FROM PUBLIC;`).
     - Grants least-privilege table permissions: `anon` receives `SELECT` only; `authenticated` receives permissions on seller-owned tables, with `INSERT` strictly revoked on `orders` and `order_items`.
     - Implements 13 hardened RLS policies enforcing seller multi-tenant isolation, public live catalog visibility, and secret token-gated order receipt access.
  4. Created comprehensive test suite in `buyer-web/src/test/rls.test.ts` (35 test assertions) verifying catalog RLS enforcement, seller isolation across all tables, public buyer catalog boundary, DPDP Act 2023 order privacy, and defense-in-depth negative write rejections.
  5. Updated `scripts/verify-schema.mjs` to assert `rowsecurity = true` across all 5 tables and assert that all 13 policies are registered in PostgreSQL.
  6. Updated `buyer-web/src/test/schema.test.ts` to include migration 008 in the baseline schema suite.
  7. Updated `docs/16-security-architecture.md` with final RLS policies and table grants.
  8. Authored `docs/TASK-1.2-RLS-TEST-REPORT.md` and `docs/TASK-1.2-COMPLETION-REPORT.md`.

* **Files Created / Modified:**
  * Created: `supabase/migrations/008_enable_rls_and_policies.sql`
  * Created: `buyer-web/src/test/rls.test.ts`
  * Created: `docs/RLS-ACCESS-MATRIX.md`
  * Created: `docs/TASK-1.2-RLS-SECURITY-MATRIX.md`
  * Created: `docs/TASK-1.2-RLS-TEST-REPORT.md`
  * Created: `docs/TASK-1.2-COMPLETION-REPORT.md`
  * Modified: `scripts/verify-schema.mjs`
  * Modified: `buyer-web/src/test/schema.test.ts`
  * Modified: `docs/16-security-architecture.md`
  * Modified: `docs/IMPLEMENTATION-LOG.md`
  * Modified: `docs/32-implementation-plan.md`

* **Verification Commands Executed & Results:**
  1. `node scripts/verify-schema.mjs` ➔ 8 migrations applied, 5 tables with `rowsecurity = true`, 13 policies verified (Exit code 0).
  2. `npm --prefix buyer-web test` ➔ 69/69 tests passed across 3 test suites: `smoke.test.tsx` (1), `schema.test.ts` (33), `rls.test.ts` (35) (Exit code 0).
  3. `npm --prefix buyer-web run typecheck` ➔ TypeScript strict mode passed with 0 errors (Exit code 0).
  4. `npm --prefix buyer-web run lint` ➔ ESLint passed with 0 warnings/errors (Exit code 0).

* **Verdict:**
  * **READY FOR TASK-1.3**

---

### `TASK-1.3: Atomic Order Creation, Reservation & Payment Transition RPCs`
* **Phase:** Phase 1 — Database & Security Foundation
* **Date:** 2026-09-11
* **Requirement IDs:** `REQ-FR-B4.1`, `REQ-FR-S3.2`, `REQ-SEC-01..04`, `REQ-PRV-01..02`, `ADR-003`, `ADR-009`
* **Status:** **COMPLETED**
* **Change Summary:**
  1. Created migration `supabase/migrations/009_create_core_business_rpcs.sql` implementing 6 hardened business RPCs:
     - `create_order_with_reservation`: Atomic multi-item cart validation, canonicalization, live drop check, deterministic row locking (`ORDER BY id ASC`), integer Paisa subtotal/shipping calculation, order + order_items insertion, 15-minute hold reservation.
     - `mark_order_paid`: Authenticated seller payment confirmation, seller ownership verification (`drops.seller_id = auth.uid()`), idempotency, contested hold detection (`PRODUCT_ALREADY_RECLAIMED`), uncontested hold reclamation, atomic transition to `paid` and `sold`.
     - `release_expired_holds`: Reaper routine identifying genuine expired holds (`hold_expires_at < NOW()`), releasing products back to `available`, clearing `reserved_by_order_id`, and setting order status to `cancelled`.
     - `force_release_hold`: Seller manual override to release active holds and cancel pending orders.
     - `mark_product_sold_offline`: Seller manual walk-in sale override transitioning available garments directly to `sold`.
     - `get_order_by_token`: Token-gated order receipt retrieval protecting buyer PII under India's DPDP Act 2023.
  2. Applied `SECURITY DEFINER SET search_path = public, pg_temp;` across all routines to prevent search-path hijacking.
  3. Revoked default `PUBLIC` execute privileges on all routines and granted permissions on a strict role boundary: `anon` can only execute public buyer routines (`create_order_with_reservation`, `get_order_by_token`); seller/maintenance routines require authenticated seller context or service role.
  4. Created comprehensive test suite in `buyer-web/src/test/rpcs.test.ts` (37 tests) covering single-item checkout, multi-item checkout, free shipping threshold, empty cart, cart limit (10 items), duplicate ID canonicalization, closed/draft drop rejection, cross-drop cart rejection, sold/reserved product rejection, input format validation (phone, pincode, name, address), multi-item all-or-nothing rollback atomicity, seller payment confirmation, cross-seller rejection, payment idempotency, uncontested reclamation, contested rejection (`PRODUCT_ALREADY_RECLAIMED`), hold reaper expiration, token-gated retrieval, seller manual overrides, and routine privilege boundaries.
  5. Tested actual multi-client concurrency and race conditions: 2, 5, and 20 concurrent buyers competing for a single item (exactly 1 winner, zero over-reservations), overlapping multi-item cart collision (uncontested item preserved), reverse-order deadlock prevention (`[P1, P2]` vs `[P2, P1]`), and concurrent payment confirmations.
  6. Updated `scripts/verify-schema.mjs` to assert routine existence, definer security type, and routine privilege revocation for `anon` and `PUBLIC`.
  7. Updated `buyer-web/src/test/schema.test.ts` and `buyer-web/src/test/rls.test.ts` to include migration 009 in baseline setup.
  8. Authored `docs/TASK-1.3-RPC-CONTRACT.md`, `docs/TASK-1.3-CONCURRENCY-TEST-REPORT.md`, and `docs/TASK-1.3-COMPLETION-REPORT.md`.

* **Files Created / Modified:**
  * Created: `supabase/migrations/009_create_core_business_rpcs.sql`
  * Created: `buyer-web/src/test/rpcs.test.ts`
  * Created: `docs/TASK-1.3-RPC-CONTRACT.md`
  * Created: `docs/TASK-1.3-CONCURRENCY-TEST-REPORT.md`
  * Created: `docs/TASK-1.3-COMPLETION-REPORT.md`
  * Modified: `scripts/verify-schema.mjs`
  * Modified: `buyer-web/src/test/schema.test.ts`
  * Modified: `buyer-web/src/test/rls.test.ts`
  * Modified: `docs/32-implementation-plan.md`
  * Modified: `docs/IMPLEMENTATION-LOG.md`

* **Verification Commands Executed & Results:**
  1. `node scripts/verify-schema.mjs` ➔ 9 migrations applied, 5 tables, 8 indexes, 9 Paisa columns, 5 triggers, 13 RLS policies, 6 RPCs verified with SECURITY DEFINER and revoked PUBLIC execution (Exit code 0).
  2. `npm --prefix buyer-web test -- --run` ➔ 106/106 tests passed across 4 test suites: `smoke.test.tsx` (1), `schema.test.ts` (33), `rls.test.ts` (35), `rpcs.test.ts` (37) (Exit code 0).
  3. `npm --prefix buyer-web run typecheck` ➔ TypeScript strict mode passed with 0 errors (Exit code 0).
  4. `npm --prefix buyer-web run lint` ➔ ESLint passed with 0 warnings/errors (Exit code 0).

* **Verdict:**
  * **PASS — READY FOR TASK-1.4**

---

### `TASK-1.3.1: Transactional Business RPC Hardening Pass`
* **Phase:** Phase 1 — Database & Security Foundation
* **Date:** 2026-09-11
* **Requirement IDs:** `REQ-FR-B4.1`, `REQ-FR-S3.2`, `REQ-SEC-01..04`, `REQ-PRV-01..02`, `ADR-003`, `ADR-009`
* **Status:** **COMPLETED**
* **Change Summary:**
  1. **Global Reaper Privilege Hardening:** In `supabase/migrations/009_create_core_business_rpcs.sql`, revoked `EXECUTE` on `release_expired_holds()` from `authenticated` as well as `anon` and `PUBLIC`. Restricted routine execution strictly to `service_role`. Maintained `SECURITY DEFINER` and pinned `search_path = public, pg_temp;`.
  2. **Schema Privilege Verification:** Updated `scripts/verify-schema.mjs` with strict assertions ensuring `authenticated` and `anon` are blocked from `release_expired_holds` and `service_role` possesses explicit `EXECUTE` privileges.
  3. **Automated Negative & Positive Privilege Tests:** Added tests in `buyer-web/src/test/rpcs.test.ts` verifying that `authenticated` sellers and `anon` callers receive SQLSTATE 42501 (`permission denied`) when invoking `release_expired_holds`, while `service_role` execution succeeds. Verified that anonymous callers retain access to public buyer RPCs (`create_order_with_reservation`, `get_order_by_token`).
  4. **Buyer PII Exposure Decision Documented:** Documented that `get_order_by_token` returns only `buyer_name` (for greeting on the `/order/[id]` receipt screen), gated by 128-bit secret `order_token` (UUIDv4) and order ID, and strictly excludes sensitive fulfillment PII (`buyer_phone`, `shipping_address`, `pincode`). Added automated test asserting exclusion of sensitive PII and cross-order token isolation.
  5. **Idempotency & Retry Semantics Formalized (Model B):** Formalized and documented the checkout retry model as **Model B: Inventory-level duplicate protection without request-level idempotency**. Verified via automated tests that sequential duplicate submissions for a 1-of-1 product fail on the second attempt with `STOCK_UNAVAILABLE`, leaving the first reservation and order untouched.
  6. **Reaper State Regression Suite:** Added tests verifying that trusted `service_role` reaper execution cancels only genuine expired holds (`hold_expires_at < clock_timestamp()`), while leaving paid, cancelled, and unexpired orders across multiple sellers completely intact.
  7. **Evidence Classification:** Updated `docs/TASK-1.3-CONCURRENCY-TEST-REPORT.md` to explicitly classify PGlite as an in-process WASM simulation and state that real multi-connection PostgreSQL validation is scheduled for the pre-production staging gate.
  8. **Comprehensive Hardening Report:** Authored formal report [`docs/TASK-1.3.1-HARDENING-REPORT.md`](file:///c:/LiveDrop/docs/TASK-1.3.1-HARDENING-REPORT.md).

* **Files Created / Modified:**
  * Created: `docs/TASK-1.3.1-HARDENING-REPORT.md`
  * Modified: `supabase/migrations/009_create_core_business_rpcs.sql`
  * Modified: `scripts/verify-schema.mjs`
  * Modified: `buyer-web/src/test/rpcs.test.ts`
  * Modified: `docs/TASK-1.3-RPC-CONTRACT.md`
  * Modified: `docs/TASK-1.3-COMPLETION-REPORT.md`
  * Modified: `docs/TASK-1.3-CONCURRENCY-TEST-REPORT.md`
  * Modified: `docs/IMPLEMENTATION-LOG.md`

* **Verification Commands Executed & Results:**
  1. `node scripts/verify-schema.mjs` ➔ 9 migrations applied, 5 tables, 8 indexes, 9 Paisa columns, 5 triggers, 13 RLS policies, 6 RPCs verified; `release_expired_holds` revoked from anon and authenticated, granted to service_role (Exit code 0).
  2. `npm --prefix buyer-web test -- --run` ➔ 114/114 tests passed across 4 test suites: `smoke.test.tsx` (1), `schema.test.ts` (33), `rls.test.ts` (35), `rpcs.test.ts` (45) (Exit code 0).
  3. `npm --prefix buyer-web run typecheck` ➔ TypeScript strict mode passed with 0 errors (Exit code 0).
  4. `npm --prefix buyer-web run lint` ➔ ESLint passed with 0 warnings/errors (Exit code 0).

* **Verdict:**
  * **PASS — TASK-1.3 CLOSED; READY FOR TASK-1.4**

---

### `TASK-1.4: Supabase Integration, Realtime Foundation & Development Data/Environment Gate`
* **Phase:** Phase 1 — Database & Security Foundation
* **Date:** 2026-09-11
* **Requirement IDs:** `NFR-SYS-01`, `REQ-SEC-01..04`, `REQ-PRV-01..02`, `ADR-003`, `ADR-009`
* **Status:** **COMPLETED**
* **Change Summary:**
  1. **Roadmap Reconciliation:** Reconciled roadmap numbering in `docs/32-implementation-plan.md` to formally record TASK-1.4 as the architectural bridge connecting the database core to the buyer/seller application vertical slices.
  2. **Buyer Web Supabase Client & Strict Environment Validation:** Installed `@supabase/supabase-js`. Implemented `buyer-web/src/lib/supabase/env.ts` validating public environment variables and rejecting any presence of service-role keys with fatal errors. Implemented `buyer-web/src/lib/supabase/client.ts` configuring a browser-safe anonymous Supabase client with session persistence disabled.
  3. **Seller Mobile Supabase Service & Config:** Added `supabase_flutter: ^2.17.2` to `seller-app`. Implemented `seller-app/lib/core/config/env_config.dart` with validation and service-role protection. Implemented `seller-app/lib/core/services/supabase_service.dart` managing client lifecycle and authentication session state.
  4. **Strongly Typed Domain Contracts & Paisa Enforcement:** Created `buyer-web/src/types/domain.ts` and `seller-app/lib/domain/models/models.dart` representing all database entities, relations, and RPC payloads with strict integer Paisa monetary typing (`number` / `int`).
  5. **Typed Error Classification Hierarchy:** Created `buyer-web/src/lib/errors.ts` and `seller-app/lib/core/errors/exceptions.dart` mapping database/RPC errors (`STOCK_UNAVAILABLE`, `EMPTY_CART`, `EXCEEDS_CART_LIMIT`, `MIXED_DROP_PRODUCTS`, `INVALID_DROP`, `PRODUCT_ALREADY_RECLAIMED`, `INVALID_ORDER_TOKEN`, `UNAUTHORIZED`, `NETWORK_ERROR`) into structured application error classes without leaking raw stack traces.
  6. **Application Data Access Layers:** Created `buyer-web/src/lib/data/buyer-catalog.ts` for typed public drop fetching, product grid retrieval, atomic checkout RPC invocation, and token-gated receipt retrieval with PII minimization. Created `seller-app/lib/data/repositories/seller_repository.dart` for authenticated seller operations. Prohibited `release_expired_holds()` from both client surfaces.
  7. **Realtime Foundation:** Implemented `buyer-web/src/lib/realtime/catalog-realtime.ts` with drop-scoped channel subscription (`drop:{dropId}:products`), monotonic entity version defense against out-of-order network events, and explicit unsubscription cleanup. Implemented `seller-app/lib/data/realtime/seller_order_realtime.dart` for seller order events.
  8. **Deterministic Development Seed Fixtures:** Created `supabase/seed.sql` containing synthetic test fixtures for seller profiles, drops (draft, live, closed), products across states, and representative orders. Integrated seed validation into `scripts/verify-schema.mjs`.
  9. **Comprehensive Verification:** Wrote 18 new automated integration and contract tests across web and mobile. Verified that all 132 tests in `buyer-web` and 10 tests in `seller-app` pass with exit code 0. Passed TypeScript strict typecheck, ESLint, Next.js production build, Flutter analyze, and schema verification.

* **Files Created / Modified:**
  * Created: `buyer-web/src/lib/supabase/env.ts`
  * Created: `buyer-web/src/lib/supabase/client.ts`
  * Created: `buyer-web/src/types/domain.ts`
  * Created: `buyer-web/src/lib/errors.ts`
  * Created: `buyer-web/src/lib/data/buyer-catalog.ts`
  * Created: `buyer-web/src/lib/realtime/catalog-realtime.ts`
  * Created: `buyer-web/src/test/data-layer.test.ts`
  * Created: `buyer-web/src/test/realtime.test.ts`
  * Created: `seller-app/lib/core/config/env_config.dart`
  * Created: `seller-app/lib/core/errors/exceptions.dart`
  * Created: `seller-app/lib/core/services/supabase_service.dart`
  * Created: `seller-app/lib/domain/models/models.dart`
  * Created: `seller-app/lib/data/repositories/seller_repository.dart`
  * Created: `seller-app/lib/data/realtime/seller_order_realtime.dart`
  * Created: `seller-app/test/seller_repository_test.dart`
  * Created: `seller-app/test/realtime_test.dart`
  * Created: `supabase/seed.sql`
  * Created: `docs/TASK-1.4-SUPABASE-INTEGRATION-REPORT.md`
  * Modified: `buyer-web/package.json` & `buyer-web/package-lock.json`
  * Modified: `seller-app/pubspec.yaml` & `seller-app/pubspec.lock`
  * Modified: `scripts/verify-schema.mjs`
  * Modified: `docs/32-implementation-plan.md`
  * Modified: `docs/IMPLEMENTATION-LOG.md`

* **Verification Commands Executed & Results:**
  1. `node scripts/verify-schema.mjs` ➔ All 9 migrations, 5 tables, 8 indexes, 9 Paisa columns, 5 triggers, 13 RLS policies, 6 RPCs, 19 routine privileges, and seed data verified (Exit code 0).
  2. `npm --prefix buyer-web test -- --run` ➔ 132/132 tests passed across 6 test suites (Exit code 0).
  3. `npm --prefix buyer-web run typecheck` ➔ TypeScript strict mode passed with 0 errors (Exit code 0).
  4. `npm --prefix buyer-web run lint` ➔ ESLint passed with 0 warnings/errors (Exit code 0).
  5. `npm --prefix buyer-web run build` ➔ Next.js optimized production build generated cleanly (Exit code 0).
  6. `& "C:\flutter\bin\flutter.bat" analyze` ➔ No issues found (Exit code 0).
  7. `& "C:\flutter\bin\flutter.bat" test` ➔ 10/10 tests passed (Exit code 0).

* **Verdict:**
  * **PASS — TASK-1.4 COMPLETE; READY FOR BUYER/SELLER VERTICAL SLICE**





