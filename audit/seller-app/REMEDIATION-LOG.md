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
| SA-SEC-001 | P0 | **Fixed — live** (hosted DB, 2026-10-04) | `supabase/migrations/034_lock_down_public_view_privileges.sql`: views SELECT-only for client roles, default privileges tightened, TRUNCATE/REFERENCES/TRIGGER revoked; RLS untouched | `PASS 10.3 anon UPDATE through view denied: permission denied for view public_seller_storefronts`; `PASS 10.4`, `PASS 10.5`, `PASS 10.9 anon/authenticated hold SELECT only on every view in public`; `PASS 19.20a/b/c` (`run_local_db_audit.console.txt`) | Done 2026-10-04 — see "Live verification" below; pre-deployment proof above is historical |
| SA-SEC-002 | P0 | **Partially fixed** | `.github/workflows/secret-scan.yml`, `.gitleaks.toml` (gitleaks on new commits, redacted); `docs/ops/credential-rotation-runbook.md` | gitleaks passed on PRs #10–#12 and on main. Previously: the workflow has not executed yet. Cross-check secrets scan of diff + untracked files found no credentials | Done by owner on 2026-10-03: the leaked staging seller account was deleted, so the exposed login no longer works. Remaining: review Auth logs/data since 2026-09-26; decide on a history purge; confirm the first gitleaks run passes |
| SA-PAY-001 | P0 | **Fixed** (deploy pending) | `035_payment_claim_safety_and_refunds.sql`: `verify_manual_upi_payment` via `apply_upi_payment_transition`; ledger invariant | `PASS 13.5c late advance verified -> order confirmed/advance_paid … total_paid=25000 … balance_due=225000`; `PASS 19.4`, `PASS 19.4b`, `PASS 19.21 ledger invariant holds for 22 of 22 orders` | Apply 035; review orders listed by hosted H11 (already damaged, not rewritten) |
| SA-PAY-002 | P0 | **Fixed** (deploy pending) | 035: late path locks products `ORDER BY id`, status-predicated updates with row-count check | `PASS 14.2 … order Y keeps the piece (no overwrite)`; `PASS 14.2b exactly one live paid order owns #A02`; `PASS 13.6`, `PASS 19.5` | Apply 035 |
| SA-PAY-003 | P0 | **Fixed** (deploy pending) | 035: `release_expired_holds` skips claimed orders/attempts, SKIP LOCKED; claimed attempts verifiable after window. App: overdue labelling (`pending_verifications_screen.dart`, `models.dart`) | `PASS 13.8 … attempt=awaiting_seller_verification … still in seller queue=1 \| verify afterwards -> success=true`; `PASS 19.11`, `PASS 19.12`; Flutter `payments_refunds_test.dart` "Overdue claims (SA-PAY-003) …" | Apply 035; reconcile claims listed by hosted H20 with sellers |
| SA-PAY-004 | P0 | **Fixed** (deploy pending) | 035: `orders.refund_*` columns + constraints + index, `record_refund` RPC, backfill of 023 notes. App: Refunds owed list, Mark refunded, refund dialog (`seller_repository.dart`, `pending_verifications_screen.dart`, `seller_dashboard_screen.dart`, `seller_error_messages.dart`) | `PASS 13.6 … refund_status=required refund_amount=158000 reason=LATE_PAYMENT_INVENTORY_UNAVAILABLE`; `PASS 19.5`, `19.5b`, `19.7`, `19.9a`–`19.9h`, `19.17`; Flutter `payments_refunds_test.dart` "Refunds owed …", "verify response with refund_required=true shows a blocking refund dialog"; audit `SA-AUD-T20 (refund part fixed)` | Apply 035; review refunds owed per drop with hosted H15 |
| SA-OPS-001 | P0 | **Fixed — live** (hosted DB, 2026-10-04) | 035: lazy expiry in `create_order_with_reservation` via `release_stale_hold`; `036_schedule_reaper_in_database.sql` (pg_cron, guarded); `.github/workflows/reaper-cron.yml` comment: backup trigger only | `PASS 19.1 checkout of a piece behind an expired, unclaimed hold -> success=true`; `PASS 19.2`; `PASS 19.3`; `PASS 14.5 lazy expiry released the stale hold once; exactly one racer reserved the piece`; `PASS 19.18 pg_cron not available here: 036 applied as a no-op`. 036 scheduling run twice against a stub `cron` schema left exactly one job (no real pg_cron tested) | Done 2026-10-04 — see "Live verification" below; pre-deployment proof above is historical |
| SA-PAY-005 | P0 | **Fixed** (deploy pending) | 035: `force_release_hold` → `PAYMENT_CLAIM_PENDING`; `close_drop` and `reject_manual_upi_payment` keep claimed holds; data repair to `late_claim_pending_review`. App: Release hidden while a claim exists, friendly message (`order_card.dart`, `kanban_board_screen.dart`, `seller_error_messages.dart`) | `PASS 16.1b force_release_hold with a claim in flight -> PAYMENT_CLAIM_PENDING`; `PASS 16.1c`, `PASS 16.2`, `PASS 19.10a`–`c`, `PASS 19.15`; Flutter `order_card_release_test.dart` "PAYMENT_CLAIM_PENDING becomes a friendly message" | Apply 035 |
| SA-INT-001 | P0 | **Fixed** | `core/validation/product_rules.dart`, `core/services/intake_error_classifier.dart`, `core/services/offline_intake_queue.dart` (needsAttention, updateItem/discardItem/retryItem, 23505 reconciliation), `presentation/intake/intake_draft_fields.dart`, `camera_intake_screen.dart`, `products/queued_piece_editor.dart`, `products_inventory_screen.dart`, `product_details_screen.dart` | `flutter test` +121 passed: `product_rules_test.dart`, `intake_form_validation_test.dart`, `intake_queue_classification_test.dart`, `inventory_queue_status_test.dart` ("queued, retrying and needs-attention pieces are never rendered as \"Available\""); audit `SA-AUD-T16/T17/T18/T25 (fixed)` | Ship a new app build |
| SA-RT-001 | P0 | **Fixed** | `data/realtime/seller_live_store.dart` (new), `presentation/common/live_refresh.dart` (new), `data/realtime/seller_order_realtime.dart` (deleted), `main.dart`, dashboard/kanban/inventory/payments screens | `seller_live_store_test.dart`: "a payment_attempts event bumps the revision and the payment counts without a manual refresh", "Orders (All Drops) reloads on a live order event", "Payments tab badge and queue update from a payment_attempts event without a refresh", "verifying a payment invalidates every tab immediately" | Ship a new app build |
| SA-AND-001 | P0 | **Fixed — live** (CI, 2026-10-04) | `seller-app/android/app/build.gradle.kts` (release signing from `key.properties`/env, `GradleException` otherwise), `scripts/build-seller-apk.ps1`, `.github/workflows/seller-app-ci.yml` (release job, certificate check), `docs/ops/android-release-signing.md` | Not run: no release build was produced here and the CI release job has not executed (needs owner secrets) | Done 2026-10-04 — see "Live verification" below; pre-deployment proof above is historical |
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

## P1 round 1 (2026-10-04) — owner decisions: 30-minute live claim hold, drop→shop shipping threshold, reset page on the website

| Finding | Status | What changed | Proof | Owner actions |
|---|---|---|---|---|
| SA-PAY-007 | Fixed (deploy pending) | 037: claim on a pending order holds 30 min while the drop is live (24 h otherwise); re-submitting a UTR keeps the original window; after expiry the order is released and the claim moves to `late_claim_pending_review` (stays in the queue, verifiable via the late path) | Suite 13: PASS 13.2, 13.8, 13.8b, 13.14a/b; suite 19: PASS 19.11, 19.12, 19.22a–d, 19.23; 14.7 PASS (4/4) | Run Database Deploy (apply) |
| SA-PAY-008 | Fixed (deploy pending) | 037 `resolve_free_shipping_threshold`: drop → shop → none, used by checkout; column defaults dropped; buyer-web single helper (`src/lib/checkout/shipping.ts`); app helper `free_shipping_rules.dart`, shop threshold editable in Settings | PASS 13.10a–d; buyer-web 687/687; app tests `free_shipping_rules_test.dart`, `free_shipping_settings_test.dart` | Run Database Deploy (apply); review shop/drop thresholds in the app |
| SA-AUTH-001 | Fixed in repo — owner action required | buyer-web `/seller/reset-password` (token_hash recovery, noindex, no-referrer); app sends `redirectTo` to it | `seller-reset-password.test.tsx`; `password_reset_test.dart` | Supabase: add redirect URL and change the Reset Password email template |
| SA-SHIP-001 | Fixed | Dashboard shortcut opens the Ready-to-ship list; no placeholder/“Auto” AWB; dispatch requires courier + valid tracking + confirmation; labels never invent an AWB | Audit T08 inverted and passing; `shipping_dispatch_test.dart` | — |
| SA-OFF-001 | Fixed (device check pending) | Queue in app support dir with migration from the old temp location; atomic manifest writes + `.bak`; corrupt manifest quarantined and recovered; queue processed at start and on resume | Audit T14/T19 inverted and passing; `offline_intake_queue_durability_test.dart` | Install the next build on a phone and confirm queued photos survive "Clear cache" |

Totals after this round: DB harness 87 PASS (37 migrations), remaining FINDING 11.5b, 12.3, 12.7, 13.3c, 13.9, 18.1 (all not yet addressed); flutter analyze clean, flutter test 161/161, audit Flutter 26/26; buyer-web 687/687, tsc and lint clean.

## P1 round 2 (2026-10-04) — migration 038: storage, suspension, duplicate UTRs

Local test database: PostgreSQL 16.10 (portable Windows binaries, throwaway cluster). Evidence paths in `evidence/` are now repo-relative.

| Finding | Status | What changed | Proof | Owner actions |
|---|---|---|---|---|
| SA-SEC-003 | Fixed (deploy pending) | 038: `product_images_seller_insert` / `_update` also require `is_seller_approved(auth.uid())` | PASS 11.5b (unapproved upload rejected), 11.5c (approved seller still uploads), 20.32 | Run Database Deploy (apply); if H21 fails, run section 1 of 038 in the Supabase SQL editor |
| SA-SEC-008 | Fixed (deploy pending) | 038: `product_images_public_read` dropped; `product_images_seller_read` lets a seller list only their own folder (needed for upsert). Public object URLs keep working | PASS 18.1 (anon lists 0 objects), 18.1b, 18.1c, 20.31 | As above. Then run the HTTP probe at the end of `tests/sql/90_hosted_readonly_checks.sql`: it should return `[]` |
| SA-ONB-002 | Fixed (deploy pending) | 038: trigger on `profiles` closes live drops when approval is revoked (SQL update or `admin_approve_seller`), using `close_drop_safely` (`close_drop` refactored onto it). Checkout and `initiate_payment_attempt` return `SELLER_SUSPENDED`. Claims and verification still work; buyer-web knows the code. One-time repair closes live drops of sellers suspended before 038 (tested: before=live, after=closed; approved seller's drop untouched) | PASS 12.7, 20.10–20.20, 20.30, 20.34; buyer-web `data-layer.test.ts` | Run Database Deploy (apply); H23 should list no live drop of an unapproved seller |
| SA-PAY-011 | Fixed (deploy pending) | 038: `normalize_payment_reference` (no spaces, upper case) at claim and verify; a UTR already verified elsewhere is refused at claim time; unique index on the normalised verified reference | PASS 13.3c, 20.1–20.7, 20.33 | Run Database Deploy (apply); review H22 (should be empty). If 038 warned that the index was skipped, resolve those duplicates and re-run apply |

Also in this round:
- The harness now also runs `2*.sql` suites, including the new suite 20.
- The deploy workflow applies 038 and records it in the migration history.
- `post_checks.sql` adds H21/H22 (strict: H21 fails the apply run if the storage policies were refused).
- `90_hosted_readonly_checks.sql` adds H21–H23.
- Docs updated: `12-database-design.md` §6, `13-api-contract.md`, `16-security-architecture.md` §3.2–3.3, RTM row REQ-AUD-SA-03.

Not done in this round (same findings): there is no "UTR already claimed on order X" hint on the seller's verification card. The same UTR claimed but not verified on two orders is still accepted (INFO 13.3a); verification refuses the second one.

Totals after this round:
- DB harness (38 migrations): 117 PASS, 0 FAIL. Remaining FINDINGs: 12.3 (SA-INV-003) and 13.9 (SA-PAY-015), both P2.
- 038 re-applied twice cleanly. The refused-policy path was simulated (WARNING, no rollback of the rest).
- buyer-web: 688/688 tests, tsc clean, lint clean.
- No Dart code changed this round.

## P1 round 4a (2026-10-04): migration 039, account safety, drops and inventory

Owner decisions:
- Undo an offline sale within 30 minutes (ADR-014).
- Drop status changes exactly as docs/09 says.
- Passwords of at least 10 characters.
- Email confirmation for new sellers.

| Finding | Status | What changed | Proof | Owner actions |
|---|---|---|---|---|
| SA-AUTH-002 | Fixed | `main.dart`: the shell waits for the profile; a load error shows "Could not load your boutique" with Try again / Sign out. The dashboard shows only for a loaded, approved profile, and the intake queue never syncs without one | Audit T07 inverted (gate stays closed) | Ship a new app build |
| SA-AUTH-003 | Fixed in repo; owner action required | Minimum 10 characters in the app (registration), on the website reset page and in `config.toml`; `enable_confirmations = true`. The login screen explains an unconfirmed email | buyer-web `seller-reset-password.test.tsx` (10 characters) | Supabase → Auth → Providers → Email: Minimum password length 10, turn on **Confirm email** |
| SA-AUTH-004 | Fixed (deploy pending) | 039: `upi_id`, `upi_vpa` and `phone_number` changes need a password sign-in in the last 10 minutes (JWT `amr`, hint `REAUTH_REQUIRED`); every payee change goes to `payee_change_log`. App: password dialog showing the new UPI ID, live-drop warning, recent changes list; the phone edit needs the password too | SQL 21.30–21.34, 21.41; `account_drops_inventory_test.dart` (password before save, wrong password saves nothing, unchanged UPI ID asks nothing) | Run Database Deploy (apply); ship a new app build. After deploy, change the UPI ID once in the app to confirm the password step works on hosted |
| SA-SEC-004 | Fixed | `image_service.dart` clears EXIF before encoding (orientation is already applied by decode) | Audit T23 inverted: no Make, no GPS, empty EXIF | Ship a new app build. Photos already uploaded keep their EXIF |
| SA-DROP-001 | Fixed (deploy pending) | 039 trigger: only draft→live and live→closed. App: "Re-open Draft" replaced by "New drop"; close dialog explains what happens | SQL 12.5, 12.4b (now PASS), 21.1–21.2; widget test (closed drop shows "New drop") | Run Database Deploy (apply) |
| SA-DROP-002 | Fixed (deploy pending) | 039 trigger: slug locked once the drop leaves draft. App: read-only link field with a lock note | SQL 12.4c (PASS), 21.3–21.4; widget test (read-only field) | Run Database Deploy (apply) |
| SA-DROP-004 | Fixed | Go-live checklist. It blocks with no piece on sale, unfinished uploads (ADR-006), UPI off or no UPI ID, or another live drop. A missing stream link is only a warning. Also shows a copy-link button | `account_drops_inventory_test.dart` (readiness rules; Go Live is blocked with nothing on sale) | Ship a new app build |
| SA-INV-001 | Fixed (deploy pending) | 039: `sold_offline_at`, `undo_mark_product_sold_offline` (ADR-014; docs/09 amended). App: no Mark Sold on reserved pieces (with the reason shown), confirm dialog, "Undo" on the snackbar and button for 30 minutes, friendly errors | SQL 21.20–21.27; widget tests (reserved, confirm then undo, no undo after 30 min) | Run Database Deploy (apply) |
| SA-INV-002 | Fixed | `DropRules.intakeTarget` (live, else draft, never closed) in the shell and inventory. Camera intake is disabled on closed drops and shows "Adding to: <drop> · LIVE/DRAFT". Saving into a closed drop is refused | `account_drops_inventory_test.dart` (DropRules; closed drop has no camera intake) | Ship a new app build |
| SA-PAY-012 | Fixed (deploy pending) | 039: checkout returns `UPI_DISABLED` / `UPI_NOT_CONFIGURED` before reserving. Payment settings warns while a drop is live; the go-live checklist blocks with UPI off | SQL 13.13 (PASS), 21.10–21.11 | Run Database Deploy (apply) |

Totals:
- DB harness (39 migrations): 0 FAIL. Remaining FINDINGs: 12.3 and 13.9, both P2.
- Suite 21: 21/21. 039 re-applied twice cleanly; post-checks H24 PASS.
- `flutter analyze` clean. `flutter test`: 188 pass, 2 fail, and those 2 fail only on Windows (temp-folder lock in `inventory_queue_status_test.dart`, unrelated).
- Audit Flutter suite 26/26.
- buyer-web: all tests pass.

## P1 round 4b (2026-10-04): payments, orders, labels, placeholder controls (app only, no migration)

| Finding | Status | What changed | Proof | Owner actions |
|---|---|---|---|---|
| SA-PAY-009 | Fixed | The claim card shows: payment type ("Full / Advance / Balance payment of ₹total"), piece codes and photo, buyer phone, time left with what happens after it, the late-claim consequence (piece still free: verifying confirms the order again; piece sold: verifying records a refund owed), and "Buyer claimed at" instead of a mislabelled "Paid on". The confirm dialog names the type, pieces and UTR. The fake screenshot is removed. The claim query embeds buyer phone, order status, total, token and pieces | Audit T09, T12, T13 inverted; `payments_orders_labels_test.dart` | Ship a new app build |
| SA-PAY-010 | Fixed | Reject offers "Ask buyer to fix (keep piece)" (`releaseHold: false`) and "Reject & release piece". Late claims only offer reject. After a keep-hold reject, "Message buyer" sends the buyer their order link to resubmit the UTR | Audit T11 inverted; widget tests | Ship a new app build |
| SA-PAY-013 | Fixed | `PaymentReminder`: the amount actually due (advance, full or balance) and the buyer's own order link; never the raw UPI ID. Orders now load `order_token` | Unit tests for the advance / full / balance / no-token messages | Ship a new app build |
| SA-ORD-004 | Fixed | Kanban "Closed" tab (cancelled / expired), with the reason on each card (refund owed, refunded, advance kept, released). Closed orders no longer appear under "Paid" | Audit T20 fully fixed; widget test (refund-owed card) | Ship a new app build |
| SA-ORD-005 | Fixed | `OrderActions` derives buttons the way the server allows: pending → pay link and Release (no claim); advance paid → "Ask for balance"; paid → "Mark packed"; packed → Dispatch and label; shipped → reprint. The order details primary button follows the same rules | Audit T03, T21 inverted; table-driven unit test | Ship a new app build |
| SA-SHIP-002 | Fixed | A label can be generated only for a fully paid order (`LABEL_NOT_ALLOWED` otherwise), so PREPAID is never printed with a balance due. The barcode is drawn only for a real AWB. The fake "Routing" line is removed. Times are local (round 3) | Unit tests (blocked reasons, generation refused, barcode only with AWB) | Ship a new app build |
| SA-UX-002 | Fixed | Removed or made real: Remarks field (removed), screenshot (removed), notification switches (honest "not available yet" until SA-NOT-001), haptics switch (really turns vibration off, remembered on the phone), "Clear image memory" (really clears it; the intake queue is untouched), "Remember me" (removed; the session is always kept), "Active Verified Boutique" (now from the profile), duplicate "Save PDF" button (merged), fake profile `+91 9999999999` in Orders (removed), support phone from `AdminConfig` | Audit T10 inverted; haptics unit test | Ship a new app build |

Totals:
- `flutter analyze` clean.
- `flutter test`: 210 pass, 2 fail, and those 2 fail only on Windows (temp-folder lock in `inventory_queue_status_test.dart`).
- Audit Flutter suite 26/26.
- No database change.

## P1 round 4c (2026-10-04): reliability, download size, tests in CI (migration 040)

| Finding | Status | What changed | Proof | Owner actions |
|---|---|---|---|---|
| SA-RT-002 | Fixed | The live store already reconnects, catches up after a reconnect or resume, polls while the channel is down and debounces bursts (P0 round, ADR-013). The remaining gap was that the seller could not tell: the shell now shows "Live updates paused: reconnecting…" while the channel is down and hides it on reconnect | `reliability_test.dart` (banner appears on drop, disappears on reconnect, catch-up runs) | Ship a new app build |
| SA-PERF-001 | Fixed (deploy pending for analytics) | Order lists ask for the newest 300 orders at most, with a note on the Orders screen when capped; recent activity asks for 20. Migration 040 `seller_sales_summary(p_from, p_utc_offset_minutes)` (SECURITY INVOKER, RLS-scoped, sellers only) returns revenue, items, holds, 7 local days and top products. The app uses it and falls back to the local computation until 040 is deployed | Suite 22 (22.1–22.7); suite 15: 15.1b (300 orders, about 420 KB instead of about 2.8 MB), 15.1c (summary about 1.5 KB); `reliability_test.dart` | Run Database Deploy (apply); check H25 |
| SA-CI-001 | Fixed | New workflow `db-tests.yml`: every PR touching migrations, SQL tests or deploy scripts applies all migrations to a PostgreSQL 16 service and runs every audit suite plus the post-deploy checks. It fails on any FAIL, ERROR, failed migration, or FINDING outside the known open list (12.3, 13.9). Flutter was already pinned and gitleaks already runs | Local dry run of the result check (known findings pass, an unlisted finding fails) | None |
| SA-TEST-001 | Fixed | The SQL audit suites run in CI (above). Seller App CI also runs the audit Flutter suite (`run_flutter_audit_tests.sh`). Rounds 4a–4c added app tests for money (claims, refunds, labels, reminders), stock (Mark Sold / undo, intake target), login (approval gate, re-auth, passwords) and order states | CI jobs; `account_drops_inventory_test.dart`, `payments_orders_labels_test.dart`, `reliability_test.dart` | None |

Totals:
- DB harness (40 migrations): 152 PASS, 0 FAIL. Remaining FINDINGs: 12.3 and 13.9, both P2.
- Post-checks H21–H25 PASS. 040 re-applied twice cleanly.
- `flutter analyze` clean. `flutter test`: 212 pass, 2 fail, and those 2 fail only on Windows.
- Audit Flutter suite 26/26.

## Live verification, rounds 2–4c (2026-10-04)

| Item | Evidence |
|---|---|
| Migrations 038, 039 | Database Deploy run 37206628912 (apply): H21 storage policies (public listing removed, uploads need an approved seller), H22 suspension trigger + normalised-UTR index, H24 drop lifecycle + payee guard/log + offline-sale undo, all PASS. The 038 repair closed 1 live drop of an unapproved seller |
| Migration 040 | Database Deploy run 37207948510 (apply): H25 `seller_sales_summary` sellers only, PASS; 034–040 recorded in `supabase_migrations.schema_migrations` |
| CI on `main` code | PR #21: Seller App CI (analyze, `flutter test`, audit Flutter 26/26) and `db-tests.yml` (all migrations + SQL suites on PostgreSQL 16) passed |
| SA-AUTH-001 / SA-AUTH-003 hosted settings | Set by the owner in Supabase Auth: custom SMTP, rate limit, reset template + redirect URL, minimum password length 10, Confirm email on (owner-reported; not readable from the repo) |
| App-side fixes | Not yet verified on a device; they need a new app build (see HANDOFF "Waiting on the owner") |

## P1 round 5 (2026-10-04): crash reporting and push notifications (migration 041, ADR-015)

| Finding | Status | What changed | Proof | Owner actions |
|---|---|---|---|---|
| SA-OBS-001 | Fixed in repo | Firebase Crashlytics via `AppLog`: uncaught errors reported, handled errors reported. 31 silent `catch (_)` blocks now log; haptics stay silent on purpose. Home, Products and Settings show a retry banner when loading fails | `crash_reporting_push_test.dart`; debug APK built with Firebase config processed | Add GitHub secret `GOOGLE_SERVICES_JSON` (contents of `android/app/google-services.json`) so CI and release builds include Firebase |
| SA-NOT-001 | Fixed in repo; owner setup required | 041: device tokens, preferences, `push_outbox` filled by order/claim triggers, service-only dispatcher API, pg_net wake-up + pg_cron backstop. Edge Function `push-dispatch` (FCM HTTP v1). App: permission prompt, token register/unregister, foreground display, tap routing, real switches in Settings | SQL suite 23 (8/8); Deno tests 3/3; Flutter tests | 1. Run Database Deploy (apply), check H26. 2. Firebase → Project settings → Service accounts → Generate new private key, then paste its JSON as Supabase Edge Function secret `FCM_SERVICE_ACCOUNT`. 3. Add GitHub secret `SUPABASE_ACCESS_TOKEN` and run "Deploy Edge Functions" (or `npx supabase functions deploy push-dispatch --no-verify-jwt`). 4. New app build; check a test order produces a notification |

Totals:
- DB harness (41 migrations): 160 PASS, 0 FAIL. Remaining FINDINGs: 12.3 and 13.9, both P2.
- `flutter analyze` clean. `flutter test`: 218 pass, 2 fail, and those 2 fail only on Windows.
- Audit Flutter suite 26/26. Deno tests 3/3.

## Live verification, round 5 (2026-10-05)
- Database Deploy run 37226127405 (apply, 034–041): post-checks H21, H22, H24, H25 and H26 passed. H26 reported `pg_net=t cron job=t`.
- The owner set the Supabase Edge Function secret `FCM_SERVICE_ACCOUNT`.
- The owner added the GitHub secrets `GOOGLE_SERVICES_JSON` and `SUPABASE_ACCESS_TOKEN`. The token is scoped to the LiveDrop Staging project with Edge Functions read-write and Project Settings read, and expires 2026-10-12.
- **Still open:** run **Deploy Edge Functions**, then do a test order on a phone running the app.

## P1 round 6 (2026-10-05): operator console, backups, app links (migration 042, ADR-016)

| Finding | Status | What changed | Proof | Owner actions |
|---|---|---|---|---|
| SA-OPS-002 | Fixed in repo | Website `/admin`: approve or suspend sellers (a reason is required to suspend; suspension closes live drops), list refunds owed, find an order, record a refund. Built on admin-only RPCs (042) that need a password sign-in within 10 minutes, with every action logged in `admin_actions`. No service-role key | SQL 24.1–24.6; `admin-console.test.tsx` (6) | After Database Deploy for 042, add yourself in the SQL editor: `INSERT INTO public.platform_admins (user_id, note) SELECT id, 'owner' FROM auth.users WHERE email = '<your e-mail>';` |
| SA-ONB-001 | Fixed in repo | The console shows each seller's onboarding-fee UTR (from sign-up), whether their email is confirmed, and pending, approved or suspended status, with the last suspension reason | SQL 24.2, 24.4 | — |
| SA-OPS-004 | Fixed in repo; owner setup required | `db-backup.yml`, nightly at 02:00 IST: encrypted `pg_dump` of `public` and of the auth accounts, plus a restore test that rebuilds from migrations and matches every row count; 30-day private artifact. The same restore test runs in `db-tests.yml` on every database PR. Restore guide: docs/40 | Local restore test: 13 tables, 15 rows, all counts match | Add the GitHub secret `BACKUP_PASSPHRASE` (keep it in your password manager), then run **Database Backup** once |
| SA-AND-003 | Fixed in repo | `livedrop-seller://open/<section>` opens the app on that tab (`AppLinkService`, `app_links`). The password-reset success page has an "Open the LiveDrop Seller app" button. Verified https App Links are left for after the Play release (they need the Play signing fingerprint) | `app_links_test.dart` (2); reset page test | — |
| SA-DB-001 | Closed | The Database Deploy post-checks (H21–H27) verify the hosted schema against the repo on every apply. Run 37226127405 passed | Run 37226127405 | — |

Also in this round:
- The audit harness now reports psql `ERROR`s from the suites, so CI fails on them. Previously a suite that errored part-way was silent.
- Test 22.4 seeded its "today" order an hour back, so it failed between 00:00 and 01:00 IST. It now uses one minute.

Totals:
- DB harness (42 migrations): 166 PASS, 0 FAIL. Remaining FINDINGs: 12.3 and 13.9 (P2).
- Post-check H27 PASS locally.
- buyer-web: `tsc` and `eslint` clean; vitest 52 files, 694 tests pass (plus the 6 new admin tests and the updated reset test).
- Seller app: `flutter analyze` clean. `flutter test`: 220 pass, plus the same 2 inventory_queue_status tests that fail only on Windows.


## Fix (2026-10-05): signed releases were built without Firebase
- Release 39 on the owner's phone (Mi 10i) showed no notification permission prompt and registered no push token.
- Cause: the `release-android` job never wrote `google-services.json`, so `AppLog.crashlyticsReady` was false and push and crash reporting stayed off. Only the debug job wrote it.
- Fix:
  - The release job now requires the `GOOGLE_SERVICES_JSON` secret and writes the file.
  - The build fails if the compiled release resources lack `google_app_id`.

## Fix (2026-10-05): checkout blocked when the seller has advance payments off
- **Found by:** the owner's end-to-end test. "Place Order & Hold Items" did nothing useful for a drop whose seller had advance confirmation off.
- **Cause:** buyer-web always sent `p_confirmation_mode = 'advance'`, so `create_order_with_reservation` answered `ADVANCE_CONFIRMATION_DISABLED`.
- **Fix:**
  - Checkout now sends the mode that matches the drop's setting, falling back to the seller's setting (`confirmationModeFor`, the same rule as the server).
  - The data layer retries once with `full_payment` on `ADVANCE_CONFIRMATION_DISABLED` or `ADVANCE_EXCEEDS_TOTAL`. That first request creates no order, and the retry reuses the same idempotency key.
- **Tests:** `checkout-confirmation-mode.test.ts` (4); buyer-web 698/698.

## Fix (2026-10-05): UPI apps declined LiveDrop payment links (migration 043, SA-PAY-015)
- **Found by:** the owner's end-to-end test. A ₹1 advance paid through the link or QR failed on two phones with "exceeded your account limit"; no money was debited.
- **Cause:** `generate_upi_payment_uri` put `tr=<reference>` in the link. `tr` is a merchant field in the UPI deep-link spec, and payer apps and banks decline merchant-style requests to personal UPI IDs, often showing a limit message.
- **Fix (043):**
  - The link is now the plain P2P form `pa, pn, am, cu, tn`.
  - The note carries the order code; the seller still verifies by UTR.
  - Name and note keep only letters, digits, spaces and dots, which also fixes SA-PAY-015 (`#`, `%`, `&` in store names). SQL 13.9 now passes, and 12.3 is the only remaining known FINDING.
- **Tests:** suite 25 (4/4); harness 43 migrations, 171 PASS, 0 FAIL; post-check H28.
- **Not verifiable without a real payment:** retest after Database Deploy. If an app still declines, the remaining causes are outside LiveDrop (see the owner note in PR).
- **Owner decision (2026-10-05):** no "pay to UPI ID" fallback. The seller's UPI ID stays hidden from buyers (REQ-BLK-1R). If apps still decline personal UPI IDs, sellers switch to a business UPI ID.

## Fix (2026-10-05): buyers can pay a personal UPI ID (migration 044, owner decision)
- **Diagnosis (on the owner's Mi 10i, over adb, no money moved):**
  - Google Pay and WhatsApp both open LiveDrop's payment link, then refuse it before any PIN:
    - Google Pay: "You've exceeded the bank limit for this payment";
    - WhatsApp: "Your money was not transferred".
  - The refusal happens with or without the amount and note, and as if opened from Chrome.
  - A payment the owner started manually in Google Pay to the same UPI ID went through.
  - Conclusion: UPI apps decline link- or QR-started payments to personal UPI IDs.
- **Owner decision:**
  - Keep the personal UPI ID; no merchant account, because of the merchant MDR: 0.4% above ₹2,000 from 2026-10-15, with small merchants under ₹1 lakh a month reportedly exempt.
  - Offer buyer-started payment methods, and show the UPI ID on the payment page. This revises REQ-BLK-1R.
- **Fix:**
  - The payment page now has:
    - **Option 1, Pay on WhatsApp:** opens the seller's chat with "I'm paying ₹X for LD-XXXXXX"; the buyer taps ₹ and pays.
    - **Option 2, Pay to the UPI ID:** UPI ID and amount with copy buttons, and the order code for the note.
    - The QR code and "Pay with UPI App" remain, with a note that some apps decline them.
  - 044 adds `whatsapp_number` (the public storefront phone) to `get_order_by_token`. A freshly created order fetches its receipt once to get it.
- **Tests:** SQL 25.5; harness 44 migrations, 172 PASS, 0 FAIL; post-check H29; buyer-web 699/699 (privacy tests updated to the new decision, plus WhatsApp and UPI ID tests).


## Fix (2026-10-06): Facebook Live video not showing on the drop page
- **Found by:** the owner's test.
- **Cause:** the drop's stream link was a Facebook **share link** (`facebook.com/share/v/…`), which the Facebook app's "Copy link" produces. Facebook's embed player cannot play share links and shows "Video unavailable". The full video address (`facebook.com/<page>/videos/<id>/`) plays fine; both were checked in a browser on the live drop.
- **Fix:**
  - **Seller app:** `StreamLinkResolver` follows the share link's redirect once when a drop is saved and stores the full address. If that fails, the seller is told how to copy the full link, and can still save.
  - **Website:** share links are not embedded. The page shows "Watch the live on Facebook" instead of a broken player.
- **Tests:**
  - `stream_link_resolver_test.dart` (5); a live check converted the owner's real share link.
  - `facebook-live-player.test.tsx`: new share-link test; buyer-web 700/700.
  - `flutter test`: 225 pass, plus the 2 Windows-only failures.
