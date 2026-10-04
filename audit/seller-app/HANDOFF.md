# Seller-app remediation — handoff (2026-10-04, updated after the 038–040 deploy)

Read this first in a new session, then `REMEDIATION-LOG.md` (what is fixed and the proof) and
`FINDINGS.json` (all 95 audit findings with remediation and regression tests).

## Where things stand
- **All 11 P0 (must-fix) findings are fixed.** Live proof is in `REMEDIATION-LOG.md`.
  - Database migrations 034–036 applied to the hosted project via the **Database Deploy** workflow.
  - The pg_cron reaper runs every minute.
  - The signed release build passes and is verified against the upload-key fingerprint.
- **P1 round 1 is merged (PR #14):**
  - SA-PAY-007: 30-minute claim hold during a live.
  - SA-PAY-008: one free-shipping rule.
  - SA-AUTH-001: password-reset page at `/seller/reset-password`.
  - SA-SHIP-001: the shipping shortcut no longer generates a fake AWB.
  - SA-OFF-001: durable intake queue.
  - SA-PAY-006, SA-PAY-018, SA-INT-002, SA-OFF-003 and SA-CQ-001 were fixed alongside the P0s.
- **P1 round 2 (migration 038, this branch):**
  - SA-SEC-003: only approved sellers can upload product images.
  - SA-SEC-008: nobody can list the image bucket except their own folder.
  - SA-ONB-002: suspending a seller closes their live drops; checkout and new payment requests return `SELLER_SUSPENDED`.
  - SA-PAY-011: UTRs are normalised; a UTR verified on one order cannot pay for another.
  - Proof is in `REMEDIATION-LOG.md` (P1 round 2).
- **P1 round 3 (PR #17, merged):** SA-ORD-001/002/003. Order times are shown in local time, WhatsApp keeps +91, and names with double spaces no longer crash the order screen.
- **P1 round 4a (migration 039):**
  - SA-AUTH-002/003/004
  - SA-SEC-004
  - SA-DROP-001/002/004
  - SA-INV-001/002
  - SA-PAY-012
  - Owner decisions: ADR-014 (undo an offline sale within 30 minutes), drop status changes exactly as the spec says, 10-character passwords, email confirmation on.
  - Proof is in `REMEDIATION-LOG.md` (P1 round 4a).
- **P1 round 4b (app only):** SA-PAY-009/010/013, SA-ORD-004/005, SA-SHIP-002, SA-UX-002. Payment card facts, reject with keep-hold, reminders with the order link, Closed tab, server-matched order buttons, labels only when fully paid, and no placeholder controls. Proof is in `REMEDIATION-LOG.md` (P1 round 4b).
- **P1 round 4c (migration 040):** SA-RT-002 (paused banner), SA-PERF-001 (300-order cap, `seller_sales_summary`), SA-CI-001 (`db-tests.yml`), SA-TEST-001 (audit suites in CI). This completes the owner's 21-item batch.

## Owner decisions (binding)
- An unverified UTR claim holds a piece **30 min while the drop is live**, 24 h otherwise. After that the piece returns to sale and the claim stays in the queue as a late claim. It is never expired.
- Free-shipping threshold: **drop value → shop value → none** (no hidden ₹2,000 default).
- Password reset happens on the **website page** (`https://livedrop-in.vercel.app/seller/reset-password`), using a token_hash link.
- The project "LiveDrop Staging" is used as **production**. A separate free staging project is recommended but not yet created.
- Distribution is through the **Google Play Store** with Play App Signing. CI signs with the upload key (secrets `ANDROID_*`, var `ANDROID_RELEASE_CERT_SHA256`).
- Improvements and the redesign only start **after all P0/P1 blockers are fixed**.

## Live state (checked 2026-10-04)
- All code from rounds 1–4c is on `main` (PRs #14–#18, #21; #19/#20 were merged into stacked branches and brought to `main` by #21).
- Database Deploy run 37207948510 (apply) put migrations 034–040 live and recorded them in the migration history. Post-checks H21, H22, H24 and H25 passed.
  - 038's one-time repair closed 1 live drop of a seller who was not approved.
- Supabase Auth, set by the owner on 2026-10-04:
  - custom SMTP (Gmail);
  - email rate limit;
  - Reset Password template (`token_hash` link to `/seller/reset-password`) and redirect URL;
  - minimum password length 10;
  - **Confirm email** on.

## Waiting on the owner
1. Build the seller app from `main` and install it. Most fixes from rounds 3–4c are in the app. On the phone, check:
   - change the UPI ID (password prompt; if it always says "confirm your password again", the hosted JWT has no `amr` password entry: tell the next session);
   - Mark Sold, then Undo;
   - reject a claim with "Ask buyer to fix";
   - print a label for a fully paid order;
   - a closed drop offers "New drop";
   - password reset email end to end.
2. Check which seller's live drop 038 closed (SA-ONB-002 repair) and whether that seller should be approved.
3. SA-SEC-002:
   - Review the Auth logs since 2026-09-26.
   - Check whose token is in commit `0dd7c3f` (`scratch/test-jwt.mjs`).
   - Enable GitHub Push protection.
4. Review the shop and drop free-shipping thresholds in the app (old rows were silently 200000).
5. Finish Firebase setup (SA-OBS-001 / SA-NOT-001). The project `livedrop-eaf3d` and Android app are created; round 5 code is in the repo. Remaining steps are in `REMEDIATION-LOG.md` (P1 round 5, owner actions): Database Deploy for 041, the `FCM_SERVICE_ACCOUNT` Supabase secret, GitHub secrets `GOOGLE_SERVICES_JSON` + `SUPABASE_ACCESS_TOKEN`, and deploying `push-dispatch`.

## Next blockers (P1), in agreed order
- **Needs an owner account first:**
  - SA-OBS-001 crash reporting (Sentry or Firebase Crashlytics).
  - SA-NOT-001 push notifications (a Firebase project).
- **Then the remaining MEDIUM P1 items**, listed in `REMEDIATION-LOG.md` and `FINDINGS.json` (priority P1, not yet fixed).
  - All SQL-proven P1 FINDINGs are now fixed. The harness still prints only the P2 items 12.3 (SA-INV-003) and 13.9 (SA-PAY-015).
  - Not yet done for SA-PAY-011: the seller card does not show "UTR already claimed on order X".

## How to work in this repo
- **Database tests:**
  - Setup: `audit/seller-app/tests/sql/run_local_db_audit.sh` on a throwaway PostgreSQL 16, with `PGHOST`/`PGPORT`/`PGUSER` set (see `audit/seller-app/README.md`).
  - On the owner's Windows PC (no PostgreSQL, WSL or Docker): unzip EnterpriseDB's `postgresql-16.x-windows-x64-binaries.zip` into the session scratchpad. Then run `initdb -U postgres -A trust` and `pg_ctl -o "-p 55432" start`, and run the harness from Git Bash with `PGHOST=localhost PGPORT=55432 PGUSER=postgres`.
  - Strip local absolute paths from `evidence/` before committing.
  - Expect every migration to PASS and no new FINDING lines.
- **App checks:** in `seller-app`, run `flutter analyze` and `flutter test`. Run the audit tests with `audit/seller-app/tests/flutter/run_flutter_audit_tests.sh`.
- **Website checks:** in `buyer-web`, run `npm ci && npm test && npx tsc --noEmit && npm run lint`.
- **Deploying database changes:**
  - Add a new migration `0NN_*.sql`.
  - Extend `.github/workflows/db-deploy.yml` and `scripts/db-deploy/*.sql`.
  - After merge, the owner runs Database Deploy (check-only first, then apply).
- **Follow AGENTS.md:**
  - Never weaken RLS.
  - Pin `search_path` on SECURITY DEFINER functions.
  - Use integer paisa.
  - Use RPCs for state changes.
  - Update the docs and the RTM.
