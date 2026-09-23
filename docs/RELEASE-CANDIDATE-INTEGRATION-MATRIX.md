# LiveDrop — Release Candidate Integration Matrix (Phase 54)

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-24  
**Audit Stage:** Stage 5 — Integration, Verification & Cross-Stack Parity Audit  
**Authoritative Index:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Operating Guardrails:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)  
**Target Environments:**
* **Physical Hardware:** Xiaomi M2007J17I (`7732644d`), Android 12 (API 31), 1080×2400 Display
* **Hosted Staging:** Supabase PostgreSQL 17.6 (`aoagqdtnrbmayfoajzes.supabase.co` in `ap-south-1`)
* **Local Test Automation:** Next.js Turbopack (`127.0.0.1:3000`), PGlite WASM 18.3, Mock Supabase Gateway (`127.0.0.1:54321`)

---

## 1. Executive Summary & Cross-Stack Architecture

The LiveDrop Release Candidate consists of four decoupled subsystems acting in lockstep:
1. **Seller Mobile Application (Flutter 3.41.6 / Dart 3.11.4)**: Provides camera-first garment ingestion, inventory management, drop scheduling, direct UPI payment manual verification, 4-stage fulfillment Kanban, and 4×6 thermal shipping label rendering.
2. **Buyer Web Experience (Next.js 16.3.4 / React 19 / TypeScript 5)**: Server-rendered anonymous buyer storefront, multi-angle garment gallery, isolated drop cart, high-concurrency reservation engine, direct UPI intent & QR presentation, and token-gated order tracking.
3. **Database & Realtime Core (Supabase / PostgreSQL 17.6)**: 27 relational migrations, 16 procedural triggers, 15 security-definer RPCs, row-level locking (`FOR UPDATE`), 100% integer Paisa currency invariants, and zero public table mutations.
4. **Autonomous Infrastructure & SRE (GitHub Actions / Scheduled Reapers)**: Automated cron sweeps executing `release_expired_holds()`, unmatched claim triage, and token validation.

---

## 2. 26-Vector End-to-End Commerce Integration Matrix

The following matrix records the systematic verification of every critical cross-subsystem interaction, covering data flow, security boundary enforcement, error handling, and test evidence.

| # | Operational Domain | Subsystem Interaction | Data Flow & Protocol | Guardrails Enforced | Verification Method & Artifacts | Status |
|---|---|---|---|---|---|---|
| **1** | **Seller Onboarding & Security Gate** | Flutter Seller App ➔ Supabase Auth ➔ PostgreSQL Triggers | `auth.signUp()` ➔ `trg_on_auth_user_created` creates profile with `is_approved = false`. | Zero unauthorized drop creation; unapproved sellers gated by `trg_enforce_drops_seller_approval`. | Physical device testing (`physical_device_register.png`), Migration 021, `seller_auth_registration_test.dart`. | ✅ **PASS** |
| **2** | **UPI VPA & Payee Configuration** | Flutter Seller App ➔ Supabase RPC | Seller saves VPA (e.g. `psuvraneel@okaxis`), Payee Name, and Advance % via `profiles` table. | Authoritative VPA format validation; Advance required calculated strictly on server in Paisa. | Physical device verification (`physical_device_payment_upi_settings.png`), `seller_repository_test.dart`. | ✅ **PASS** |
| **3** | **Drop Creation & Scheduling** | Flutter Seller App ➔ Supabase REST | Seller creates drop with title, start/end time, and custom slug. PostgREST insert into `drops`. | Status machine: `draft` ➔ `scheduled` ➔ `active` ➔ `closed`. Slug uniqueness enforced. | Physical device verification (`physical_device_dashboard.png`), `drops_list_screen.dart`, Playwright E2E. | ✅ **PASS** |
| **4** | **Multi-Angle Garment Intake** | Flutter Camera ➔ Disk Queue ➔ Supabase Storage | Camera captures up to 4 images ➔ writes to local cache ➔ `OfflineIntakeQueue` background upload ➔ `products.image_urls`. | Sub-30s capture loop; offline queue retries with exponential backoff on network drop; zero lost images. | `offline_intake_queue_test.dart` (10/10 PASS), `CameraIntakeScreen`, physical device camera integration. | ✅ **PASS** |
| **5** | **Real-Time Catalog Publishing** | PostgreSQL ➔ Realtime Publication ➔ Next.js / Flutter | Changes in `products` published to `supabase_realtime`. Public view `public_products_catalog` hides private fields. | Zero leakage of seller contact, costs, or internal notes to public buyers; anonymous SELECT enabled. | Migration 016 & 019, `catalog-feed.test.tsx`, `verify-schema.mjs`. | ✅ **PASS** |
| **6** | **Anonymous Buyer Discovery** | Web Browser ➔ Next.js Dynamic Route | Buyer navigates to `https://<domain>/drop/[slug]`. SSR loads drop and products from public projection. | No authentication required for buyers; Facebook Live copy-pasteable URL; zero server-side pre-rendering cache stale. | `app/drop/[slug]/page.tsx` (`force-dynamic`), Playwright TC-E2E-01, unit tests in `smoke.test.tsx`. | ✅ **PASS** |
| **7** | **Garment Multi-Image Carousel** | Next.js Buyer Webfront | Interactive thumbnail and modal preview for garment angles. Status badges: Available, Reserved, Sold. | High-contrast Noir badges; responsive layout for mobile viewport (360px–430px) and desktop. | `ProductCard.tsx`, `ProductDetailModal.tsx`, React 19 render-time state sync, `smoke.test.tsx`. | ✅ **PASS** |
| **8** | **Cart Management & Isolation** | Next.js Local Storage Engine | Buyer adds item to cart. Cart state scoped strictly to `drop_id` in localStorage. | Cross-drop mixing prevented; subtotal computed in integer Paisa; expired drop cleanses cart. | `cart-storage.ts`, `cart-storage.test.ts` (14/14 PASS). | ✅ **PASS** |
| **9** | **High-Concurrency Stock Reservation** | Next.js ➔ `rpc/create_order_with_reservation` | Simultaneous buyers submit checkout for last item. Database executes `SELECT FOR UPDATE` on `products`. | Exactly 1 winner gets reservation; remaining 3 get `STOCK_UNAVAILABLE`; 0 negative inventory; zero deadlocks. | Playwright TC-E2E-01, Failure injection Scenario 01, `rpcs.test.ts`. | ✅ **PASS** |
| **10** | **Checkout Idempotency & Conflict Guard** | Next.js ➔ `create_order_with_reservation` | Header `x-idempotency-key` with UUID or request hash submitted during order creation. | Resubmitting duplicate payload returns existing order; payload mismatch returns 409 conflict; 0 double orders. | Migration 022, `checkout-idempotency.test.ts` (18/18 PASS), Failure injection Scenario 31. | ✅ **PASS** |
| **11** | **Dynamic Delivery & Advance Calculation** | Next.js ➔ Server-Side RPC | Total = Items Subtotal + Delivery Fee. Advance Required = `CEIL(Total * advance_percent / 100)`. | 100% server calculated; integer Paisa; client cannot tamper with amounts; balance due tracked. | `orders` table constraints, `storefront-and-state-machine.test.ts`. | ✅ **PASS** |
| **12** | **Direct Peer-to-Peer UPI Payment Intent** | Next.js ➔ `rpc/initiate_payment_attempt` | Generates standard UPI URI: `upi://pay?pa=<vpa>&pn=<name>&am=<paisa/100>&cu=INR&tn=<order_token>`. | Dynamic QR code and native app deep links (GPay, PhonePe, Paytm); zero payment gateway fees. | `DirectUpiPaymentView.tsx`, `direct-upi-payments.test.ts` (35/35 PASS). | ✅ **PASS** |
| **13** | **Buyer Payment Claim & 24h Hold Extension** | Next.js ➔ `rpc/submit_buyer_payment_claim` | Buyer inputs 12-digit bank UTR / Ref #. Order transitions to `PAYMENT_SUBMITTED`. | Reservation hold extended by 24 hours to give seller time to manually verify bank account; duplicate UTR blocked. | Migration 014 & 023, `persistent-payment-claims-ui.test.tsx` (16/16 PASS). | ✅ **PASS** |
| **14** | **Seller Real-Time Verification Alert** | PostgreSQL Realtime ➔ Flutter Seller App | Realtime postgres_changes event notifies seller app of pending payment claim. | In-app counter badge increments; notification sound/vibration; zero manual polling required. | `pending_verifications_screen.dart`, physical device verification (`physical_device_payments_tab.png`). | ✅ **PASS** |
| **15** | **Seller Manual UPI Approval** | Flutter ➔ `rpc/verify_manual_upi_payment` | Seller checks bank SMS / app, matches UTR, and taps "Verify & Accept". | Inserts record into immutable `order_payments` ledger; order becomes `PAID`; inventory permanently decremented. | `verify_manual_upi_payment` RPC, physical device verification (`orders_retry2.png`), Playwright TC-E2E-02. | ✅ **PASS** |
| **16** | **Seller Manual UPI Rejection** | Flutter ➔ `rpc/reject_manual_upi_payment` | Seller taps "Reject (Fraud/Unreceived)". Order transitions to `PAYMENT_REJECTED`. | Inventory lock released instantly back to `AVAILABLE`; buyer alerted in real time with reason. | Migration 015, Failure injection Scenario 07, `direct-upi-payments.test.ts`. | ✅ **PASS** |
| **17** | **Late Payment Claim & Unmatched Ledger** | Next.js ➔ `rpc/submit_buyer_payment_claim` | Buyer submits UTR after reservation expired and item was re-sold to another buyer. | Payment claim isolated in `unmatched_payment_claims` table; seller notified to issue refund; 0 orphaned money. | Migration 023, Failure injection Scenario 08, `direct-upi-payments.test.ts`. | ✅ **PASS** |
| **18** | **Expired Hold Reaper Engine** | GitHub Actions / SRE Runner ➔ `rpc/release_expired_holds` | Background worker calls reaper every 1 minute. Releases unconfirmed reservations. | Items with `hold_expires_at < NOW()` and no payment claim reset to `AVAILABLE`; order marked `EXPIRED`. | `scripts/run-reaper.mjs`, `.github/workflows/reaper-cron.yml`, Scenario 05. | ✅ **PASS** |
| **19** | **Token-Gated Order Tracking Route** | Next.js Dynamic Route ➔ `rpc/get_order_by_token` | Buyer navigates to `/order/[id]?token=<order_token>`. | Anonymous lookup strictly gated by cryptographically random order token; UUID enumeration attacks return 404/403. | `app/order/[id]/page.tsx`, `order-route.test.tsx` (12/12 PASS), Scenario 19. | ✅ **PASS** |
| **20** | **WhatsApp Direct Seller Handoff** | Next.js Buyer Webfront ➔ WhatsApp Web/App | Deep link generates `https://wa.me/<seller_phone>?text=<encoded_order_details>`. | Pre-fills order token, item summary, and balance due; sanitizes phone number; seamless dispute resolution. | `lib/utils/whatsapp.ts`, `whatsapp-chat.test.ts` (14/14 PASS). | ✅ **PASS** |
| **21** | **Real-Time Kanban Order State Pipeline** | PostgreSQL Realtime ➔ Flutter Seller App | 4-column drag/tap board: Pending Payment ➔ Paid ➔ Ready to Ship ➔ Shipped. | Live order updates; state transition validation; sub-second synchronization with buyer actions. | `kanban_board_screen.dart`, physical device verification (`physical_device_orders_tab.png`). | ✅ **PASS** |
| **22** | **Order Fulfillment & Packing Check** | Flutter Seller App ➔ `rpc/mark_order_ready_to_ship` | Seller confirms physical garment inspection and packing checklist. | Validates order is `PAID` before allowing packaging; state updates to `READY_TO_SHIP`. | Migration 026, `shipping_dialog.dart`, Playwright TC-E2E-03. | ✅ **PASS** |
| **23** | **4×6 Thermal Shipping Label Generation** | Flutter Seller App ➔ PDF Engine | Generates 400×600 pt vector PDF with Code-128 barcode, buyer address, order ID, and delivery notes. | Compatible with TSC, Zebra, and standard Bluetooth thermal printers; pixel-perfect high-density typography. | `pdf_label_service.dart`, `shipping_label_screen.dart`, `sprint2_seller_operations_test.dart`. | ✅ **PASS** |
| **24** | **Carrier Tracking Dispatch** | Flutter ➔ `rpc/mark_order_shipped` | Seller enters Courier Name (Delhivery, Bluedart, etc.) and Tracking AWB. | Order status transitions to `SHIPPED`; buyer order tracking page displays live tracking link. | Migration 026, `order_details_screen.dart`, Playwright TC-E2E-03. | ✅ **PASS** |
| **25** | **Safe Drop Closure Invariant Guard** | Flutter Seller App ➔ Supabase REST | Seller taps "End Live Drop". Database trigger `trg_drops_safe_closure` validates drop state. | Drop closure blocked if any reservations are active (`PAYMENT_PENDING` or `PAYMENT_SUBMITTED`); prevents orphaned orders. | Migration 024, `seller_repository.dart`, failure injection Scenario 32. | ✅ **PASS** |
| **26** | **Physical Hardware & Network Resilience** | Xiaomi M2007J17I ➔ Supabase Remote Gateway | App operates under fluctuating mobile network (4G/5G/WiFi) and intermittent offline state. | Bounded offline intake queue with persistent file store; sub-second JWT skew recovery; zero unhandled crash. | Physical device verification on `7732644d`, in-app retry mechanism, `OfflineIntakeQueue`. | ✅ **PASS** |

---

## 3. Security Boundary & Guardrails Verification Summary

| Architectural Guardrail | Specification Rule | Verification Evidence | Status |
|---|---|---|---|
| **No Floating-Point Currency** | RULE-CUR-01: Money MUST always be represented as an integer in Paisa (`150000` = ₹1,500.00). | Checked all 27 DDL files, Next.js models, Flutter models, RPC inputs/outputs. Zero `float` or `double` found. | ✅ **COMPLIANT** |
| **No Direct UI Database Mutations** | RULE-SEC-01: UI components must never call raw `supabase.from('products').update(...)` for state transitions. | 100% of inventory and order transitions routed through security definer RPCs (`create_order_with_reservation`, etc.). | ✅ **COMPLIANT** |
| **No Service-Role Key Leaks** | RULE-SEC-02: Supabase Service-Role key MUST NEVER appear in client-facing environments. | Grep audit of `buyer-web/.next/static`, `seller-app/lib`, and APK bundle confirmed zero service keys. | ✅ **COMPLIANT** |
| **No Weakening of RLS** | RULE-SEC-03: Never disable RLS, drop RLS policies, or grant public write permissions. | Remote Supabase audit via MCP confirmed RLS active on all 7 tables; public access restricted to projection views. | ✅ **COMPLIANT** |
| **Pinned PostgreSQL Search Path** | RULE-SEC-04: All `SECURITY DEFINER` functions must include `SET search_path = public, pg_temp`. | Verified on all 15 RPCs across migrations 001–027. Remote database verified via `execute_sql`. | ✅ **COMPLIANT** |

---

## 4. Cross-System Environmental Sign-Off

* **Seller Mobile Subsystem:** Verified on Xiaomi `M2007J17I` (`7732644d`), Android 12 (API 31). Zero compilation or runtime crashes.
* **Buyer Web Subsystem:** Verified on Next.js 16.3.4 (App Router, Turbopack). 391 unit/component tests passed, 3 multi-role Playwright E2E passed.
* **Database & Staging Subsystem:** Verified on hosted Supabase staging (`aoagqdtnrbmayfoajzes`). 27 migrations, 16 triggers, 15 RPCs live and active.
* **SRE & Background Tasks:** Verified reaper logic in `scripts/run-reaper.mjs` and GitHub Actions workflow `.github/workflows/reaper-cron.yml`.
