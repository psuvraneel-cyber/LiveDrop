# ADR-009: Currency Integer Paisa Standardization, Secure Token RPC & Concurrency Hardening

## Status
**Accepted**

## Context
During the pre-implementation consistency gate audit, four critical technical discrepancies were identified across the documentation suite:
1. **Currency Representation Mismatch**: `AGENTS.md` (Rule 5), `35-engineering-conventions.md`, and `36-ai-agent-development-rules.md` strictly prohibit floating-point or decimal representations for money, mandating integer **Paisa** (`150000` = ₹1,500.00). However, the initial database DDL and API contracts used `NUMERIC(10, 2)` and floating-point JSON numbers, while the SQLite queue schema used `REAL`.
2. **PII Security Hole in Orders RLS Policy**: The draft RLS policy `orders_buyer_read_with_token` contained an `OR id::text = current_setting('request.headers', true)::json->>'x-order-id'` clause, which allowed any unauthenticated actor knowing an order UUID to bypass `order_token` validation and scrape customer names, phones, and addresses. Additionally, standard PostgREST queries cannot inspect URL query parameters via `request.headers`.
3. **Missing Lock in `mark_order_paid`**: The `mark_order_paid` RPC checked whether expired products were reclaimed via a `SELECT COUNT(*)` without acquiring `FOR UPDATE` row locks, creating a race condition if another buyer checked out concurrently.
4. **Shipping Policy Storage Location**: `DEC-001` in `37-open-decisions.md` recommended storing shipping fees on `drops` (with a seller profile default), whereas `12-database-design.md` omitted shipping columns from `drops` and stored them only on `profiles`.

## Decision
1. **Paisa Currency Standardization**:
   * All monetary values in the database, APIs, RPCs, and local caches are strictly typed as 32-bit/64-bit integers representing Indian **Paisa** (`price_paisa`, `subtotal_paisa`, `shipping_fee_paisa`, `total_paisa`, `free_shipping_threshold_paisa`).
   * Division by 100 is performed strictly at the final UI rendering layer for human display (e.g. `₹${(price_paisa / 100).toFixed(2)}`).
   * The SQLite offline queue schema updates `price REAL` to `price_paisa INTEGER NOT NULL`.
2. **Hardened Token-Gated Receipt Access via Dedicated RPC**:
   * Remove the vulnerable `OR id::text = ...` clause from the `orders` RLS policy.
   * Provide a dedicated `SECURITY DEFINER` function `get_order_by_token(p_order_id UUID, p_order_token UUID)` that returns the sanitized order receipt and bundled items only when the provided token cryptographically matches `orders.order_token`.
3. **Atomic Concurrency Hardening**:
   * `create_order_with_reservation`: Enforce deterministic primary-key sorting (`ORDER BY id ASC`) and input deduplication (`v_sanitized_ids`) before acquiring `FOR UPDATE` locks.
   * `mark_order_paid`: Enforce `SELECT id FROM products ... ORDER BY id ASC FOR UPDATE` locking on all bundled product rows before checking `v_contested_count`, completely closing the race window.
   * Add lazy cleanup: `create_order_with_reservation` invokes `PERFORM release_expired_holds()` at the start of execution to reclaim expired stock on demand.
4. **Drop-Level Shipping Configuration with Profile Default**:
   * Add `shipping_fee_paisa INT NOT NULL DEFAULT 8000` and `free_shipping_threshold_paisa INT DEFAULT 200000` to the `drops` table.
   * Retain `default_shipping_fee_paisa` and `free_shipping_threshold_paisa` on `profiles` as the seller's reusable template when creating new drops.
   * Order calculation in `create_order_with_reservation` authoritatively reads shipping parameters from `drops`.
5. **Standardized Order Code Format**:
   * Standardize customer order codes to 6-character Crockford Base32: `LD-[0-9A-Z]{6}` (e.g., `LD-7K92MF`), yielding over 2.1 billion combinations and eliminating enumeration risk.

## Consequences
* **Positive**: Absolute mathematical alignment with AI Agent operating rules; zero floating-point rounding bugs; 100% closed PII security boundary; mathematically serialized state transitions.
* **Negative**: Requires multiplying and dividing by 100 when serializing/deserializing prices in TypeScript and Flutter presentation layers.
