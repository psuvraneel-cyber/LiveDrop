# 28 — Deployment Architecture & Infrastructure Strategy: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. System Topology & Environments

LiveDrop operates across three isolated environments:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            ENVIRONMENT SEPARATION                          │
├────────────────────┬─────────────────────────────┬──────────────────────────┤
│ Environment        │ Frontend (Web & Mobile)     │ Backend (Database & API) │
├────────────────────┼─────────────────────────────┼──────────────────────────┤
│ **Local Dev**      │ Next.js `localhost:3000`    │ Local Supabase Docker CLI│
│                    │ Flutter Android Emulator    │ `127.0.0.1:54322`        │
├────────────────────┼─────────────────────────────┼──────────────────────────┤
│ **Staging**        │ Cloudflare Pages Preview    │ Supabase Cloud Project   │
│                    │ Flutter Debug APK           │ `livedrop-staging`       │
├────────────────────┼─────────────────────────────┼──────────────────────────┤
│ **Production**     │ Cloudflare Pages Production │ Supabase Cloud Project   │
│                    │ Flutter Release APK         │ `livedrop-prod`          │
└────────────────────┴─────────────────────────────┴──────────────────────────┘
```

---

## 2. Component Deployment Specifications

### 2.1 Buyer Webfront (Next.js App Router)
* **Hosting Platform:** Cloudflare Pages (or Vercel Edge).
* **Build Engine:** `@cloudflare/next-on-pages` or native Next.js edge runtime.
* **CI/CD Pipeline:** GitHub integration triggers automated deployment upon push to `main` branch.
* **Domain & HTTPS:** Subdomain `drop.store` or `livedrop.pages.dev` with automated free SSL/TLS encryption via Cloudflare Universal SSL.

### 2.2 Backend & Data Layer (Supabase Cloud)
* **Components:** PostgreSQL 15+ engine, PostgREST API, Realtime WebSocket engine, GoTrue Auth, and S3-compatible Object Storage.
* **Database Migrations:** Managed via Supabase CLI (`supabase migration up`). All schema changes are versioned SQL scripts.
* **Storage Buckets:**
  * `product-images`: Public read, authenticated write (via seller app).
  * `seller-assets`: Public read (UPI QR code images, boutique logos).

### 2.3 Seller Mobile App Distribution (Flutter Android)
* **Distribution Strategy:** Direct standalone release APK sideloading via Google Drive / USB, bypassing the $25 Google Play developer account registration fee during MVP validation.
* **Build Command:**
  ```bash
  flutter build apk --release --split-per-abi --obfuscate --split-debug-info=./debug_symbols
  ```
* **Release Artifact:** `app-arm64-v8a-release.apk` (< 22 MB).

---

## 3. Free-Tier Cost Audit & Operational Risk Analysis

> [!WARNING]
> The initial claim of a "guaranteed ₹0 forever architecture" is an **operational assumption**, not a contractual SLA. Cloud providers can alter free tier allocations, enforce inactivity pauses, or bill for overages.

### Free Tier Limits vs Operational Reality

| Cloud Service | Stated Free Tier Allowance | Operational Consumption Risk | Risk Severity | Mandatory Mitigation Strategy |
|---|---|---|---|---|
| **Supabase Database** | 500 MB relational storage | Negligible in early stage (~50 MB for 100 drops × 30 items) | **LOW** | Archive closed drops older than 6 months if storage exceeds 350 MB. |
| **Supabase Inactivity** | **Auto-pauses after 7 days of inactivity** | If a boutique skips broadcasting for 8 days, database goes offline! | **HIGH** | Schedule automated daily keepalive health probe via GitHub Actions cron. |
| **Supabase Realtime** | **200 concurrent connections** | A viral stream with 250 viewers exhausts connection slots. | **HIGH** | Auto-sleep background tabs; fallback to 10s REST polling if WebSocket rejects. |
| **Supabase Storage Egress**| **2 GB monthly egress bandwidth** | 100 viewers × 40 thumbs × 15 drops = 2.4 GB egress (Exceeds quota!). | **HIGH** | Enforce 1-year immutable caching and route storage requests through Cloudflare CDN cache proxy. |
| **Cloudflare Pages** | Unlimited requests, 100 GB bandwidth | 100% safe for MVP scale | **LOW** | Standard edge caching rules applied. |
| **Direct UPI** | 0% transaction fees (NPCI) | Standard P2P/P2M transfer limits (~₹1,00,000/day) | **LOW** | Sufficient for boutique daily sales volumes. |

---

## 4. Rollback & Disaster Recovery Procedures

1. **Frontend Web Rollback:** Cloudflare Pages maintains instant instant-rollback capability. Reverting to any prior deployment hash executes in `< 5 seconds`.
2. **Database Schema Rollback:** Every migration in `supabase/migrations/` has an associated down-migration script (`001_create_profiles.down.sql`).
3. **Database Data Restore:** Point-in-time recovery (PITR) or daily logical SQL dumps (`pg_dump`) allow restoring database state in `< 10 minutes`.
