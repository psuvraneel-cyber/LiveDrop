# Seller-app remediation — handoff (2026-10-04, updated after P1 round 2)

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

## Owner decisions (binding)
- An unverified UTR claim holds a piece **30 min while the drop is live**, 24 h otherwise. After that the piece returns to sale and the claim stays in the queue as a late claim. It is never expired.
- Free-shipping threshold: **drop value → shop value → none** (no hidden ₹2,000 default).
- Password reset happens on the **website page** (`https://livedrop-in.vercel.app/seller/reset-password`), using a token_hash link.
- The project "LiveDrop Staging" is used as **production**. A separate free staging project is recommended but not yet created.
- Distribution is through the **Google Play Store** with Play App Signing. CI signs with the upload key (secrets `ANDROID_*`, var `ANDROID_RELEASE_CERT_SHA256`).
- Improvements and the redesign only start **after all P0/P1 blockers are fixed**.

## Waiting on the owner
1. Run **Actions → Database Deploy** in `apply` mode (after the round-2 PR is merged). This puts migrations 037 and 038 live.
   - If check H21 fails, the deploy role could not change the storage policies. Run section 1 of `038_storage_suspension_and_utr_guards.sql` in the Supabase SQL editor, then re-run apply.
   - If 038 logged that it skipped the normalised-UTR index, review H22 and re-run apply.
2. Set up custom SMTP in Supabase (Gmail app password, `smtp.gmail.com:465`).
3. Raise the email rate limit.
4. Edit the Reset Password email template to link to `https://livedrop-in.vercel.app/seller/reset-password?token_hash={{ .TokenHash }}&type=recovery`.
5. Add that URL to Auth → URL Configuration → Redirect URLs.
6. SA-SEC-002:
   - Review the Auth logs since 2026-09-26.
   - Check whose token is in commit `0dd7c3f` (`scratch/test-jwt.mjs`).
   - Enable GitHub Push protection.
7. Review the shop and drop free-shipping thresholds in the app (old rows were silently 200000).

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
