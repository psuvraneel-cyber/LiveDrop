# LiveDrop — Phase 1 Fulfillment State Machine & Packing Verification

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-22  
**Governing Roles:** Supply Chain Systems Engineer & Backend Architect  
**Authoritative Index:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Operating Guardrails:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)  
**Related Specs:** [`docs/09-system-state-machines.md`](file:///c:/LiveDrop/docs/09-system-state-machines.md), [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md)

---

## 1. Fulfillment Lifecycle & State Machine

Order fulfillment in LiveDrop governs the transition of purchased garments from confirmed payment through warehouse packaging and carrier handoff.

```
                  ┌───────────────────────────────┐
                  │           not_ready           │
                  │ (Order placed / hold active)  │
                  └──────────────┬────────────────┘
                                 │
             Full Payment Verified (balance_due = 0)
             & Packing Verified via mark_order_ready_to_ship()
                                 │
                                 ▼
                  ┌───────────────────────────────┐
                  │         ready_to_ship         │
                  │  (packed_at set, label printed│
                  └──────────────┬────────────────┘
                                 │
             Courier & Tracking Logged via mark_order_shipped()
                                 │
                                 ▼
                  ┌───────────────────────────────┐
                  │            shipped            │
                  │ (shipped_at set, dispatched)  │
                  └───────────────────────────────┘
```

---

## 2. Invariants & Enforcements (`026_fulfillment_state_machine.sql`)

### 2.1 Database Schema Extensions
1. **Packed Timestamp:**
   ```sql
   ALTER TABLE orders ADD COLUMN IF NOT EXISTS packed_at TIMESTAMPTZ;
   ```
2. **Authoritative `mark_order_ready_to_ship` RPC:**
   - **Authorization:** Only the seller who owns the drop may invoke this RPC. Unauthorized calls are rejected with `FORBIDDEN`.
   - **Financial Settlement Gate:** Strict prerequisite check:
     ```sql
     IF v_order.payment_status != 'paid' OR v_order.balance_due_paisa > 0 THEN
         RETURN jsonb_build_object(
             'success', false,
             'error', 'ORDER_NOT_FULLY_PAID'
         );
     END IF;
     ```
   - **Idempotency:** If the order is already in `ready_to_ship` or `shipped` status, the RPC returns `success: true` without raising errors or altering existing timestamps.
   - **State Transition:** Updates `fulfilment_status = 'ready_to_ship'` and sets `packed_at = COALESCE(packed_at, NOW())`.

### 2.2 Hardened `mark_order_shipped` RPC
- **Enforced Packaging Stage (SEC-05):**
  Orders cannot bypass the packing verification stage. If an order in `not_ready` status is passed to `mark_order_shipped`, execution aborts:
  ```sql
  IF v_order.fulfilment_status != 'ready_to_ship' THEN
      RETURN jsonb_build_object(
          'success', false,
          'error', 'ORDER_NOT_READY_TO_SHIP'
      );
  END IF;
  ```
- **Tracking & Courier Recording:**
  Requires non-empty `tracking_number` and `courier_name`. Updates `fulfilment_status = 'shipped'`, `shipped_at = NOW()`, and records shipping metadata.

---

## 3. Client & UI Integration

### 3.1 Flutter Seller Domain Model & Repository
1. **Model:** `SellerOrder` in [`seller-app/lib/domain/models/models.dart`](file:///c:/LiveDrop/seller-app/lib/domain/models/models.dart) parses `packedAt` from JSON.
2. **Repository:** `markOrderReadyToShip(String orderId)` exposed in [`seller-app/lib/data/repositories/seller_repository.dart`](file:///c:/LiveDrop/seller-app/lib/data/repositories/seller_repository.dart).
3. **Dispatch Dialog:** [`seller-app/lib/presentation/orders/shipping_dialog.dart`](file:///c:/LiveDrop/seller-app/lib/presentation/orders/shipping_dialog.dart) automatically verifies that the order is marked `ready_to_ship` prior to calling `markOrderShipped`, preventing premature carrier dispatch errors.

---

## 4. Verification

1. **Automated Failure Injection (Scenario 36):**
   - Unpaid order packing attempt: correctly rejected with `ORDER_NOT_FULLY_PAID`.
   - Cross-seller packing attempt: correctly blocked with `FORBIDDEN`.
   - Direct shipment of `not_ready` order: correctly blocked with `ORDER_NOT_READY_TO_SHIP`.
   - Valid transition sequence: `not_ready` -> `ready_to_ship` -> `shipped` succeeds with full audit trail.
2. **Automated Schema Verification:**
   - `scripts/verify-schema.mjs`: PASSED with exit code 0.
