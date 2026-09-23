# LiveDrop.in — Vercel Production Deployment & Operations Guide

**System:** LiveDrop Buyer Storefront (`buyer-web`)  
**Target Platform:** Vercel (Edge & Serverless Next.js 16)  
**Primary Domain:** `https://livedrop.in`  
**Authoritative Reference:** [`docs/28-deployment-architecture.md`](file:///c:/LiveDrop/docs/28-deployment-architecture.md)

---

## 1. Overview & System Specifications

The LiveDrop buyer storefront is built on **Next.js 16.3+ (App Router)** with React 19 and Turbopack. It is designed to be hosted globally on Vercel's edge network for sub-100ms first-contentful-paint across India.

### Deployment Summary
| Setting | Production Specification |
|---|---|
| **Vercel Project Name** | `livedrop-in` (Display: `LiveDrop.in`) |
| **Root Directory** | `buyer-web` |
| **Framework Preset** | `Next.js` |
| **Build Command** | `npm run build` |
| **Output Directory** | `.next` (default) |
| **Install Command** | `npm ci` |
| **Primary Domain** | `livedrop.in` |
| **Domain Alias** | `www.livedrop.in`, `livedrop-in.vercel.app` |

---

## 2. Production Environment Variables Checklist

Set these variables in the **Vercel Dashboard ➔ Project Settings ➔ Environment Variables** (or inject via Vercel CLI):

| Variable Name | Environment | Value Example | Security Classification |
|---|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Production, Preview | `https://aoagqdtnrbmayfoajzes.supabase.co` | **PUBLIC** (Browser Safe) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Production, Preview | `sb_publishable_7jbVHNR-o2ZTQZJzapUctg_...` | **PUBLIC** (Browser Safe, RLS-enforced) |
| `NEXT_PUBLIC_APP_ENV` | Production | `production` | **PUBLIC** |
| `NEXT_PUBLIC_APP_BASE_URL` | Production | `https://livedrop.in` | **PUBLIC** |

> [!CAUTION]
> **Strict Guardrail:** `SUPABASE_SERVICE_ROLE_KEY` must **NEVER** be entered in Vercel environment variables for `buyer-web`. The buyer application uses zero service-role keys.

---

## 3. Deployment Methods

### Method A: Automated GitHub Actions CI/CD (Recommended)
Workflow file: [`.github/workflows/deploy-buyer-web-vercel.yml`](file:///c:/LiveDrop/.github/workflows/deploy-buyer-web-vercel.yml)

Every push to `main` executes:
1. **Pre-flight Quality Gate:** Runs ESLint, TypeScript check, and the 391 Vitest unit/integration tests.
2. **Build & Deploy:** Compiles Next.js with Turbopack and deploys atomic release to Vercel production.
3. **Health Check:** Automatically pings `https://livedrop.in` to ensure 200 OK response.
4. **Pull Requests:** Automatically builds and deploys preview branches without affecting production.

#### GitHub Repository Secrets Setup:
Add the following secrets to GitHub under **Settings ➔ Secrets and variables ➔ Actions**:
- `VERCEL_TOKEN`: Generated at [vercel.com/account/tokens](https://vercel.com/account/tokens)
- `VERCEL_ORG_ID`: Found in `.vercel/project.json` or team settings
- `VERCEL_PROJECT_ID`: Found in `.vercel/project.json` or project settings

---

### Method B: Automated PowerShell Deployment Script
Run directly from your terminal:
```powershell
.\scripts\deploy-buyer-web.ps1
```
*Options:*
- `.\scripts\deploy-buyer-web.ps1 -TargetEnv production` (Deploys directly to production)
- `.\scripts\deploy-buyer-web.ps1 -VercelToken "your_token"` (Uses non-interactive token)
- `.\scripts\deploy-buyer-web.ps1 -SkipTests` (Skips unit tests if already validated)

---

### Method C: Manual Vercel CLI Deployment
```bash
cd buyer-web
npx vercel login
npx vercel link --yes --project livedrop-in
npx vercel deploy --prod --yes
```

---

## 4. DNS Configuration for LiveDrop.in

Configure the following DNS records in your domain registrar (GoDaddy, Namecheap, Cloudflare, etc.):

### Record 1: Apex Domain (`livedrop.in`)
- **Type:** `A`
- **Name / Host:** `@` (or leave empty)
- **Value / Destination:** `76.76.21.21`
- **TTL:** Auto (or 3600)

### Record 2: Subdomain (`www.livedrop.in`)
- **Type:** `CNAME`
- **Name / Host:** `www`
- **Value / Destination:** `cname.vercel-dns.com.`
- **TTL:** Auto (or 3600)

*Note: Once DNS records propagate (typically 2-15 minutes), Vercel automatically issues and renews Let's Encrypt SSL/TLS certificates with zero manual intervention.*

---

## 5. Rollback & Emergency Procedures

If a faulty release is detected in production:

1. **Instant Vercel Instant Rollback:**
   - In Vercel Dashboard: Go to **Deployments** ➔ Click on the last known healthy deployment ➔ Click **Instant Rollback**.
   - Via Vercel CLI:
     ```bash
     cd buyer-web
     npx vercel rollback [DEPLOYMENT_ID]
     ```
2. **Git Revert:**
   - Revert the commit on `main` and push; GitHub Actions will automatically deploy the previous revision within 90 seconds.
