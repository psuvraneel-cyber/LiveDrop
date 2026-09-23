# LiveDrop — Source of Truth & Documentation Hierarchy

**Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative  
**Governing Role:** Principal Product Architect & Senior Staff Software Engineer  

---

## 1. Document Authority & Precedence

To maintain strict internal consistency across the engineering lifecycle, all project documentation follows an explicit hierarchy of authority. When conflicts or ambiguities arise between documents, higher-precedence documents strictly override lower-precedence documents unless an approved Architecture Decision Record (ADR) explicitly states otherwise.

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Architecture Decision Records (ADRs) & Decisions         │
│    (docs/adr/*.md, docs/37-open-decisions.md)               │
├─────────────────────────────────────────────────────────────┤
│ 2. Product Brief (docs/01-product-brief.md)                 │
│    Core vision, target users, problem & value proposition   │
├─────────────────────────────────────────────────────────────┤
│ 3. PRD & Functional Specs (docs/02-prd.md, docs/07-*.md)    │
│    Authoritative product requirements & capabilities        │
├─────────────────────────────────────────────────────────────┤
│ 4. UI/UX Specification (docs/03-ui-ux-specification.md)     │
│    User interactions, screen flows & design system          │
├─────────────────────────────────────────────────────────────┤
│ 5. Technical Design & Contracts (docs/04-*, docs/12-*, etc.)│
│    Implementation architecture, schema, APIs, security     │
├─────────────────────────────────────────────────────────────┤
│ 6. Implementation Plan & Conventions (docs/32-*, 35-*, 36-*)│
│    Execution roadmaps, coding conventions, agent rules      │
└─────────────────────────────────────────────────────────────┘
```

### Precedence Matrix

| Priority | Document Type | Scope of Authority | Conflict Behavior |
|---|---|---|---|
| **1** | **ADRs & Approved Decisions** (`docs/adr/`, `docs/37-open-decisions.md`) | Overrides all prior architectural, security, or product assumptions. | Supersedes all other technical or design documents upon acceptance. |
| **2** | **Product Brief** (`docs/01-product-brief.md`) | Defines product vision, user personas, core pain points, and zero-cost strategy. | If a technical or UX feature violates the core value proposition, the Product Brief prevails. |
| **3** | **PRD & Functional Spec** (`docs/02-prd.md`, `docs/07-functional-specification.md`) | Defines functional requirements (FR), business capabilities, and success criteria. | Governs what the system must do. Overrules technical shortcuts. |
| **4** | **UI/UX Specification** (`docs/03-ui-ux-specification.md`) | Defines design tokens, screen layouts, mobile ergonomics, and user interactions. | Governs visual layout, client validation feedback, and touch behaviors. |
| **5** | **Technical Design & Contracts** (`docs/04-technical-design.md`, `docs/12-database-design.md`, `docs/13-api-contract.md`, etc.) | Defines engineering architecture, PostgreSQL DDL, RPCs, RLS, and security. | Governs implementation structure, database transactions, and network contracts. |
| **6** | **Operational & Execution Specs** (`docs/32-implementation-plan.md`, `docs/35-engineering-conventions.md`, `AGENTS.md`) | Defines development phases, definition of done, conventions, and AI instructions. | Governs the software development process and engineering quality gates. |

---

## 2. Topic-to-Document Governance Mapping

When developing or reviewing specific subsystems, refer to the authoritative document designated below:

| Functional / Technical Domain | Governing Master Document | Secondary Reference |
|---|---|---|
| **Project Status & Release Gates** | [`docs/00-project-status.md`](file:///c:/LiveDrop/docs/00-project-status.md) | [`docs/34-definition-of-done.md`](file:///c:/LiveDrop/docs/34-definition-of-done.md) |
| **Product Vision & Personas** | [`docs/01-product-brief.md`](file:///c:/LiveDrop/docs/01-product-brief.md) | [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md) |
| **Product Requirements & Scope** | [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md) | [`docs/33-mvp-scope-and-priorities.md`](file:///c:/LiveDrop/docs/33-mvp-scope-and-priorities.md) |
| **UI Design, Layout & Design System** | [`docs/03-ui-ux-specification.md`](file:///c:/LiveDrop/docs/03-ui-ux-specification.md) | [`docs/23-accessibility-and-ux-quality.md`](file:///c:/LiveDrop/docs/23-accessibility-and-ux-quality.md) |
| **System Architecture Overview** | [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md) | [`docs/10-domain-model.md`](file:///c:/LiveDrop/docs/10-domain-model.md) |
| **Requirements Traceability** | [`docs/06-requirements-traceability-matrix.md`](file:///c:/LiveDrop/docs/06-requirements-traceability-matrix.md) | [`docs/05-requirements-audit.md`](file:///c:/LiveDrop/docs/05-requirements-audit.md) |
| **State Transitions & Lifecycles** | [`docs/09-system-state-machines.md`](file:///c:/LiveDrop/docs/09-system-state-machines.md) | [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md) |
| **Database Schema, DDL & Indexes** | [`docs/12-database-design.md`](file:///c:/LiveDrop/docs/12-database-design.md) | [`docs/11-data-dictionary.md`](file:///c:/LiveDrop/docs/11-data-dictionary.md) |
| **API Endpoints & RPC Functions** | [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md) | [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md) |
| **Realtime WebSocket Channels** | [`docs/14-realtime-contract.md`](file:///c:/LiveDrop/docs/14-realtime-contract.md) | [`docs/09-system-state-machines.md`](file:///c:/LiveDrop/docs/09-system-state-machines.md) |
| **Stock Reservation & Concurrency** | [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md) | [`docs/adr/ADR-002-atomic-reservation-engine.md`](file:///c:/LiveDrop/docs/adr/ADR-002-atomic-reservation-engine.md) |
| **Security, Auth & RLS** | [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md) | [`docs/17-threat-model.md`](file:///c:/LiveDrop/docs/17-threat-model.md) |
| **Customer Privacy & PII Storage** | [`docs/18-privacy-and-data-handling.md`](file:///c:/LiveDrop/docs/18-privacy-and-data-handling.md) | [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md) |
| **Validation Rules & Formats** | [`docs/19-validation-and-business-rules.md`](file:///c:/LiveDrop/docs/19-validation-and-business-rules.md) | [`docs/07-functional-specification.md`](file:///c:/LiveDrop/docs/07-functional-specification.md) |
| **Offline Sync & Image Queue** | [`docs/21-offline-and-sync-strategy.md`](file:///c:/LiveDrop/docs/21-offline-and-sync-strategy.md) | [`docs/adr/ADR-006-seller-offline-upload-queue.md`](file:///c:/LiveDrop/docs/adr/ADR-006-seller-offline-upload-queue.md) |
| **Performance Budgets & Limits** | [`docs/22-performance-budget.md`](file:///c:/LiveDrop/docs/22-performance-budget.md) | [`docs/08-non-functional-requirements.md`](file:///c:/LiveDrop/docs/08-non-functional-requirements.md) |
| **Testing Strategy & Cases** | [`docs/25-testing-strategy.md`](file:///c:/LiveDrop/docs/25-testing-strategy.md) | [`docs/26-test-case-catalog.md`](file:///c:/LiveDrop/docs/26-test-case-catalog.md) |
| **End-to-End Scenarios** | [`docs/27-e2e-test-scenarios.md`](file:///c:/LiveDrop/docs/27-e2e-test-scenarios.md) | [`docs/26-test-case-catalog.md`](file:///c:/LiveDrop/docs/26-test-case-catalog.md) |
| **Deployment & Cloud Infrastructure** | [`docs/28-deployment-architecture.md`](file:///c:/LiveDrop/docs/28-deployment-architecture.md) | [`docs/29-environment-and-secrets.md`](file:///c:/LiveDrop/docs/29-environment-and-secrets.md) |
| **Implementation Plan** | [`docs/32-implementation-plan.md`](file:///c:/LiveDrop/docs/32-implementation-plan.md) | [`docs/34-definition-of-done.md`](file:///c:/LiveDrop/docs/34-definition-of-done.md) |
| **Engineering Rules & Conventions** | [`docs/35-engineering-conventions.md`](file:///c:/LiveDrop/docs/35-engineering-conventions.md) | [`docs/36-ai-agent-development-rules.md`](file:///c:/LiveDrop/docs/36-ai-agent-development-rules.md) |
| **AI Coding Agent Guardrails** | [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md) | [`docs/36-ai-agent-development-rules.md`](file:///c:/LiveDrop/docs/36-ai-agent-development-rules.md) |
| **Phase 0 Audit & Architecture Reconciliation** | [`docs/PHASE-0-ARCHITECTURE-RECONCILIATION.md`](file:///c:/LiveDrop/docs/PHASE-0-ARCHITECTURE-RECONCILIATION.md) | [`docs/PHASE-0-IMPLEMENTATION-TRUTH-MATRIX.md`](file:///c:/LiveDrop/docs/PHASE-0-IMPLEMENTATION-TRUTH-MATRIX.md) |
| **Phase 1 Critical Blocker Remediation** | [`docs/PHASE-1-BLOCKER-REMEDIATION-REPORT.md`](file:///c:/LiveDrop/docs/PHASE-1-BLOCKER-REMEDIATION-REPORT.md) | [`docs/PHASE-1-VALIDATION-REPORT.md`](file:///c:/LiveDrop/docs/PHASE-1-VALIDATION-REPORT.md) |
| **Phase 1 Security & Fulfillment Controls** | [`docs/PHASE-1-SECURITY-REMEDIATION.md`](file:///c:/LiveDrop/docs/PHASE-1-SECURITY-REMEDIATION.md) | [`docs/PHASE-1-FULFILLMENT-STATE-MACHINE.md`](file:///c:/LiveDrop/docs/PHASE-1-FULFILLMENT-STATE-MACHINE.md) |
| **Phase 1 Payment & Mobile Resilience** | [`docs/PHASE-1-PAYMENT-RECOVERY.md`](file:///c:/LiveDrop/docs/PHASE-1-PAYMENT-RECOVERY.md) | [`docs/PHASE-1-OFFLINE-RELIABILITY.md`](file:///c:/LiveDrop/docs/PHASE-1-OFFLINE-RELIABILITY.md) |

---

## 3. Protocol for Documentation Updates

1. **No Silent Changes:** No developer or AI agent may alter architecture, database schema, security policies, or API signatures without updating the corresponding specification document and linking to an approved ADR.
2. **Atomic Updates:** If a database column is added or modified, the developer must update:
   - `docs/12-database-design.md`
   - `docs/11-data-dictionary.md`
   - `docs/13-api-contract.md` (if exposed)
   - `docs/06-requirements-traceability-matrix.md`
3. **Traceability Preservation:** Every requirement ID (e.g., `REQ-FR-B1`) must maintain continuous bidirectional mapping through the traceability matrix to its implementation tasks and test cases.
4. **ADR Requirement:** Any deviation from approved architecture requires a new ADR in `docs/adr/` submitted for architectural review before code changes begin.
