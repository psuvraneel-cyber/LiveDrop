# 17 — Performance Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Launch, login, dashboard, inventory, image pipeline, order list, payment queue, realtime, search, memory, rebuilds, lists |
| Executed | Suite 15 (seller query cost under RLS with a seasoned seller: 20 drops × 100 pieces, 2,000 orders, nested items); T24 image micro-benchmark (Dart VM on the audit host); suite 14.1 (40 concurrent checkouts); code inspection for request counts, rebuilds, list virtualisation |
| Not executed | Anything on a phone (launch, frame timings, memory, real network latency, Realtime latency) — NOT TESTED; budgets from docs/22 cannot be confirmed |

## 1. Measurements

| Item | Measured | Budget (docs/22) | Notes |
|---|---|---|---|
| `getAllOrders()` server time + size, 2,000 orders | **≈144 ms, ≈2,473 KB JSON** | — | Called by Home (×2), Orders, Analytics, Shipping shortcut and on every realtime event (`15_perf_seller_queries.out`) |
| RLS plan for the order list | Seq scan + hashed sub-plan on `drops`, 1.2 ms for 2,000 rows | — | SQL is not the bottleneck |
| `getPendingVerifications()` | 2.0 ms (empty queue) | — | Cheap |
| `getProducts(liveDrop)` | 0.5 ms | — | Cheap |
| Image compression 1280×720 → 720×720 | **389–444 ms, 552 KB** JPEG (dev host) | < 600 ms, < 250 KB WebP | Synthetic textured photo (worst-case entropy) |
| Image compression 4000×3000 → 1200×1200 | **2.95–3.0 s, 1,158 KB** JPEG (dev host) | < 600 ms | Low-end phones are several times slower than the host CPU |
| 40 concurrent checkouts on one piece | Exactly one winner, no errors | — | `14_concurrency.out` 14.1 |
| Cold start, login, dashboard on device | NOT TESTED | < 2.5 s cold start | Device plan D1–D2 |
| Realtime push latency | NOT TESTED | < 2 s | Only Kanban subscribes |
| PDF label generation | NOT TESTED | < 1 s | — |

## 2. Code-level checks

| Check | Finding |
|---|---|
| N+1 queries | None on the server path (PostgREST embeds items/products). Client-side duplication instead: `getRecentActivity` re-fetches all orders and claims already fetched by the dashboard (SA-PERF-002) |
| Excessive network requests | Home performs **7 sequential requests**; every realtime event = one full nested order download (SA-PERF-001, SA-RT-002) |
| Unbounded payloads | No pagination anywhere; payload grows with lifetime orders (SA-PERF-001) |
| JSON parsing | `fromJson` for thousands of nested orders on the UI isolate → likely frame drops on low-end phones (INFERRED) |
| Analytics | Computed in Dart from the full order history on every open (SA-ANL-001) |
| Duplicate subscriptions | None (channel replaced on drop change) |
| Large image decoding | Lists use `Image.network` with full 1200 px sources for 54 px thumbnails, no `cacheWidth` → decode cost and image-cache churn |
| Blocking UI | Compression runs in `compute` (good); repository JSON decode runs on the UI isolate |
| Inefficient lists | Kanban, Products, Payments, Drops use `ListView.builder` (good); Home and Analytics use non-lazy `ListView`/`GridView.count` (small, fine) |
| Unnecessary rebuilds | Per-card 1 s `Timer.periodic` countdown for pending orders (visible cards only, acceptable); IndexedStack keeps 5 tabs alive (memory, no rebuilds) |
| Unnecessary animations | Infinite LIVE pulse, skeleton shimmer, bounce buttons — cheap; not harmful to comprehension |
| Search latency | Client-side filtering over loaded lists per keystroke — fine for hundreds of items |

## 3. Expected behaviour during a busy live (model)
A live with 300 buyers and 100 pieces produces several hundred order/claim events in an hour. With the Kanban open on the live drop, each event downloads the full drop order list (tens to hundreds of KB with nested items) and parses it on the UI isolate; on 4G this means continuous background downloads and possible jank exactly when the seller needs the phone most. The fix is architectural but small: incremental updates from Realtime payloads + a summary RPC, paginated "history" views, and JSON parsing off the UI isolate.

## 4. Recommendations (ordered by value)
1. Summary RPC for Home/Live Command Center (counts, queues) — one round trip (SA-PERF-002).
2. Drop- and status-scoped, paginated order queries; incremental realtime updates (SA-PERF-001, SA-RT-002).
3. Native image compression to 1080–1200 px WebP/JPEG q75–80 (target < 250 KB, < 600 ms on target device) (SA-PERF-003); thumbnails via `cacheWidth`/smaller renditions.
4. Ledger-based SQL analytics (SA-ANL-001).
5. Device benchmark (plan D1, D4, D5) to confirm budgets.

## 5. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-PERF-001 | MEDIUM | P1 | Unpaginated nested order downloads everywhere (≈2.4 MB per season) |
| SA-PERF-003 | MEDIUM | P2 | Image output/time above ADR-005 and docs/22 budgets |
| SA-PERF-002 | LOW | P2 | Seven sequential requests on Home |
| SA-RT-002 | MEDIUM | P1 | Full refetch per realtime event |
| SA-ANL-001 | MEDIUM | P2 | Analytics computed client-side from all orders |
