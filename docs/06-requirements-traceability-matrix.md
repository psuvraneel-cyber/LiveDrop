# 06 — Requirements Traceability Matrix (RTM): LiveDrop

**Document Version:** 2.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline (Fully Reconciled with Plan and Catalog)  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  
**Implementation Plan:** [`docs/32-implementation-plan.md`](file:///c:/LiveDrop/docs/32-implementation-plan.md)  
**Test Case Catalog:** [`docs/26-test-case-catalog.md`](file:///c:/LiveDrop/docs/26-test-case-catalog.md)  

---

## 1. Traceability Architecture

The Requirements Traceability Matrix (RTM) establishes a closed-loop verification chain connecting business needs to code execution:
```
PRD Requirement ──► UX Location ──► Domain Rule ──► DB Entity ──► API / RPC ──► UI Component ──► Test Case ──► Implementation Task
```

---

## 2. Master Traceability Matrix

| Req ID | PRD Source | UX Location | Domain Rule | DB Entity | API / RPC | UI Component | Test Case ID | Implementation Task | Status |
|---|---|---|---|---|---|---|---|---|---|
| **REQ-FR-B1.1** | `02-prd.md` §3.2 | Catalog Grid | RULE-PRD-01 | `products`, `drops` | `GET /rest/v1/products?drop_id=...` | `ProductGrid.tsx` | `TC-BUY-01` | `TASK-2.1` | **Implemented** |
| **REQ-FR-B1.2** | `02-prd.md` §3.2 | Product Card | RULE-PRD-02 | `products` | PostgREST SELECT | `ProductCard.tsx` | `TC-BUY-01` | `TASK-2.1` | **Implemented** |
| **REQ-FR-B1.3** | `02-prd.md` §3.2 | Sticky Filter Bar | RULE-PRD-03 | N/A (Client Filter) | N/A | `CatalogToolbar.tsx` | `TC-BUY-02`, `TC-BUY-03` | `TASK-2.1` | **Implemented** |
| **REQ-FR-B1.4** | `02-prd.md` §3.2 | Cart Trigger | RULE-PRD-04 | N/A (Client State) | N/A | `ProductCard.tsx` | `TC-BUY-04` | `TASK-2.2` | **Implemented** |
| **REQ-FR-B2.1** | `02-prd.md` §3.2 | Bottom Cart Bar | RULE-ORD-01 | N/A (Client State) | N/A | `StickyCartBar.tsx` | `TC-BUY-04` | `TASK-2.2` | **Implemented** |
| **REQ-FR-B2.2** | `02-prd.md` §3.2 | Cart Drawer | RULE-ORD-02 | N/A (Client State) | N/A | `CartDrawer.tsx` | `TC-BUY-04` | `TASK-2.2` | **Implemented** |
| **REQ-FR-B3.1** | `02-prd.md` §3.2 | Delivery Form & Checkout | RULE-BYR-01..04 | `orders` | `rpc/create_order_with_reservation` | `CheckoutForm.tsx`, `CheckoutReview.tsx`, `checkout/page.tsx` | `TC-BUY-05`, `TC-BUY-06`, `TC-CON-01..06` | `TASK-2.3` | **Implemented** |
| **REQ-FR-B3.2** | `02-prd.md` §3.2 | Local Persistence | RULE-BYR-05 | `localStorage` | N/A | `cart-storage.ts`, `cart-context.tsx` | `TC-BUY-05` | `TASK-2.2` | **Implemented** |
| **REQ-FR-B3.3** | `02-prd.md` §3.2 | Storefront & Advance Confirmation Domain | RULE-ORD-01..12 | `profiles`, `drops`, `orders`, `order_payments` | `rpc/create_order_with_reservation`, `rpc/confirm_order_advance`, `rpc/release_expired_holds` | Domain Models, Storefront contracts | `TC-CON-07..15`, `storefront-and-state-machine.test.ts` | `TASK-2.4A` | **Implemented** |
| **REQ-FR-B4.1** | `02-prd.md` §3.2 | WhatsApp Checkout | RULE-ORD-01..06 | `orders`, `order_items`, `products` | `rpc/create_order_with_reservation` | `WhatsAppCheckout.tsx` | `TC-BUY-07`, `TC-CON-01..06` | `TASK-3.3` | **Mapped** |
| **REQ-FR-B4.2** | `02-prd.md` §3.2 | WhatsApp Redirect | RULE-INT-01 | N/A (Deep Link) | N/A | `WhatsAppCheckout.tsx` | `TC-BUY-09` | `TASK-3.3` | **Mapped** |
| **REQ-FR-B4.3** | `02-prd.md` §3.2 | Confirmation Screen | RULE-ORD-07 | `orders`, `profiles` | `rpc/get_order_by_token` | `CheckoutSuccessView.tsx` | `TC-BUY-10` | `TASK-2.3` | **Implemented** |
| **REQ-FR-S1.1** | `02-prd.md` §4.2 | Ingestion Viewfinder | RULE-CAM-01 | N/A (Hardware) | N/A | `camera_screen.dart` | `TC-SEL-03` | `TASK-5.1` | **Mapped** |
| **REQ-FR-S1.2** | `02-prd.md` §4.2 | Sub-30s Loop | RULE-CAM-02 | `products` | `POST /storage/v1/object/...` + INSERT | `product_form_overlay.dart` | `TC-SEL-03`, `TC-SEL-04` | `TASK-5.2` | **Mapped** |
| **REQ-FR-S1.3** | `02-prd.md` §4.2 | Drop Publishing | RULE-DRP-01..05 | `drops` | `POST /rest/v1/drops` | `create_drop_screen.dart` | `TC-SEL-02`, `TC-SEL-05` | `TASK-4.2` | **Mapped** |
| **REQ-FR-S2.1** | `02-prd.md` §4.2 | Live Dashboard Grid | RULE-PRD-05 | `products` | Realtime `products` channel | `live_dashboard_screen.dart` | `TC-SEL-06` | `TASK-4.2`, `TASK-6.1` | **Mapped** |
| **REQ-FR-S2.2** | `02-prd.md` §4.2 | Metric Counters | RULE-DRP-04 | `products`, `orders` | Aggregate Query / Realtime | `live_dashboard_screen.dart` | `TC-SEL-06` | `TASK-6.1` | **Mapped** |
| **REQ-FR-S2.3** | `02-prd.md` §4.2 | Manual Overrides | RULE-PRD-06 | `products` | `rpc/mark_product_sold_offline` | `product_action_sheet.dart` | `TC-SEL-10` | `TASK-1.2`, `TASK-6.1` | **Mapped** |
| **REQ-FR-S3.1** | `02-prd.md` §4.2 | Kanban Pipeline | RULE-ORD-08..10 | `orders` | Realtime `orders` channel | `kanban_board_screen.dart` | `TC-SEL-06` | `TASK-6.1` | **Mapped** |
| **REQ-FR-S3.2** | `02-prd.md` §4.2 | Order Card Actions | RULE-ORD-07 | `orders`, `products` | `rpc/mark_order_paid` | `order_card.dart` | `TC-SEL-07`, `TC-REC-03` | `TASK-6.2` | **Mapped** |
| **REQ-FR-S4.1** | `02-prd.md` §4.2 | 4×6 Thermal Label | RULE-LBL-01 | N/A (Client PDF) | N/A | `shipping_label_view.dart` | `TC-SEL-08` | `TASK-7.1` | **Mapped** |
| **REQ-FR-S4.2** | `02-prd.md` §4.2 | Label Content & Barcode | RULE-LBL-02 | `orders`, `profiles` | Client Render | `shipping_label_view.dart` | `TC-SEL-08` | `TASK-7.1` | **Mapped** |
| **REQ-FR-S4.3** | `02-prd.md` §4.2 | Print & Share Dispatch | RULE-LBL-03 | `orders` | `PATCH /rest/v1/orders` | `shipping_label_view.dart` | `TC-SEL-09` | `TASK-7.2` | **Mapped** |

---

## 3. Coverage Analysis & Verification Integrity

### 3.1 Requirements Without Verification Mechanisms
* **Result:** **0 Requirements Unmapped**. Every functional requirement from `REQ-FR-B1.1` to `REQ-FR-S4.3` is paired with an authoritative test case in [`docs/26-test-case-catalog.md`](file:///c:/LiveDrop/docs/26-test-case-catalog.md).

### 3.2 Tests Without Formal Requirements
* **Result:** **0 Orphan Tests**. All test cases in the catalog derive directly from functional rules, security invariants, or concurrency edge-cases.

### 3.3 Implementation Tasks Without Requirements
* **Result:** **0 Orphan Tasks**. All implementation tasks in [`docs/32-implementation-plan.md`](file:///c:/LiveDrop/docs/32-implementation-plan.md) trace directly to approved system requirements, and every task identifier in this matrix references an authentic task in the roadmap.
