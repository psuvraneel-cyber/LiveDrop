# LiveDrop — Architecture Decision Register (Phase 0 Baseline)

**Document Version:** 1.0.0  
**Audit Date:** 2026-09-22  
**Governing Standard:** Section 34 & 42-Q of Phase 0 Specification  

---

## 1. Architecture Decision Matrix

### Decision 1: Buyer Realtime vs Edge-Cached Polling (1,000 Concurrent Users)
- **Option A: 1:1 Supabase Realtime WebSocket per Buyer**
  - *Complexity:* Low (already partially written).
  - *Cost:* High ($25/mo Pro base + $10 per 1,000 active connections).
  - *Latency:* 50–200ms.
  - *Reliability:* Poor on free/pro tier ceilings; disconnect storms crash DB with 3s polling.
  - *Scaling:* Hard ceiling at plan connection quota.
  - *Maintenance:* High connection state monitoring required.
- **Option B: Edge-Cached Polling (SWR on CDN)**
  - *Complexity:* Low (Next.js route handler + Cloudflare/Vercel cache headers).
  - *Cost:* Zero (runs on free Cloudflare/Vercel edge).
  - *Latency:* 3,000–5,000ms.
  - *Reliability:* Extreme (absorbs 100k+ users without origin hit).
  - *Scaling:* Virtually unlimited.
  - *Maintenance:* Very low.
- **Option C: Hybrid Architecture (RECOMMENDED)**
  - *Design:* Buyers use 3-second SWR Edge-cached polling; Sellers retain dedicated Realtime WebSockets for order Kanban and claims.
  - *Trade-off:* 3s latency for buyers is completely acceptable for clothing flash sales; sellers get instant alerts. Zero extra cost.

---

### Decision 2: Seller Offline Ingestion Reliability
- **Option A: In-Memory / Direct HTTP (Current Codebase)**
  - *Complexity:* Minimal.
  - *Cost:* Zero.
  - *Reliability:* Extremely fragile. Any dropped cellular connection loses photo and metadata.
  - *Migration Risk:* High (unusable for tier-2/3 Indian boutique sellers with spotty 4G/5G).
- **Option B: Persistent SQLite + Background Worker (ADR-006 RECOMMENDED)**
  - *Complexity:* Medium (Requires `sqflite`, `path_provider`, and isolate/workmanager).
  - *Cost:* Zero.
  - *Reliability:* High. Images written to local disk immediately upon shutter press; syncs in background.
  - *Migration Risk:* Low (isolated to `seller-app`).

---

### Decision 3: Seller Push Notifications
- **Option A: Foreground WebSocket Realtime Only (Current Codebase)**
  - *Complexity:* None.
  - *Cost:* Zero.
  - *Reliability:* Poor. If seller switches apps, locks phone, or takes a phone call, no alerts are received.
- **Option B: Firebase Cloud Messaging (FCM) + Supabase Webhook / Edge Function (RECOMMENDED)**
  - *Complexity:* Medium (Firebase project setup, APNs/FCM keys, service worker).
  - *Cost:* Free tier on Firebase.
  - *Reliability:* High. Wakes app on incoming high-value payment claims and orders.
  - *Migration Risk:* Requires adding Firebase credentials to CI.

---

### Decision 4: Hosting & Image Delivery
- **Option A: Raw Supabase Storage URLs (Current Codebase)**
  - *Complexity:* None.
  - *Cost:* Free tier throttles after 2 GB/month (exhausted in 1 live drop).
  - *Latency:* Depends on Supabase AWS region.
  - *Reliability:* Fails abruptly when monthly egress quota is exceeded.
- **Option B: Cloudflare Caching Proxy + Supabase S3 (RECOMMENDED)**
  - *Complexity:* Low (CNAME record + Cloudflare Page Rule `Cache-Control: immutable`).
  - *Cost:* $0 on Cloudflare Free.
  - *Latency:* < 50ms edge caching across Indian metros.
  - *Reliability:* High (shields Supabase Storage from egress spikes).

---

### Decision 5: Seller Onboarding Model
- **Option A: Open Self-Service Registration (Current Code in Mig 020)**
  - *Complexity:* Low.
  - *Security:* Disastrous (fake UTRs, malicious sellers, brand impersonation).
  - *Operational Burden:* Extreme (fraud cleanup, manual post-facto bans).
- **Option B: Admin-Gated & Invite-Only Onboarding (RECOMMENDED)**
  - *Complexity:* Low (Add `is_approved` boolean on `profiles`, default `false`).
  - *Security:* High. Only vetted boutique owners can publish drops.
  - *Operational Burden:* Low for MVP boutique pilot (manual WhatsApp vetting).

---

## 2. Decisions Requiring Human Architectural Approval

1. **Approval Gate for Seller Accounts:**
   - *Question:* Should we revert migration 020's automatic profile creation and enforce `is_approved = false` by default, requiring platform admin activation before a seller can create drops?
   - *Recommendation:* **APPROVE**. Unverified self-service registration represents a critical P0 security risk.

2. **Adoption of Hybrid Realtime (Option C):**
   - *Question:* Should the buyer webfront stop attempting 1:1 WebSocket connections on drops with >200 concurrent viewers and rely on 3-second CDN-cached HTTP delta polling?
   - *Recommendation:* **APPROVE**. This keeps infrastructure within free/low-cost tiers while guaranteeing stability under 1,000-user bursts.

3. **In-Flight Checkout Recovery Strategy:**
   - *Question:* Should the buyer webfront persist the active checkout idempotency key to `sessionStorage` to allow seamless retry on page refresh?
   - *Recommendation:* **APPROVE**. Eliminates false `STOCK_UNAVAILABLE` errors when mobile browsers reload interrupted requests.
