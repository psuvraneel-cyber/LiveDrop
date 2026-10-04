# ADR-016: Operator Console, Nightly Backups and Seller-App Links

## Status
**Accepted**, 2026-10-05. The project owner chose a small admin page (over SQL snippets) and a free nightly backup job (over Supabase Pro).

## Context
* **SA-OPS-002 / SA-ONB-001:** approving a seller and recording a refund the seller cannot record were possible only in the SQL editor. The onboarding-fee UTR typed at sign-up was visible only in auth metadata.
* **SA-OPS-004:** there was no tested backup, and the free plan pauses an unused project.
* **SA-AND-003:** nothing outside the app could open it (no deep links).

## Decision
1. **Operator console at `/admin` on the website** (migration 042):
   * Admins are listed in `platform_admins`, added by the owner in the SQL editor. No client can read or write that table.
   * The page signs in as a normal Supabase user with the anon key. It never uses a service-role key.
   * Every call is an `admin_*` RPC that checks `is_platform_admin()` itself.
   * Writes need a password sign-in within the last 10 minutes (`REAUTH_REQUIRED`), like the payee guard in 039.
   * Every write is logged in `admin_actions` (who, what, when, why). The log also decides whether an unapproved seller shows as *pending* or *suspended*.
   * Suspending needs a reason, and closes the seller's live drops (trigger from 038).
   * Refunds go through `record_refund`, with the same checks as for sellers. It accepts an admin only inside `admin_record_refund` (transaction-local flag plus admin check).
   * Buyer phone numbers and addresses are never returned.
   * The session is kept in memory only, so closing the tab signs out.
2. **Nightly backup** (`.github/workflows/db-backup.yml`, 02:00 IST):
   * `pg_dump` of schema `public` (schema and data) and of `auth.users` and `auth.identities` (data only). Read-only on the hosted database.
   * A **restore test**: rebuild the schema from the migrations in a throwaway Postgres 17, load the data, and require every table's row count to match the backup.
   * The dumps are encrypted with the owner's `BACKUP_PASSPHRASE` (gpg, AES-256) and kept as a private 30-day artifact. Nothing unencrypted is uploaded.
   * The same restore test runs on every database pull request (`db-tests.yml`) against the audit seed data.
   * Restore steps: `docs/40-backup-and-restore.md`.
3. **Seller-app links** use the custom scheme `livedrop-seller://open/<home|products|orders|payments|settings>` (`AppLinkService`, package `app_links`).
   * The password-reset success page offers "Open the LiveDrop Seller app".
   * A custom scheme needs no file on the website and survives a domain change. Verified https App Links would need the Play App Signing certificate fingerprint published in `assetlinks.json`; that is left for when the app is on Play.

## Consequences
* The owner can approve sellers, see the fee UTR, suspend with a reason and record refunds from a phone browser. Every action is logged.
* There is one more privileged code path, so it is covered by SQL suite 24, post-check H27 and `admin-console.test.tsx`.
* Backups cost nothing but depend on the owner keeping `BACKUP_PASSPHRASE` safe: without it the backups cannot be read.
* Not backed up: product images in Supabase Storage. Re-uploading them is the documented recovery path.
* The nightly connection probably also counts as activity against the free-plan pause. This is not guaranteed.
* Store slugs are not reserved, so a store named `admin` would be shadowed by the console route. The same is already true of `shop`, `cart`, `checkout`, `order` and `seller`. Tracked as a follow-up.
