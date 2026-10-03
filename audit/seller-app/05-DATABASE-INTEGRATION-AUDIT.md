# 05 — Seller Data / Database Integration Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Every seller-app database interaction; migrations 001–033; RLS, triggers, RPCs, grants |
| Executed | Local PostgreSQL 16 (port 55432) with `tests/sql/00_supabase_shim.sql` (Supabase roles, `auth.uid()`, storage schema, default privileges, realtime publication) + all migrations; suites 10–18; catalog inventory |
| Not executed | Hosted project (no credentials, by design). Read-only hosted queries are provided in `tests/sql/90_hosted_readonly_checks.sql` (H1–H11) |

## 1. Every seller-app database interaction

Auth = role required; RLS/guard = what the server enforces; Error = what the app does on failure; Retry = automatic retry; Tx = transaction semantics.

| # | Table / function | Caller | Purpose | Auth | RLS / guard | Expected result | Error behaviour | Retry | Tx |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `profiles` SELECT | `getProfile` (`seller_repository.dart:39-60`) | Shell, dashboard, Kanban, settings, labels | authenticated | `profiles_seller_select` (own row) | 1 row | Throws `LiveDropException`; shell swallows it → **fail-open gate** (SA-AUTH-002) | No | single stmt |
| 2 | `profiles` UPDATE | `updateProfile`, `updateUpiSettings` (`:218-302`) | Store data, order defaults, UPI | authenticated | own row; approval column immutable (trigger) | updated row | Snackbar with raw error | No | single |
| 3 | `profiles` UPSERT | registration (`seller_registration_screen.dart:136-146`) | Duplicate of trigger provisioning | authenticated | own row | — | **Swallowed** (SA-ONB-003) | No | single |
| 4 | `drops` SELECT | `getDrops` (`:63-79`) | Lists, target drop selection | authenticated | own + public live/closed (approved sellers) | own drops | Exception → callers swallow in several places | No | single |
| 5 | `drops` INSERT | `createDrop` (`:511-549`) | New draft | authenticated | `drops_seller_manage`; unique slug → `SLUG_TAKEN` | draft row | Mapped message | No | single |
| 6 | `drops` UPDATE (details) | `updateDrop` (`:552-590`) | Title, slug, fees, stream URL | authenticated | own; **slug editable while live** (SA-DROP-002) | row | Mapped `SLUG_TAKEN` | No | single |
| 7 | `drops` UPDATE (status draft/live) | `updateDropStatus` (`:595-637`) | Go live / unpublish / re-open | authenticated | approval trigger for go-live; one-live index; →closed blocked | row | Mapped `MULTIPLE_LIVE_DROPS` | No | single |
| 8 | `close_drop` RPC | `updateDropStatus(closed)` (`:603`) | Safe closure | authenticated owner | 024: releases unclaimed holds, keeps claims | `{success}` | **Result ignored** (SA-DROP-005) | No | function tx |
| 9 | `products` SELECT | `getProducts` (`:82-98`) | Inventory, intake code suggestion | authenticated | own drops | rows by code | Exception → swallowed in intake/dashboard | No | single |
| 10 | `products` INSERT | `createProduct` (`:646-687`) via queue | New garment | authenticated | RLS own drop; CHECK code; UNIQUE(drop,code); status unconstrained (SA-INV-003) | row | 23505 → `DUPLICATE_PRODUCT_CODE`; others raw | **Queue backoff, forever** (SA-OFF-003) | single |
| 11 | `update_product` RPC | `updateProduct` (`:692-727`) | Edit title/price/size | authenticated owner | 025: only `available`; GUC-gated trigger | `{success, product}` | Mapped | No | function tx |
| 12 | `mark_product_sold_offline` RPC | `:193-215` | Sold elsewhere | authenticated owner | 009: refuses reserved/sold | `{success}` | Raw error text (SA-INV-001) | No | function tx |
| 13 | Storage upload | `uploadProductImage` (`:731-757`) | Product photos | authenticated | folder = uid (no approval check, SA-SEC-003) | public URL | Exception → queue failure | Queue backoff | n/a |
| 14 | `orders` + `order_items` + `products` SELECT | `getAllOrders` (`:760-820`) | Dashboard, Kanban, analytics, shipping shortcut, realtime refresh | authenticated | `orders_seller_select` via drop | **all orders ever, nested** (SA-PERF-001) | Exception → Kanban error state; dashboard swallows | No | single |
| 15 | `orders` SELECT (drop) | `getOrders` (`:101-146`) | **Unused** | — | — | — | — | — | — |
| 16 | `payment_attempts` + `orders!inner` SELECT | `getPendingVerifications` (`:305-342`) | Payments queue | authenticated | via order → drop | claimed + late attempts | Error state with retry | No | single |
| 17 | `payment_attempts` SELECT | `getPaymentAttemptsForOrder` (`:345-380`) | Order details | authenticated | via order | attempts | Exception | No | single |
| 18 | `verify_manual_upi_payment` RPC | `:383-411` | Confirm UPI receipt | authenticated owner (or service) | 023; idempotent on attempt; reference reuse check | `{success,…}` | Exception text in snackbar; **`refund_required` ignored** (SA-PAY-004) | No | function tx, row locks attempt→order |
| 19 | `reject_manual_upi_payment` RPC | `:478-508` | Reject claim | authenticated owner | 015; `p_release_hold` | `{success}` | Snackbar | No | function tx |
| 20 | `force_release_hold` RPC | `:167-190` | Cancel pending order, free pieces | authenticated owner | 009; **ignores claims** (SA-PAY-005) | `{success}` | Snackbar | No | function tx |
| 21 | `mark_order_ready_to_ship` RPC | `:450-475` | Packed | authenticated owner | 026: paid + not_ready | `{success}` | Snackbar | No | function tx |
| 22 | `mark_order_shipped` RPC | `:413-446` | Ship with tracking | authenticated owner | 026: paid + ready; idempotent `ALREADY_SHIPPED` | `{success}` | Snackbar | No | function tx |
| 23 | Realtime `orders` | `SellerOrderRealtimeSubscription` | Kanban refresh | authenticated (RLS-filtered changes) | per-drop filter | INSERT/UPDATE payloads | Parse errors swallowed | Library reconnect only | n/a |
| 24 | Analytics/activity (client aggregation of #14 + #16) | `getSellerAnalytics`, `getRecentActivity` | Charts, activity | authenticated | — | computed | Activity returns `[]` on any error | No | n× single |

Non-atomic client sequences: dispatch = #21 then #22 (two transactions; a failure between leaves `ready_to_ship`, which is recoverable). Intake = upload(s) then #10 (orphaned objects if the insert fails permanently).

## 2. Schema/client consistency checks

| Check | Result |
|---|---|
| Missing columns | None found: model fields exist in the latest schema (`packed_at`, `verification_expires_at`, `image_urls`, `stream_url`, payment/fulfilment status) |
| Stale RPC names | None; **stale parameter name** `p_override_reference` vs `p_utr` (SA-PAY-014) |
| Stale migrations | `force_release_hold` and `mark_product_sold_offline` still at 009 and unaware of payment attempts (SA-PAY-005) |
| Incorrect types | Money is `int` paisa end-to-end (PASS AGENTS rule 5); timestamps parsed as UTC and displayed without conversion (SA-ORD-001) |
| Null assumptions | `fromJson` hard-casts many columns `as String/int`; Realtime payload parsing failures are swallowed (orders created during a live may not refresh the list) |
| Inconsistent enums | Dart enums cover every DB value; unknown values silently map to a default (e.g. unknown order status → `pending`) |
| Duplicated business logic | Free-shipping rule in 4 places (SA-PAY-008); order action rules re-derived in the UI (SA-ORD-005); profile provisioning in trigger + client (SA-ONB-003) |
| Client-side trust | None for money/inventory — server recomputes totals and enforces transitions |
| Unsafe direct mutations | Product/order lifecycle updates blocked by triggers (PASS 12.2a/b, 12.10b). Remaining direct paths: drop status draft↔live and slug (SA-DROP-002/003), product INSERT status (SA-INV-003), seller DELETE of cancelled orders with ledger rows (SA-PAY-018), anonymous writes through the storefront view (SA-SEC-001) |
| Hidden database failures | 33 `catch (_)` blocks; `close_drop` result ignored; `getRecentActivity` returns `[]` (SA-OBS-001) |

## 3. Migration verification

| Check | Result | Evidence |
|---|---|---|
| Apply cleanly, in order (001→033) on a fresh database | **PASS** (33/33) | `evidence/migration-apply.log` |
| Ordering issues | None blocking; several functions are redefined 3–5 times (e.g. `get_order_by_token` in 009/010/013/014/015/028/030) — the last definition wins and was the one tested | `grep CREATE OR REPLACE FUNCTION` |
| Deployed schema matches client expectations | **Unknown — no hosted access**; no CI deploy/drift check (SA-DB-001) | run H6 |
| Triggers work | PASS for products immutability, orders payment immutability, drop safe closure, seller approval go-live, profile approval immutability | 12.2, 12.4a, 12.6, 12.10b |
| RPCs work (normal paths) | PASS: checkout under contention, verify idempotency, ready/ship guards, close_drop claim preservation | 13.1, 14.1, 12.8, 16.2 |
| RPCs (edge paths) | **FAIL**: late claims, release with claims, claim expiry, suspension, thresholds | suites 13, 14, 16 |
| RLS works | PASS on all 7 base tables (enabled; not FORCED, fine since tables are owned by postgres and RPCs are SECURITY DEFINER by design) | `schema-inventory.out`, suite 11 |
| SECURITY DEFINER hardened | 20/20 pin `search_path = public, pg_temp` (AGENTS rule 7 PASS); EXECUTE grants broader than needed (SA-SEC-007) | `security-definer-search-path.out`, `anon-executable-functions.out` |
| Views | `public_seller_storefronts` auto-updatable + ALL to anon (SA-SEC-001); `public_products_catalog` not updatable (3-table join) but also holds ALL grants | `schema-inventory.out` |
| Seller isolation | PASS except via the storefront view | suites 10/11 |
| Ledger immutability | Direct INSERT/UPDATE/DELETE revoked from authenticated (011:39) — PASS; **cascade delete through orders** — FAIL (SA-PAY-018) | suite 17 |
| Lock ordering | verify vs reaper deadlock (SA-INT-002) | 14.3 |
| Retention | None (SA-OPS-003) | — |

## 4. Performance of seller queries (local, see [17](17-PERFORMANCE-AUDIT.md))
`getAllOrders` for one seasoned seller (2,000 orders): ≈2.4 MB JSON, ≈144 ms server time on a dev host; RLS plan uses a hashed sub-plan over `drops` (efficient). Pending verifications and product lists are cheap. The problem is payload size and frequency, not SQL.

## 5. Hosted verification still required
Run `tests/sql/90_hosted_readonly_checks.sql` in the Supabase SQL editor (read-only) and the non-destructive PATCH probe at its end:
- H1–H3: storefront view privileges/updatability/options (confirms SA-SEC-001 in production)
- H4–H5: default privileges and anon-executable functions
- H6: applied migration versions vs 001–033 (SA-DB-001)
- H7–H8: realtime publication, pg_cron availability (for SA-OPS-001 fix)
- H9–H11: live data health — expired-but-holding orders, refund-owed orders, ledger vs `total_paid_paisa` mismatches

## 6. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-SEC-001 | CRITICAL | P0 | Storefront view writable by anon/other sellers |
| SA-PAY-002 | CRITICAL | P0 | Late-claim verification race → double sale |
| SA-PAY-018 | MEDIUM | P1 | Refund-owed ledger rows deletable through order cascade |
| SA-INT-002 | MEDIUM | P1 | Verify vs reaper deadlock |
| SA-DB-001 | MEDIUM | P1 | Hosted schema state unverifiable |
| SA-INV-003 | MEDIUM | P2 | Products insertable as sold/reserved |
| SA-DROP-003 | MEDIUM | P2 | live→draft bypasses safe closure |
| SA-OPS-003 | MEDIUM | P2 | No retention/purge |
| SA-DB-002 | LOW | P2 | No ledger/total reconciliation |
| SA-DB-003 | LOW | P2 | No status history |
| SA-SEC-007 | LOW | P2 | Over-broad EXECUTE grants |
