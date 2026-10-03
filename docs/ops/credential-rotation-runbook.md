# Credential rotation runbook — leaked staging seller credential (SA-SEC-002)

Owner action required: yes. Nothing in this runbook can be done from the repository; it needs the
Supabase dashboard and GitHub repository settings.
Severity: CRITICAL / P0. Repository visibility: **public**.

> Rule for everyone working through this runbook: never paste the leaked value (or any new password,
> token or key) into an issue, pull request, chat, commit, CI log or this document. Refer to it as
> "the credential in commit 0abdaeb".

## 1. What leaked

| Item | Where | Status |
|---|---|---|
| Seller account e-mail + **password** for the Supabase project the seed script targets | commit `0abdaeb` (2026-09-26), file `scripts/seed-legitimate-staging-drop.mjs`, lines 13–14 | Removed from `HEAD` in `ebb80cd` (2026-10-03, script now reads `STAGING_SELLER_EMAIL` / `STAGING_SELLER_PASSWORD` from the environment). **Still in Git history**, and in every clone or fork made since 2026-09-26. Rotation not recorded anywhere. |
| Project URL and anon key (same file, lines 10–11) | commit `0abdaeb` | The anon key is public by design (it ships in every app build). No action beyond this runbook, unless you decide to roll the project's JWT signing keys for other reasons. |
| An `authenticated` user access token (JWT) and the anon key | commit `0dd7c3f`, file `scratch/test-jwt.mjs` (deleted from `HEAD` in `3bda65d`) | The token expired on 2026-09-23 20:13 UTC and cannot be replayed; no refresh token was committed. Revoke that user's sessions anyway (step 2) and include the file in any history purge (step 4). Identify the user by decoding the token's `sub` claim **locally**; do not paste the token anywhere. |

Detection: `gitleaks git --redact --log-opts="--all" .` with the repository's `.gitleaks.toml` reports
`livedrop-hardcoded-password` at `scripts/seed-legitimate-staging-drop.mjs:14` in `0abdaeb` (the default
gitleaks rules alone miss it; that is why the custom rule exists).

## 2. Rotate the password and revoke sessions (do first, today)

1. Supabase dashboard → the project from the seed script → **Authentication → Users**. Find the seller
   by the e-mail address in commit `0abdaeb` (look it up locally with
   `git show 0abdaeb:scripts/seed-legitimate-staging-drop.mjs`; do not copy it elsewhere).
2. Note the user's UUID.
3. Decide:
   - **Account still needed** (staging seller): set a new random password from the password manager
     (user row → *Reset password* / *Send password recovery*, or the admin API from a trusted machine).
     Store it only in the password manager and in the `STAGING_SELLER_PASSWORD` secret of whoever runs
     the seed script.
   - **Account not needed**: ban it (user row → *Ban user*) instead of deleting it; its profile is
     referenced by drops (`ON DELETE RESTRICT`), so a delete either fails or, if forced, destroys the
     audit trail you need for step 3.
4. Revoke every session of that user so existing refresh tokens stop working. In the SQL editor:

   ```sql
   -- replace with the UUID from step 2
   delete from auth.sessions where user_id = '00000000-0000-0000-0000-000000000000';
   ```

   Refresh tokens belong to sessions and are removed with them. Access tokens already issued stay valid
   until they expire (project JWT expiry, 1 hour by default); wait that long before step 3's
   "no activity after rotation" check.
5. Repeat step 4 for the user identified from `scratch/test-jwt.mjs` (commit `0dd7c3f`).
6. Check the seller's payout details were not changed: in `public.profiles` for that UUID, compare
   `upi_vpa`, `upi_id`, `upi_display_name` and `upi_enabled` with what the seller expects. A changed
   payee VPA would redirect buyers' UPI payments.

## 3. Review activity since 2026-09-26

1. Dashboard → **Logs → Auth** (Logs Explorer). Filter on the user UUID / e-mail from step 2, time range
   2026-09-26 00:00 UTC until now. Look for password logins (`grant_type=password`), token refreshes and
   password/e-mail changes from IP addresses or user agents the team does not recognise.
2. Log retention depends on the Supabase plan (short on the free plan). If the retained window does not
   reach back to 2026-09-26, write that down in the completion record: the review is then partial and the
   data review below is the main evidence.
3. Data review for that seller (SQL editor, read-only):

   ```sql
   -- replace the UUID; all timestamps are UTC
   select id, slug, status, created_at, updated_at from public.drops
    where seller_id = '00000000-0000-0000-0000-000000000000'
      and greatest(created_at, updated_at) >= '2026-09-26';
   select p.id, p.code, p.status, p.price_paisa, p.created_at, p.updated_at
     from public.products p join public.drops d on d.id = p.drop_id
    where d.seller_id = '00000000-0000-0000-0000-000000000000'
      and greatest(p.created_at, p.updated_at) >= '2026-09-26';
   select o.id, o.order_code, o.status, o.payment_status, o.updated_at
     from public.orders o join public.drops d on d.id = o.drop_id
    where d.seller_id = '00000000-0000-0000-0000-000000000000'
      and o.updated_at >= '2026-09-26';
   ```

   Anything the team did not do (price changes, products marked sold, payments verified or rejected,
   drops opened/closed, profile edits) is a security incident: keep the evidence, notify affected buyers
   if money is involved, and record it below.

## 4. Decide on purging the history

Rotation (step 2) is what makes the leak harmless. Purging history only reduces how easily the dead
credential can be found. Decide explicitly and record the decision.

**Option A — keep history (acceptable once step 2 is done).** The old password is useless. Document the
decision below.

**Option B — purge with `git filter-repo` and a coordinated force-push.**

1. Announce a freeze: nobody pushes; open pull requests will have to be recreated or rebased.
2. On a trusted machine (requires `pip install git-filter-repo`):

   ```bash
   git clone --mirror https://github.com/<owner>/LiveDrop.git livedrop-purge.git
   cd livedrop-purge.git
   # replacements.txt lives OUTSIDE any repository and is shredded afterwards.
   # One line per value:  <literal leaked value>==>***REMOVED***
   git filter-repo --replace-text ../replacements.txt
   git filter-repo --path scratch/test-jwt.mjs --invert-paths
   git push --force --mirror origin
   shred -u ../replacements.txt   # or delete securely
   ```

3. Everyone deletes their old clone and clones again (an old clone pushed back would reintroduce the
   commits).
4. Limits you must accept:
   - Every commit SHA from `0abdaeb`/`0dd7c3f` onwards changes. References to SHAs in `docs/` and
     `audit/` (including this runbook) become stale.
   - Forks, existing clones, CI caches and anyone who already copied the value keep it. GitHub keeps
     old commits reachable through pull request refs and cached views until GitHub Support removes them:
     open a support request ("remove cached views / sensitive data") after the force-push.
   - Branch protection must allow the force-push temporarily; re-enable it immediately afterwards.

## 5. Stop it happening again

1. GitHub → Settings → **Code security** → enable **Secret scanning** (Secret Protection) and **Push
   protection**. Both are free for public repositories. Review any existing alerts under
   Security → Secret scanning.
2. CI: `.github/workflows/secret-scan.yml` runs gitleaks (rules: default set + `.gitleaks.toml`) on every
   push and pull request, over the commits introduced only, with redacted output, and fails on findings.
   Make the check **`gitleaks (new commits)`** required for `main` (Settings → Rules/Branches).
3. Local pre-commit (optional): `gitleaks git --pre-commit --staged --redact` before committing.
4. Seed and test scripts take credentials from environment variables only (done for the seed script in
   `ebb80cd`); prefer short-lived per-run test accounts created and deleted by the script.
5. A finding that is a false positive: fix the pattern so it is clearly a placeholder, or add the
   fingerprint printed in the job summary to a `.gitleaksignore` file in a reviewed pull request.

## 6. Completion record

Fill in as each step is done. Never paste secrets.

| Step | Done by | Date/time (UTC) | Evidence / notes |
|---|---|---|---|
| 2.3 Password rotated or account banned (which) | | | |
| 2.4 Sessions revoked for the seed-script seller | | | |
| 2.5 Sessions revoked for the user in `0dd7c3f` | | | |
| 2.6 Payout details checked unchanged | | | |
| 3.1 Auth logs reviewed (window actually covered) | | | |
| 3.3 Data review done; unexpected activity found? | | | |
| 4 History decision (A keep / B purge) and date of force-push if B | | | |
| 4 GitHub Support cache removal requested (ticket id) if B | | | |
| 5.1 Secret scanning + push protection enabled | | | |
| 5.2 `gitleaks (new commits)` required on `main` | | | |
