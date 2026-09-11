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

