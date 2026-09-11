# ADR-001: Two-Tier Architecture (Next.js Webfront + Flutter Seller + Supabase BaaS)

## Status
**Accepted**

## Context
LiveDrop serves two distinct user classes with vastly different environments and requirements:
1. **Buyers**: Watch Instagram/Facebook live streams on mobile phones. They demand zero-install friction, instant web load times (< 2 seconds over mobile 4G), and zero login barrier to claim high-demand single-piece fashion items before others.
2. **Sellers**: Boutique merchants running active live streams who need high-speed batch camera photography (50 items in < 5 minutes), local hardware thermal printer connectivity, push notifications, and offline resilience during unreliable warehouse Wi-Fi.

Building a monolithic full-stack custom backend requires maintaining servers, deployment pipelines, Redis caches, and database connection poolers, violating the lean bootstrap cost constraint.

## Decision
Adopt a modern **Two-Tier BaaS Architecture**:
* **Buyer Tier**: Mobile-first Responsive Web Application built with **Next.js 14+ (App Router, TypeScript)** hosted statically on Cloudflare Pages / Vercel. Connects directly to Supabase via `@supabase/supabase-js` using the public anonymous key.
* **Seller Tier**: Native Android Application built with **Flutter (Dart 3, Riverpod)**. Interacts with device camera, background threads, and system print drivers. Connects directly to Supabase using authenticated seller sessions.
* **Backend Tier**: **Supabase (Managed PostgreSQL 15+, Realtime WebSockets, Storage, and Auth)**. All complex transactional logic is encapsulated in PostgreSQL Stored Procedures (RPCs).

```
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│        Buyer Webfront           │       │       Seller Native App         │
│  (Next.js / Cloudflare Pages)   │       │      (Flutter / Android)        │
└────────────────┬────────────────┘       └────────────────┬────────────────┘
                 │ Anon Key                                │ Auth JWT (Bearer)
                 ▼                                         ▼
┌───────────────────────────────────────────────────────────────────────────┐
│                           Supabase BaaS                                   │
│  ┌───────────────────────┐  ┌──────────────────────┐  ┌────────────────┐  │
│  │ PostgreSQL 15 + RLS   │  │ Realtime WebSockets  │  │ Object Storage │  │
│  │ (Tables & Atomic RPC) │  │ (Product Status Bus) │  │ (Images & CDN) │  │
│  └───────────────────────┘  └──────────────────────┘  └────────────────┘  │
└───────────────────────────────────────────────────────────────────────────┘
```

## Alternatives Considered
1. **Custom Node.js / Express Microservices**: High operational overhead, deployment costs, and infrastructure maintenance. Rejected for MVP.
2. **Flutter Web for Buyers**: Heavy initial bundle download (> 2-3 MB canvaskit/wasm), slow first contentful paint (> 4-6s on 3G/4G), poor mobile browser URL sharing. Rejected.
3. **PWA for Sellers**: Unable to reliably access system printer spoolers, camera frame buffers, and background thread image compression. Rejected.

## Consequences
* **Positive**: Fast time-to-market; near-zero operating costs on starter tier; extreme performance for buyers; native hardware integration for sellers.
* **Negative**: Business logic is split between TypeScript/Dart client repositories and PostgreSQL PL/pgSQL functions. Requires strict RPC contract discipline.

## Security Implications
All tables must enforce Row-Level Security (RLS). Public clients cannot perform unrestricted `INSERT` or `UPDATE` on core tables without going through hardened `SECURITY DEFINER` RPC functions.

## Operational Implications
PostgreSQL functions must be managed through version-controlled database migrations (e.g., Supabase CLI) and covered by automated regression tests.
