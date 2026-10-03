# LiveDrop

**Fast, zero-friction live commerce for boutique sellers in India.**

[![Buyer Web CI](https://github.com/psuvraneel-cyber/LiveDrop/actions/workflows/buyer-web-ci.yml/badge.svg)](https://github.com/psuvraneel-cyber/LiveDrop/actions/workflows/buyer-web-ci.yml)
[![Seller App CI](https://github.com/psuvraneel-cyber/LiveDrop/actions/workflows/seller-app-ci.yml/badge.svg)](https://github.com/psuvraneel-cyber/LiveDrop/actions/workflows/seller-app-ci.yml)

---

## The Problem

Thousands of Indian micro-boutique sellers run their entire businesses through Facebook Live and WhatsApp. A typical session looks like this:

1. **Seller goes live** on Facebook, showing 30–60 unique, single-piece garments in 90 minutes.
2. **Buyers comment** "MINE 04" or "BOOKED" in a flood of messages.
3. **Seller drowns** in 50+ simultaneous WhatsApp chats, trying to figure out who claimed what first.
4. **Disputes erupt** when two buyers both believe they booked the same one-of-a-kind saree.
5. **After the stream**, the seller spends 3–5 hours manually collecting addresses, matching blurry UPI payment screenshots, and handwriting courier labels.

The result: lost sales, angry customers, wrong shipments, and exhausted sellers.

## What LiveDrop Does

LiveDrop replaces this entire chaotic workflow with a real-time digital system:

| Pain Point | LiveDrop Solution |
|---|---|
| "Who commented first?" disputes | **Atomic database-level reservations** — first tap wins, zero collisions |
| Blurry screenshots to identify items | **Flash codes** (`#A01`, `#B12`) on every product card |
| 50+ WhatsApp messages to collect addresses | **Zero-login checkout form** with auto-saved buyer details |
| Manually matching UPI payments | **Structured UPI QR + UTR verification** pipeline |
| 3+ hours handwriting courier labels | **1-tap 4×6" thermal shipping label PDF** generation |
| Needing buyers to install an app | **Zero-download mobile web** — works in any browser |

### The Two-Sided System

**Buyers** get a fast, zero-friction mobile web experience. No app download, no account creation, no passwords. They open a link, see the live catalog with real-time availability, add items to a cart, enter shipping details, and check out via WhatsApp — all in under 45 seconds.

**Sellers** get a native Android app purpose-built for speed. They photograph a garment, assign a flash code, set a price, and publish it in under 30 seconds. After the live stream, a Kanban-style order pipeline lets them verify payments, confirm orders, and print thermal shipping labels with one tap.

---

## Architecture

LiveDrop runs on an ultra-lean **two-tier BaaS architecture** designed to operate at **₹0 monthly cost** within cloud free tiers:

```
┌──────────────────────────────────────┐       ┌──────────────────────────────────────┐
│         Buyer Web Catalog            │       │       Seller Operations App          │
│   Next.js 16 · React 19 · Tailwind  │       │     Flutter 3.41 · Dart 3.11         │
│                                      │       │                                      │
│  • Zero-download mobile web          │       │  • Camera-first product ingestion     │
│  • Real-time stock availability      │       │  • Offline SQLite upload queue        │
│  • UPI QR + WhatsApp checkout        │       │  • Kanban order management pipeline   │
│  • < 1.5s First Contentful Paint     │       │  • 1-tap thermal label printing       │
└──────────────────┬───────────────────┘       └──────────────────┬───────────────────┘
                   │ Anon Key (RLS-protected)                     │ Authenticated JWT
                   ▼                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                     Supabase Cloud (BaaS · AWS ap-south-1 Mumbai)                   │
│                                                                                     │
│  PostgreSQL 17 + Row-Level Security    Realtime WebSockets    Object Storage (CDN)  │
│  • Atomic checkout RPCs               • Instant sold badges   • WebP product images │
│  • Deadlock-free row locking           • Reconnect recovery   • < 250 KB per image  │
│  • Integer Paisa math (no floats)      • State sync           • Cloudflare edge     │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                  ▲
                                  │ Cron (GitHub Actions)
                            ┌─────┴──────┐
                            │   Reaper   │  Releases expired 15-min holds
                            │  Keepalive │  Prevents free-tier pause
                            └────────────┘
```

**No custom backend server.** All business logic runs as PostgreSQL RPCs inside Supabase, protected by Row-Level Security policies. The clients talk directly to the database through Supabase's REST and Realtime APIs.

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Buyer Frontend** | Next.js 16 (App Router), React 19, TypeScript, Tailwind CSS v4, Motion (Framer) |
| **Seller App** | Flutter 3.41, Dart 3.11, Material 3, Riverpod, flutter_animate |
| **Backend** | Supabase Cloud (PostgreSQL 17, Realtime, GoTrue Auth, Storage) |
| **Database** | 32 versioned SQL migrations, RLS on every table, 15 SECURITY DEFINER RPCs, check constraints |
| **CI/CD** | GitHub Actions (lint → typecheck → test → build), scheduled reaper cron |
| **Hosting** | Vercel at [livedrop.in](https://livedrop.in) (buyer web), Direct APK (seller app) |
| **Testing** | Vitest + Testing Library + PGlite (web), Playwright (E2E), Flutter Test (app) |

---

## Key Features

### Buyer Web (`/buyer-web`)
- **Live drop catalog** — real-time 2-column grid with flash codes, prices, and availability badges
- **Multi-item sticky cart** — bundle items across a 90-minute stream into a single order
- **Zero-login checkout** — name, WhatsApp number, pincode, address — auto-saved for repeat buyers
- **Atomic reservation** — database-level locking guarantees no double-sells on single-piece items
- **WhatsApp handoff** — order summary deep-linked directly into seller's WhatsApp chat
- **UPI payment screen** — QR code display with copy-able UPI ID and UTR input for verification
- **Haute-couture UI** — luxury dark theme with gold accents, serif typography, 3:4 portrait cards

### Seller App (`/seller-app`)
- **Rapid camera ingestion** — photograph, tag, price, and publish a product in < 30 seconds
- **Live drop management** — create/schedule drops, manage product inventory per drop
- **Kanban order pipeline** — visual board tracking orders from pending → confirmed → dispatched
- **Payment verification** — structured UTR-based UPI payment verification workflow
- **Thermal label printing** — generate 4×6" PDF shipping labels, print via Bluetooth to thermal printers
- **Offline-first queue** — SQLite upload queue for unreliable network conditions
- **Luxury Boutique Noir theme** — deep obsidian UI with metallic gold accents

### Backend (`/supabase`)
- **32 versioned migrations** — profiles, drops, products, orders, order items, payment attempts, indexes, triggers, RLS, RPCs, and hardening patches
- **Atomic RPCs** — `create_order_with_reservation`, `initiate_payment_attempt`, `submit_buyer_payment_claim`, `verify_manual_upi_payment`
- **Row-Level Security** — every table protected; anonymous buyers access only public projection views, sellers only access their own data
- **Integer currency** — all money stored as Paisa (₹1,500.00 = `150000`), enforced by database check constraints
- **Automated reaper** — GitHub Actions cron releases expired 15-minute checkout holds and 24-hour verification windows
- **Public projection views** — `public_drops`, `public_products_catalog`, `public_seller_storefronts` prevent direct table queries from anonymous users

---

## Repository Structure

```
LiveDrop/
├── buyer-web/                 # Buyer mobile web catalog (Next.js / TypeScript)
│   ├── src/app/               # App Router pages (home, shop, drop, cart, checkout, orders)
│   ├── src/components/        # UI components (header, dock, cards, checkout, filters)
│   ├── src/lib/               # Supabase client, repositories, cart storage, validators
│   └── e2e/                   # Playwright end-to-end tests
│                              # 460 Vitest tests across 44 suites
│
├── seller-app/                # Seller native Android app (Flutter / Dart)
│   ├── lib/core/              # Services (camera, PDF labels, offline queue, Supabase)
│   ├── lib/data/              # Repositories & realtime order subscriptions
│   ├── lib/domain/            # Immutable models & state machines
│   ├── lib/presentation/      # Screens, widgets, Riverpod controllers
│   └── test/                  # 49 Flutter unit and widget tests
│
├── supabase/                  # Database configuration
│   ├── migrations/            # 32 versioned SQL migrations
│   ├── functions/             # Edge Functions
│   ├── seed.sql               # Deterministic development seed data
│   └── config.toml            # Supabase CLI configuration
│
├── scripts/                   # SRE and developer automation
│   ├── run-reaper.mjs         # Cron hold reaper (releases expired reservations)
│   └── verify-schema.mjs     # PGlite migration verifier
│
├── docs/                      # 48+ engineering specification documents
│   ├── SOURCE-OF-TRUTH.md     # Governance hierarchy
│   ├── 01-product-brief.md    # Vision, personas, value proposition
│   ├── 12-database-design.md  # Full PostgreSQL DDL
│   ├── 13-api-contract.md     # API/RPC contracts
│   ├── 16-security-architecture.md  # RLS policies, threat model
│   └── ...
│
├── .github/workflows/         # CI pipelines + scheduled cron jobs
│   ├── buyer-web-ci.yml       # Lint, typecheck, test, build
│   ├── seller-app-ci.yml      # Analyze, test, APK build
│   ├── reaper-cron.yml        # Scheduled hold reaper
│   └── supabase-keepalive.yml # Free-tier pause prevention
└── AGENTS.md                  # AI agent operating rules & guardrails
```

---

## Getting Started

### Prerequisites

| Tool | Version |
|---|---|
| Node.js | ≥ 20.x |
| npm | ≥ 10.x |
| Flutter | ≥ 3.24.x (stable) |
| Dart | ≥ 3.5.x |
| Java JDK | ≥ 17 |
| Android SDK | API 34+ |
| Supabase CLI | ≥ 1.140.0 |

### Buyer Web

```bash
cd buyer-web
cp .env.example .env.local        # Add your Supabase URL and anon key
npm install
npm run dev                        # → http://localhost:3000
```

Available scripts:
- `npm run dev` — Start development server
- `npm run build` — Production build
- `npm run lint` — Run ESLint
- `npm run typecheck` — TypeScript type checking
- `npm test` — Run Vitest unit tests
- `npm run test:e2e` — Run Playwright E2E tests

### Seller App

```bash
cd seller-app
cp .env.example .env               # Add your Supabase credentials
flutter pub get
flutter run                         # Run on connected Android device/emulator
```

### Supabase (Database)

```bash
supabase start                      # Start local Supabase stack
supabase db reset                   # Apply all migrations + seed data
supabase migration list             # Verify migration status
```

### Environment Variables

The buyer web requires these environment variables (see [`buyer-web/.env.example`](buyer-web/.env.example)):

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project HTTPS endpoint |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Public anonymous API key (RLS-protected) |
| `NEXT_PUBLIC_APP_ENV` | Runtime environment (`development` / `production`) |
| `NEXT_PUBLIC_APP_BASE_URL` | Canonical URL for WhatsApp deep links |

> **⚠️ Security:** The Supabase service-role key must **never** appear in any client-facing environment variable (`NEXT_PUBLIC_*`) or Flutter asset bundle.

---

## How It Works — End to End

```
 Seller goes live on Facebook
        │
        ▼
 ┌─────────────────┐    Photographs garments     ┌──────────────────┐
 │  Seller App      │ ──────────────────────────→ │  Supabase DB     │
 │  (Flutter)       │    Assigns flash codes       │  (PostgreSQL)    │
 └─────────────────┘    Sets prices, publishes     └────────┬─────────┘
                                                            │
        Seller shares link in Facebook Live chat            │
        ──────────────────────────────────────→              │
                                                            │
 ┌─────────────────┐    Browses live catalog      ┌────────▼─────────┐
 │  Buyer's Phone   │ ◄────────────────────────── │  Buyer Web       │
 │  (any browser)   │    Sees real-time status     │  (Next.js)       │
 └────────┬────────┘                               └────────┬─────────┘
          │                                                  │
          │  Taps "Add to Bag" → Reviews Cart                │
          │  Enters shipping details                         │
          │  Taps "Confirm & Order via WhatsApp"             │
          │                                                  │
          │         ┌────────────────────────────┐            │
          │         │  Atomic Reservation RPC    │ ◄──────────┘
          │         │  (PostgreSQL transaction)  │
          │         │  • Locks items             │
          │         │  • Creates order record    │
          │         │  • Returns order code      │
          │         └────────────────────────────┘
          │
          ▼
 ┌─────────────────┐
 │  WhatsApp Chat   │  Buyer sends UPI payment screenshot
 │  (Seller ↔ Buyer)│  Seller verifies via Seller App
 └────────┬────────┘
          │
          ▼
 ┌─────────────────┐
 │  Seller App      │  Confirms payment → Prints shipping label → Dispatches
 └─────────────────┘
```

---

## Documentation

This project is backed by **40+ engineering specification documents** covering every aspect from database DDL to threat models. Key documents:

| Document | What it covers |
|---|---|
| [Product Brief](docs/01-product-brief.md) | Vision, personas, market context |
| [PRD](docs/02-prd.md) | Functional requirements and KPIs |
| [Database Design](docs/12-database-design.md) | PostgreSQL schema, constraints, indexes |
| [API Contract](docs/13-api-contract.md) | RPC signatures, request/response formats |
| [Security Architecture](docs/16-security-architecture.md) | RLS policies, auth model, privilege containment |
| [Concurrency Spec](docs/15-concurrency-and-reservation-spec.md) | Race condition resolution, row locking |
| [Implementation Plan](docs/32-implementation-plan.md) | 11-phase vertical slice delivery plan |
| [Testing Strategy](docs/25-testing-strategy.md) | 13-layer test pyramid |

See [`docs/SOURCE-OF-TRUTH.md`](docs/SOURCE-OF-TRUTH.md) for the full governance hierarchy and document index.

---

## Project Status

LiveDrop has completed its **full pre-implementation specification gate** — all architecture, database schemas, security models, and API contracts are documented and frozen.

**Current state:**
- ✅ **Buyer Web** — 460/460 tests passing (44 Vitest suites), deployed to [livedrop.in](https://livedrop.in)
- ✅ **Seller App** — 49/49 tests passing, clean `flutter analyze` (0 errors), verified on physical Android hardware
- ✅ **Database** — 32 migrations applied, all RLS policies and RPCs verified via PGlite
- ✅ **CI/CD** — GitHub Actions pipelines operational for both apps + scheduled reaper cron

---

## License

Proprietary. All rights reserved.
