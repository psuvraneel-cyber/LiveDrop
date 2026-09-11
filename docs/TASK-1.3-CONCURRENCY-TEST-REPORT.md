# TASK-1.3 — Concurrency, Contention & Deadlock Freedom Test Report

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Task Scope:** Phase 1 / TASK-1.3 (Concurrency Verification)  
**Governing Documents:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md), [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md), [`docs/25-testing-strategy.md`](file:///c:/LiveDrop/docs/25-testing-strategy.md)  
**Test Suite:** `buyer-web/src/test/rpcs.test.ts`  
**Execution Engine:** `@electric-sql/pglite` (PostgreSQL 18.3 WASM in-memory relational engine)

---

## 1. Executive Summary

LiveDrop operates under extreme flash-sale concurrency conditions: when a live streamer presents a unique, 1-of-1 handloom garment, hundreds of viewers attempt to tap "Order via WhatsApp" simultaneously. Under such intense write-contention, naive application code or non-deterministic locking leads to race conditions, inventory double-selling, negative stock, or database deadlocks (`ERROR: deadlock detected`).

During TASK-1.3, we executed automated concurrency and contention suites simulating multi-buyer race conditions against the `create_order_with_reservation` and `mark_order_paid` PostgreSQL routines.

### Key Results
* **Zero Overselling / Zero Double-Reservations:** In all 1-of-1 contention scenarios (2, 5, and 20 concurrent buyers), exactly **1 buyer succeeded** and acquired the hold; 100% of competing transactions were cleanly rejected with `STOCK_UNAVAILABLE`.
* **Zero Deadlocks:** Transactions requesting overlapping inventory in opposite orders (`[P1, P2]` vs `[P2, P1]`) executed without deadlocks or aborts due to mandatory `ORDER BY id ASC` deterministic row-level locking.
* **Partial Collision Atomicity:** When competing for overlapping multi-item carts, the buyer who acquired the contested shared item completed their full cart; the competing buyer experienced an atomic all-or-nothing rollback with zero stranded locks.
* **Concurrent Payment Idempotency:** Simultaneous payment confirmations for the same order resolved safely with zero duplicate writes.

---

## 2. Concurrency Test Scenarios & Empirical Evidence

### Scenario TC-CON-01: Two Concurrent Buyers Competing for Single 1-of-1 Product

* **Description:** Two distinct buyers submit simultaneous checkout requests for the exact same available garment.
* **Concurrent Clients:** 2
* **Requested Products:** Product `#01` (Single 1-of-1 inventory item)
* **Transaction Execution Model:** Parallel asynchronous promises launched simultaneously via `Promise.all([client1, client2])`.
* **Database Locking Behavior:** Both PostgreSQL transactions attempt to acquire row-level lock via:
  ```sql
  SELECT id, price_paisa, drop_id, status
  FROM products
  WHERE id = ANY(v_unique_ids)
  ORDER BY id ASC
  FOR UPDATE;
  ```
  PostgreSQL serializes the row lock. Transaction 1 evaluates `status = 'available'`, generates the order, transitions product to `reserved`, sets `reserved_by_order_id`, and commits. Transaction 2 unblocks from the lock, re-reads the committed row, finds `status = 'reserved'`, and raises `STOCK_UNAVAILABLE`.
* **Expected Result:**
  - Exactly 1 transaction succeeds (`success: true`).
  - Exactly 1 transaction fails (`success: false`, `error: "STOCK_UNAVAILABLE"`).
  - Database contains exactly 1 order and 1 order item.
  - Product is reserved with `reserved_by_order_id` equal to the winning order ID.
* **Actual Result:** **PASS** (1 success, 1 failure, 0 deadlocks).

---

### Scenario TC-CON-02: Five Concurrent Buyers Competing for Single 1-of-1 Product

* **Description:** Five buyers simultaneously submit orders for a single high-demand garment during a flash drop.
* **Concurrent Clients:** 5
* **Requested Products:** Product `#01`
* **Transaction Execution Model:** `Promise.all` initiating 5 concurrent RPC calls against the database engine.
* **Expected Result:**
  - Exactly 1 winner (`success: true`).
  - Exactly 4 rejections (`success: false`, `error: "STOCK_UNAVAILABLE"`).
  - Exactly 1 order created in `orders`.
  - Exactly 1 line item in `order_items`.
* **Actual Result:** **PASS**
  - Winner count: `1`
  - Rejection count: `4`
  - Database order count: `1`
  - Product `status`: `'reserved'`

---

### Scenario TC-CON-03: High-Stress Flash Drop (20 Concurrent Buyers for Single Product)

* **Description:** Stress contention simulation with 20 simultaneous buyer submissions competing for one item.
* **Concurrent Clients:** 20
* **Requested Products:** Product `#01`
* **Transaction Execution Model:** 20 concurrent parallel calls launched via `Promise.all`.
* **Database Behavior:** The engine serializes the 20 callers across the single row lock. The first transaction to acquire the lock successfully completes the order. The remaining 19 transactions sequentially evaluate `status != 'available'` and return `STOCK_UNAVAILABLE` with zero mutations.
* **Expected Result:**
  - Exactly 1 winner (`success: true`).
  - Exactly 19 losers (`success: false`, `error: "STOCK_UNAVAILABLE"`).
  - Zero double-reservations.
  - Exactly 1 order in database.
* **Actual Result:** **PASS** (1 winner, 19 losers, zero database integrity violations).

---

### Scenario TC-CON-04: Overlapping Multi-Item Cart Collision

* **Description:** Multi-item cart contention where Buyer A requests `[P1, P2]` and Buyer B requests `[P2, P3]` simultaneously (P2 is the contested shared item).
* **Concurrent Clients:** 2
* **Payloads:**
  - Buyer A: `[Product_1, Product_2]`
  - Buyer B: `[Product_2, Product_3]`
* **Locking Strategy:**
  - Buyer A locks in order: `P1`, then `P2`.
  - Buyer B locks in order: `P2`, then `P3`.
* **Database Behavior:** Whichever buyer acquires the lock on `P2` successfully completes their full 2-item cart. The other buyer attempts to lock `P2`, finds it reserved or contention-aborted, and the entire transaction rolls back cleanly. The un-contested item for the losing buyer (`P1` or `P3`) is NOT reserved and remains completely available.
* **Expected Result:**
  - Exactly 1 buyer succeeds (`success: true`, 2 items reserved).
  - Exactly 1 buyer fails (`success: false`, `error: "STOCK_UNAVAILABLE"`).
  - No partial carts created.
  - The uncontested item of the losing buyer remains `status = 'available'`.
* **Actual Result:** **PASS**
  - Winning buyer has 2 items reserved.
  - Losing buyer has 0 items reserved; their unique item remained `'available'`.

---

### Scenario TC-CON-05: Reverse-Order Deadlock Prevention (Opposite Array Ordering)

* **Description:** Two buyers submit orders containing the exact same two products, but in opposite array order: Buyer 1 submits `[P1, P2]` while Buyer 2 submits `[P2, P1]`.
* **Concurrent Clients:** 2
* **Potential Hazard:** In naive SQL, if Transaction 1 locked `P1` then waited for `P2`, while Transaction 2 locked `P2` then waited for `P1`, a cyclic wait would trigger `ERROR: deadlock detected (SQLSTATE 40P01)`.
* **PostgreSQL Deterministic Guard:**
  Inside `create_order_with_reservation`, the query acquires locks via:
  ```sql
  SELECT id FROM products WHERE id = ANY(v_unique_ids) ORDER BY id ASC FOR UPDATE;
  ```
  Regardless of client array order, PostgreSQL sorts the IDs and acquires locks in identical order (`P1` then `P2`) for both transactions.
* **Expected Result:**
  - No deadlock detected.
  - Exactly 1 transaction succeeds.
  - Exactly 1 transaction receives `STOCK_UNAVAILABLE`.
* **Actual Result:** **PASS** (Zero deadlocks; clean serialization).

---

### Scenario TC-PAY-08: Concurrent Payment Confirmation Race

* **Description:** Two simultaneous seller requests attempt to mark the same order paid (e.g., rapid double-tap or concurrent device sync).
* **Concurrent Clients:** 2
* **Database Guard:** `mark_order_paid` locks the order row `FOR UPDATE`. If an order is already marked `paid`, it returns `{"success": true, "already_paid": true}` idempotently.
* **Expected Result:**
  - Both calls succeed (`success: true`).
  - Order is marked `paid`.
  - Products are marked `sold`.
  - Zero duplicate records or constraint violations.
* **Actual Result:** **PASS**.

---

## 3. Test Suite Execution Summary

```
 RUN  v5.0.0 C:/LiveDrop/buyer-web

 ✓ src/test/smoke.test.tsx (1 test) 27ms
 ✓ src/test/rls.test.ts (35 tests) 2090ms
 ✓ src/test/schema.test.ts (33 tests) 2226ms
 ✓ src/test/rpcs.test.ts (37 tests) 2279ms

 Test Files  4 passed (4)
      Tests  106 passed (106)
   Duration  2.71s
```

All 37 dedicated RPC unit and concurrency tests passed with 100% success rate.
