# ADR-014: Undo of an Offline Sale Within 30 Minutes

## Status
**Accepted**, 2026-10-04. Approved by the project owner during the seller-app audit remediation (SA-INV-001).

## Amends
`09-system-state-machines.md` §3.2, which lists `sold` → `available` as "Forbidden in MVP". The rule still holds for every piece sold through an order. This ADR adds one narrow exception.

## Context
**SA-INV-001** (seller-app audit): "Mark Sold" (`mark_product_sold_offline`) takes a piece off sale immediately. Sellers use it during a live stream for pieces sold over the phone or in person. A mistaken tap was permanent. No RPC returned the piece to sale, so the garment stayed off sale for the rest of the drop.

## Decision
1. `mark_product_sold_offline` records `products.sold_offline_at`. It also refuses pieces of a closed drop (`DROP_CLOSED`) and reserved pieces (`PRODUCT_RESERVED`, unchanged).
2. A new RPC, `undo_mark_product_sold_offline(p_product_id)`, sets the piece back to `available` and clears `sold_offline_at`. It does this only when all of the following hold:
   * the caller owns the drop;
   * the piece is `sold` with `sold_offline_at` set (sold offline, not through an order);
   * `sold_offline_at` is no more than **30 minutes** ago;
   * no order that is not `cancelled` or `expired` contains the piece;
   * the drop is not `closed`.

   Errors: `NOT_SOLD_OFFLINE`, `UNDO_WINDOW_EXPIRED`, `PRODUCT_HAS_ORDER`, `DROP_CLOSED`, `PRODUCT_NOT_FOUND_OR_UNAUTHORIZED`. A repeated call on an available piece returns `idempotent: true`.
3. Direct table updates stay forbidden for sellers. The RPC is the only way back.
4. The app offers "Undo" for 30 minutes after Mark Sold, and asks for confirmation before marking a piece sold.

## Consequences
* **Positive:** a mis-tap during a live no longer loses a garment for the whole drop.
* **Negative:** for 30 minutes a piece can move from sold back to available. Buyers watching the catalogue may see it reappear. That is the intended outcome of an undo.
* **Verification:** SQL suite `audit/seller-app/tests/sql/21_p1_round4.sql` (21.20–21.27) and the seller-app widget tests for Mark Sold and Undo.
