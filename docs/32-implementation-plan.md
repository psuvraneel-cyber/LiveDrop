# 32 — Master Engineering Implementation Roadmap: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  
**Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  
**Definition of Done:** [`docs/34-definition-of-done.md`](file:///c:/LiveDrop/docs/34-definition-of-done.md)  

---

## 1. Roadmap Architecture: Vertical Slices

LiveDrop is engineered in **11 sequential vertical slices** (Phases 0 through 10). Each slice delivers end-to-end functionality across database, client, security, and verification layers, allowing continuous validation without architectural guesswork.

```
Phase 0: Workspace & Repo Foundation
   └── Phase 1: Database DDL, RPCs & Security Foundation
          └── Phase 2: Buyer Catalog Edge Feed
                 └── Phase 3: Unified Reservation & WhatsApp Checkout
                        └── Phase 4: Seller Auth & Drop Controller
                               └── Phase 5: Seller Ingestion Viewfinder
                                      └── Phase 6: Realtime Kanban Pipeline
                                             └── Phase 7: 4×6 Thermal PDF Engine
                                                    └── Phase 8: Offline Upload Queue
                                                           └── Phase 9: Realtime Hardening
                                                                  └── Phase 10: E2E Validation & Gate Sign-off
```

---

## 2. Granular Task Breakdown by Vertical Slice

### Phase 0 — Workspace & Repository Foundation
* **Goal:** Initialize multi-package repository structure, linting, toolchains, and environment configs.

#### `[COMPLETED] TASK-0.1: Initialize Antigravity Monorepo Workspace`
* **Requirement IDs:** `NFR-SYS-01`
* **Status:** **COMPLETED** (Verified 2026-09-11 — see [`docs/PHASE-0-COMPLETION-REPORT.md`](file:///c:/LiveDrop/docs/PHASE-0-COMPLETION-REPORT.md))
* **Dependencies:** None.
* **Files / Modules Expected:**
  * `buyer-web/` (Next.js 16+ App Router, TypeScript, Vitest, ESLint)
  * `seller-app/` (Flutter 3.41+ Android project, Dart 3.11+)
  * `supabase/` (Supabase configuration, migrations, seed structure)
  * `.github/workflows/` (Buyer web CI, Seller app CI, keepalive)
  * `scripts/` (Keepalive probe)
* **Inputs:** Approved project specifications.
* **Outputs:** Compiling empty projects for web and mobile with zero product features.
* **Acceptance Criteria:** `tsc --noEmit`, `eslint`, `vitest`, `next build`, `flutter analyze`, `flutter test`, and debug APK build all pass with exit code 0.
* **Tests:** Automated smoke tests executed and passed on both platforms.
* **Security:** Complete `.gitignore` protecting secrets, environment variables, and build outputs.
* **Definition of Done:** Both projects scaffolded, linting clean, tests green, and documented in Git.

---

### Phase 1 — Database & Security Foundation
* **Goal:** Deploy PostgreSQL relational schema, indexes, RLS policies, and core transaction RPCs.

#### `[COMPLETED] TASK-1.1: Deploy Relational Tables & Indexes`
* **Requirement IDs:** `REQ-DB-01..05`
* **Status:** **COMPLETED** (Verified 2026-09-11 — see [`docs/TASK-1.1-COMPLETION-REPORT.md`](file:///c:/LiveDrop/docs/TASK-1.1-COMPLETION-REPORT.md))
* **Dependencies:** `TASK-0.1`
* **Files Created:**
  * `supabase/migrations/001_create_profiles.sql`
  * `supabase/migrations/002_create_drops.sql`
  * `supabase/migrations/003_create_products.sql`
  * `supabase/migrations/004_create_orders.sql`
  * `supabase/migrations/005_create_order_items.sql`
  * `supabase/migrations/006_create_indexes.sql`
  * `buyer-web/src/test/schema.test.ts`
  * `scripts/verify-schema.mjs`
* **Inputs:** [`docs/12-database-design.md`](file:///c:/LiveDrop/docs/12-database-design.md).
* **Outputs:** 5 core tables (`profiles`, `drops`, `products`, `orders`, `order_items`) and 8 justified performance indexes.
* **Acceptance Criteria:** Foreign keys, check constraints, integer Paisa currency, and indexes apply with zero errors.
* **Tests:** 25/25 automated schema assertions pass in Vitest (`buyer-web/src/test/schema.test.ts`) and standalone migration verification (`scripts/verify-schema.mjs`).
* **Security:** Non-nullable seller ownership references validated across all entities. RLS isolated for TASK-1.3 per plan.

#### `[COMPLETED] TASK-1.2: Row-Level Security & Database Access Control`
* **Requirement IDs:** `REQ-SEC-01..04`, `REQ-PRV-01..02`, `ADR-003`, `ADR-009`
* **Status:** **COMPLETED** (Verified 2026-09-11 — see [`docs/TASK-1.2-COMPLETION-REPORT.md`](file:///c:/LiveDrop/docs/TASK-1.2-COMPLETION-REPORT.md))
* **Dependencies:** `TASK-1.1`
* **Files Created / Modified:**
  * `supabase/migrations/008_enable_rls_and_policies.sql`
  * `buyer-web/src/test/rls.test.ts`
  * `docs/RLS-ACCESS-MATRIX.md`
  * `docs/TASK-1.2-RLS-SECURITY-MATRIX.md`
  * `docs/TASK-1.2-RLS-TEST-REPORT.md`
  * `docs/TASK-1.2-COMPLETION-REPORT.md`
  * `scripts/verify-schema.mjs`
  * `buyer-web/src/test/schema.test.ts`
  * `docs/16-security-architecture.md`
* **Inputs:** [`docs/RLS-ACCESS-MATRIX.md`](file:///c:/LiveDrop/docs/RLS-ACCESS-MATRIX.md), [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md), ADR-003.
* **Outputs:** Hardened RLS enabled on all 5 core tables (`profiles`, `drops`, `products`, `orders`, `order_items`), least-privilege table grants, 13 security policies.
* **Acceptance Criteria:** Seller multi-tenancy isolation strictly enforced (`auth.uid()`). Public anonymous buyers can read only live drops and products. Orders and order items are strictly token-gated by secret `order_token` (header `x-order-token`). Direct REST `INSERT` on `orders` and `order_items` blocked for all roles.
* **Tests:** 35/35 automated security test assertions pass under distinct role contexts (`anon`, `authenticated` Seller A, `authenticated` Seller B) in `buyer-web/src/test/rls.test.ts`, plus schema and standalone verifications (69/69 total tests pass).
* **Security:** India DPDP Act 2023 order privacy verified, zero open enumeration, zero cross-seller data leakage.

#### `[COMPLETED] TASK-1.3: Implement Core Database RPC Functions`
* **Requirement IDs:** `REQ-FR-B4.1`, `REQ-FR-S3.2`, `REQ-SEC-01..04`, `ADR-003`, `ADR-009`
* **Status:** **COMPLETED** (Verified 2026-09-11 — see [`docs/TASK-1.3-COMPLETION-REPORT.md`](file:///c:/LiveDrop/docs/TASK-1.3-COMPLETION-REPORT.md))
* **Dependencies:** `TASK-1.2`
* **Files Created / Modified:**
  * `supabase/migrations/009_create_core_business_rpcs.sql`
  * `buyer-web/src/test/rpcs.test.ts`
  * `docs/TASK-1.3-RPC-CONTRACT.md`
  * `docs/TASK-1.3-CONCURRENCY-TEST-REPORT.md`
  * `docs/TASK-1.3-COMPLETION-REPORT.md`
  * `scripts/verify-schema.mjs`
  * `buyer-web/src/test/schema.test.ts`
  * `buyer-web/src/test/rls.test.ts`
* **Inputs:** RPC definitions from [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md), [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md), [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md).
* **Outputs:** 6 hardened RPCs: `create_order_with_reservation`, `mark_order_paid`, `release_expired_holds`, `get_order_by_token`, `force_release_hold`, `mark_product_sold_offline`.
* **Acceptance Criteria:** Functions enforce `SECURITY DEFINER SET search_path = public, pg_temp;`. Mathematical deadlock-free row locking (`ORDER BY id ASC`). Multi-item all-or-nothing atomicity. Integer Paisa monetary integrity. Default `PUBLIC` execution revoked; seller routines restricted to authenticated seller sessions.
* **Tests:** 37/37 automated RPC and concurrency assertions pass in `buyer-web/src/test/rpcs.test.ts` (106/106 total repository tests pass). Concurrency stress-tested across 2, 5, and 20 simultaneous competing clients with 0 over-reservations and 0 deadlocks.
* **Security:** `REVOKE ALL ON FUNCTION ... FROM PUBLIC;` enforced across all 6 routines. Seller ownership verification (`auth.uid() = drop.seller_id`) enforced. Uncontested/contested expired hold resolution (`PRODUCT_ALREADY_RECLAIMED`) verified.


---

### Phase 2 — Buyer Catalog Feed
* **Goal:** Build high-speed, SSR mobile catalog grid with search and live stock badges.

#### `TASK-2.1: Implement Edge SSR Catalog Page`
* **Requirement IDs:** `REQ-FR-B1.1`, `NFR-01`
* **Dependencies:** `TASK-1.3`
* **Files Expected:** `buyer-web/src/app/drop/[slug]/page.tsx`, `ProductGrid.tsx`
* **Inputs:** Drop slug parameter, Supabase PostgREST client.
* **Outputs:** Server-rendered product grid loading in < 1.5s on 4G.
* **Acceptance Criteria:** Displays boutique logo, drop title, and 2-column square image grid.
* **Tests:** Playwright snapshot test; Lighthouse FCP benchmark.
* **Performance:** Ensure image skeleton loaders prevent CLS.

#### `TASK-2.2: Implement Flash Code Badge & Search Bar`
* **Requirement IDs:** `REQ-FR-B1.2`, `REQ-FR-B1.3`
* **Dependencies:** `TASK-2.1`
* **Files Expected:** `buyer-web/src/components/catalog/SearchBar.tsx`, `ProductCard.tsx`
* **Outputs:** Interactive code search input and status chips (`All`, `Available`).
* **Acceptance Criteria:** Monospace 16px ExtraBold badges. Search filters instant client-side.
* **Tests:** Vitest component tests.

---

### Phase 3 — Reservation & WhatsApp Order Flow
* **Goal:** Sticky bottom cart, delivery form with localStorage persistence, atomic RPC, and WhatsApp handoff.

#### `TASK-3.1: Build Sticky Cart Bar & Drawer`
* **Requirement IDs:** `REQ-FR-B2.1`, `REQ-FR-B2.2`
* **Dependencies:** `TASK-2.2`
* **Files Expected:** `StickyCartBar.tsx`, `CartDrawer.tsx`, `useCart.ts`
* **Outputs:** Floating bottom bar, bundle drawer with item removal and running subtotal.
* **Acceptance Criteria:** Min 48×48px touch targets; emerald green action color.

#### `TASK-3.2: Build Delivery Form with Local Storage`
* **Requirement IDs:** `REQ-FR-B3.1`, `REQ-FR-B3.2`
* **Dependencies:** `TASK-3.1`
* **Files Expected:** `CartDrawer.tsx`
* **Outputs:** 4 minimal fields (Name, Phone, Pincode, Address) with `localStorage` autofill.
* **Acceptance Criteria:** Validates 10-digit Indian mobile and 6-digit pincode; includes `[Clear Saved Info]` link.

#### `TASK-3.3: Wire Atomic Checkout RPC & WhatsApp Dispatcher`
* **Requirement IDs:** `REQ-FR-B4.1`, `REQ-FR-B4.2`, `REQ-FR-B4.3`
* **Dependencies:** `TASK-3.2`, `TASK-1.2`
* **Files Expected:** `WhatsAppCheckout.tsx`, `whatsapp.ts`, `app/order/[id]/page.tsx`
* **Outputs:** Transaction submission, stock collision modal handling, WhatsApp redirect, and static UPI receipt page.
* **Acceptance Criteria:** Contested items outlined in red with remove action; WhatsApp deep link encoded cleanly.
* **Tests:** End-to-end checkout test in Playwright.

---

### Phase 4 — Seller Authentication & Drop Management
* **Goal:** Seller login in Flutter app and Drop session controller.

#### `TASK-4.1: Implement Seller Auth & Session Guard`
* **Requirement IDs:** `SEC-AUT-01`
* **Dependencies:** `TASK-0.1`, `TASK-1.3`
* **Files Expected:** `seller-app/lib/presentation/auth/login_screen.dart`, `supabase_client.dart`
* **Outputs:** Email/password login with secure token persistence.

#### `TASK-4.2: Build Drops Overview & Drop Controller`
* **Requirement IDs:** `REQ-FR-S1.3`, `RULE-DRP-01..05`
* **Dependencies:** `TASK-4.1`
* **Files Expected:** `drops_list_screen.dart`, `create_drop_screen.dart`
* **Outputs:** Drops list, create drop form, toggle between `Draft`, `Live`, and `Closed`.
* **Acceptance Criteria:** Enforces single active live drop per seller.

---

### Phase 5 — Seller Product Ingestion Engine
* **Goal:** Sub-30-second camera intake with client WebP compression and auto-incremented flash codes.

#### `TASK-5.1: Build Camera Viewfinder & Client WebP Compressor`
* **Requirement IDs:** `REQ-FR-S1.1`, `REQ-FR-S1.2`
* **Dependencies:** `TASK-4.2`
* **Files Expected:** `camera_screen.dart`, `image_service.dart`
* **Outputs:** Square 1:1 guide viewfinder, auto-crop, and WebP compression < 250 KB.
* **Acceptance Criteria:** Shutter-to-reset latency < 0.8s on physical test device.

#### `TASK-5.2: Product Form Overlay & Code Incrementer`
* **Requirement IDs:** `REQ-FR-S1.2`
* **Dependencies:** `TASK-5.1`
* **Files Expected:** `product_form_overlay.dart`, `product_repository.dart`
* **Outputs:** Suggested flash code (`#A15`), numeric price keypad, background upload trigger.

---

### Phase 6 — Seller Realtime Order Pipeline (Kanban)
* **Goal:** 3-column Kanban order board with live WebSocket updates and UPI verification.

#### `TASK-6.1: Build Visual Kanban Order Pipeline`
* **Requirement IDs:** `REQ-FR-S3.1`
* **Dependencies:** `TASK-4.2`, `TASK-3.3`
* **Files Expected:** `kanban_board_screen.dart`, `order_card.dart`
* **Outputs:** 3 tabs: Pending, Paid / Ready to Pack, Dispatched. Live countdown timers on pending orders.

#### `TASK-6.2: Implement Mark as Paid Conflict-Guarded Transition`
* **Requirement IDs:** `REQ-FR-S3.2`, `RULE-ORD-07`
* **Dependencies:** `TASK-6.1`, `TASK-1.2`
* **Files Expected:** `order_card.dart`, `order_repository.dart`
* **Outputs:** Invokes `mark_order_paid` RPC. Catches `PRODUCT_ALREADY_RECLAIMED` error and alerts seller.

---

### Phase 7 — 4×6 Thermal Courier Slip & Dispatch
* **Goal:** Client-side 4×6 inch PDF label generator and courier dispatch workflow.

#### `TASK-7.1: Build Client-Side 4×6 PDF Shipping Slip Layout`
* **Requirement IDs:** `REQ-FR-S4.1`, `REQ-FR-S4.2`
* **Dependencies:** `TASK-6.2`
* **Files Expected:** `pdf_service.dart`, `shipping_label_view.dart`
* **Outputs:** 4×6 inch (100×150 mm) thermal PDF containing Recipient, Sender, Contents, and Code-128 Barcode.
* **Acceptance Criteria:** Renders in < 1s; outputs to Bluetooth ESC/POS or Android Print Spooler.

#### `TASK-7.2: Dispatch Workflow & Courier Tracking`
* **Requirement IDs:** `REQ-FR-S4.3`
* **Dependencies:** `TASK-7.1`
* **Files Expected:** `order_card.dart`
* **Outputs:** Tracking number input modal; transitions order to `shipped`.

---

### Phase 8 — Offline Ingestion Upload Queue
* **Goal:** SQLite/Hive local storage cache for garment intake in zero-connectivity environments.

#### `TASK-8.1: Implement Local Queue & Background Worker`
* **Requirement IDs:** `REQ-OFF-01..04`
* **Dependencies:** `TASK-5.2`
* **Files Expected:** `local_queue_repository.dart`, `upload_worker.dart`
* **Outputs:** Queues WebP images and metadata; resumes background uploads with exponential backoff on reconnect.

---

### Phase 9 — Realtime Hardening & Keepalive
* **Goal:** Edge-case WebSocket handling, version ordering, and free-tier keepalive automation.

#### `TASK-9.1: Realtime Monotonic Versioning & Reconnect Resync`
* **Requirement IDs:** `REQ-RT-01..03`
* **Dependencies:** `TASK-2.1`, `TASK-6.1`
* **Files Expected:** `useRealtimeProducts.ts`, `realtime_manager.dart`
* **Outputs:** Discards out-of-order events using `version` sequence; fetches REST snapshot on reconnect.

#### `TASK-9.2: Free Tier Keepalive Automation`
* **Requirement IDs:** `REQ-OPS-01`
* **Dependencies:** `TASK-1.1`
* **Files Expected:`.github/workflows/supabase-keepalive.yml`
* **Outputs:** Automated 24-hour health check ping preventing Supabase 7-day inactivity pause.

---

### Phase 10 — End-to-End Validation & Release Gate
* **Goal:** Complete test suite execution across all 13 layers, performance benchmarking, and production release gate sign-off.

#### `TASK-10.1: Execute Automated E2E & Concurrency Test Harness`
* **Requirement IDs:** `ALL`
* **Dependencies:** Phases 1 through 9.
* **Files Expected:** `tests/e2e/`, `tests/k6/concurrency_test.js`
* **Outputs:** All 9 E2E scenarios verified; 20-client simultaneous collision benchmarked.

#### `TASK-10.2: Performance Budget Audit & Gate Sign-Off`
* **Requirement IDs:** `NFR-01..06`
* **Dependencies:** `TASK-10.1`
* **Outputs:** Production readiness report transitioning `docs/00-project-status.md` to `READY FOR IMPLEMENTATION`.
