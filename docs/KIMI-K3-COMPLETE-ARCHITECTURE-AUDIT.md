# LiveDrop Architecture Audit (KIMI-K3)

## Executive Summary
LiveDrop is a specialized live-commerce and fulfillment operating system built for independent social-commerce and home-boutique sellers. The platform is designed to eliminate the friction of selling unique items via social live streams by providing a zero-download, zero-login mobile web catalog for buyers, paired with a Flutter-based native Android app for sellers.

Currently, the core database schema (Migrations 001 to 014), Role-Level Security (RLS) policies, and high-concurrency reservation RPCs are robustly implemented and tracked in the `main` branch. The buyer web application features a Next.js App Router catalog, checkout forms, and Direct UPI views.

However, several critical implementation gaps exist in the **tracked codebase**:
1. **Seller Mobile App**: The tracked Flutter app is merely a skeleton. Crucial features like camera ingestion, Kanban order boards, and 4x6 thermal PDF label generation exist only as uncommitted, untracked work-in-progress files.
2. **Offline Queue (Seller App)**: Although documented as Phase 8, the SQLite-based background queue for camera uploads is completely missing.
3. **Fulfillment Idempotency**: Migration 015, which introduces idempotency keys for checkouts, is currently untracked and not yet part of the official baseline.
4. **Realtime Hardening**: Phase 9 monotonic versioning and connection resilience logic is not fully present.
5. **Load Testing**: Physical Load Testing for 1,000 users (Phase 10) is absent.

The system's data layer (PostgreSQL schema, RLS, and RPCs) is structurally sound up to migration 014. However, the system is NOT production-ready for 1,000 simultaneous users due to the missing seller app components, offline ingestion queue, and lack of extensive edge-caching validation on the frontend catalog.

## Current Completion Matrix

| Area | Feature | Status | Evidence |
|---|---|---|---|
| BUYER | Edge SSR Catalog | IMPLEMENTED | `buyer-web/src/app/drop/[slug]/page.tsx` |
| BUYER | Cart & Checkout | IMPLEMENTED | `buyer-web/src/app/checkout/page.tsx`, `buyer-web/src/components/checkout/CheckoutForm.tsx` |
| BUYER | Realtime Updates | PARTIALLY IMPLEMENTED | `buyer-web/src/lib/realtime/catalog-realtime.ts` (lacks Phase 9 monotonic versioning) |
| SELLER | App Setup & Routing | IMPLEMENTED | `seller-app/lib/main.dart` |
| SELLER | Camera Intake | MISSING (WIP Untracked) | `seller-app/lib/presentation/intake/camera_intake_screen.dart` is untracked |
| SELLER | Kanban Board | MISSING (WIP Untracked) | `seller-app/lib/presentation/orders/` is untracked |
| SELLER | Shipping Label PDF | MISSING (WIP Untracked) | `seller-app/lib/core/services/pdf_label_service.dart` is untracked |
| SELLER | Offline SQLite Upload Queue | MISSING | No `upload_worker.dart` or `local_queue` in `seller-app/lib/data/` |
| BACKEND | Core Tables & Indexes | IMPLEMENTED | `supabase/migrations/001_create_profiles.sql` to `006_create_indexes.sql` |
| BACKEND | RPCs (Atomicity) | IMPLEMENTED | `supabase/migrations/009_create_core_business_rpcs.sql` |
| PAYMENTS | Direct UPI Intent | IMPLEMENTED | `buyer-web/src/components/checkout/DirectUpiPaymentView.tsx` |
| PAYMENTS | Manual Verification | IMPLEMENTED | `supabase/migrations/013_direct_upi_and_manual_payment_verification.sql` |
| SECURITY | RLS & Security Definer | IMPLEMENTED | `supabase/migrations/008_enable_rls_and_policies.sql` |
| BACKEND | Fulfillment Idempotency | MISSING (WIP Untracked) | `015_fulfillment_idempotency_and_rejection_release.sql` is untracked |
| DEPLOYMENT | CI/CD Workflows | IMPLEMENTED | `.github/workflows/` (based on prior validation) |

## Gap Analysis

1. **Missing feature (Seller Operations)**: The vast majority of the seller application (Camera Intake, Drops, Orders, Fulfillment) is completely missing from the tracked codebase. It currently exists only as uncommitted, untracked files.
2. **Missing feature (Offline Queue)**: Phase 8 of the implementation plan specifies a local SQLite/Hive queue for handling unstable networks during camera ingestion. This is entirely missing from the codebase.
3. **Partially implemented feature (Realtime Hardening)**: The frontend connects to Realtime but lacks the monotonic version ordering and resync logic required to prevent stale inventory states during reconnect storms.
4. **Security gap (Seller Authentication)**: Seller Authentication relies on an ad-hoc screen. A robust invitation, suspension, and account recovery flow is missing. Public data exposure through anon reads is not fully mitigated, as `016_public_projection_views.sql` remains untracked.
5. **Performance gap**: The buyer web catalog lacks explicit edge-caching configurations (e.g., `Cache-Control` headers for CDN) specifically designed for 1,000 concurrent hit bursts.
6. **Testing gap**: Rigorous load testing (Phase 10) for 1,000 users has never been executed.

## Target Architecture — 1,000 Concurrent Users

To support 1,000 concurrent users (950 buyers, 50 sellers) during a flash-sale drop without crashing:

* **Frontend & CDN (Buyer)**: Vercel or Cloudflare Edge. Catalog pages must use ISR (Incremental Static Regeneration) with a 5-10 second revalidation window. Images must be served through a specialized Image CDN (e.g., Cloudflare Images) to offload bandwidth from Supabase Storage.
* **Live Inventory Updates**: Rather than 1,000 individual Supabase Realtime WebSocket connections (which would exhaust Free/Pro tier limits), transition to a **broadcast/fanout layer** (e.g., Supabase Realtime Broadcast or a lightweight Ably/Pusher proxy) that pushes only ID + Status deltas. Alternatively, use CDN-cached HTTP polling.
* **Database (Supabase PostgreSQL)**: Use connection pooling (PgBouncer/Supavisor). The `create_order_with_reservation` RPC natively uses `idempotency_key` (introduced in untracked Migration 015) to absorb checkout retry storms safely.
* **Seller Mobile**: The Flutter app communicates directly with Supabase via authenticated REST and a single dedicated Realtime channel for order Kanban updates.

## Capacity Model

For 1,000 concurrent users:
* **Catalog Requests**: ~3,000-5,000 req/min during peak bursts. ISR at the Edge must drop origin hits to < 10 req/min.
* **Checkout Requests (Peak Burst)**: Up to 50 req/sec during flash drops. Supabase Postgres with PgBouncer can comfortably handle 50 TPS for the atomic `create_order_with_reservation` RPC, provided RLS doesn't trigger expensive subqueries.
* **Realtime Connections**: 1,000 WebSocket connections will exceed the Supabase Free tier (and standard Pro tier limits). **Bottleneck identified.** A fanout mechanism or CDN-cached polling (every 3-5s) is mandatory to prevent connection exhaustion.
* **Image Bandwidth**: Assuming 100 products * 250KB WebP images = 25MB per catalog load. 1,000 users = 25GB egress in 10 minutes. Cloudflare Image caching is mandatory.

## Production Security Model

* **Public/Client Privileges**: Anonymous buyers have read-only access to `drops` and `products` via strict RLS. Order modifications are only permitted via `SECURITY DEFINER` RPCs using an untamperable `order_token`.
* **Seller Privileges**: Sellers are isolated via RLS (`auth.uid() = seller_id`). Sellers can only mutate their own inventory and orders.
* **Service-Role Boundaries**: Background jobs operate via `service_role`. The service key is NEVER bundled into the Next.js client or Flutter APK.
* **Idempotency & Rate Limiting**: The `create_order_with_reservation` RPC must check `idempotency_key` (needs Migration 015 committed) to prevent duplicate cart checkouts. Rate limiting (e.g., Upstash or Cloudflare WAF) must be applied to the Next.js API routes handling the checkout handoff.
* **Public Data Projection**: Must commit `016_public_projection_views.sql` to explicitly sanitize buyer-facing read queries and prevent unauthorized data scraping.

## Proposed Database Changes

The tracked database schema is robust (001-014), but the following additions (currently existing as WIP untracked files) must be reviewed, finalized, and committed:

1. **Migration 015: Idempotency & Rejection Release**
   * **Reason**: Prevents duplicate order creation and safely handles payment rejection releases.
2. **Migration 016: Public Projection Views**
   * **Reason**: Sanitizes public read access to ensure sensitive seller and product data isn't exposed via raw PostgREST queries.
3. **Migration 017: Performance Indexes**
   * **Reason**: Adds composite indexes like `orders(status, hold_expires_at)` to prevent sequential scans during high-concurrency reaper executions.
4. **Migration 018: Storage Buckets**
   * **Reason**: Configures secure storage buckets for product images and seller assets.
5. **Schema Change: `audit_logs` table**
   * **Reason**: Track payment verification approvals and rejections by sellers for dispute resolution.

## Seller App Completion Roadmap

The seller app requires significant implementation effort to transition from the current tracked skeleton to a production-ready application.

* **PHASE A**: Formalize Authentication & Seller Invitation Flow.
* **PHASE B**: Settings & Storefront Configuration (UPI VPA validation).
* **PHASE C**: Camera Intake & Inventory Management. (Review and commit untracked `presentation/intake/` files).
* **PHASE D**: Live Dashboard & Kanban Board. (Review and commit untracked `presentation/orders/` files).
* **PHASE E**: Fulfillment & Labels. (Review and commit untracked `pdf_label_service.dart`).
* **PHASE F**: Offline Ingestion Queue (SQLite/Hive). **CRITICAL MISSING GAP.**
* **PHASE G**: Realtime Sync & Background Worker Resumption.
* **PHASE H**: Notifications (FCM implementation for 'New Order' push alerts).

## Buyer Experience Completion Roadmap

* **PHASE A**: Edge Caching & ISR configuration for `DropHeader` and `ProductGrid`.
* **PHASE B**: Implement Realtime Hardening (Monotonic versioning check inside `useRealtimeProducts.ts`).
* **PHASE C**: WhatsApp Checkout resiliency (ensure deep links fallback to clipboard copy if app is uninstalled).
* **PHASE D**: Direct UPI Intent refinement (handling specific Android/iOS UPI app link behaviors).
* **PHASE E**: End-to-end Idempotency testing (incorporating untracked `idempotency.ts` logic).

## Production Test Strategy

1. **Database & RLS**: Maintain Vitest suite in `buyer-web/src/test/` asserting isolation matrices.
2. **Integration (API)**: Ensure all RPCs (`create_order_with_reservation`, `mark_order_shipped`) continue to pass the failure injection harnesses.
3. **E2E Browser**: Expand Playwright tests (commit untracked `buyer-web/e2e/`) to cover Edge cases (expired hold recovery).
4. **Load & Concurrency**: Create a dedicated `k6` script targeting the checkout RPC with 50 TPS to validate Postgres locking and idempotency.
5. **Physical Mobile**: Distribute APK via Firebase App Distribution and physically test the camera viewfinder, offline queue resilience, and thermal PDF generation on various Android devices.

## Master Implementation Roadmap

1. **TASK-1**: Review, audit, and commit the untracked Database Migrations (015-018) to the main branch.
2. **TASK-2**: Review, audit, and commit the untracked Seller App components (Intake, Orders, Fulfillment).
3. **TASK-8.1**: Implement Seller Local Queue (SQLite) for offline reliability. *Depends on Camera Ingestion.*
4. **TASK-9.1**: Buyer Realtime Monotonic Versioning. *Depends on Catalog UI.*
5. **TASK-10.1**: K6 Load Testing Harness. *Depends on full environment deployment.*
6. **TASK-SEC-1**: Seller Invitation & Onboarding Flow.
7. **TASK-PERF-1**: Next.js ISR & Cloudflare caching setup. *Depends on Vercel/Hosting configuration.*

## Release Gates

* **GATE 1 (Feature Complete)**: Seller offline queue is implemented, and all untracked WIP files are finalized and merged.
* **GATE 2 (Security)**: `audit_logs` and `public_projection_views` are implemented; no PII exposure verified.
* **GATE 3 (Physical Device)**: Camera ingestion works offline, and Thermal PDF successfully prints via Bluetooth.
* **GATE 4 (Concurrency)**: K6 load test proves 0 over-reservations at 50 checkouts/second.
* **GATE 5 (Production Deployment)**: Supabase Pro plan activated (to handle connection limits or fanout implemented) and Cloudflare caching enabled.

## Final Engineering Assessment

**CURRENT STATE**: The backend data layer up to migration 014 (schema, RLS, RPCs, payment state machine) and the Next.js buyer web catalog are solidly implemented and tracked. 

**NOT COMPLETE**: The seller mobile app is virtually non-existent in the tracked codebase, with critical features like camera ingestion and order management floating as untracked WIP files. The heavily documented Phase 8 offline upload queue is entirely missing. The buyer catalog lacks robust Realtime reconnect hardening (Phase 9) and explicit Edge caching. 

**PRODUCTION BLOCKERS**: The missing seller application features (intake, kanban, fulfillment) and the missing offline queue. Untracked idempotency and projection migrations must be committed.

**1,000 USER BLOCKERS**: Supabase Free Tier WebSocket connection limits (500 max) will block 1,000 concurrent live buyers. A shift to a broadcast fanout layer or CDN-cached HTTP polling is mandatory.

**SECURITY BLOCKERS**: Lack of committed public projection views (`016_public_projection_views.sql`) to explicitly sanitize anonymous buyer reads.

**RECOMMENDED ARCHITECTURE**: Proceed with Supabase PostgreSQL as the authoritative transactional core. Implement Edge caching (ISR) on Vercel for the Next.js catalog to shield the database from read storms. Move away from 1:1 WebSocket connections for buyers towards a broadcast fanout or HTTP polling model. 

**IMPLEMENTATION ROADMAP**: Immediately prioritize auditing and committing the untracked WIP files (Migrations 015-018, Seller App UI). Following this, construct the missing offline SQLite queue for the seller app, harden the buyer realtime logic, and execute rigorous physical device and k6 load testing before any production launch.
