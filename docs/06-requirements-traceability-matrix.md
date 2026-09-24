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
| **REQ-FR-B3.3** | `02-prd.md` §3.2 | Storefront & Advance Confirmation Domain | RULE-ORD-01..12 | `profiles`, `drops`, `orders`, `order_payments` | `rpc/create_order_with_reservation`, `rpc/release_expired_holds` | Domain Models, Storefront contracts | `TC-CON-07..15`, `storefront-and-state-machine.test.ts` | `TASK-2.4A` | **Implemented** |
| **REQ-FR-B3.4** | `02-prd.md` §3.2 | Payment Authority Hardening & Idempotent Transitions | RULE-PAY-01..08 | `profiles`, `orders`, `order_payments` | `rpc/record_verified_payment`, `rpc/release_expired_holds` | Backend Webhook RPC, Idempotent Ledger | `TC-PAY-01..25`, `storefront-and-state-machine.test.ts` | `TASK-2.4A.1` | **Implemented** |
| **REQ-FR-B3.5** | `02-prd.md` §3.2 | Payment Authority Enforcement & Direct Mutation Hardening | RULE-PAY-09..12 | `orders`, `products` | `trg_enforce_orders_payment_immutability`, `trg_enforce_products_inventory_immutability` | Database Trigger & RLS Hardening | `A01..A13`, `storefront-and-state-machine.test.ts`, `rpcs.test.ts` | `TASK-2.4A.2` | **Implemented** |
| **REQ-FR-B3.6** | `02-prd.md` §3.2 | Direct Peer-to-Peer UPI Payment & Manual Seller Verification | RULE-PAY-13..25 | `payment_attempts`, `order_payments`, `profiles` | `rpc/initiate_payment_attempt`, `rpc/submit_buyer_payment_claim`, `rpc/verify_manual_upi_payment`, `rpc/reject_manual_upi_payment` | `DirectUpiPaymentView.tsx`, `payment_settings_screen.dart`, `pending_verifications_screen.dart` | `POS01..16`, `UPI-A01..35`, `direct-upi-payments.test.ts` | `TASK-2.4B` | **Implemented** |
| **REQ-FR-B3.7** | `02-prd.md` §3.2 | Persistent Payment Claims & Resume-Safe Buyer UX | RULE-PAY-26..35 | `payment_attempts`, `orders`, `products` | `rpc/submit_buyer_payment_claim`, `rpc/verify_manual_upi_payment`, `rpc/release_expired_holds`, `rpc/get_order_by_token` | `DirectUpiPaymentView.tsx`, `PendingVerificationsScreen` | `PERSIST-01..04`, `TIMER-01..06`, `EXPIRY-01..05`, `RACE-01..04`, `UI-01..08` | `TASK-2.4C` | **Implemented** |
| **REQ-FR-B3.8** | `02-prd.md` §3.2 | Production Readiness, Reaper Scheduling & Hosted Integration Gate | RULE-PAY-01..35, RULE-OPR-01..05 | `profiles`, `drops`, `products`, `orders`, `payment_attempts`, `order_payments` | All 14 Core RPCs, `release_expired_holds` | `LiveDropSellerApp`, `run-reaper.mjs`, `reaper-cron.yml`, `validate-hosted-supabase.mjs` | Acceptance Matrix Vectors 1..20 | `TASK-2.5` | **Implemented** |
| **REQ-FR-B3.9** | `02-prd.md` §3.2 | Real Staging Deployment & 30-Scenario Failure Injection Gate | RULE-PAY-01..35, RULE-OPR-01..05 | `profiles`, `drops`, `products`, `orders`, `payment_attempts`, `order_payments` | All 14 Core RPCs, `trg_enforce_orders_payment_immutability` | Test Harness, Secret Audit | Failure Matrix 01..30, 356 regression tests | `TASK-2.5A` | **Implemented** |
| **REQ-FR-B3.10** | Architecture Audit | Buyer Web Production Resilience, Tracking Route & WhatsApp Handoff | RULE-PAY-13..35, ADR-003, ADR-005 | `orders`, `payment_attempts`, `profiles` | `rpc/get_order_by_token` | `app/error.tsx`, `app/order/[id]/page.tsx`, `whatsapp.ts`, `DirectUpiPaymentView.tsx` | `order-route.test.tsx`, `whatsapp-chat.test.ts`, `error-boundaries.test.tsx` | `TASK-2.6` | **Implemented** |
| **REQ-FR-B4.1** | `02-prd.md` §3.2 | WhatsApp Checkout | RULE-ORD-01..06 | `orders`, `order_items`, `products` | `rpc/create_order_with_reservation` | `WhatsAppCheckout.tsx` | `TC-BUY-07`, `TC-CON-01..06` | `TASK-3.3` | **Mapped** |
| **REQ-FR-B4.2** | `02-prd.md` §3.2 | WhatsApp Redirect | RULE-INT-01 | N/A (Deep Link) | N/A | `WhatsAppCheckout.tsx` | `TC-BUY-09` | `TASK-3.3` | **Mapped** |
| **REQ-FR-B4.3** | `02-prd.md` §3.2 | Confirmation Screen | RULE-ORD-07 | `orders`, `profiles` | `rpc/get_order_by_token` | `CheckoutSuccessView.tsx` | `TC-BUY-10` | `TASK-2.3` | **Implemented** |
| **REQ-FR-S1.1** | `02-prd.md` §4.2 | Ingestion Viewfinder | RULE-CAM-01 | N/A (Hardware) | N/A | `camera_intake_screen.dart` | `TC-SEL-03`, `sprint2_seller_operations_test.dart` | `TASK-5.1` | **Implemented** |
| **REQ-FR-S1.2** | `02-prd.md` §4.2 | Sub-30s Loop | RULE-CAM-02 | `products` | `POST /storage/v1/object/...` + INSERT | `camera_intake_screen.dart`, `image_service.dart` | `TC-SEL-03`, `TC-SEL-04`, `sprint2_seller_operations_test.dart` | `TASK-5.2` | **Implemented** |
| **REQ-FR-S1.3** | `02-prd.md` §4.2 | Drop Publishing | RULE-DRP-01..05 | `drops` | `POST /rest/v1/drops` | `drops_list_screen.dart`, `create_drop_screen.dart` | `TC-SEL-02`, `TC-SEL-05`, `seller_repository_test.dart` | `TASK-4.2` | **Implemented** |
| **REQ-FR-S2.1** | `02-prd.md` §4.2 | Live Dashboard Grid | RULE-PRD-05 | `products` | Realtime `products` channel | `seller_dashboard_screen.dart` | `TC-SEL-06`, `luxury_ui_and_motion_test.dart` | `TASK-4.2`, `TASK-6.1` | **Implemented** |
| **REQ-FR-S2.2** | `02-prd.md` §4.2 | Metric Counters | RULE-DRP-04 | `products`, `orders` | Aggregate Query / Realtime | `seller_dashboard_screen.dart` | `TC-SEL-06`, `luxury_ui_and_motion_test.dart` | `TASK-6.1` | **Implemented** |
| **REQ-FR-S2.3** | `02-prd.md` §4.2 | Manual Overrides | RULE-PRD-06 | `products` | `rpc/mark_product_sold_offline` | `product_details_screen.dart`, `products_inventory_screen.dart` | `TC-SEL-10`, `seller_repository_test.dart` | `TASK-1.2`, `TASK-6.1` | **Implemented** |
| **REQ-FR-S3.1** | `02-prd.md` §4.2 | Kanban Pipeline | RULE-ORD-08..10 | `orders` | Realtime `orders` channel | `kanban_board_screen.dart` | `TC-SEL-06`, `sprint2_seller_operations_test.dart` | `TASK-6.1` | **Implemented** |
| **REQ-FR-S3.2** | `02-prd.md` §4.2 | Order Card Actions | RULE-ORD-07 | `orders`, `products` | `rpc/mark_order_paid`, `rpc/mark_order_shipped` | `order_card.dart`, `order_details_screen.dart` | `TC-SEL-07`, `TC-REC-03`, `sprint2_seller_operations_test.dart` | `TASK-6.2` | **Implemented** |
| **REQ-FR-S4.1** | `02-prd.md` §4.2 | 4×6 Thermal Label | RULE-LBL-01 | N/A (Client PDF) | N/A | `shipping_label_screen.dart`, `pdf_label_service.dart` | `TC-SEL-08`, `sprint2_seller_operations_test.dart` | `TASK-7.1` | **Implemented** |
| **REQ-FR-S4.2** | `02-prd.md` §4.2 | Label Content & Barcode | RULE-LBL-02 | `orders`, `profiles` | Client Render | `shipping_label_screen.dart`, `pdf_label_service.dart` | `TC-SEL-08`, `sprint2_seller_operations_test.dart` | `TASK-7.1` | **Implemented** |
| **REQ-FR-S4.3** | `02-prd.md` §4.2 | Print & Share Dispatch | RULE-LBL-03 | `orders` | `rpc/mark_order_shipped` | `shipping_label_screen.dart`, `shipping_dialog.dart` | `TC-SEL-09`, `sprint2_seller_operations_test.dart` | `TASK-7.2` | **Implemented** |
| **REQ-FR-S1.4** | User Override | In-App Seller Registration & Onboarding Fee | RULE-PRD-01..03, RULE-PAY-01 | `auth.users`, `profiles` | `auth.signUp`, `trg_on_auth_user_created` | `seller_registration_screen.dart` | `seller_auth_registration_test.dart` | `TASK-4.1A` | **Implemented** |
| **REQ-FR-S1.5** | User Override | Admin WhatsApp Support & Password Reset | RULE-INT-01 | `auth.users` | `auth.resetPasswordForEmail`, WhatsApp Intent | `seller_login_screen.dart`, `admin_config.dart` | `seller_auth_registration_test.dart` | `TASK-4.1B` | **Implemented** |
| **REQ-BLK-1A** | Architecture Audit | Seller Provisioning Security & Approval Gate | SEC-01 | `profiles`, `drops` | `rpc/admin_approve_seller`, `trg_enforce_drops_seller_approval` | `seller_pending_approval_screen.dart` | Migration 021, Scenario 29 | `TASK-PHASE1-1A` | **Implemented** |
| **REQ-BLK-1B** | Architecture Audit | Buyer Public Catalog Projections Wiring | SEC-02 | `public_products_catalog`, `public_seller_storefronts` | PostgREST View SELECT | `buyer-catalog.ts`, `drop/[slug]/page.tsx` | `catalog-feed.test.tsx`, Scenario 34 | `TASK-PHASE1-1B` | **Implemented** |
| **REQ-BLK-1C** | Architecture Audit | Checkout Idempotency & Conflict Detection | RULE-ORD-01 | `orders` | `rpc/create_order_with_reservation` | `idempotency.ts`, `checkout/page.tsx` | `checkout-idempotency.test.ts`, Scenario 31 | `TASK-PHASE1-1C` | **Implemented** |
| **REQ-BLK-1D** | Architecture Audit | Buyer Payment-State Sync & Bounded Polling | RULE-PAY-26..35 | `orders`, `payment_attempts` | `rpc/get_order_by_token`, Polling Loop | `DirectUpiPaymentView.tsx` | `persistent-payment-claims-ui.test.tsx`, Scenario 17 | `TASK-PHASE1-1D` | **Implemented** |
| **REQ-BLK-1E** | Architecture Audit | Late UPI Payment Recovery & Grace Period | RULE-PAY-13..25 | `payment_attempts`, `orders`, `products` | `rpc/submit_buyer_payment_claim` | `DirectUpiPaymentView.tsx` | Scenario 08, 13, 33 | `TASK-PHASE1-1E` | **Implemented** |
| **REQ-BLK-1F** | Architecture Audit | Safe Drop Closure Invariant Guard | RULE-DRP-05 | `drops`, `orders` | `trg_drops_safe_closure` | `seller_repository.dart` | Migration 024 Trigger Test | `TASK-PHASE1-1F` | **Implemented** |
| **REQ-BLK-1G** | Architecture Audit | Seller Offline Intake Background Queue | ADR-006 | Device Flash, `products` | `offline_intake_queue.dart` | `camera_intake_screen.dart` | `offline_intake_queue_test.dart` | `TASK-PHASE1-1G` | **Implemented** |
| **REQ-BLK-1H** | Architecture Audit | Live Inventory Editing & Immutability | RULE-PRD-06 | `products` | `rpc/update_product` | `product_details_screen.dart` | Scenario 35 | `TASK-PHASE1-1H` | **Implemented** |
| **REQ-BLK-1I** | Architecture Audit | Fulfillment State Machine & Packing Check | SEC-05 | `orders` | `rpc/mark_order_ready_to_ship`, `rpc/mark_order_shipped` | `shipping_dialog.dart` | Scenario 36 | `TASK-PHASE1-1I` | **Implemented** |
| **REQ-BLK-1J** | User Request / Intake UX | Multi-Angle Garment Intake & Buyer Carousel | RULE-PRD-01..05 | `products (image_urls)`, `storage.objects` | `OfflineIntakeQueue`, Supabase Storage | `CameraIntakeScreen`, `ProductsInventoryScreen`, `ProductCard` | `catalog-feed.test.tsx`, `offline_intake_queue_test.dart` | `TASK-PHASE1-1J` | **Implemented** |
| **REQ-BLK-1K** | Production Checkout | PostgREST RPC Overload Disambiguation (`get_order_by_token`) | RULE-PAY-13..35, ADR-001 | `orders`, `pg_proc` | `rpc/get_order_by_token(uuid, text)` | `buyer-catalog.ts`, `checkout/page.tsx` | Migration 028, Vitest (391 tests), Live Order Verification | `TASK-PHASE1-1K` | **Implemented** |
| **REQ-BLK-1L** | User Request / Storefront Arch | Seller Storefront Routing, Canonical URL & Lookbook Showcase Mode | RULE-PRD-01..05, ADR-002, ADR-009 | `profiles`, `drops`, `public_seller_storefronts`, `public_products_catalog` | `getStorefrontData`, `getAllVerifiedStorefronts`, `getAllActiveLiveDrops` | `BoutiqueStorefrontView.tsx`, `app/[storeSlug]/page.tsx`, `HomeStorefront.tsx`, `seller_settings_screen.dart` | `storefront-route.test.tsx`, `storefront_url_test.dart` | `TASK-PHASE1-1L` | **Implemented** |
| **REQ-BLK-1M** | User Request / Haute Couture | Mobile-First Redesign, 4-Tab Dock, Editorial Monogram Header | RULE-PRD-01..05, ADR-009 | N/A (Client Layout & Styling) | N/A | `LuxuryTopHeader.tsx`, `MobileBottomDock.tsx`, `HomeStorefront.tsx` | `mobile-bottom-dock.test.tsx`, Vitest Suite | `TASK-PHASE1-1M` | **Implemented** |
| **REQ-BLK-1N** | User Request / Live Commerce | Facebook Live Video Commerce, Stream URL & Live Room View | RULE-DRP-01..05, ADR-009 | `drops (stream_url)` | `POST /rest/v1/drops`, PostgREST SELECT | `FacebookLivePlayer.tsx`, `CinematicLiveRoomView.tsx`, `create_drop_screen.dart` | `facebook-live-player.test.tsx`, `cinematic-live-room.test.tsx` | `TASK-PHASE1-1N` | **Implemented** |
| **REQ-BLK-1O** | User Request / Haute Couture | Adaptive Bottom Sheet Quick-View & Dedicated Category Directory | RULE-PRD-01..04, ADR-009 | `products`, `profiles` | `getAllVerifiedStorefronts`, `getAllActiveLiveDrops` | `ProductQuickViewDrawer.tsx`, `ShopCategoryDirectory.tsx`, `app/shop/page.tsx` | `product-quick-view-drawer.test.tsx`, `shop-category-directory.test.tsx` | `TASK-PHASE1-1O` | **Implemented** |
| **REQ-RC-01** | Release Candidate Gate | Physical Hardware Integration & Verification | RULE-DEV-01 | Xiaomi M2007J17I (`7732644d`) | Flutter Native Engine | `store.livedrop.seller_app` | 16 Hardware Screen Verifications | `PHASE-4` | **Implemented** |
| **REQ-RC-02** | Release Candidate Gate | Remote Staging Parity (Migrations 015-027) | RULE-DB-01 | Hosted Supabase `aoagqdtnrbmayfoajzes` | Supabase MCP Migrations | All 7 tables, 2 views, 16 triggers | Remote Migration Verification | `PHASE-2` | **Implemented** |
| **REQ-RC-03** | Release Candidate Gate | Cross-Stack Integration Matrix (26 Vectors) | RULE-ARC-01..35 | Cross-Stack | REST / Realtime / RPC | `buyer-web`, `seller-app`, Supabase | `RELEASE-CANDIDATE-INTEGRATION-MATRIX.md` | `PHASE-54` | **Implemented** |
| **REQ-RC-04** | Release Candidate Gate | Final Release Readiness & Defect Accounting | RULE-REL-01 | Complete Platform | All RPCs, Triggers, Views, Endpoints | Full System | `FINAL-RELEASE-CANDIDATE-REPORT.md` | `PHASE-58` | **Implemented** |

---

## 3. Coverage Analysis & Verification Integrity

### 3.1 Requirements Without Verification Mechanisms
* **Result:** **0 Requirements Unmapped**. Every functional requirement from `REQ-FR-B1.1` to `REQ-FR-S4.3` is paired with an authoritative test case in [`docs/26-test-case-catalog.md`](file:///c:/LiveDrop/docs/26-test-case-catalog.md).

### 3.2 Tests Without Formal Requirements
* **Result:** **0 Orphan Tests**. All test cases in the catalog derive directly from functional rules, security invariants, or concurrency edge-cases.

### 3.3 Implementation Tasks Without Requirements
* **Result:** **0 Orphan Tasks**. All implementation tasks in [`docs/32-implementation-plan.md`](file:///c:/LiveDrop/docs/32-implementation-plan.md) trace directly to approved system requirements, and every task identifier in this matrix references an authentic task in the roadmap.
