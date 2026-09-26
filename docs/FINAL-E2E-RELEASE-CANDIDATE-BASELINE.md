# LiveDrop — Final E2E Release Candidate Baseline
**Document ID:** `docs/FINAL-E2E-RELEASE-CANDIDATE-BASELINE.md`  
**Execution Date:** 2026-09-26  
**Status:** RECORDED & ACTIVE  
**Authority:** [docs/SOURCE-OF-TRUTH.md](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md) · [docs/AGENTS.md](file:///c:/LiveDrop/AGENTS.md)

---

## 1. System Baseline Telemetry

| Parameter | Value | Verification Source |
| :--- | :--- | :--- |
| **Git Commit Hash** | `9c45852` (*feat: implement final buyer UI freeze with enhanced order lookup...*) | `git rev-parse HEAD` |
| **Git Branch** | `main` (synchronized with `origin/main`) | `git branch` |
| **Buyer Web Version** | `0.1.0` (`Next.js 16.3.4`, `React 19.2.8`, `Turbopack`) | `buyer-web/package.json` |
| **Seller App Version** | `1.0.0+1` (`Flutter SDK ^3.11.4`, `supabase_flutter: ^2.17.2`) | `seller-app/pubspec.yaml` |
| **Staging Supabase Project** | `aoagqdtnrbmayfoajzes` (*"LiveDrop Staging"*) | Supabase MCP `list_projects` |
| **Staging Database Host** | `db.aoagqdtnrbmayfoajzes.supabase.co` (PostgreSQL 17.6) | Hosted Supabase Infrastructure |
| **Staging Region** | `ap-south-1` (Mumbai, India) | Supabase Configuration |
| **Staging Database Status** | `ACTIVE_HEALTHY` | Supabase Cloud Management API |
| **Latest Database Migration** | `032_add_stream_url_to_drops.sql` (32 active migrations) | `supabase/migrations/` |
| **Buyer Deployment Domain** | `https://livedrop-in.vercel.app` | Vercel Staging / Production Proxy |
| **Seller Dart Configuration** | `BUYER_BASE_URL=https://livedrop-in.vercel.app` | `seller-app/lib/core/config/env_config.dart` |
| **Known Open Defects** | None (460/460 buyer unit/integration tests passing) | Vitest Test Suite |

---

## 2. Git History Snapshot (Last 10 Commits)

```
9c45852 feat: implement final buyer UI freeze with enhanced order lookup, cart management, and storefront components
0abdaeb feat: complete buyer-web production repair with cart UX consolidation and design system cleanup
2fb26f7 chore(buyer-web): clean up unused subtotalPaisa in cart drawer and page
94855f6 fix(buyer-web): structural layout repair, data hygiene, and cart reconciliation pass
ecc47d2 ci: add GitHub Actions workflow for automated Vercel deployment of buyer web
c5c97c2 feat: introduce global CSS reset and design tokens for LiveDrop buyer app
70cf696 feat: implement buyer web storefront, navigation components, catalog, and test suite
ca8b11a feat(buyer-web): Haute Couture UI redesign matching template 1:1 with Stitch design taste
c48c7ef Fix CSS regression: Install and configure Tailwind CSS v4 to apply styling
82cbed8 ci: use direct Vercel cloud deploy without local prebuilt
```

---

## 3. Environment & Security Boundaries

1. **No Service-Role Key Leakage:** Client configurations (`buyer-web/.env.local`, `seller-app/lib/core/config/env_config.dart`) strictly contain public publishable anon keys (`sb_publishable_*`). Under no circumstances is the Supabase Service-Role key compiled into artifacts or committed to git.
2. **PostgreSQL RLS Active:** Row-Level Security policies are strictly enforced across all 8 core tables (`profiles`, `drops`, `products`, `orders`, `order_items`, `payment_attempts`, `verified_payments`, `audit_logs`).
3. **Database-Enforced Price Authority:** Monetary amounts strictly operate on integer Paisa (`price_paisa`). Frontend calculations are cosmetic projections; backend RPCs validate subtotals, shipping thresholds, advance deposits, and payment balances before state transitions.
