# 11 — Realtime / Synchronization Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Realtime channels, subscription lifecycle, reconnect, ordering, fallbacks; server-side state freshness (reaper) |
| Executed | Code trace (seller + buyer realtime), publication membership in local DB (migration 019), GitHub Actions API for reaper runs (read-only) |
| Not executed | Live Realtime latency on hosted Supabase; device background/foreground/network transitions |

## 1. Channels

| Side | Channel | Tables / events | Filter | Subscriber | Start | Stop | Fallback |
|---|---|---|---|---|---|---|---|
| Seller | `seller-orders-<dropId>` | `orders` INSERT, UPDATE | `drop_id=eq.<dropId>` | `KanbanBoardScreen` | After initial load **only if a drop is selected** (default is "All Drops" → none) | `dispose`, drop change | **None** (manual refresh) |
| Buyer | catalogue channel per drop | `products` `*` | drop | `catalog-realtime.ts` | Page load | Unmount | 3 s polling; monotonic `version` gate against out-of-order events |

Publication `supabase_realtime` contains `products`, `orders`, `payment_attempts` (019). The seller app uses only `orders`. Documentation (docs/14) specifies a seller-scoped channel `seller:{seller_id}:orders` covering all drops — not implemented (SA-DOC-001).

## 2. Lifecycle properties (seller)

| Property | Behaviour | Assessment |
|---|---|---|
| What is synchronised | Order list of one drop (by full refetch on any event) | Products, claims, dashboard counters are not synchronised (SA-RT-001) |
| Reconnect | Left to `realtime_client`; the app never observes channel status (`onStatusChanged` unused) | No "updates paused" indicator; no catch-up refetch after reconnect (SA-RT-002) |
| Duplicate listeners | Previous channel removed before creating a new one | OK |
| Memory leaks | Channel removed in `dispose` | OK |
| Stale subscriptions | After sign-out the Kanban is disposed with the shell | OK |
| Event ordering | Each event triggers an independent `getAllOrders(dropId)`; responses are not sequenced, so an older response can overwrite a newer one | INFERRED race (low impact; next event/refresh corrects) |
| Deduplication | Not needed (full refetch) | Costly: one full nested download per event (SA-PERF-001) |
| Payload handling | Payload parsed to `SellerOrder` then discarded (parse errors swallowed) | Wasted; incremental apply would avoid refetches |
| Auth | Realtime uses the session JWT; RLS applies to postgres_changes; token refresh handled by the library | INFERRED |

## 3. Scenario checks

| Scenario | Seller app today | Evidence |
|---|---|---|
| New order arrives | Visible only on Orders tab with a drop selected; Home/Products unchanged | `kanban_board_screen.dart:95-105` |
| Payment claim arrives | **Not visible** until the Payments tab is pulled to refresh (claims are `payment_attempts`, not subscribed) | `pending_verifications_screen.dart:41-69` |
| Verification changes state | Payments list reloads itself; other tabs stale (IndexedStack) | SA-CQ-001 |
| Product becomes unavailable (reserved/sold) | Seller Products tab stale; buyer site updates within ~1–3 s | SA-RT-001; buyer `catalog-realtime.ts` |
| Order status changes (reaper, buyer actions) | Kanban (selected drop) refetches; otherwise stale | — |
| Seller changes inventory (edit, mark sold) | Buyer site updates via realtime/polling; seller's other tabs stale | — |
| App backgrounded / foregrounded | No refresh on resume (no lifecycle observer outside camera) | PROVEN-CODE; device NOT TESTED |
| Network loss / restoration | No banner; no catch-up | SA-RT-002 |
| Token refresh | Library-managed | INFERRED |
| Logout / login | Shell rebuilt → fresh subscriptions | OK |

## 4. State freshness on the server: the reaper

Realtime can only propagate state that exists. The most important "sync" defect is server-side: expired holds are released only by `release_expired_holds()`, called from GitHub Actions (`*/5` configured). The scheduler actually ran it **≈5 times per day** — median gap 5 h 07 min, max 7 h 42 min across the last 30 scheduled runs (`evidence/hosted-reaper-schedule.md`, PROVEN-HOSTED). `create_order_with_reservation` does not reclaim expired holds lazily. Effect on a live: every abandoned checkout keeps a unique piece "Reserved" for the rest of the stream, for buyers and seller alike (SA-OPS-001, CRITICAL).

Fix options (recommended first):
1. `pg_cron` job every minute calling the reaper inside the database (check availability with H8), with per-order commits and consistent lock order (also fixes SA-INT-002).
2. Lazy expiry inside the checkout RPC (release an expired, unclaimed hold under the same row lock before the availability check) — makes correctness independent of any scheduler.
3. Keep the GitHub workflow only as a backup monitor (alert if H9 > 0 for more than 2 minutes).

## 5. Target design for the seller app
One **LiveSession store** (app-level, created when a drop is live or selected):
- Subscribes to `orders`, `payment_attempts` (seller-scoped via RLS) and `products` of the active drop.
- Applies payloads incrementally; refetches a small summary RPC on `SUBSCRIBED` after (re)connect and on app resume.
- Exposes counters and queues to Home, Products, Orders, Payments; shows a banner when the channel is not `SUBSCRIBED`.
- Pairs with FCM for background alerts (claims, late claims, expiring windows) — see [13](13-NOTIFICATION-AUDIT.md).

## 6. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-OPS-001 | CRITICAL | P0 | Reaper runs ≈5×/day; no lazy expiry — holds last hours |
| SA-RT-001 | HIGH | P0 | No realtime on Home/Products/Payments; Kanban only for one selected drop |
| SA-RT-002 | MEDIUM | P1 | No status/reconnect/catch-up; full refetch per event |
| SA-INT-002 | MEDIUM | P1 | Verify vs reaper deadlock |
| SA-CQ-001 | MEDIUM | P1 | Tabs never refresh on focus |
| SA-DOC-001 | MEDIUM | P2 | Realtime contract in docs/14 not implemented |
