# 02 — Seller App Architecture (as implemented)

| | |
|---|---|
| Audited commit | `94ccfc9` (see [01](01-REPOSITORY-MAP.md) for the `main` delta — no seller/backend changes) |
| Date | 2026-10-03 |
| Scope | Every runtime path from a seller screen to PostgreSQL |
| Executed | Full read of `seller-app/lib`, migrations 001–033; local DB + Flutter audit suites |
| Not executed | Hosted Supabase, Android device |
| Diagram | [02-ARCHITECTURE.mmd](02-ARCHITECTURE.mmd) |

## 1. Layering

```
UI (StatefulWidgets, 5-tab IndexedStack + pushed routes)
  │   no state-management layer; each screen calls the repository in initState / on tap
  ▼
"Domain/service" layer — thin: ImageService (isolate compression), PdfLabelService,
  OfflineIntakeQueue (JSON manifest + JPEG files + in-process Timer retries), UrlLauncherHelper
  ▼
SellerRepository (one class, 1,031 lines) — every PostgREST / RPC / Storage call
SellerOrderRealtimeSubscription — the only Realtime wrapper
  ▼
supabase_flutter 2.17.2 (PKCE auth, session in SharedPreferences, auto token refresh)
  ▼
PostgREST (tables + RPC)  •  Realtime (postgres_changes)  •  Storage (product-images)  •  GoTrue
  ▼
PostgreSQL: RLS on all business tables, SECURITY DEFINER RPCs (20, search_path pinned),
  immutability triggers (products, orders payment fields, drops closure, profile approval)
  ▲
GitHub Actions cron → scripts/run-reaper.mjs → release_expired_holds() (service role)
```

The design intent — client is never authoritative for money or inventory — is **mostly honoured**: prices, totals, reservation, payment state and fulfilment transitions are decided in SQL. The defects are (a) holes in the SQL itself (late-claim paths, release, reaper cadence, a writable public view) and (b) a client that does not reflect the server state machine or live state.

## 2. Inventory of external interactions

### 2.1 Direct table access (PostgREST)

| # | Operation | Table | Caller (file:line) | Server guard |
|---|---|---|---|---|
| T1 | SELECT own profile | `profiles` | `seller_repository.dart:43-47` (`getProfile`) — used by shell, dashboard, Kanban, settings, payments | RLS `id = auth.uid()` |
| T2 | UPDATE profile fields | `profiles` | `seller_repository.dart:266-271` (`updateProfile`), `289-298` (`updateUpiSettings`) | RLS + `enforce_profiles_approval_immutability` (blocks `is_approved`) |
| T3 | UPSERT profile after sign-up | `profiles` | `seller_registration_screen.dart:136-146` (errors swallowed) | RLS insert/update own row |
| T4 | SELECT drops | `drops` | `seller_repository.dart:67-71` | RLS (own + public live/closed of approved sellers) |
| T5 | INSERT drop (draft) | `drops` | `seller_repository.dart:533-537` | RLS own; unique slug |
| T6 | UPDATE drop details (title, **slug**, fees, stream) | `drops` | `seller_repository.dart:573-578` | RLS own; no status-aware slug lock (SA-DROP-002) |
| T7 | UPDATE drop status draft↔live | `drops` | `seller_repository.dart:612-624` | `enforce_drops_seller_approval` (go-live needs approval), one-live unique index; →closed blocked unless via RPC |
| T8 | SELECT products of a drop | `products` | `seller_repository.dart:86-90` | RLS |
| T9 | INSERT product | `products` | `seller_repository.dart:662-675` (from intake queue) | RLS own drop; CHECK code `^#[A-Z0-9]{1,6}$`; UNIQUE(drop_id, code); status not constrained on insert (SA-INV-003) |
| T10 | SELECT orders + items + products (no limit) | `orders`, `order_items`, `products` | `seller_repository.dart:767-813` (`getAllOrders`) | RLS via drop ownership |
| T11 | SELECT orders (drop) — **unused** | `orders` | `seller_repository.dart:105-138` | — |
| T12 | SELECT payment attempts (+order code/buyer) | `payment_attempts`, `orders` | `seller_repository.dart:309-334`, `351-372` | RLS via order → drop |
| — | Direct UPDATE of products / order lifecycle / drop→closed | — | not used by the app; **blocked** by triggers | PASS 12.2a/b, 12.4a, 12.10b |

### 2.2 RPC calls

| RPC | Caller | Definition (latest) | Notes |
|---|---|---|---|
| `update_product` | `seller_repository.dart:701-709` | 025 | Only available pieces; price > 0 — PASS |
| `mark_product_sold_offline` | `:197-200` | 009 | Refuses reserved/sold; no undo (SA-INV-001) |
| `force_release_hold` | `:172-175` | **009** (never revised) | Ignores in-flight payment claims (SA-PAY-005) |
| `verify_manual_upi_payment` | `:390-396` | 023 | Late-claim defects SA-PAY-001/002/004/006; param-name drift (SA-PAY-014) |
| `reject_manual_upi_payment` | `:486-493` | 015 | Always called with `p_release_hold=true` (SA-PAY-010) |
| `mark_order_ready_to_ship` | `:454-457` | 026 | Called immediately before shipping (no real pack step) |
| `mark_order_shipped` | `:423-431` | 026 | Requires paid + ready — PASS 12.8 |
| `close_drop` | `:603` | 024 | Result ignored by the client (SA-DROP-005); preserves claims — PASS 16.2 |
| Buyer RPCs (not called by the app) | buyer-web | `create_order_with_reservation` 022, `initiate_payment_attempt` 013, `submit_buyer_payment_claim` 023, `get_order_by_token` 030 | Behaviour that the seller must manage |
| `release_expired_holds` | GitHub Actions only | 014 | ~5 runs/day in practice (SA-OPS-001) |
| `admin_approve_seller` | SQL editor only | 021 | No admin UI (SA-OPS-002) |

### 2.3 Edge Functions
None exist (`supabase/functions/` is empty). Consequently there is no server-originated push, webhook, scheduled function or image processing.

### 2.4 Storage
| Operation | Caller | Path | Notes |
|---|---|---|---|
| `uploadBinary(..., upsert: true)` + `getPublicUrl` | `seller_repository.dart:731-757` via `OfflineIntakeQueue.processQueue` | `product-images/{sellerId}/{dropId}/{code}_{queueId}_{angle}.jpg` | Public bucket, 5 MB, jpeg/png/webp; folder must equal `auth.uid()` (PASS 11.5a) but approval not required (SA-SEC-003); EXIF kept (SA-SEC-004) |

### 2.5 Realtime
| Channel | Filter | Events | Subscriber | Lifetime |
|---|---|---|---|---|
| `seller-orders-<dropId>` | `orders.drop_id = dropId` | INSERT, UPDATE | `KanbanBoardScreen._setupRealtime` (`kanban_board_screen.dart:95-105`) **only when a drop is selected** | Re-created on drop change; removed in `dispose` |

Nothing subscribes to `products` or `payment_attempts`, although both are in the `supabase_realtime` publication (migration 019). Each event triggers a full `getAllOrders(dropId)` refetch.

### 2.6 Local state, caching, retries
| Concern | Where | Behaviour |
|---|---|---|
| Session | supabase_flutter (SharedPreferences) | Auto-refresh; `SellerAuthGate` listens to `authStateChanges` (`main.dart:113-121`) |
| Intake queue | `offline_intake_queue.dart` | `queue.json` + `images/*.jpg` in `Directory.systemTemp` (Android cache dir); statuses pending→uploading→uploaded→completed/failed; completed items never removed |
| Retries | intake queue only | `min(60, 2^retry)` s + 0–3 s jitter, forever, no error classification (`:334-343`) |
| Caching | none | Each screen refetches; Flutter in-memory image cache only (`Image.network` without `cacheWidth`) |
| Auth reads | `SellerRepository._requireSellerId()` (`:28-36`) | Throws `UnauthorizedException` if no user |

## 3. Runtime flows

### 3.1 Start-up and gating
`main()` validates dart-defines and initialises Supabase (failures → `ConfigurationErrorScreen` with retry). Splash → `SellerAuthGate` (session present → `SellerHomeScreen`). The home screen loads the profile; **only a successfully loaded, unapproved profile shows the pending screen** — any error falls through to the full dashboard (SA-AUTH-002). Server-side, unapproved sellers cannot go live (trigger `enforce_drops_seller_approval`, PASS 12.6).

### 3.2 Intake
Camera (`camera` controller, ResolutionPreset.high, JPEG) or `image_picker` → `ImageService.processIntakeImage` in an isolate (decode with EXIF orientation baked, centre-crop 1:1, ≤1200 px, JPEG q85, EXIF retained) → bottom sheet (code suggestion `#<prefix><nn>`, title, price in whole ₹, size chips) → `OfflineIntakeQueue.enqueue` writes files + manifest → optimistic "Available" product in the UI → `processQueue` uploads each angle, then inserts the product row.

### 3.3 Payment verification
Buyer: checkout RPC reserves pieces (15-min hold) → `initiate_payment_attempt` (UPI intent) → `submit_buyer_payment_claim` with UTR (hold extended to 24 h; late if order cancelled/expired). Seller: Payments tab lists attempts in claimed/late states → Verify (`verify_manual_upi_payment`) or Reject (`reject_manual_upi_payment`, always releasing). Reaper expires holds and claimed attempts after their window.

### 3.4 Fulfilment
Kanban tabs are computed client-side from `status/payment_status/fulfilment_status`. Dispatch dialog calls `mark_order_ready_to_ship` (if not ready) then `mark_order_shipped`. Labels are generated client-side as PDF and handed to the system print/share sheet.

## 4. Architectural assessment

| Question | Answer |
|---|---|
| Is the server authoritative for money/inventory? | Yes for the normal paths (PASS 12.2, 12.8, 13.1, 14.1). Defects live in specific RPC branches and in a public view (P0 list). |
| Is the client's model of state correct? | No. It reconstructs the order state machine loosely (SA-ORD-005), ignores refund signals (SA-PAY-004), and has no live state (SA-RT-001, SA-CQ-001). |
| Is the layering a problem? | Not by itself. A single repository is fine at this size; what is missing is an app-level **live session store** (one subscription set, shared by all tabs) and a typed result/error layer. |
| Where should new logic go? | Into SQL/RPCs for every rule that involves money, inventory or authorisation (reaper/lazy expiry, refund state, claim-aware release, threshold rule); into one client store for live state; nothing new on the client that duplicates server rules. |
| Unjustified complexity? | None found. Avoid adding microservices/queues; pg_cron + a few RPCs + FCM via one Edge Function cover the gaps (see [22](22-IMPROVEMENT-ROADMAP.md#e-architectural-improvements)). |
