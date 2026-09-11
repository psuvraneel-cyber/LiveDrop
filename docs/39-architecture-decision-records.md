# LiveDrop — Architecture Decision Records (ADR) Index

## 1. Purpose
Architecture Decision Records (ADRs) capture critical technical choices, the rationale behind them, trade-offs evaluated, and their consequences on the LiveDrop system. Once an ADR is marked **Accepted**, it is binding on all future engineering activities.

---

## 2. ADR Status Key
* **Proposed**: Under review; feedback solicited.
* **Accepted**: Formally approved; guides current implementation.
* **Superseded**: Replaced by a subsequent ADR.
* **Rejected**: Evaluated and discarded.

---

## 3. ADR Registry

| ADR ID | Title | Status | Date | Primary Author | Governed Domain |
|---|---|---|---|---|---|
| [ADR-001](file:///c:/LiveDrop/docs/adr/ADR-001-two-tier-architecture.md) | Two-Tier Architecture (Next.js Buyer + Flutter Seller + Supabase) | **Accepted** | 2026-09-11 | Principal Architect | Full System Topology |
| [ADR-002](file:///c:/LiveDrop/docs/adr/ADR-002-atomic-reservation-engine.md) | Atomic Reservation & Checkout RPC Engine | **Accepted** | 2026-09-11 | Database Architect | Concurrency & Data Integrity |
| [ADR-003](file:///c:/LiveDrop/docs/adr/ADR-003-unauthenticated-buyer-model-and-order-privacy.md) | Unauthenticated Buyer Model & Token-Scoped Order Privacy | **Accepted** | 2026-09-11 | Security Architect | Auth & RLS Security |
| [ADR-004](file:///c:/LiveDrop/docs/adr/ADR-004-whatsapp-deep-link-handshake-and-upi-model.md) | WhatsApp Deep-Link Handshake & UPI Direct Payment | **Accepted** | 2026-09-11 | Lead Architect | Business Workflow & Payments |
| [ADR-005](file:///c:/LiveDrop/docs/adr/ADR-005-client-side-image-compression-and-storage.md) | Client-Side Image Compression & CDN Storage Architecture | **Accepted** | 2026-09-11 | Mobile & Cloud Lead | Performance & Storage |
| [ADR-006](file:///c:/LiveDrop/docs/adr/ADR-006-seller-offline-upload-queue.md) | Seller Local SQLite Offline Ingestion Queue | **Accepted** | 2026-09-11 | Mobile Lead | Offline Resilience |
| [ADR-007](file:///c:/LiveDrop/docs/adr/ADR-007-client-side-pdf-shipping-label-engine.md) | Client-Side 4×6 Thermal PDF Shipping Label Engine | **Accepted** | 2026-09-11 | Mobile Lead | Logistics & Hardware |
| [ADR-008](file:///c:/LiveDrop/docs/adr/ADR-008-zero-cost-infrastructure-limits-and-mitigations.md) | Zero-Cost Infrastructure Limits & Keepalive Mitigations | **Accepted** | 2026-09-11 | DevOps Architect | Cloud Cost & Availability |
| [ADR-009](file:///c:/LiveDrop/docs/adr/ADR-009-currency-standardization-and-concurrency-hardening.md) | Currency Integer Paisa Standardization, Secure Token RPC & Concurrency Hardening | **Accepted** | 2026-09-11 | Principal Architect | Schema, Security & Concurrency |

---

## 4. ADR Modification Process
1. Never alter an accepted ADR's historical text.
2. If an architectural decision changes, author a new ADR (e.g., `ADR-009`) referencing the superseded ADR.
3. Update this index and cross-references in [SOURCE-OF-TRUTH.md](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md).
