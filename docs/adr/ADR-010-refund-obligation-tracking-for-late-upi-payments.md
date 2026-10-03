# ADR-010: Refund-Obligation Tracking for Late Direct-UPI Payments

## Status
**Accepted** — 2026-10-03. Approved by the project owner via the seller-app audit remediation request.

## Supersedes
The free-text refund note written into `orders.notes` by migration 023 (late payment on an order whose piece was no longer available). It does not supersede ADR-004.

## Context
The seller-app audit (commit 94ccfc9, `audit/seller-app/`) found that late direct-UPI payments were handled unsafely:
1. **SA-PAY-001:** a verified late *advance* marked the order fully paid (`total_paid` = order total) although the ledger held only the advance.
2. **SA-PAY-002:** verifying a late claim overwrote the reservation of a piece that another buyer already held, so one unique garment ended up on two paid orders.
3. **SA-PAY-004:** money received for an order whose piece was gone was only recorded in a free-text note. Nothing could list, total or close the refund the seller owed.
4. **SA-PAY-006:** a late advance on a resold piece failed with a CHECK violation (`chk_orders_balance_formula`).
5. **SA-PAY-018:** a seller could delete a refund-owed order, and the cascade removed its verified ledger rows.

Money moves directly from buyer to seller over UPI (ADR-004), so LiveDrop cannot refund automatically. It can only make the obligation impossible to lose.

## Decision
1. Add structured refund columns to `orders` (`refund_status` none/required/refunded, `refund_amount_paisa`, `refund_reason`, `refund_required_at`, `refund_reference`, `refunded_at`, `refund_recorded_by`) with CHECK constraints and a partial index on `drop_id WHERE refund_status = 'required'`. The columns are protected from direct seller updates.
2. `verify_manual_upi_payment` locks the order's products before deciding. A piece counts as available only if it is free or already reserved by this order. If the pieces are available, a late advance revives the order as `confirmed/advance_paid` with correct amounts and a new hold. If not, the verified ledger row is still recorded (the money was received), the order stays cancelled/expired, and `refund_status = 'required'` with `refund_amount_paisa += amount` and `refund_reason = 'LATE_PAYMENT_INVENTORY_UNAVAILABLE'`. Another buyer's reservation is never overwritten.
3. The ledger invariant `total_paid_paisa = SUM(verified order_payments)` is checked before and asserted after every verification.
4. New RPC `record_refund(p_order_id, p_refund_reference, p_note)` lets the owning seller (or service role) close the obligation with a validated reference. It is idempotent for the same reference.
5. Orders with ledger rows or a refund status other than `none` cannot be deleted.
6. Legacy orders flagged by migration 023 are backfilled to `refund_status = 'required'`.
7. The seller app shows "Refunds owed" under Payments and on Home, and shows a blocking dialog when a verification creates a refund obligation.

## Consequences
* **Positive:** a garment can no longer be sold twice through the late path. Every rupee received without a piece is listed until the seller records a refund. Order totals agree with the ledger.
* **Negative:** refunds are still made outside LiveDrop; the system records the seller's reference but cannot confirm it. Orders already damaged before 035 are not rewritten; hosted checks H10/H11/H15 list them for manual review.
* **Verification:** SQL 13.5c, 13.6, 13.7, 14.2, 14.2b, 17.1, 19.4–19.9h, 19.17, 19.21; Flutter `payments_refunds_test.dart`, `dashboard_money_alerts_test.dart`, audit `SA-AUD-T20`.
