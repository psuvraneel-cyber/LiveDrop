# LiveDrop Seller App — Audit Workspace

Audit of commit `94ccfc9` (2026-10-03). **Audit-only:** nothing outside `audit/seller-app/` was changed. Start with [00-EXECUTIVE-SUMMARY.md](00-EXECUTIVE-SUMMARY.md) and [FINAL-SELLER-APP-READINESS.md](FINAL-SELLER-APP-READINESS.md).

## Layout

```
audit/seller-app/
├── 00-EXECUTIVE-SUMMARY.md … 22-IMPROVEMENT-ROADMAP.md   reports (one per audit area)
├── 02-ARCHITECTURE.mmd                                    architecture diagram (Mermaid)
├── FINAL-SELLER-APP-READINESS.md                          verdict, 25 answers, P0–P3, remaining work
├── FINDINGS.json                                          95 findings, machine-readable
├── tests/
│   ├── sql/
│   │   ├── 00_supabase_shim.sql         Supabase-compatible roles, auth.uid(), storage schema, default privileges
│   │   ├── 05_audit_helpers.sql         schema `audit`: fixed sellers/drops/products, role switching, seed()
│   │   ├── 10_exposure_and_view_dml.sql  anon/seller access through public views
│   │   ├── 11_seller_isolation.sql       cross-seller reads/writes, RPCs, storage folders
│   │   ├── 12_lifecycle_guards.sql       codes, direct mutations, drop transitions, approval, fulfilment
│   │   ├── 13_payments.sql               claims, verification, late claims, duplicates, thresholds, UPI URI
│   │   ├── 14_concurrency.sh             40-way checkout race, late-claim race, verify vs reaper deadlock
│   │   ├── 15_perf_seller_queries.sql    cost of the app's unpaginated queries (seasoned seller)
│   │   ├── 16_release_and_close_with_claims.sql  Release / close_drop with a buyer claim in flight
│   │   ├── 17_ledger_deletion.sql        can verified ledger rows be deleted with their order
│   │   ├── 18_storage_enumeration.sql    anonymous listing of product images
│   │   ├── 90_hosted_readonly_checks.sql READ-ONLY queries (H1–H13) + non-destructive HTTP probes for the hosted project
│   │   ├── 91_local_catalog_inventory.sql  catalog inventory of the local audit DB
│   │   └── run_local_db_audit.sh         creates a throwaway DB, applies shim + migrations, runs everything
│   └── flutter/
│       ├── audit_fakes.dart              fake repository / URL launcher / builders
│       ├── audit_*_test.dart             T01–T25 (26 tests)
│       └── run_flutter_audit_tests.sh    copies seller-app to a scratch dir and runs the tests there
└── evidence/                             raw outputs of every run (see below)
```

## Re-running the local database audit

Requirements: PostgreSQL 16 client/server you can create databases on (never a hosted project — the script drops and creates databases).

```bash
# example: a disposable cluster listening on a unix socket, port 55432
PGHOST=/var/run/postgresql PGPORT=55432 PGUSER=postgres \
  audit/seller-app/tests/sql/run_local_db_audit.sh
```

It (1) recreates database `livedrop_audit`, (2) applies `00_supabase_shim.sql`, (3) applies `supabase/migrations/001…033` in order (log: `evidence/migration-apply.log`), (4) installs `05_audit_helpers.sql`, (5) runs every `1*.sql` suite inside a rolled-back transaction (outputs `evidence/<suite>.out`), (6) writes catalog evidence (`schema-inventory.out`, `anon-executable-functions.out`, `security-definer-search-path.out`), and (7) runs `14_concurrency.sh` against a copy database (`livedrop_conc`).

Each line in the outputs is tagged:
- `PASS` — the control behaves as intended,
- `FINDING` — the defect is present (maps to an `SA-…` id),
- `INFO` — measured behaviour recorded for the reports,
- `INCONCLUSIVE` — the scenario could not be established (none in the final run).

When a fix lands, the corresponding `FINDING` condition is designed to flip to `PASS`, so the suites can be adopted as CI regression tests.

### What the shim does and does not emulate
Emulated: roles `anon`/`authenticated` (NOINHERIT)/`service_role` (BYPASSRLS)/`authenticator`; `auth.uid()`, `auth.role()`, `auth.jwt()` reading `request.jwt.claims`; `auth.users` (only used columns); `storage.buckets`/`storage.objects` with RLS and `storage.foldername()`; Supabase's documented default privileges in `public`; publication `supabase_realtime`. Not emulated: PostgREST/GoTrue/Storage HTTP layers, Realtime servers, pg_cron/pg_net. Results that depend on hosted configuration are marked for confirmation with `90_hosted_readonly_checks.sql`.

## Re-running the Flutter audit tests

```bash
FLUTTER=/path/to/flutter WORK=/tmp/ld-seller \
  audit/seller-app/tests/flutter/run_flutter_audit_tests.sh
```

The script copies `seller-app/` to `$WORK`, adds the tests under `test/audit/`, runs `flutter pub get --enforce-lockfile` and `flutter test` with `TZ=Asia/Kolkata`, and writes `evidence/flutter-audit-tests.out`. The product tree is never modified. Flutter 3.41.6 was used.

Tests T01–T25 assert the **current** behaviour, so a passing test means "the defect (or control) is still there". Invert the marked expectations as fixes land.

## Hosted read-only checks (run by the owner)

`tests/sql/90_hosted_readonly_checks.sql` contains only catalog/aggregate `SELECT`s (H1–H13) for the Supabase SQL editor, plus commented, non-destructive HTTP probes:
- PATCH against the all-zero UUID on `public_seller_storefronts` (cannot touch a row; secure = 401/403, vulnerable = 200 `[]`),
- Storage list with the anon key (secure = `[]`).

Run on staging first, then production, and file the outputs under `evidence/hosted/`.

## Evidence index

| File | Produced by | Content |
|---|---|---|
| `migration-apply.log` | DB harness | 33/33 migrations PASS |
| `10_…` … `18_….out`, `14_concurrency.out` | DB harness | Suite results |
| `schema-inventory.out`, `anon-executable-functions.out`, `security-definer-search-path.out` | DB harness | RLS flags, view updatability, grants, policies, function privileges, `search_path` pinning |
| `run_local_db_audit.console.txt` | DB harness | Console summary of the last full run |
| `flutter-audit-tests.out` | Flutter harness | T01–T25 output (26/26 pass) |
| `flutter-test-existing.out` | `flutter test` on the unmodified app | 49/49 pass |
| `flutter-analyze.out` | `flutter analyze` | No issues |
| `buyer-web-vitest.out` | `npm test` in a scratch copy of buyer-web | 655/655 pass |
| `hosted-reaper-schedule.md` | GitHub Actions API (read-only) | Actual reaper run times and gaps |

## Safety notes
- No hosted write, no use of the leaked credential (its value is redacted everywhere in this audit), no destructive tests.
- The SQL suites run inside transactions that are rolled back; the harness only touches the throwaway databases `livedrop_audit` and `livedrop_conc`.
