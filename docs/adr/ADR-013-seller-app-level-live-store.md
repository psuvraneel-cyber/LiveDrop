# ADR-013: Seller App-Level Live Store

## Status
**Accepted** — 2026-10-03. Approved by the project owner via the seller-app audit remediation request.

## Supersedes
The per-drop seller channel in `14-realtime-contract.md` §3.2 (`seller-orders`, filtered by `drop_id`, implemented in the removed `seller_order_realtime.dart`).

## Context
**SA-RT-001** (seller-app audit, commit 94ccfc9): realtime was subscribed only for the drop selected on the Kanban screen. The dashboard counters, the products list, "All Drops" orders and the Payments queue did not update until the seller pulled to refresh. A buyer's payment claim could sit unseen during a live sale. Requirements REQ-FR-S2.1, S2.2 and S3.1 were marked Implemented without a test that would catch this.

## Decision
1. While a seller is signed in, one app-level `SellerLiveStore` opens a single channel `seller:{seller_id}:live:{n}` with `postgres_changes` on `orders`, `payment_attempts` and `products`. RLS scopes orders and attempts; products and orders are also filtered by the seller's drop ids on the client.
2. Bursts of events are debounced (400 ms) into one `revision` bump. Home, Products, Orders and Payments reload from PostgREST when the revision changes; hidden tabs reload when shown. Realtime payloads are hints, never data.
3. The store keeps the badge counts: pending claims, overdue claims and refunds owed.
4. A successful seller RPC bumps the revision at once.
5. Catch-up: after a reconnect, or a resume after more than 3 s in the background, the store bumps the revision and refetches counts. While the channel is down it polls every 30 s.

## Consequences
* **Positive:** one WebSocket per seller instead of one per screen or drop, which suits the 200-connection free-tier limit (ADR-008). Every screen is live, and missed events are recovered.
* **Negative:** any change causes a full reload of the visible screen (cheap at current volumes; revisit if queries grow). Products events for other sellers' public products reach the client and are discarded there.
* **Verification:** `seller-app/test/seller_live_store_test.dart` (payment_attempts event updates counts; Orders "All Drops" reloads on a live order event; Payments badge and queue update without refresh; verifying invalidates every tab immediately), `dashboard_money_alerts_test.dart`.
