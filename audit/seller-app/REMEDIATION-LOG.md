# Seller-app audit — P0 remediation log

Audit record: `audit/seller-app/` reports 00–22 and `FINDINGS.json` describe commit **94ccfc9** and are left unchanged.
This log covers the uncommitted P0 remediation on top of `origin/main`, dated 2026-10-03. Statements are based on `git diff` / `git status` and the evidence files in `audit/seller-app/evidence/`.

## Verification runs (local, all exit 0)

| Check | Result | Evidence |
|---|---|---|
| DB harness `run_local_db_audit.sh` (PostgreSQL 16, migrations 001–036) | 36 migrations applied, 0 failed; no FINDING line for any P0 | `run_local_db_audit.console.txt`, `migration-apply.log` (`PASS  034_…`, `PASS  035_…`, `PASS  036_…`) |
| Suite 19 (new, `tests/sql/19_p0_remediation.sql`) | 34 PASS, 0 FINDING | `19_p0_remediation.out` |
| Suites 10, 14, 16, 17 | 0 FINDING | `10_…out`, `14_concurrency.out`, `16_…out`, `17_ledger_deletion.out` |
| `flutter analyze` (seller-app) | `No issues found!` | `flutter-analyze.out` |
| `flutter test` (seller-app) | `00:18 +121: All tests passed!` | `flutter-test-existing.out` |
| Audit Flutter runner | `00:18 +26: All tests passed!` | `flutter-audit-tests.out` |
| buyer-web vitest | `Test Files 49 passed (49)`, `Tests 655 passed (655)` | `buyer-web-vitest.out` |

FINDING lines still printed (none P0, not in scope): 11.5b SA-SEC-003, 12.3 SA-INV-003, 12.7 SA-ONB-002, 13.2 SA-PAY-007, 13.3c SA-PAY-011, 13.9 SA-PAY-015, 13.10a/b SA-PAY-008, 18.1 SA-SEC-008.

Test fix made during the cross-check: `tests/sql/15_perf_seller_queries.sql` now derives order codes from the row number. Random codes collided in about 1 run in 9; this was a test bug, not a product bug.

## Findings

| Finding | Sev | Status | What changed (files) | Proof | Remaining owner actions |
|---|---|---|---|---|---|
| SA-SEC-001 | P0 | **Fixed — live** (hosted DB, 2026-10-04) | `supabase/migrations/034_lock_down_public_view_privileges.sql`: views SELECT-only for client roles, default privileges tightened, TRUNCATE/REFERENCES/TRIGGER revoked; RLS untouched | `PASS 10.3 anon UPDATE through view denied: permission denied for view public_seller_storefronts`; `PASS 10.4`, `PASS 10.5`, `PASS 10.9 anon/authenticated hold SELECT only on every view in public`; `PASS 19.20a/b/c` (`run_local_db_audit.console.txt`) | Apply 034 to hosted **first** (the hole is live there); run H1 and H14 in `tests/sql/90_hosted_readonly_checks.sql` (SELECT only, zero rows) and the curl PATCH probe (expect 42501) |
| SA-SEC-002 | P0 | **Partially fixed** | `.github/workflows/secret-scan.yml`, `.gitleaks.toml` (gitleaks on new commits, redacted); `docs/ops/credential-rotation-runbook.md` | gitleaks passed on PRs #10–#12 and on main. Previously: the workflow has not executed yet. Cross-check secrets scan of diff + untracked files found no credentials | Done by owner on 2026-10-03: the leaked staging seller account was deleted, so the exposed login no longer works. Remaining: review Auth logs/data since 2026-09-26; decide on a history purge; confirm the first gitleaks run passes |
| SA-PAY-001 | P0 | **Fixed** (deploy pending) | `035_payment_claim_safety_and_refunds.sql`: `verify_manual_upi_payment` via `apply_upi_payment_transition`; ledger invariant | `PASS 13.5c late advance verified -> order confirmed/advance_paid … total_paid=25000 … balance_due=225000`; `PASS 19.4`, `PASS 19.4b`, `PASS 19.21 ledger invariant holds for 22 of 22 orders` | Apply 035; review orders listed by hosted H11 (already damaged, not rewritten) |
| SA-PAY-002 | P0 | **Fixed** (deploy pending) | 035: late path locks products `ORDER BY id`, status-predicated updates with row-count check | `PASS 14.2 … order Y keeps the piece (no overwrite)`; `PASS 14.2b exactly one live paid order owns #A02`; `PASS 13.6`, `PASS 19.5` | Apply 035 |
| SA-PAY-003 | P0 | **Fixed** (deploy pending) | 035: `release_expired_holds` skips claimed orders/attempts, SKIP LOCKED; claimed attempts verifiable after window. App: overdue labelling (`pending_verifications_screen.dart`, `models.dart`) | `PASS 13.8 … attempt=awaiting_seller_verification … still in seller queue=1 \| verify afterwards -> success=true`; `PASS 19.11`, `PASS 19.12`; Flutter `payments_refunds_test.dart` "Overdue claims (SA-PAY-003) …" | Apply 035; reconcile claims listed by hosted H20 with sellers |
| SA-PAY-004 | P0 | **Fixed** (deploy pending) | 035: `orders.refund_*` columns + constraints + index, `record_refund` RPC, backfill of 023 notes. App: Refunds owed list, Mark refunded, refund dialog (`seller_repository.dart`, `pending_verifications_screen.dart`, `seller_dashboard_screen.dart`, `seller_error_messages.dart`) | `PASS 13.6 … refund_status=required refund_amount=158000 reason=LATE_PAYMENT_INVENTORY_UNAVAILABLE`; `PASS 19.5`, `19.5b`, `19.7`, `19.9a`–`19.9h`, `19.17`; Flutter `payments_refunds_test.dart` "Refunds owed …", "verify response with refund_required=true shows a blocking refund dialog"; audit `SA-AUD-T20 (refund part fixed)` | Apply 035; review refunds owed per drop with hosted H15 |
| SA-OPS-001 | P0 | **Fixed — live** (hosted DB, 2026-10-04) | 035: lazy expiry in `create_order_with_reservation` via `release_stale_hold`; `036_schedule_reaper_in_database.sql` (pg_cron, guarded); `.github/workflows/reaper-cron.yml` comment: backup trigger only | `PASS 19.1 checkout of a piece behind an expired, unclaimed hold -> success=true`; `PASS 19.2`; `PASS 19.3`; `PASS 14.5 lazy expiry released the stale hold once; exactly one racer reserved the piece`; `PASS 19.18 pg_cron not available here: 036 applied as a no-op`. 036 scheduling run twice against a stub `cron` schema left exactly one job (no real pg_cron tested) | Apply 036; if it logs the "could not schedule" NOTICE, enable pg_cron (Dashboard → Database → Extensions) and re-run 036; check H8/H17 (job active, runs succeed) and H18 (expired unclaimed holds = 0 within ~2 min) |
| SA-PAY-005 | P0 | **Fixed** (deploy pending) | 035: `force_release_hold` → `PAYMENT_CLAIM_PENDING`; `close_drop` and `reject_manual_upi_payment` keep claimed holds; data repair to `late_claim_pending_review`. App: Release hidden while a claim exists, friendly message (`order_card.dart`, `kanban_board_screen.dart`, `seller_error_messages.dart`) | `PASS 16.1b force_release_hold with a claim in flight -> PAYMENT_CLAIM_PENDING`; `PASS 16.1c`, `PASS 16.2`, `PASS 19.10a`–`c`, `PASS 19.15`; Flutter `order_card_release_test.dart` "PAYMENT_CLAIM_PENDING becomes a friendly message" | Apply 035 |
| SA-INT-001 | P0 | **Fixed** | `core/validation/product_rules.dart`, `core/services/intake_error_classifier.dart`, `core/services/offline_intake_queue.dart` (needsAttention, updateItem/discardItem/retryItem, 23505 reconciliation), `presentation/intake/intake_draft_fields.dart`, `camera_intake_screen.dart`, `products/queued_piece_editor.dart`, `products_inventory_screen.dart`, `product_details_screen.dart` | `flutter test` +121 passed: `product_rules_test.dart`, `intake_form_validation_test.dart`, `intake_queue_classification_test.dart`, `inventory_queue_status_test.dart` ("queued, retrying and needs-attention pieces are never rendered as \"Available\""); audit `SA-AUD-T16/T17/T18/T25 (fixed)` | Ship a new app build |
| SA-RT-001 | P0 | **Fixed** | `data/realtime/seller_live_store.dart` (new), `presentation/common/live_refresh.dart` (new), `data/realtime/seller_order_realtime.dart` (deleted), `main.dart`, dashboard/kanban/inventory/payments screens | `seller_live_store_test.dart`: "a payment_attempts event bumps the revision and the payment counts without a manual refresh", "Orders (All Drops) reloads on a live order event", "Payments tab badge and queue update from a payment_attempts event without a refresh", "verifying a payment invalidates every tab immediately" | Ship a new app build |
| SA-AND-001 | P0 | **Fixed — live** (CI, 2026-10-04) | `seller-app/android/app/build.gradle.kts` (release signing from `key.properties`/env, `GradleException` otherwise), `scripts/build-seller-apk.ps1`, `.github/workflows/seller-app-ci.yml` (release job, certificate check), `docs/ops/android-release-signing.md` | Not run: no release build was produced here and the CI release job has not executed (needs owner secrets) | Create and back up the upload keystore; add `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` and `vars.ANDROID_RELEASE_CERT_SHA256`; confirm the first release job on main; move testers off debug-signed builds |
| SA-PAY-006 | P1 (alongside) | **Fixed** (deploy pending) | 035 refund path for late advance on a resold piece | `PASS 13.7 late advance, piece gone -> success=true … refund=required/25000`; `PASS 19.6` | Apply 035 |
| SA-PAY-018 | P1 (alongside) | **Fixed** (deploy pending) | 035: `prevent_finalized_order_deletion()` SECURITY DEFINER, pinned search_path, refuses orders with ledger rows or a refund status | `PASS 17.1 seller DELETE of a refund-owed order … ERR P0001 … verified ledger rows before=1 after=1`; `PASS 17.2`, `17.3` (unchanged), `PASS 19.8`, `PASS 19.9h` | Apply 035; hosted H13 |
| SA-INT-002 | P1 (alongside) | **Fixed** (deploy pending) | 035: lock order orders → payment_attempts → products in verify, reject, close_drop; SKIP LOCKED in reaper and lazy expiry | `PASS 14.3 no deadlock; reaper left the claimed order alone and the seller's verification succeeded`; `PASS 14.4 no deadlock …` (stable over two extra runs) | Apply 035 |
| SA-CI-001 | P1 (partial) | **Partially fixed** | `.github/workflows/seller-app-ci.yml`: `FLUTTER_VERSION: "3.41.6"` pinned | Not run in CI yet; local toolchain is the same 3.41.6 | Remaining parts of SA-CI-001 are still open |

## Owner actions, in order

1. Apply migrations **034**, then 035 and 036, to staging, then production (034 first: SA-SEC-001 is live on hosted).
2. Run `audit/seller-app/tests/sql/90_hosted_readonly_checks.sql` H1–H20 (read-only). Pay attention to H1/H14 (views), H8/H17/H18 (reaper), H10/H11/H15/H20 (data already affected).
3. Enable pg_cron if 036 logged that it could not schedule, and re-run 036.
4. Rotate the leaked staging seller password (`docs/ops/credential-rotation-runbook.md`).
5. Create the release keystore and GitHub secrets (`docs/ops/android-release-signing.md`).
6. Open item outside this change: `scripts/verify-schema.mjs` still expects 17 paisa columns; 035 adds `refund_amount_paisa`, so it should be 18.


## Live verification (2026-10-04)

| Finding | Evidence |
|---|---|
| SA-SEC-001 | [Database Deploy run 37186682317](https://github.com/psuvraneel-cyber/LiveDrop/actions/runs/37186682317) (apply): 034 applied; H1 `anon`/`authenticated` = `SELECT` only on `public_seller_storefronts`; H14 write privileges on public views = 0; "PASS security checks (H1/H14/H16)". |
| SA-OPS-001 | Same run: 035 and 036 applied; pg_cron 1.6.4; job `livedrop-release-expired-holds` schedule `* * * * *` active; "PASS reaper schedule (H17)". H11/H15/H20 = 0 (no orders damaged by the pre-035 defects). |
| SA-PAY-001…005, SA-PAY-006, SA-PAY-018, SA-INT-002 | Migration 035 applied by the same run; H16 function-privilege matrix PASS. |
| SA-AND-001 | [Seller App CI run 37187572362](https://github.com/psuvraneel-cyber/LiveDrop/actions/runs/37187572362) on main: "Signed release (AAB + APK)" passed: APK Signature Scheme v2 verified, single signer, certificate SHA-256 matches `vars.ANDROID_RELEASE_CERT_SHA256`, not the debug certificate, not debuggable. |
| SA-SEC-002 | Staging seller account deleted by the owner (credential no longer usable); gitleaks passes on new commits. Remaining owner checks: Auth-log review since 2026-09-26, token in commit `0dd7c3f`, GitHub push protection. |
