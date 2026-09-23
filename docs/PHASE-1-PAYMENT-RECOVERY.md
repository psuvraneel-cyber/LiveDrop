# LiveDrop — Phase 1 Payment Recovery, Idempotency & Realtime Sync

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-22  
**Governing Roles:** Payments Architect & Distributed Systems Engineer  
**Authoritative Index:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Operating Guardrails:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)  
**Related ADRs:** ADR-002 (Atomic Reservation), ADR-008 (Payment Authority), ADR-009 (Integer Paisa)

---

## 1. Background & Failure Modes Addressed

In peer-to-peer UPI live commerce, mobile network dropouts, multi-app context switches (switching from browser to PhonePe/GPay/Paytm and back), and banking gateway latency introduce severe asynchronous race conditions:
1. **Network Retry Duplication:** Rapid double-tapping of the checkout button or automated client retry loops could submit duplicate orders or trigger `STOCK_UNAVAILABLE` on identical payloads.
2. **Silent Realtime WebSocket Blindness:** Anonymous buyers subscribing to Supabase Realtime CDC channels miss postgres change events because custom HTTP authorization headers (`x-order-token`) are omitted from standard WebSocket upgrade requests.
3. **Late UPI Confirmation After Hold Expiration:** A buyer may take 8 minutes to complete a UPI transfer on a 5-minute reservation. If the hold expired and the reaper script executed, the buyer's money was debited by their bank, but the platform recorded the order as expired/cancelled.

---

## 2. Blocker 1C: Checkout Request Idempotency & Payload Conflict Detection

### 2.1 Technical Specification (`022_checkout_idempotency_conflict_detection.sql`)
1. **Idempotency Key Persistence:**
   The `orders` table stores a unique `idempotency_key TEXT` scoped per drop:
   ```sql
   CREATE UNIQUE INDEX idx_orders_drop_idempotency 
   ON orders (drop_id, idempotency_key) 
   WHERE idempotency_key IS NOT NULL;
   ```
2. **Cryptographic Payload Fingerprinting:**
   The client generates a SHA-256 fingerprint of the normalized checkout payload:
   ```typescript
   // buyer-web/src/lib/checkout/idempotency.ts
   export async function hashPayload(payload: Record<string, unknown>): Promise<string> {
     const canonical = JSON.stringify(payload, Object.keys(payload).sort());
     // SHA-256 hash output
   }
   ```
3. **Conflict Detection In `create_order_with_reservation`:**
   When an incoming checkout request matches an existing `(drop_id, idempotency_key)`:
   - If the payload hash and buyer parameters match the existing order: the RPC returns the existing order receipt immediately (`status: 'success'`).
   - If the payload differs (e.g., different product items or different buyer phone number): the RPC rejects the request immediately with:
     ```json
     { "error": "CHECKOUT_IDEMPOTENCY_CONFLICT" }
     ```
   This prevents request hijacking and accidental parameter mutation during network retries.

---

## 3. Blocker 1D: Buyer Payment-State Synchronization & Dual-Mode Recovery

### 3.1 Architectural Problem
Supabase Realtime CDC evaluates PostgreSQL Row-Level Security policies during change broadcast. For anonymous buyers, `auth.uid()` is null, and custom HTTP request headers cannot be evaluated in WebSocket workers. Realtime events were silently dropped.

### 3.2 Dual-Mode Realtime + Bounded Polling Engine (`DirectUpiPaymentView.tsx`)
To guarantee deterministic UI reconciliation without overloading PostgreSQL, the buyer checkout client implements a layered synchronization engine:
1. **Primary WebSocket Listener:** Listens on `postgres_changes` for `orders` and `payment_attempts`. If supported, transitions are instantaneous (<200ms).
2. **Adaptive Bounded Polling Fallback:**
   - Active when the payment attempt is in `awaiting_seller_verification`.
   - Polling interval: Every 3,000ms.
   - Bounded duration: 600,000ms (10 minutes).
   - Query: `get_order_by_token(order_id, receipt_token)`.
3. **Document Visibility & Window Focus Trigger:**
   When a buyer returns from their UPI banking application (GPay, PhonePe, Paytm), the browser triggers a `visibilitychange` / `focus` event. The client immediately dispatches a high-priority status query, ensuring zero delay upon returning to the tab.

---

## 4. Blocker 1E: Late UPI Payment Recovery & Grace Period Extension

### 4.1 Problem Mechanics
A buyer transfers funds via UPI, but due to SMS verification or bank delay, submits their 12-digit UTR 30 seconds after their reservation window expired. Under previous behavior, the platform rejected the claim as `ORDER_EXPIRED`.

### 4.2 Grace Period & Auto-Reinstatement Engine (`023_late_upi_recovery.sql`)
When `submit_buyer_payment_claim` is called:
```sql
-- Check if order is expired or hold has passed
IF v_order.status = 'cancelled' OR (v_order.hold_expires_at IS NOT NULL AND v_order.hold_expires_at < NOW()) THEN
    -- Check if products have been re-purchased or re-reserved by another buyer
    SELECT bool_or(p.status != 'available' AND p.reserved_by_order_id != p_order_id)
    INTO v_products_taken
    FROM order_items oi
    JOIN products p ON p.id = oi.product_id
    WHERE oi.order_id = p_order_id;

    IF NOT v_products_taken THEN
        -- AUTOMATIC RECOVERY: Products are still free
        -- Re-lock inventory to this order
        UPDATE products
        SET status = 'reserved',
            reserved_by_order_id = p_order_id,
            hold_expires_at = NOW() + INTERVAL '15 minutes'
        WHERE id IN (SELECT product_id FROM order_items WHERE order_id = p_order_id);

        -- Restore order to pending with extended hold
        UPDATE orders
        SET status = 'pending',
            hold_expires_at = NOW() + INTERVAL '15 minutes'
        WHERE id = p_order_id;

        -- Record payment attempt
        INSERT INTO payment_attempts (...)
        VALUES (..., 'awaiting_seller_verification', NOW() + INTERVAL '15 minutes');

        RETURN jsonb_build_object(
            'success', true,
            'recovery_status', 'LATE_CLAIM_RECOVERED',
            'hold_expires_at', NOW() + INTERVAL '15 minutes'
        );
    ELSE
        -- PRODUCTS TAKEN: Money was paid but items cannot be fulfilled
        -- Record orphan payment attempt for administrative/seller refund
        INSERT INTO payment_attempts (...)
        VALUES (..., 'unmatched_late_claim', NULL);

        RETURN jsonb_build_object(
            'success', false,
            'error', 'ORDER_EXPIRED_HOLD_RELEASED',
            'support_ticket_required', true
        );
    END IF;
END IF;
```

### 4.3 Deterministic Ledger & Paisa Invariants
- Expected amount is strictly verified against `orders.subtotal_paisa + orders.shipping_paisa` or `orders.advance_required_paisa`.
- Currency calculations strictly operate on 64-bit integer Paisa. Floating-point conversions are banned.
- UTR uniqueness is preserved via `uq_order_payments_reference_verified`.
