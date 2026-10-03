# 20 — Automated Test Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Existing tests (seller Flutter, buyer Vitest, scripts), CI, new audit-only tests, requirements-to-test matrix |
| Executed | `flutter analyze`; `flutter test` (existing); `npm test` in buyer-web (Vitest); new audit suites: SQL 10–18 (local Postgres + Supabase shim) and Flutter T01–T25 (26 tests) |
| Not executed | Integration/golden tests (none exist); hosted staging scripts (`scripts/validate-hosted-supabase.mjs`, `test-concurrency-10-trials.mjs`, `run-e2e-suite.mjs`) — require hosted credentials; device tests |

## 1. Results

| Suite | Result | Evidence |
|---|---|---|
| `flutter analyze` | No issues | `evidence/flutter-analyze.out` |
| Seller Flutter tests (10 files, 49 tests) | **49/49 pass** | `evidence/flutter-test-existing.out` |
| Buyer-web Vitest (49 files, 655 tests) | **655/655 pass** (40.4 s) | `evidence/buyer-web-vitest.out` |
| Integration / golden / e2e on device | None exist | — |
| Database tests in CI | None (migrations never applied in CI) | `.github/workflows` |
| Audit SQL suites 10–18 | Migrations 33/33 apply; PASS controls + FINDINGs as reported | `evidence/1*.out`, `14_concurrency.out` |
| Audit Flutter tests (26) | 26/26 pass — each asserts the current (defective or control) behaviour | `evidence/flutter-audit-tests.out` |

## 2. What the existing tests actually cover
| File | Focus | Business-critical coverage |
|---|---|---|
| `seller_repository_test.dart` (14) | Env/init guards, model parsing | Parsing only |
| `offline_intake_queue_test.dart` (5) | Enqueue, reload, happy upload, one network failure, multi-angle | Happy paths; no permanent errors, duplicates, corruption, races |
| `sprint2_seller_operations_test.dart` (5) | Image crop/scale, PDF label, OrderCard buttons | Asserts "PREPAID" and Dispatch-for-paid (would not catch SA-SHIP-002/SA-ORD-005) |
| `realtime_test.dart` (2) | `SellerOrder.fromJson` on realtime-like maps | No subscription behaviour |
| `seller_auth_registration_test.dart` (4) | Screens render | No auth flow |
| `luxury_ui_and_motion_test.dart` (6), `seller_ui_verification_test.dart` (4), `seller_settings_screen_test.dart` (1), `storefront_url_test.dart` (6), `widget_test.dart` (2) | Rendering, URL formatting | URL generation covered |

Conclusion: the 49 tests protect rendering and parsing; **none exercises money, inventory, authorisation or concurrency**, which is where every CRITICAL finding sits. The 655 buyer tests are broad on UI behaviour but run against mocks; no test shares fixtures with the SQL rules (threshold parity, SA-PAY-008).

## 3. Requirements-to-test matrix

| # | Requirement / risk | Existing tests | Audit tests (this audit) | Coverage |
|---|---|---|---|---|
| R1 | Seller login, session, logout | smoke render | — | ✖ |
| R2 | Approval gate (server + client) | render of pending screen | 12.6, T06, T07 | ◐ (client fails open) |
| R3 | Seller isolation (tables, RPCs, storage) | — | 10.6, 11.1–11.5 | ✔ (audit) |
| R4 | Public view exposure / DML | — | 10.2–10.9, H1–H3 | ✔ (audit; defect) |
| R5 | Storage access (upload/list) | — | 11.5, 18.1 | ✔ (audit; defects) |
| R6 | Product code/title rules | — | 12.1, T17 | ✔ (audit; defect) |
| R7 | Price/product edit restrictions | — | 12.2a/b | ✔ |
| R8 | Product insert status | — | 12.3 | ✔ (defect) |
| R9 | Image pipeline (crop, orientation, EXIF, size, time) | crop/scale | T22–T24 | ✔ |
| R10 | Intake queue durability/idempotency | 5 happy-path | T14–T19, T25 | ✔ (defects) |
| R11 | Drop lifecycle (go live, close, reopen, slug, one-live) | — | 12.4–12.6, 16.2 | ✔ |
| R12 | Buyer URL generation | 6 + settings | — | ✔ |
| R13 | Buyer catalogue sync / same drop | buyer Vitest (mocked) | — | ◐ no e2e |
| R14 | Concurrent reservation | hosted script (not in CI) | 14.1 | ✔ (audit) |
| R15 | Payment verify happy path + idempotency | — | 13.1 | ✔ |
| R16 | Late claims (advance/full, available/resold) | — | 13.5–13.7, 14.2 | ✔ (defects) |
| R17 | Claim expiry / reaper | — | 13.8, hosted run history | ✔ (defect) |
| R18 | Duplicate UTR | — | 13.3 | ✔ (defect) |
| R19 | Reject / release with claims | — | 13.4, 16.1, T11 | ✔ (defects) |
| R20 | Ledger immutability | — | 17.1–17.3 | ✔ (defect) |
| R21 | Fulfilment transitions | OrderCard render | 12.8, T03, T21 | ✔ |
| R22 | Shipping label content | PDF test (asserts PREPAID) | T08 | ◐ |
| R23 | Realtime delivery to seller | parse only | — (code review) | ✖ |
| R24 | Notifications | — | — | ✖ (feature absent) |
| R25 | Timezone display | — | T04, T05 | ✔ (defect) |
| R26 | Shipping fee / threshold parity | — | 13.10 | ✔ (defect) |
| R27 | Suspension | — | 12.7 | ✔ (defect) |
| R28 | Password reset | — | — | ✖ |
| R29 | Analytics correctness | render only | — | ✖ |
| R30 | Performance budgets | — | 15.x, T24 (host) | ◐ (no device) |
| R31 | Device behaviours (camera, lifecycle, printing, intents) | — | — | ✖ (plan in 16) |

## 4. Tests to add before real sellers
1. **CI database job**: start Postgres, apply `tests/sql/00_supabase_shim.sql` + migrations, run suites 10–18; as each fix lands, flip the corresponding `FINDING` assertions to `PASS` (they are written to make that a one-line change).
2. **CI Flutter job**: include `audit/seller-app/tests/flutter` (copy into `test/audit` as the runner does) with `TZ=Asia/Kolkata`; invert defect assertions as fixes land.
3. **Contract tests**: repository ↔ RPC signatures (would have caught `p_override_reference`).
4. **Parity tests**: shipping/threshold quote — same fixtures in SQL and Vitest.
5. **E2E (Playwright + seller-app integration test)**: seller creates drop → go live → buyer opens URL → reserves → claims → seller verifies → buyer page shows paid; repeat for late claim and release-with-claim.
6. **Device checklist** D1–D18 from [16](16-ANDROID-AUDIT.md#4-physical-device-validation-plan-brief-section-37--to-run-before-real-sellers) with recorded evidence.
7. **Secret scanning** (gitleaks) and manifest lint in CI.

## 5. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-TEST-001 | MEDIUM | P1 | Tests cover rendering/parsing, not money/inventory/auth/concurrency |
| SA-CI-001 | MEDIUM | P1 | Floating Flutter, no migration job, no secret scan, debug artifact |
| SA-AND-005 | MEDIUM | P1 | No device validation |
| SA-DB-001 | MEDIUM | P1 | Hosted schema state unverifiable |
