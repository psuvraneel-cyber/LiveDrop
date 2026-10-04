# 40 — Backup and Restore (SA-OPS-004, ADR-016)

## What is backed up
The **Database Backup** workflow (`.github/workflows/db-backup.yml`) runs nightly at 02:00 IST and can also be started manually from Actions. Each run produces:

| File | Contents |
|---|---|
| `livedrop-public-<time>.dump.gpg` | Schema `public`: every table, function and policy, plus all data (sellers, drops, products, orders, payments, logs) |
| `livedrop-auth-<time>.dump.gpg` | Seller accounts: `auth.users` and `auth.identities` (data only, including password hashes) |
| `counts.tsv` | Row count of every `public` table when the backup was taken |
| `restore-test.txt` | Result of the restore test for this backup |

* Both dumps are encrypted with the repository secret `BACKUP_PASSPHRASE` (gpg, AES-256).
* Runs are kept for **30 days** under the run's artifacts.
* **Not included:** product images in Supabase Storage. They are recovered by re-uploading, or by downloading the `product-images` bucket separately.

Every run proves the backup can be restored:
* It rebuilds the schema from `supabase/migrations` in a fresh Postgres.
* It loads the data.
* It fails unless every table has exactly the backed-up row count.

## One-time setup (owner)
1. Choose a long passphrase and keep it in your password manager. **Without it the backups cannot be opened.**
2. In GitHub, go to **Settings → Secrets and variables → Actions → New repository secret** and add `BACKUP_PASSPHRASE` with that passphrase.
3. Go to **Actions → Database Backup → Run workflow** and check that the run passes, with "PASS restore test" in its summary.

## Restoring
Restore into a **new** Supabase project first. Never restore over the live project unless you mean to replace it.

1. Download the run's artifact and decrypt it:
   ```bash
   gpg --decrypt livedrop-public-<time>.dump.gpg > public.dump
   ```
   ```bash
   gpg --decrypt livedrop-auth-<time>.dump.gpg > auth.dump
   ```
2. In the new project, run the migrations (Database Deploy, or `supabase db push`). This creates the schema, extensions, cron jobs and policies.
3. Load the accounts, then the data. `<NEW_DB_URL>` is the new project's session-pooler or direct connection string.
   ```bash
   pg_restore --data-only --no-owner --disable-triggers -d "<NEW_DB_URL>" auth.dump
   ```
   ```bash
   pg_restore --data-only --no-owner --disable-triggers --schema=public -d "<NEW_DB_URL>" public.dump
   ```
   If the migrations seeded rows (for example `app_config`), empty those tables first, as `scripts/db-backup/restore_test.sh` does.
4. Compare row counts with `counts.tsv`:
   ```bash
   psql "<NEW_DB_URL>" -X -A -t -F $'\t' -f scripts/db-backup/table_counts.sql
   ```
5. Point the apps at the new project: update the buyer website's environment and the seller app's build configuration, and redeploy the `push-dispatch` function with its secret.
6. Delete the decrypted dumps.

## Free-plan pausing
* The free plan pauses a project after a period without activity. The nightly backup connects to the database every day, which probably counts as activity, but Supabase does not guarantee it.
* If the project does pause, restore it from the Supabase dashboard. No data is lost when a project pauses.
