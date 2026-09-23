# LiveDrop — 1,000-User Scalability & Performance Audit (Phase 0 Baseline)

**Document Version:** 1.0.0  
**Audit Date:** 2026-09-22  
**Target Scenario:** 1,000 Concurrent Users (950 Buyers, 50 Sellers) During a Live Boutique Drop Burst  
**Governing Standard:** Section 14, 15, 16, 32 & 33 of Phase 0 Specification  

---

## 1. Performance Findings Matrix

| Area | Current Architecture | Expected Load (1k Users) | Bottleneck Identified | Concrete Evidence | Required Change | Benchmark Method |
|---|---|---|---|---|---|---|
| **Buyer Realtime Subscriptions** | 1:1 Supabase Realtime WebSocket per buyer | 950 simultaneous WebSockets on drop start | Connection limit exhaustion. Free tier capped at 200 conns; Pro capped at 500 conns. | [`catalog-realtime.ts:75`](file:///c:/LiveDrop/buyer-web/src/lib/realtime/catalog-realtime.ts#L75) | Transition to CDN-cached HTTP delta polling (3-5s) or a broadcast fanout layer. | k6 WebSocket connection load test (1,000 conns). |
| **Realtime Disconnect Polling Storm** | 3-second `setInterval` polling fallback | 800 disconnected buyers polling every 3s | PostgREST connection pool saturation (266 req/sec against un-cached Postgres view). | [`catalog-realtime.ts:149`](file:///c:/LiveDrop/buyer-web/src/lib/realtime/catalog-realtime.ts#L149) | Edge caching via Cloudflare / Vercel ISR (`s-maxage=3, stale-while-revalidate=5`). | Apache Benchmark / k6 GET flood (300 RPS). |
| **Garment Image Egress** | Direct uncompressed 1200x1200px JPEG from Supabase Storage | 1,000 buyers loading 100 items (~22 MB per buyer) | 22 GB egress per broadcast; exceeds 2 GB/month Free tier limit by 11x in 30 minutes. | [`image_service.dart:74`](file:///c:/LiveDrop/seller-app/lib/core/services/image_service.dart#L74), [`seller_repository.dart:649`](file:///c:/LiveDrop/seller-app/lib/data/repositories/seller_repository.dart#L649) | WebP compression (<100KB), thumbnail pipeline (300px for grid), and Cloudflare CDN proxy. | Egress calculation & Lighthouse network throttle. |
| **Single-Piece Reservation Lock Contention** | `create_order_with_reservation` row locks `FOR UPDATE` | 100 concurrent checkout attempts on the same piece | Row-level lock queueing in Postgres. Safe for integrity, but P99 latency spikes under contention. | [`015_fulfillment_idempotency_and_rejection_release.sql:196`](file:///c:/LiveDrop/supabase/migrations/015_fulfillment_idempotency_and_rejection_release.sql#L196) | Invariant is preserved (1 winner, 99 get `STOCK_UNAVAILABLE`). Need pre-checkout availability checks. | k6 concurrency script targeting single piece with 100 threads. |
| **Reaper Sequential Scan Under Load** | `release_expired_holds()` iterates expired orders | Scheduled every 5 minutes during active live drops | Without indexes, scanned entire `orders` table. Mitigated locally by Migration 017 indexes. | [`017_create_performance_indexes.sql:11`](file:///c:/LiveDrop/supabase/migrations/017_create_performance_indexes.sql#L11) | Apply Migration 017 to remote staging & production database. | EXPLAIN ANALYZE on 10,000 synthetic order records. |

---

## 2. 1,000-User Capacity Model & Burst Scenarios

| Scenario | Modeled Workload | Requests / Sec | Active Connections | Messages / Sec | DB Queries / Sec | DB Conns Required | Storage Egress | Platform Bottleneck & Verdict |
|---|---|---|---|---|---|---|---|---|
| **Case 1: 1,000 Buyers Browsing Drop** | 950 buyers viewing catalog, scrolling grid | ~50 req/sec (assets & navigation) | 950 HTTP, 200 WS (max) | ~10 msg/sec | 5–10 QPS | 5–10 | ~25 MB/sec | **UNSUPPORTED on Free Tier** (WS & Egress limits). |
| **Case 2: 1,000 Buyers Opening Drop Simultaneously** | Drop goes live, link shared on live stream | 1,000 req in 5 sec (200 RPS) | 1,000 HTTP conns | 0 | 200 QPS (SSR hits) | 30–50 | 22 GB egress burst | **UNSUPPORTED without Edge CDN/ISR**. |
| **Case 3: 100 Concurrent Checkouts** | 100 buyers click "Reserve Now" simultaneously | 100 RPC invocations | 100 HTTP conns | 100 WAL events | 100 transactions | 25–40 (via pooler) | Negligible (<1 MB) | **LIKELY SUPPORTED** by Postgres row locks. |
| **Case 4: 50 Checkout Requests / Sec** | Sustained flash sale checkout rate | 50 RPS | 50 HTTP conns | 50 WAL events | ~150 QPS | 20–30 | Negligible | **SUPPORTED NOW** if using Supavisor pooler. |
| **Case 5: 100 Checkout Requests / Sec** | Peak burst during high-heat garment release | 100 RPS | 100 HTTP conns | 100 WAL events | ~300 QPS | 40–60 (max pool) | Negligible | **NOT PROVEN**; approaching DB connection pool ceiling. |
| **Case 6: One-Item Reservation Race** | 100 buyers racing for identical single-piece item | 100 concurrent RPCs | 100 HTTP conns | 1 WAL update | 1 write, 99 aborts | 10–15 | Negligible | **SUPPORTED NOW**; 1 succeeds, 99 return `STOCK_UNAVAILABLE`. |
| **Case 7: Multi-Item Reservation Burst** | 50 buyers reserving 3–5 items each | 50 RPCs (200 items locked) | 50 HTTP conns | ~200 WAL updates | ~150 QPS | 15–25 | Negligible | **SUPPORTED NOW**; ordered locking (`ORDER BY id ASC`) prevents deadlocks. |
| **Case 8: Realtime Reconnect Storm** | Network glitch disconnects 800 buyers | 800 reconnects in 2 sec | 800 WS handshakes | 0 | 266 QPS (polling fallback) | 60+ (EXHAUSTION) | ~5 MB/sec | **UNSUPPORTED**; causes database 504 Gateway Timeout. |
| **Case 9: Image Download Burst** | 1,000 buyers downloading 50 garment photos | 50,000 image requests | 500–1,000 HTTP | 0 | 0 (Static storage) | 0 | 11 GB in 60s | **UNSUPPORTED**; blows monthly egress quota in 1 min. |
| **Case 10: Payment Claim Burst** | 50 buyers submit UTRs within 60 seconds | ~1 RPS | 50 HTTP conns | 50 WAL events | ~5 QPS | 5 | Negligible | **SUPPORTED NOW**; `submit_buyer_payment_claim` is fast. |
| **Case 11: Large Expired-Hold Reaper Run** | Reaper cleans 200 expired reservations at once | 1 invocation / 5 min | 1 service connection | 200 WAL updates | 1 batch query | 1 | Negligible | **SUPPORTED NOW** (with Migration 017 indexes). |

---

## 3. Buyer Realtime Architecture Comparison

| Dimension | Option A: Supabase Realtime per Buyer | Option B: Edge CDN + Periodic Polling | Option C: Hybrid (CDN Polling for Buyers, Realtime for Sellers) | Option D: Dedicated Fanout Proxy (Ably / Pusher) |
|---|---|---|---|---|
| **Latency** | 50–200ms (Immediate WebSocket) | 3,000–5,000ms | 3,000ms (Buyer), 100ms (Seller) | 100–300ms |
| **Monthly Infrastructure Cost** | High ($25 Pro base + $10/1k WS) | Zero ($0 on Cloudflare Free) | Zero to Low ($0–$25) | Medium ($30–$100/mo) |
| **Connection Ceiling** | Hard limits (200 Free / 500 Pro) | Unlimited at Edge (>100k conns) | Unlimited (Buyer), 50 conns (Seller) | 10,000+ conns |
| **Database Load** | Negligible during steady state; severe on reconnect storm | Zero on origin DB (absorbed by Edge CDN cache) | Zero on origin DB for buyers | Single webhook publisher from Postgres |
| **Failure Behavior** | Connection drops trigger 3s polling fallback storm | Graceful background revalidation (SWR) | Highly resilient; seller retains live Kanban | External dependency failure risk |
| **Implementation Effort** | Already partially implemented | Minimal (Add cache headers & SWR) | Low (Current codebase + Cache-Control) | Medium (Requires new cloud service) |
| **Recommendation** | **REJECT for Buyers** | **VIABLE** | **RECOMMENDED FOR PHASE 1** | **FUTURE PHASE 8** |
