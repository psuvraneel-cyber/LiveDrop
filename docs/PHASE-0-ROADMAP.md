# LiveDrop — Master Future Engineering Roadmap (Phase 0 Baseline)

**Document Version:** 1.0.0  
**Audit Date:** 2026-09-22  
**Governing Standard:** Section 35 & 36 of Phase 0 Specification  

---

## 1. Definitive Production Blockers Matrix

### P0 — Security & Data Integrity Blockers (MUST FIX BEFORE ANY PILOT)
1. **Unverified Seller Self-Service Registration (SEC-01)**
   - *Why:* Any user can register as a seller, provide a fake UTR for the ₹50 fee, and immediately start collecting buyer payments via their own UPI VPA.
   - *Evidence:* [`020_auto_create_seller_profile_trigger.sql`](file:///c:/LiveDrop/supabase/migrations/020_auto_create_seller_profile_trigger.sql) and [`seller_registration_screen.dart:116`](file:///c:/LiveDrop/seller-app/lib/presentation/auth/seller_registration_screen.dart#L116).
   - *Dependencies:* None.
   - *Expected Fix:* Remove auto-profile trigger on `auth.users`; introduce `is_approved` status on `profiles` (default `false`); require admin backend approval or invite codes.
   - *Validation Method:* Automated test proving unapproved user cannot create drops or products.

### P1 — Functional MVP Blockers (REQUIRED FOR BASIC OPERATION)
2. **Missing Product Edit Capability (F-01)**
   - *Why:* In live streaming, boutique sellers frequently mistype prices, sizes, or garment codes during rapid intake. The inability to correct an item forces them to discard pieces or start over.
   - *Evidence:* No `updateProduct` method in [`seller_repository.dart`](file:///c:/LiveDrop/seller-app/lib/data/repositories/seller_repository.dart); no edit UI in [`product_details_screen.dart`](file:///c:/LiveDrop/seller-app/lib/presentation/products/product_details_screen.dart).
   - *Dependencies:* Database `update_product` RPC with immutability guards on reserved items.
   - *Expected Fix:* Add `update_product` RPC and Flutter edit dialog allowing updates when `status = 'available'`.
   - *Validation Method:* Integration test confirming price/title update on available product and rejection on reserved product.

3. **Interrupted Checkout Session Recovery (SEC-03)**
   - *Why:* Mobile network drops during checkout result in the buyer refreshing the page, which generates a new idempotency key. The second attempt is rejected with `STOCK_UNAVAILABLE`, leaving the buyer unable to pay.
   - *Evidence:* [`checkout/page.tsx:63`](file:///c:/LiveDrop/buyer-web/src/app/checkout/page.tsx#L63) stores key in React `useRef`.
   - *Dependencies:* Browser `sessionStorage`.
   - *Expected Fix:* Persist `idempotency_key` and active checkout payload in `sessionStorage` so page reloads replay the same key.
   - *Validation Method:* Vitest simulating network drop, reload, and identical key replay returning the committed order.

4. **Offline Ingestion Queue in Seller App (ADR-006)**
   - *Why:* Boutique streaming environments have erratic mobile cellular coverage. Without local storage and background retry, photo intake fails and drops data.
   - *Evidence:* Zero local storage dependencies (`sqflite`, `hive`) in [`seller-app/pubspec.yaml`](file:///c:/LiveDrop/seller-app/pubspec.yaml).
   - *Dependencies:* `sqflite` or `hive`, `path_provider`.
   - *Expected Fix:* Implement SQLite-backed persistent upload queue in `seller-app`.
   - *Validation Method:* Unit test asserting image survives app restart and auto-retries upload on network return.

### P2 — Production Operations Blockers (REQUIRED FOR COMMERCIAL STABILITY)
5. **Fulfilment State Machine Hole (SEC-05)**
   - *Why:* Orders jump directly from `paid` to `shipped` without intermediate packing verification or ready-to-ship enforcement.
   - *Evidence:* [`015_fulfillment_idempotency_and_rejection_release.sql:401`](file:///c:/LiveDrop/supabase/migrations/015_fulfillment_idempotency_and_rejection_release.sql#L401).
   - *Dependencies:* Migration update.
   - *Expected Fix:* Require `fulfilment_status = 'ready_to_ship'` before `mark_order_shipped` can execute.
   - *Validation Method:* SQL constraint assertion blocking shipping on `not_ready` orders.

6. **Image Storage Egress & CDN Caching (PERF-01)**
   - *Why:* 1,000 users loading 100 images will blow the 2 GB Supabase Free tier monthly egress limit in 30 minutes.
   - *Evidence:* [`image_service.dart:74`](file:///c:/LiveDrop/seller-app/lib/core/services/image_service.dart#L74) outputs uncompressed JPEGs; no CDN proxy or `Cache-Control` header configured.
   - *Dependencies:* Cloudflare / Supabase Storage config.
   - *Expected Fix:* Set `Cache-Control: public, max-age=31536000, immutable` and front storage with Cloudflare CDN.
   - *Validation Method:* HTTP header inspection asserting cache hit on second fetch.

### P3 — 1,000-Concurrent-User Blockers (SCALABILITY GATES)
7. **Buyer Realtime Connection Exhaustion (PERF-02)**
   - *Why:* 1:1 WebSocket connections per buyer will fail at 200/500 connection limits, triggering a 3s HTTP polling storm that crashes PostgreSQL.
   - *Evidence:* [`catalog-realtime.ts:75`](file:///c:/LiveDrop/buyer-web/src/lib/realtime/catalog-realtime.ts#L75).
   - *Dependencies:* Next.js Edge Cache / Vercel ISR / Cloudflare.
   - *Expected Fix:* Adopt Hybrid Model C (Edge-cached SWR polling for buyers, Realtime WebSocket strictly for sellers).
   - *Validation Method:* k6 load test simulating 1,000 concurrent viewers with origin DB receiving < 10 RPS.

---

## 2. Updated Dependency-Aware Master Roadmap

```
[Phase 0: Baseline & Audit] ───> COMPLETED
       │
       ▼
[Phase 1: Security & Seller Control Gate]
  ├── P0: Remove unverified signup trigger (Mig 020 remediation)
  ├── P0: Admin approval flag on seller profiles
  └── P1: Product editing RPC (update_product) & Flutter UI
       │
       ▼
[Phase 2: Fulfillment & Checkout Resilience]
  ├── P1: Browser reload checkout recovery (sessionStorage idempotency)
  ├── P1: Late UPI payment claim reconciliation
  └── P2: Fulfillment state machine enforcement (PAID -> READY_TO_SHIP -> SHIPPED)
       │
       ▼
[Phase 3: Offline Intake Reliability]
  ├── P1: Add sqflite & path_provider to seller-app
  ├── P1: SQLite persistent upload queue
  └── P1: Foreground/background sync worker with restart resilience
       │
       ▼
[Phase 4: CDN & Edge Scalability (1,000 Users)]
  ├── P2: Cloudflare CDN proxy for Supabase Storage images
  ├── P2: WebP compression & 300px thumbnail generation
  └── P3: Hybrid buyer polling with Edge Cache-Control headers
       │
       ▼
[Phase 5: Observability & Operational Tooling]
  ├── Sentry integration (Buyer Web & Flutter Seller)
  ├── Automated Slack/Discord alert on Reaper failure
  └── Basic admin dashboard for seller onboarding & dispute resolution
       │
       ▼
[Phase 6: Multi-Connection Load Testing & Verification]
  ├── k6 multi-threaded checkout race test against hosted staging
  ├── 1,000-user traffic simulation
  └── Final Production Go/No-Go Gate
```
