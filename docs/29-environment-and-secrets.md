# 29 — Environment Variables & Secrets Management: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Security Architecture:** [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)  

---

## 1. Secrets Classification & Distribution Rules

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SECRETS ACCESS MATRIX                            │
├───────────────────────┬──────────────┬──────────────────┬───────────────────┤
│ Variable Name         │ Scope        │ Injection Method │ Public Exposure   │
├───────────────────────┼──────────────┼──────────────────┼───────────────────┤
│ `NEXT_PUBLIC_SUPABASE_URL` | Web Client | `.env.production`| **PUBLIC** (Safe) │
│ `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Web Client | `.env.production` | **PUBLIC** (Safe) │
│ `SUPABASE_URL`        │ Flutter App  │ `--dart-define`  │ **PUBLIC** (Safe) │
│ `SUPABASE_ANON_KEY`   │ Flutter App  │ `--dart-define`  │ **PUBLIC** (Safe) │
│ `SUPABASE_SERVICE_ROLE_KEY` | Backend CI | GitHub Secret | **STRICTLY PRIVATE**│
│ `SUPABASE_DB_PASSWORD`| Admin / DB   | Local `.env`     │ **STRICTLY PRIVATE**│
└───────────────────────┴──────────────┴──────────────────┴───────────────────┘
```

> [!CRITICAL]
> **Zero-Commit Mandate:** The `SUPABASE_SERVICE_ROLE_KEY` and `DATABASE_URL` with master passwords must **NEVER** be committed to Git, embedded into the Next.js client bundle, or compiled into the Flutter Android APK.

---

## 2. Environment Configuration by Surface

### 2.1 Buyer Webfront (`buyer-web/.env.local` / `.env.production`)
```bash
# Public Supabase Connection
NEXT_PUBLIC_SUPABASE_URL="https://xyzcompany.supabase.co"
NEXT_PUBLIC_SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Base Store Domain for Canonical Links & OpenGraph
NEXT_PUBLIC_SITE_URL="https://drop.store"
```

### 2.2 Seller Mobile App (`seller-app/` Compilation Flags)
Passed securely during compilation via `--dart-define`:
```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://xyzcompany.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```
*Extracted in Dart code:*
```dart
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
```

### 2.3 Local Development (`supabase/.env.local`)
```bash
POSTGRES_PASSWORD="local_dev_password_only"
JWT_SECRET="local_dev_jwt_secret_min_32_chars_long_12345"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

---

## 3. Mandatory `.gitignore` Standards

The following rules are enforced at repository root:

```gitignore
# Environment & Secrets
.env
.env.local
.env.*.local
*.env
*.pem
*.key
*.p12

# Supabase Local Overrides
supabase/.temp/
supabase/.branches/

# Flutter Sensitive Keystores
*.keystore
*.jks
key.properties

# Next.js Build Outputs
.next/
out/

# IDE & OS Noise
.DS_Store
Thumbs.db
```

---

## 4. Secret Rotation Playbook

If a credential leak is suspected:
1. **Anon Key Compromise:** Rotate Anon Key in Supabase Dashboard ➔ Update Cloudflare Pages environment variables ➔ Recompile Flutter release APK and distribute to seller.
2. **Service Role Key Compromise:** Immediately rotate in Supabase Dashboard ➔ Re-key GitHub Actions Secrets ➔ Audit PostgreSQL logs for unauthorized mutations.
3. **Database Master Password Compromise:** Change password immediately via Supabase Database Settings. Active connection pools restart automatically.
