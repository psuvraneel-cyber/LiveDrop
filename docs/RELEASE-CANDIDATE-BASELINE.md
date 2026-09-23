# LiveDrop — Release Candidate Baseline Report (Phase 0)

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-24  
**Audit Phase:** Phase 0 — Initial System State & Baseline Confirmation  
**Governing Roles:** Principal Software Architect, Senior QA Lead, SRE Lead  
**Authoritative Index:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Operating Guardrails:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)  

---

## 1. Source Control & Repository State

| Attribute | Authoritative Value | Evidence |
|---|---|---|
| **Git Branch** | `main` | `git branch` -> `* main` |
| **Current Commit** | `5012293` | `git log -n 1 --oneline` -> `5012293 feat: add Flutter seller app, buyer web storefront components, and database migrations` |
| **Origin Sync** | Up to date with `origin/main` | Clean branch status |
| **Working Tree Status** | Local Phase 0 & Phase 1 pre-flight commits staged/untracked; lint & build blockers remediated | Zero unhandled syntax or compilation errors |

---

## 2. Application & Runtime Versions

| Subsystem | Version | Framework / Engine | Core Dependencies |
|---|---|---|---|
| **Buyer Webfront** | `0.1.0` | Next.js 16.3.4 (Turbopack, App Router) | React 19.2.8, `@supabase/supabase-js` 2.116.0, `qrcode` 1.5.4, TypeScript 5 |
| **Seller Mobile App** | `1.0.0+1` | Flutter 3.41.6 / Dart 3.11.4 | `supabase_flutter` 2.17.2, `camera` 0.11.0+4, `image` 4.3.0, `pdf` 3.11.1, `printing` 5.13.2 |
| **Local DB Engine** | WASM 18.3 | PGlite `@electric-sql/pglite` 0.5.8 | Sequential SQL migration & RLS runner |
| **Remote Staging DB**| 17.6.1.166 | Hosted Supabase PostgreSQL 17 (ap-south-1) | Project ID: `aoagqdtnrbmayfoajzes` (Status: `ACTIVE_HEALTHY`) |
| **Test Hardware** | Android 12 (API 31) | Physical Device attached via USB ADB | `M2007J17I (mobile) • 7732644d • android-arm64` |

---

## 3. Subsystem Build & Verification Baseline

| Test Suite / Build Target | Runner | Scope | Status | Notes |
|---|---|---|---|---|
| **Buyer TypeScript** | `npm run typecheck` (`tsc --noEmit`) | Next.js App Router, SSR, Data Layer | ✅ PASS | Exit code 0 |
| **Buyer ESLint** | `npm run lint` (`eslint`) | Next.js Core Web Vitals & TypeScript | ✅ PASS | Exit code 0 (0 errors, 1 warning) |
| **Buyer Unit/Component Tests** | `npm test` (`vitest run`) | Cart, Checkout, Idempotency, RPCs, RLS | ✅ PASS | 391 passed in 20 test files |
| **Buyer Next.js Production Build** | `npm run build` (`next build`) | SSR, Dynamic Routes, Static Optimization | ✅ PASS | Routes `/`, `/cart`, `/checkout`, `/drop/[slug]`, `/order/[id]` |
| **Seller Flutter Static Analysis** | `flutter analyze` | Clean architecture, lint rules | ✅ PASS | No issues found (ran in 60.9s) |
| **Seller Flutter Unit & Widget Tests**| `flutter test` | Auth, Offline Queue, Label PDF, UI Tokens | ✅ PASS | 42 passed in 8 test suites |
| **Relational Schema Verification** | `node scripts/verify-schema.mjs` | 27 migrations, 16 triggers, 15 RPCs | ✅ PASS | PGlite verification exit code 0 |
| **Failure Injection Matrix** | `node scripts/test-failure-injections.mjs` | Concurrency, Idempotency, Security | ✅ PASS | 33 passed, 3 blocked by remote/hardware prerequisites |

---

## 4. Staging Environment & Database Migration Discrepancy

| Migration ID | Migration Name | Local Repository | Remote Staging (`aoagqdtnrbmayfoajzes`) | Status |
|---|---|---|---|---|
| `001` – `014` | Profiles, Drops, Products, Orders, RLS, Direct UPI, Persistent Claim Window | Present | Applied | Synchronized |
| `015` | `fulfillment_idempotency_and_rejection_release.sql` | Present | Pending | **Stage 2 Target** |
| `016` | `public_projection_views.sql` | Present | Pending | **Stage 2 Target** |
| `017` | `create_performance_indexes.sql` | Present | Pending | **Stage 2 Target** |
| `018` | `storage_buckets.sql` | Present | Pending | **Stage 2 Target** |
| `019` | `enable_realtime_publication.sql` | Present | Pending | **Stage 2 Target** |
| `020` | `auto_create_seller_profile_trigger.sql` | Present | Pending | **Stage 2 Target** |
| `021` | `seller_provisioning_security.sql` | Present | Pending | **Stage 2 Target** |
| `022` | `checkout_idempotency_conflict_detection.sql` | Present | Pending | **Stage 2 Target** |
| `023` | `late_upi_recovery.sql` | Present | Pending | **Stage 2 Target** |
| `024` | `safe_drop_closure.sql` | Present | Pending | **Stage 2 Target** |
| `025` | `product_editing.sql` | Present | Pending | **Stage 2 Target** |
| `026` | `fulfillment_state_machine.sql` | Present | Pending | **Stage 2 Target** |
| `027` | `product_multi_images_and_storage.sql` | Present | Pending | **Stage 2 Target** |

---

## 5. Remediated Pre-Flight Findings

1. **Accidental Nested Build Folder Purged**: `buyer-web/buyer-web/.next` removed; eliminates 4,970+ spurious ESLint errors.
2. **`eslint.config.mjs` Hardened**: Added `buyer-web/**`, `scratch/**`, and `test-results/**` to `globalIgnores`.
3. **`CheckoutSuccessView.tsx` `prefer-const` Fixed**: Changed `let startTime` to `const startTime`.
4. **`ProductDetailModal.tsx` React 19 State Adjustment**: Eliminated synchronous `setState` in `useEffect` when switching `product.id`; converted to render-time state adjustment pattern.
5. **`HomeStorefront.tsx` Dead Code Pruned**: Removed unused `useRouter`, `formatPaisaToINR`, and unreferenced state hooks.
