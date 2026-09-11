# 25 — Comprehensive Testing Strategy: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  
**Test Case Catalog:** [`docs/26-test-case-catalog.md`](file:///c:/LiveDrop/docs/26-test-case-catalog.md)  

---

## 1. Quality Engineering Philosophy & Test Pyramid

LiveDrop enforces a multi-tiered verification framework to guarantee zero-defect inventory locking, reliable courier dispatch, and rock-solid mobile performance across variable 4G networks.

```
                           ┌─────────────────────────┐
                           │   13. Physical Devices  │
                           ├─────────────────────────┤
                           │  10-12. E2E / Stress    │
                           ├─────────────────────────┤
                           │   7-9. API & Realtime   │
                           ├─────────────────────────┤
                           │  4-6. Database, RPC, RLS│
                           ├─────────────────────────┤
                           │  1-3. Unit & Components │
                           └─────────────────────────┘
```

---

## 2. The 13 Testing Layers

| Layer # | Testing Layer | Scope of Verification | Frameworks & Tools | Target Coverage | Gate Criteria |
|---|---|---|---|---|---|
| **1** | **Unit Testing** | Business utilities (WhatsApp link encoder, phone sanitizer, subtotal calc). | Vitest (Next.js), Dart test (Flutter) | > 90% logic coverage | 100% pass on CI |
| **2** | **Widget / Component** | Isolated UI components (`ProductCard`, `StickyCartBar`, `OrderCard`). | React Testing Library, Flutter Widget Tester | > 85% component paths | Zero visual regressions |
| **3** | **Integration Testing** | Repository layer, local Hive queue, state management wiring. | Vitest, Flutter integration_test | > 80% data flow paths | Repositories verify mock payloads |
| **4** | **Database Schema & DDL** | Constraints (`CHECK`, `NOT NULL`, `UNIQUE`), cascade behaviors. | pgTAP, Supabase Local CLI | 100% table schemas | Schema migrations apply cleanly |
| **5** | **PostgreSQL RPC Testing** | Transaction isolation, `create_order_with_reservation`, `mark_order_paid`. | pgTAP, custom SQL test harness | 100% procedural logic | All error branches tested |
| **6** | **Security & RLS Testing** | Cross-seller isolation, unauthenticated public restrictions, token gating. | pgTAP (`SET ROLE anon`, `SET ROLE authenticated`) | 100% RLS policies | Zero unauthorized data leaks |
| **7** | **API Contract Testing** | REST endpoints, PostgREST queries, parameter validation. | Playwright, Supertest, Postman | 100% documented endpoints | Conforms strictly to `13-api-contract.md` |
| **8** | **Realtime WebSocket Testing**| Subscription filters, payload broadcasting, reconnect resync. | Custom Node.js WebSocket client, Vitest | 100% channel definitions | Broadcast deltas arrive < 1.5s |
| **9** | **End-to-End (E2E)** | Full buyer cart flow to WhatsApp; seller intake to thermal PDF print. | Playwright (Web), Flutter Driver (Mobile) | All 9 core E2E scenarios | Zero critical journey breaks |
| **10** | **Concurrency & Stress** | 20 buyers claiming same product simultaneously; deadlock testing. | k6, pgbench, Node.js concurrency harness | Up to 50 concurrent checkouts | Zero double-bookings; zero deadlocks |
| **11** | **Performance & Budgets**| FCP < 1.5s, LCP < 2.5s, JS bundle < 300KB, intake < 30s. | Lighthouse Mobile, Chrome DevTools, Flutter Profiler | 100% budget targets | No budget threshold exceeded |
| **12** | **Offline & Recovery** | Cellular network cut during camera intake; background upload resumption. | Android network throttling, Mockito | All failure recovery playbooks | Upload queue resumes without data loss |
| **13** | **Physical Device Testing**| Budget Android phones (Redmi 9A, 3GB RAM); Bluetooth thermal printers. | Manual physical lab testing | Real-world hardware test suite | Shutter and print validated |

---

## 3. Layer-to-Requirement Verification Mapping

| Requirement Group | Primary Verification Layer | Secondary Verification Layer |
|---|---|---|
| **Flash Code & Catalog Browsing (`REQ-FR-B1`)** | Layer 2 (Widget) & Layer 7 (API) | Layer 9 (E2E) & Layer 11 (Performance) |
| **Sticky Multi-Item Cart (`REQ-FR-B2`)** | Layer 1 (Unit) & Layer 2 (Component) | Layer 9 (E2E Scenario C) |
| **Zero-Friction Delivery Form (`REQ-FR-B3`)** | Layer 1 (Sanitizer Unit) & Layer 2 (Component) | Layer 7 (Validation API) |
| **Atomic 15-Minute Reservation (`REQ-FR-B4`)** | Layer 5 (RPC Test) & Layer 10 (Concurrency) | Layer 6 (Security RLS) |
| **Sub-30s Camera Intake (`REQ-FR-S1`)** | Layer 11 (Performance) & Layer 13 (Device) | Layer 12 (Offline Queue) |
| **Live Session Monitor (`REQ-FR-S2`)** | Layer 8 (Realtime) & Layer 2 (Widget) | Layer 9 (E2E Scenario A) |
| **Visual Kanban Pipeline (`REQ-FR-S3`)** | Layer 2 (Widget) & Layer 5 (RPC Test) | Layer 9 (E2E Scenario A, F) |
| **4×6 Thermal Courier Slip (`REQ-FR-S4`)** | Layer 1 (PDF Render Unit) & Layer 13 (Printer) | Layer 2 (Widget Preview) |
| **Zero PII Exposure (`SEC-PII`)** | Layer 6 (RLS Testing) & Layer 7 (API Scrape Test) | Layer 9 (Security Audit) |

---

## 4. Test Execution Environments

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            TESTING ENVIRONMENTS                             │
├────────────────────┬─────────────────────────────┬──────────────────────────┤
│ Environment        │ Infrastructure Stack        │ Purpose                  │
├────────────────────┼─────────────────────────────┼──────────────────────────┤
│ **Local Dev / CI** │ Dockerized Supabase CLI     │ Unit, Component, Schema, │
│                    │ PostgreSQL 15, Node.js      │ pgTAP RPC and RLS tests  │
├────────────────────┼─────────────────────────────┼──────────────────────────┤
│ **Staging**        │ Cloudflare Pages Preview,   │ Full E2E Playwright,     │
│                    │ Cloud Supabase Staging DB   │ Realtime, Stress (k6)    │
├────────────────────┼─────────────────────────────┼──────────────────────────┤
│ **Hardware Lab**   │ Physical Android Devices    │ Camera intake latency,   │
│                    │ Bluetooth Thermal Printers  │ Bluetooth ESC/POS print  │
└────────────────────┴─────────────────────────────┴──────────────────────────┘
```
