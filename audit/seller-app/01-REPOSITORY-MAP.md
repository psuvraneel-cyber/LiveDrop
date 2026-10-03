# 01 — Repository Map

| | |
|---|---|
| Audited commit | `94ccfc9a1648270d9c87f9f7f0e6a32428f9069d` (branch `claude/gracious-carson-vdvdrv`). `origin/main` moved to `e745a0a` during the audit (PRs #6/#7: buyer-web styling, Vercel Analytics, `scripts/create-test-seller.mjs`); no file under `seller-app/`, `supabase/` or `.github/` changed, so nothing here is affected. |
| Date | 2026-10-03 |
| Scope | Whole repository, seller app in depth |
| Executed | File inventory, dependency lock inspection, `flutter --version`, `flutter analyze` |
| Not executed | Nothing hosted; no Android build (SDK download blocked) |

## 1. Top level

| Path | What it is | Seller relevance |
|---|---|---|
| `seller-app/` | Flutter Android seller app (the subject of this audit) | Primary |
| `buyer-web/` | Next.js 16.3.4 / React 19.2.8 buyer site, `@supabase/supabase-js` ^2.116, Vitest 5 | Public drop URL, catalogue sync, checkout totals, payment claim |
| `supabase/migrations/` | 33 ordered SQL migrations `001`–`033` — schema, RLS, RPCs, triggers, storage, realtime publication | Authoritative business rules |
| `supabase/config.toml` | Local Supabase CLI config (auth: sign-up on, confirmations off, min password 6) | Auth posture (local only) |
| `supabase/seed.sql`, `supabase/seed/` | Local seed (auth users without passwords); `seed/` empty | — |
| `supabase/functions/` | **Empty** (`.gitkeep`) — no Edge Functions exist | No server push, no webhooks |
| `.github/workflows/` | `seller-app-ci.yml`, `buyer-web-ci.yml`, `deploy-buyer-web-vercel.yml`, `reaper-cron.yml` (*/5), `supabase-keepalive.yml` (daily) | Reaper cadence, APK artifact |
| `scripts/` | 19 Node/PowerShell helpers: `run-reaper.mjs`, `build-seller-apk.ps1`, `seed-legitimate-staging-drop.mjs`, `validate-hosted-supabase.mjs`, concurrency/failure-injection scripts, responsive checks | Reaper, APK build, staging seeding |
| `docs/` | 50 spec documents (PRD, functional spec, DB design, API/realtime contracts, ADR-001…009, RTM) + `docs/audit/` (previous static audit, 14 files) | Claims reconciled in [00](00-EXECUTIVE-SUMMARY.md#documentation-vs-implementation) |
| `patches/`, `Final Buyer website design/`, `.cursor/`, `.gemini/` | Tooling/design leftovers | None |
| `audit/seller-app/` | **This audit** (reports, tests, evidence) | — |

Environment files: only `seller-app/.env.example` and `buyer-web/.env.example` are tracked (placeholders). The seller app reads configuration exclusively through `--dart-define` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APP_ENV`, `BUYER_BASE_URL`, default `https://livedrop-in.vercel.app`).

## 2. Seller app toolchain

| Item | Value | Evidence |
|---|---|---|
| Flutter | 3.41.6 stable (local audit SDK). CI floats on `channel: "stable"` (SA-CI-001) | `flutter --version`; `seller-app-ci.yml:37` |
| Dart | 3.11.4 (`sdk: ^3.11.4`) | `pubspec.yaml`, `pubspec.lock` |
| Supabase client | `supabase_flutter` 2.17.2 (supabase 2.16.1, gotrue 2.27.2, postgrest 2.9.1, realtime_client 2.13.0, storage_client 2.8.0); PKCE auth flow | `pubspec.lock`; `core/services/supabase_service.dart:38-40` |
| Camera / images | `camera` 0.11.4, `image_picker` 1.2.3, `image` 4.10.1 (pure-Dart decode/encode in a `compute` isolate) | `core/services/image_service.dart` |
| Labels | `pdf` 3.12.0 + `printing` 5.14.3 (system print/share sheet) | `core/services/pdf_label_service.dart` |
| Other | `url_launcher` 6.3.2, `intl` 0.19.0, `flutter_animate` 4.5.2, `shared_preferences` 2.5.5 (transitive, session storage) | `pubspec.lock` |
| Lints | `flutter_lints` + strict casts/inference/raw types; `flutter analyze` → **No issues found** | `analysis_options.yaml`; `evidence/flutter-analyze.out` |
| Android | `applicationId store.livedrop.seller_app`; min/target SDK from Flutter defaults; **release signed with debug key** (SA-AND-001) | `android/app/build.gradle.kts:24-37` |

## 3. Architectural characteristics (as implemented)

| Concern | Implementation | Notes / findings |
|---|---|---|
| State management | None. `StatefulWidget` + `setState` (122 calls), each screen loads its own data in `initState` | No shared store → stale tabs (SA-CQ-001) |
| Dependency injection | Constructor injection of one `SellerRepository`; singleton `SupabaseService.instance` | Testable via fakes (used by audit tests) |
| Navigation | Navigator 1.0. `MaterialApp.home` = splash → `SellerAuthGate` → `SellerHomeScreen` (5-tab `IndexedStack`); feature screens via `Navigator.push` | No deep links (SA-AND-003); pushed routes survive logout (SA-AUTH-005) |
| Networking | supabase_flutter only (PostgREST, RPC, Storage, Realtime). No HTTP client of its own | No timeouts/retry policy except the intake queue |
| Persistence | Session: supabase_flutter default (SharedPreferences). Intake queue: JSON manifest + JPEGs under `Directory.systemTemp/livedrop_intake_queue` | Cache dir, purgeable (SA-OFF-001) |
| Offline | Only product intake is queued; everything else needs network | [12-OFFLINE](12-OFFLINE-RESILIENCE-AUDIT.md) |
| Realtime | One wrapper `data/realtime/seller_order_realtime.dart` (orders INSERT/UPDATE per drop), used only by the Kanban when a drop is selected | SA-RT-001 |
| Notifications | **None** (no FCM, no local notifications); Settings toggles are placeholders | SA-NOT-001 |
| Background execution | None (no WorkManager/foreground service); queue retries are in-process `Timer`s | — |
| Analytics / telemetry | None | SA-OBS-001 |
| Crash reporting | None | SA-OBS-001 |
| Logging | 2 `debugPrint` calls; 33 `catch (_)` blocks | SA-OBS-001 |
| Feature flags | None | — |
| Localisation | English only, hard-coded strings | UX note |

## 4. `seller-app/lib` map (14,764 lines)

| Layer | Files (lines) | Responsibility |
|---|---|---|
| `main.dart` (414) | `main`, `LiveDropSellerApp`, `SellerAuthGate`, `SellerHomeScreen` | Init, auth gate, approval gate, tab shell, Add-Product/Shipping shortcuts |
| `core/config` | `env_config.dart` (90), `admin_config.dart` (53) | dart-define config, buyer URL builder, hard-coded admin WhatsApp/UPI/fee |
| `core/services` | `supabase_service.dart` (81), `offline_intake_queue.dart` (349), `image_service.dart` (104), `pdf_label_service.dart` (345) | Client singleton, intake queue, image pipeline, 4×6 label |
| `core/utils`, `core/errors`, `core/theme` | `url_launcher_helper.dart` (154), `exceptions.dart` (46), colours, theme, haptics, buttons, emblem | Intents (WhatsApp/tel/https), `LiveDropException`, design system |
| `data/repositories` | `seller_repository.dart` (1,031) | **All** PostgREST/RPC/Storage calls (see [05](05-DATABASE-INTEGRATION-AUDIT.md#1-every-seller-app-database-interaction)) |
| `data/realtime` | `seller_order_realtime.dart` (100) | Per-drop orders channel |
| `domain/models` | `models.dart` (693) | Enums + `fromJson` for profile, drop, product, order, item, attempt, analytics |
| `presentation/auth` | login (419), registration (776), pending approval (197) | Email/password auth, self-registration with ₹50 fee UTR |
| `presentation/dashboard` | `seller_dashboard_screen.dart` (723) | Home (drop pill, KPIs, quick actions, activity) |
| `presentation/intake` | `camera_intake_screen.dart` (1,203) | Camera-first multi-angle intake |
| `presentation/products` | inventory (612), details (789) | List/filter/search, edit, mark sold, share |
| `presentation/drops` | list (573), create/edit (337) | Drop CRUD, go live, close, re-open |
| `presentation/orders` | kanban (326), card (482), details (381), shipping dialog (359), shipping label (417) | Order pipeline, dispatch, labels |
| `presentation/` | `pending_verifications_screen.dart` (619), `payment_settings_screen.dart` (385), `configuration_error_screen.dart` (161) | Payment queue, UPI settings |
| `presentation/settings`, `analytics`, `splash`, `common` | settings (1,037), analytics (537), splash (226), skeletons (202) | Profile/defaults/notifications/help, revenue charts |

## 5. Tests and quality gates

| Suite | Count | Result in this audit | Evidence |
|---|---|---|---|
| `seller-app/test/` (10 files) | 49 tests | **49/49 pass** | `evidence/flutter-test-existing.out` |
| `buyer-web` Vitest | 655 tests / 49 files | **655/655 pass** (40.4 s) | `evidence/buyer-web-vitest.out` |
| Database tests in repo | none runnable in CI (scripts target hosted staging) | — | `scripts/validate-hosted-supabase.mjs` (not run: no credentials, by design) |
| Audit SQL suites (new) | suites 10–18 + catalog inventory | 33/33 migrations apply; results per suite | `evidence/1*.out`, `14_concurrency.out` |
| Audit Flutter tests (new) | 26 tests (T01–T25) | 26/26 pass (each demonstrates a defect or a control) | `evidence/flutter-audit-tests.out` |

## 6. Generated, legacy and dead code

| Item | Status |
|---|---|
| `SellerRepository.getOrders(dropId)` | Unused; selects fewer columns than the model (SA-CQ-002) |
| `SellerRepository.markOrderPaid` | Deprecated stub that throws (RPC is service-role only) |
| Kanban placeholder `SellerProfile` (`+91 9999999999`, `store@upi`) | Fallback object, practically unreachable (SA-CQ-002) |
| `_soundEnabled`, notification booleans, `_rememberMe` | UI state with no effect (SA-UX-002) |
| `scratch/` (in history: `scratch/downloaded_A01.jpg`) | Not present in HEAD |
| `docs/` references to 7 missing reports | SA-DOC-001 |

## 7. Previously reported issues re-checked

| Prior ID (docs/audit) | Current state |
|---|---|
| AUD-001 committed staging credential | Removed from HEAD in `ebb80cd`, **still in public history**; rotation unverified → SA-SEC-002 |
| AUD-002 reaper script | Fixed (`scripts/run-reaper.mjs` uses env + service role); cadence problem remains → SA-OPS-001 |
| AUD-004 deploy workflow hardening | Present in `deploy-buyer-web-vercel.yml` (not seller-relevant) |
| Seller UPI exposure in public API | Fixed by migration 033 (UPI VPA/QR removed from the view); the view itself is now writable → SA-SEC-001 |
