# LiveDrop — Fast, Zero-Friction Live Commerce for Boutique Sellers

[![System Status](https://img.shields.io/badge/Status-Specification%20Complete-success)](file:///c:/LiveDrop/docs/00-project-status.md)
[![Architecture](https://img.shields.io/badge/Architecture-Two--Tier%20BaaS-blue)](file:///c:/LiveDrop/docs/adr/ADR-001-two-tier-architecture.md)
[![Database](https://img.shields.io/badge/Database-PostgreSQL%2015%20%2B%20RLS-orange)](file:///c:/LiveDrop/docs/12-database-design.md)
[![License](https://img.shields.io/badge/License-Proprietary-red)]()

LiveDrop is a real-time live-commerce operating system purpose-built for Indian micro-boutiques selling unique, single-piece fashion and sarees via Instagram Live and Facebook Live. It replaces chaotic comment-based bidding ("MINE 04") with high-speed digital reservations, automated WhatsApp order routing, direct peer-to-peer UPI payments, and 1-tap 4×6 inch thermal shipping labels.

---

## 1. System Architecture Overview

LiveDrop follows an ultra-lean **Two-Tier BaaS Architecture** designed to operate at **₹0 baseline monthly software cost**:

```
┌──────────────────────────────────────┐       ┌──────────────────────────────────────┐
│           Buyer Webfront             │       │          Seller Native App           │
│  (Next.js 14 / TypeScript / PWA)     │       │       (Flutter 3 / Dart / Android)   │
│  • Instant 4G load (< 1.5s FCP)      │       │  • Batch camera ingestion (3s/item)  │
│  • Zero-login checkout (< 30s)       │       │  • Offline SQLite upload queue       │
│  • Realtime product status stream    │       │  • Realtime live sales dashboard     │
│  • UPI QR code & WhatsApp handshake  │       │  • 1-tap 4x6" thermal PDF printing   │
└──────────────────┬───────────────────┘       └──────────────────┬───────────────────┘
                   │ Public Anon Key                              │ Authenticated JWT
                   ▼                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           Supabase BaaS (Managed Cloud)                             │
│  ┌─────────────────────────┐ ┌───────────────────────────┐ ┌─────────────────────┐  │
│  │ PostgreSQL 15 + RLS     │ │ Realtime WebSockets       │ │ Object Storage      │  │
│  │ • Atomic Checkout RPC   │ │ • Instant 'sold' badges   │ │ • Products bucket   │  │
│  │ • Deadlock-free locks   │ │ • Monotonic state sync    │ │ • WebP < 200 KB     │  │
│  │ • Paisa-accurate math   │ │ • Reconnect recovery      │ │ • Cloudflare CDN    │  │
│  └─────────────────────────┘ └───────────────────────────┘ └─────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

---

---

## 2. Repository Layout

```
LiveDrop/
├── AGENTS.md                  # Mandatory AI Agent Operating Rules & Guardrails
├── README.md                  # Project overview and setup guide
├── .gitignore                 # Root Git ignore rules (secrets & build outputs)
├── .editorconfig              # Uniform indentation and formatting standards
│
├── docs/                      # Authoritative pre-implementation engineering specifications
│   ├── SOURCE-OF-TRUTH.md     # Governance hierarchy
│   ├── FINAL-IMPLEMENTATION-GATE.md # Pre-implementation gate sign-off
│   └── ...                    # 40+ engineering specifications & ADRs
│
├── buyer-web/                 # Buyer mobile web catalog (Next.js 15 App Router / TypeScript)
│   ├── src/app/               # App Router pages and layouts
│   ├── src/components/        # Reusable presentation components
│   ├── src/lib/               # Supabase client, repositories, and utilities
│   └── ...
│
├── seller-app/                # Seller native Android app (Flutter 3.41+ / Dart 3.11+)
│   ├── lib/core/              # Themes, formatting, error handling
│   ├── lib/data/              # Local SQLite queue & remote Supabase datasources
│   ├── lib/domain/            # Entities and repository interfaces
│   ├── lib/presentation/      # Screens, widgets, and Riverpod controllers
│   └── ...
│
├── supabase/                  # Supabase database configuration & migrations
│   ├── migrations/            # Versioned SQL migrations (Phase 1+)
│   ├── functions/             # Supabase Edge Functions (if needed)
│   ├── seed/                  # Database seed scripts
│   └── config.toml            # Local Supabase CLI configuration
│
├── scripts/                   # Developer and operational automation scripts
└── .github/                   # GitHub Actions CI/CD workflows
    └── workflows/
```

---

## 3. Development Prerequisites & Toolchains

| Tool | Required Version | Purpose |
|---|---|---|
| **Node.js** | `>= 20.x` (Detected: `v24.18.0`) | Buyer Webfront runtime & build tooling |
| **npm** | `>= 10.x` (Detected: `11.16.0`) | JavaScript package manager |
| **Flutter** | `>= 3.24.x` (Detected: `3.41.6 stable`) | Seller Android app framework (`C:\flutter\bin`) |
| **Dart** | `>= 3.5.x` (Detected: `3.11.4`) | Seller app programming language |
| **Java JDK** | `>= 17` (Detected: `17.0.18 LTS`) | Android Gradle build engine |
| **Android SDK** | `API 34/35` (Detected: `35.0.0`) | Target Android platform compilation |
| **Supabase CLI**| `>= 1.140.0` (Detected: `2.117.0`) | Local migration validation & type generation |

---

## 4. Current Status: Phase 0 (Workspace & Repository Foundation)

The LiveDrop project has cleared its **[Final Pre-Implementation Gate](file:///c:/LiveDrop/docs/FINAL-IMPLEMENTATION-GATE.md)** and is currently at **Phase 0** of the **[Implementation Plan](file:///c:/LiveDrop/docs/32-implementation-plan.md)**:
* Toolchains, directory topology, linting, testing, and CI pipelines are established.
* Product features (catalog, cart, camera ingestion, PDF label generation) remain un-implemented until their respective vertical slices in Phases 1 through 10.

---

## 5. Authoritative Documentation Index

All engineering specifications, architectural decisions, and operational guidelines are strictly cataloged in the `docs/` directory:

| Document | Description |
|---|---|
| [**SOURCE-OF-TRUTH.md**](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md) | Master governance hierarchy, domain-to-document mapping, and precedence rules. |
| [**FINAL-IMPLEMENTATION-GATE.md**](file:///c:/LiveDrop/docs/FINAL-IMPLEMENTATION-GATE.md) | Official pre-implementation audit sign-off, contradiction resolutions, and clearance. |
| [**00-project-status.md**](file:///c:/LiveDrop/docs/00-project-status.md) | Current engineering status gate, audit summary, and implementation readiness. |
| [**01-product-brief.md**](file:///c:/LiveDrop/docs/01-product-brief.md) | Product vision, target seller personas, buyer problems, and unit economics. |
| [**02-prd.md**](file:///c:/LiveDrop/docs/02-prd.md) | Product requirements, user stories, and measurable business KPIs. |
| [**03-ui-ux-specification.md**](file:///c:/LiveDrop/docs/03-ui-ux-specification.md) | High-contrast design tokens, typography, 48×48px touch targets, and wireframes. |
| [**04-technical-design.md**](file:///c:/LiveDrop/docs/04-technical-design.md) | Technical architecture blueprint and legacy draft design reconciliation matrix. |
| [**05-requirements-audit.md**](file:///c:/LiveDrop/docs/05-requirements-audit.md) | Adversarial audit identifying 16 findings across security, concurrency, and data integrity. |
| [**06-requirements-traceability-matrix.md**](file:///c:/LiveDrop/docs/06-requirements-traceability-matrix.md) | Closed-loop traceability mapping PRD ➔ UX ➔ Database ➔ API ➔ Tests ➔ Tasks. |
| [**07-functional-specification.md**](file:///c:/LiveDrop/docs/07-functional-specification.md) | Detailed functional behavior, validation bounds, and edge cases. |
| [**08-non-functional-requirements.md**](file:///c:/LiveDrop/docs/08-non-functional-requirements.md) | Latency budgets (FCP < 1.5s, LCP < 2.5s), availability, and compliance rules. |
| [**09-system-state-machines.md**](file:///c:/LiveDrop/docs/09-system-state-machines.md) | State machine diagrams and transition matrices for Drops, Products, and Orders. |
| [**10-domain-model.md**](file:///c:/LiveDrop/docs/10-domain-model.md) | Ubiquitous language, bounded contexts, aggregates, entities, and domain events. |
| [**11-data-dictionary.md**](file:///c:/LiveDrop/docs/11-data-dictionary.md) | Detailed schema dictionary for all database entities and attributes. |
| [**12-database-design.md**](file:///c:/LiveDrop/docs/12-database-design.md) | Production PostgreSQL DDL, foreign keys, check constraints, and indexes. |
| [**13-api-contract.md**](file:///c:/LiveDrop/docs/13-api-contract.md) | OpenAPI/RPC contracts for buyer checkout, seller pipeline, and catalog endpoints. |
| [**14-realtime-contract.md**](file:///c:/LiveDrop/docs/14-realtime-contract.md) | WebSocket channel topologies, payload schemas, and client reconciliation rules. |
| [**15-concurrency-and-reservation-spec.md**](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md) | Concurrency proofs, row-locking model, and 24 live-drop race condition resolutions. |
| [**16-security-architecture.md**](file:///c:/LiveDrop/docs/16-security-architecture.md) | Row-Level Security (RLS) policies, token gating, and privilege containment. |
| [**17-threat-model.md**](file:///c:/LiveDrop/docs/17-threat-model.md) | STRIDE threat model and mitigations for price tampering, scraping, and DoS. |
| [**18-privacy-and-data-handling.md**](file:///c:/LiveDrop/docs/18-privacy-and-data-handling.md) | India DPDP Act compliance, PII retention (180 days), and redaction guidelines. |
| [**19-validation-and-business-rules.md**](file:///c:/LiveDrop/docs/19-validation-and-business-rules.md) | Three-tier validation rules across Client UI, Server RPC, and Database. |
| [**20-error-and-failure-handling.md**](file:///c:/LiveDrop/docs/20-error-and-failure-handling.md) | Recovery playbooks for 24 distinct network, database, and hardware errors. |
| [**21-offline-and-sync-strategy.md**](file:///c:/LiveDrop/docs/21-offline-and-sync-strategy.md) | Pragmatic local SQLite upload queue vs deferred complex two-way offline sync. |
| [**22-performance-budget.md**](file:///c:/LiveDrop/docs/22-performance-budget.md) | Performance metrics, measurement tooling, and pass/fail thresholds. |
| [**23-accessibility-and-ux-quality.md**](file:///c:/LiveDrop/docs/23-accessibility-and-ux-quality.md) | WCAG 2.1 AA checklist, high-contrast palette, and screen-reader semantics. |
| [**24-observability-and-logging.md**](file:///c:/LiveDrop/docs/24-observability-and-logging.md) | Privacy-safe telemetry, operational health probes, and structured error logs. |
| [**25-testing-strategy.md**](file:///c:/LiveDrop/docs/25-testing-strategy.md) | 13-layer testing pyramid spanning unit, concurrency, stress, and physical devices. |
| [**26-test-case-catalog.md**](file:///c:/LiveDrop/docs/26-test-case-catalog.md) | 38 concrete, step-by-step test cases across Buyer, Seller, Security, and Edge cases. |
| [**27-e2e-test-scenarios.md**](file:///c:/LiveDrop/docs/27-e2e-test-scenarios.md) | Real-world narrative test scenarios (Scenarios A through I). |
| [**28-deployment-architecture.md**](file:///c:/LiveDrop/docs/28-deployment-architecture.md) | Hosting topology, CI/CD pipelines, Android APK release, and free-tier governance. |
| [**29-environment-and-secrets.md**](file:///c:/LiveDrop/docs/29-environment-and-secrets.md) | Secrets classification, `.env` rules, and rotation procedures. |
| [**30-backup-and-recovery.md**](file:///c:/LiveDrop/docs/30-backup-and-recovery.md) | PostgreSQL logical backup scripts, PITR rules, and disaster recovery. |
| [**31-release-and-versioning.md**](file:///c:/LiveDrop/docs/31-release-and-versioning.md) | Semantic versioning guidelines, release checklist, and smoke tests. |
| [**32-implementation-plan.md**](file:///c:/LiveDrop/docs/32-implementation-plan.md) | 11 vertical slices (Phases 0–10) detailing task dependencies and acceptance criteria. |
| [**33-mvp-scope-and-priorities.md**](file:///c:/LiveDrop/docs/33-mvp-scope-and-priorities.md) | Strict MoSCoW scoping separating MVP essentials from post-MVP features. |
| [**34-definition-of-done.md**](file:///c:/LiveDrop/docs/34-definition-of-done.md) | Strict 14-point engineering completion gate checklist. |
| [**35-engineering-conventions.md**](file:///c:/LiveDrop/docs/35-engineering-conventions.md) | Code style, folder structures, TypeScript/Dart rules, and commit formats. |
| [**36-ai-agent-development-rules.md**](file:///c:/LiveDrop/docs/36-ai-agent-development-rules.md) | Mandatory execution protocol and prohibitions for AI coding agents. |
| [**37-open-decisions.md**](file:///c:/LiveDrop/docs/37-open-decisions.md) | Register of product recommendations and human sign-off items. |
| [**38-risk-register.md**](file:///c:/LiveDrop/docs/38-risk-register.md) | Comprehensive log of product, concurrency, and operational risks and mitigations. |
| [**39-architecture-decision-records.md**](file:///c:/LiveDrop/docs/39-architecture-decision-records.md) | Master index of the authoritative Architecture Decision Records (ADRs). |

---

## 6. Protocol for AI Coding Agents
Any autonomous or semi-autonomous AI agent (Antigravity, Claude Code, Cursor, Gemini CLI) operating in this workspace is strictly bound by [**AGENTS.md**](file:///c:/LiveDrop/AGENTS.md).
Agents must follow the **READ ➔ PLAN ➔ CHANGE ➔ TEST ➔ REVIEW ➔ DOCUMENT** execution cycle. Never bypass security policies or invent unapproved product logic.

