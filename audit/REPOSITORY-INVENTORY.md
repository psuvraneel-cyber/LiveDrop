# Repository inventory

## Scope and layout

| Area | Actual location | Evidence / status |
|---|---|---|
| Buyer application | `buyer-web/` | Next.js 16.3.4, React 19.2.8, TypeScript 5, Supabase JS 2.116.0 |
| Seller application | `seller-app/` | Flutter 3.41.6 / Dart 3.11.4 locally; `supabase_flutter` 2.17.2 |
| Database | `supabase/migrations/001...032` | 32 ordered SQL migrations; local Supabase CLI unavailable |
| Background operations | `scripts/run-reaper.mjs`, `scripts/keepalive-ping.js` | GitHub Actions scheduled jobs |
| CI/CD | `.github/workflows/` | buyer CI, Vercel deployment, seller CI, reaper, keepalive |
| Tests | `buyer-web/src/test/`, `buyer-web/e2e/`, `seller-app/test/`, `scripts/test-*` | mostly Vitest/Flutter tests; no pgTAP directory or k6 assets found |
| Reference/legacy UI | `Final Buyer website design/livedrop-ui-v1/` | separate Next app; no workflow references found; likely design reference / duplicate surface |
| Existing audit/release notes | `docs/PHASE-*`, `docs/TASK-*`, `docs/FINAL-*` | historical claims only; not treated as runtime evidence |

## Technology and dependency matrix

| Component | Key versions / roles | Concern |
|---|---|---|
| Buyer | Next 16.3.4; React 19.2.8; Vitest 5; Playwright 1.63 | Package lock exists; CI pins Node 24, but local full Vitest run failed to complete. |
| Seller | Flutter SDK constraint `^3.11.4`; `supabase_flutter` 2.17.2; camera/image/PDF | No Riverpod/freezed dependencies despite the architecture convention. |
| Backend | PostgreSQL/Supabase migrations; Storage; Realtime | No local runtime available to apply the migration chain. |
| Deployment | Vercel CLI in GitHub Actions; scheduled Actions reaper | No migration deployment job or environment protection is visible. |

## Inventory conclusions

The actual product is a Flutter seller client and a Next buyer client sharing Supabase directly. There are no Next route handlers, Edge Functions, or server actions in `buyer-web/src/app`; database RPCs and PostgREST are the integration boundary. `Final Buyer website design/livedrop-ui-v1/` is a second, unintegrated web tree and is a release-governance risk until explicitly archived or designated as the non-deployable reference.
