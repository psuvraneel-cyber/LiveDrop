# 15 — Concurrency, Reservation & Transaction Correctness Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Architectural Decision: Reservation Ownership Entity

### The Question
Should an active garment reservation belong to:
1. An anonymous browser session ID (`p_session_id`),
2. A separate independent `reservations` entity table, or
3. An authoritative `Order` entity (`orders` record)?

### Authoritative Selection: Ownership by Order Entity
LiveDrop designates the **`Order` entity** (`orders.id`) as the authoritative owner of a reservation (`products.reserved_by_order_id`).

```
┌─────────────────────────────────────────────────────────────┐
│ Why Not a Browser Session?                                  │
│ • Ephemeral session strings can be spoofed or duplicated.   │
│ • If a browser crashes or switches tabs, session is lost.   │
│ • Decouples the hold from shipping and buyer contact info.  │
├─────────────────────────────────────────────────────────────┤
│ Why Not a Separate `reservations` Table?                    │
│ • Adds multi-table JOIN overhead during peak checkout.      │
│ • Incurs double-write consistency risk on checkout.         │
│ • Violates the simplicity mandate for MVP.                  │
├─────────────────────────────────────────────────────────────┤
│ Why Ownership by Order (`orders.id`):                       │
│ • Atomicity: The hold and the order are created in one ACID │
│   transaction.                                              │
│ • Unambiguous traceability: The seller Kanban card directly │
│   links to the locked items.                                │
│ • Clean expiration: Expiring the order cleanly releases all │
│   associated products in a single relational join.          │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Mathematical Proof of Concurrency & Deadlock Freedom

### 2.1 Deadlock Vulnerability in Naive Array Locking
In PostgreSQL, `SELECT ... FOR UPDATE` locks rows sequentially in the order retrieved by the query planner.
* **Failure Scenario:**
  * Transaction 1 requests items `[Item_A, Item_B]`.
  * Transaction 2 requests items `[Item_B, Item_A]`.
  * If T1 locks `Item_A` and T2 locks `Item_B`, both transactions enter mutual wait state, causing a database deadlock abort (`ERROR: deadlock detected`).

### 2.2 Proof of Deadlock Freedom via Primary Key Sorting
To guarantee absolute deadlock freedom, the `create_order_with_reservation` RPC enforces strict deterministic ordering of primary keys before requesting locks:

```sql
SELECT COUNT(*) INTO v_locked_count
FROM products
WHERE id = ANY(v_sanitized_ids)
  AND drop_id = p_drop_id
  AND status = 'available'
ORDER BY id ASC
FOR UPDATE;
```

**Formal Proof:**
1. Let $L$ be the set of all product IDs requested in transaction $T$.
2. Let $<$ be the canonical total ordering on PostgreSQL `UUID` values.
3. Every transaction acquires locks in strictly increasing order: $p_1 < p_2 < \dots < p_n$.
4. Assume for contradiction that a circular deadlock exists between transactions $T_1, T_2, \dots, T_k$ where $T_i$ holds lock on $p_a$ and waits for lock on $p_b$ held by $T_{i+1}$.
5. By the total ordering rule, $T_i$ holding $p_a$ and requesting $p_b$ implies $p_a < p_b$.
6. Following the chain: $p_1 < p_2 < \dots < p_k < p_1$, which implies $p_1 < p_1$.
7. This is a contradiction. Therefore, cyclic wait conditions are mathematically impossible.

---

## 3. Exhaustive Analysis of 24 Live-Drop Edge Scenarios

| Scenario # | Concurrency / Operational Scenario | Technical Behavior & Transaction Guard | User-Facing Outcome |
|---|---|---|---|
| **01** | **Two buyers submit same product simultaneously** | PostgreSQL serializes row lock. First transaction locks row; second transaction finds `status != 'available'` or row locked. Second transaction fails atomic availability check. | Winner proceeds to WhatsApp; loser receives instant inline modal: *"Item was just reserved by another buyer."* |
| **02** | **Simultaneous multi-item cart collision (Buyer A: #01, #02; Buyer B: #02, #03)** | Database locks items in sorted order. Whichever transaction locks `#02` first succeeds for `#02`. The losing transaction detects `#02` unavailable. | Losing buyer receives partial collision prompt highlighting `#02` in red with `[Remove]` button; other items preserved. |
| **03** | **Same product requested multiple times in one payload** | Client array de-duplicated via `SELECT array_agg(DISTINCT id)`. | System processes single hold safely without false failure. |
| **04** | **Duplicate product IDs passed maliciously** | Sanitization filters duplicate IDs before count comparison. | No array-length mismatch; atomic validation proceeds normally. |
| **05** | **15-Minute reservation expiration** | Background cron executes `release_expired_holds()`. Reverts `status = 'available'`, clears `reserved_by_order_id`, marks order `cancelled`. | Contested dress instantly reappears as green `Available` in live catalog. |
| **06** | **Buyer attempts reservation renewal** | Renewal not supported in MVP. Buyer must place a new order if hold expires. | Prevents indefinite catalog squatting. |
| **07** | **Buyer explicitly cancels cart** | If buyer taps "Clear", no order is submitted; products remain available. | Zero system footprint. |
| **08** | **Seller force-releases reservation** | Seller long-presses item in app ➔ "Force Release Hold". DB resets `status = 'available'` and flags order as cancelled by seller. | Product instantly becomes purchasable by another viewer. |
| **09** | **Seller manual sale (walk-in or FB comment)** | Seller taps "Mark Sold Offline". DB updates `status = 'sold'`. | Product permanently disabled on catalog feed. |
| **10** | **Payment confirmation** | Seller verifies UPI and taps "Mark as Paid". Invokes `mark_order_paid(order_id)`. Products ➔ `sold`; Order ➔ `paid`. | Order moves to "Ready to Pack" Kanban tab. |
| **11** | **Reservation after order creation** | Architectural anti-pattern eliminated. Reservation and order creation are a single unified atomic transaction. | Atomic guarantee: no order exists without a hold; no hold exists without an order. |
| **12** | **Order creation failure after reservation** | Unified RPC wraps both operations in one transaction. If order creation fails, database rolls back product locks automatically. | Inventory never left stranded in hold state. |
| **13** | **Reservation success followed by WhatsApp redirect failure** | Order is saved with `pending` status. Client renders fallback screen (`/order/[id]`) with `[Open WhatsApp Now]` button and static UPI QR. | Buyer can manually click to open WhatsApp or scan static UPI QR. |
| **14** | **Hold expires while seller reviews payment** | Cron marks order `cancelled` and products `available`. If seller subsequently taps "Mark as Paid", `mark_order_paid` checks for contested reclaim. | If contested: rejects with `PRODUCT_ALREADY_RECLAIMED`. If uncontested: safely marks `paid`. |
| **15** | **Seller marks expired order paid after item was claimed by Buyer B** | `mark_order_paid` strictly aborts transaction upon detecting `reserved_by_order_id != p_order_id`. | Seller alerted to conflict; double-selling prevented. |
| **16** | **Stale browser session attempts checkout** | Product status is verified at database level (`status = 'available'`) inside transaction, regardless of what stale client displays. | Rejected safely with `STOCK_UNAVAILABLE`. |
| **17** | **Reconnecting browser after cellular drop** | Client fetches fresh catalog snapshot via REST upon reconnection, reconciling out-of-order states. | Visual state updated to match ground truth. |
| **18** | **Realtime event delayed or dropped** | Checkout does not depend on Realtime. Database ACID transaction validates ground truth at moment of submission. | Zero false bookings. |
| **19** | **Duplicate rapid button taps by buyer** | Client disables button on first tap. Database enforces `UNIQUE(order_code)`. | Only single order record generated. |
| **20** | **Network timeout during transaction** | If network drops before server responds, client retries using client-generated idempotency token. | Duplicate order prevented. |
| **21** | **Malicious automated reservation script** | API enforces rate limiting (max 5 orders per 15 mins per IP). Phone numbers validated. | Rapid bot hoarding mitigated. |
| **22** | **Drop closed while reservation active** | Closing a drop prevents new checkouts (`status = 'closed'`). Existing active reservations remain valid until 15-min expiry. | Existing buyers can complete payment. |
| **23** | **Buyer alters prices in client memory** | Subtotal is computed entirely on the server using `SELECT price FROM products`. Client prices are completely ignored. | Fraud attempt neutralized. |
| **24** | **Partial checkout success handling** | If 2 of 3 items are locked by others, RPC informs client exactly which items failed. | Buyer can instantly buy remaining 1 item. |
