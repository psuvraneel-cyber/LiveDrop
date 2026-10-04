#!/usr/bin/env bash
# =============================================================================
# LiveDrop Seller-App Audit — apply all migrations to a throwaway local Postgres
# and run the audit verification suites. AUDIT-ONLY: never point this at a
# hosted Supabase project (it creates and drops a database).
#
# Usage:
#   PGHOST=/tmp PGPORT=55432 PGUSER=postgres ./run_local_db_audit.sh
#
# Environment:
#   AUDIT_DB      database to (re)create for the suites   (default livedrop_audit)
#   CONC_DB       database for 14_concurrency.sh          (default livedrop_conc)
#   EVIDENCE_DIR  where evidence files are written         (default audit/seller-app/evidence)
#                 Reviewers can point this at a scratch directory so a local run
#                 does not overwrite the committed evidence.
#
# Output: evidence files under $EVIDENCE_DIR
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
MIGRATIONS="$REPO/supabase/migrations"
EVIDENCE="${EVIDENCE_DIR:-$REPO/audit/seller-app/evidence}"
DB="${AUDIT_DB:-livedrop_audit}"
mkdir -p "$EVIDENCE"
EVIDENCE="$(cd "$EVIDENCE" && pwd)"

psql_db() { psql -X -v ON_ERROR_STOP=1 -d "$DB" "$@"; }

echo "== Recreating database $DB"
psql -X -d postgres -c "DROP DATABASE IF EXISTS $DB;" >/dev/null
psql -X -d postgres -c "CREATE DATABASE $DB;" >/dev/null

echo "== Applying Supabase shim"
psql_db -f "$HERE/00_supabase_shim.sql" >/dev/null

LOG="$EVIDENCE/migration-apply.log"
: > "$LOG"
status=0
for f in $(ls "$MIGRATIONS"/*.sql | sort); do
  name="$(basename "$f")"
  if out=$(psql_db -q -f "$f" 2>&1); then
    echo "PASS  $name" | tee -a "$LOG"
  else
    echo "FAIL  $name" | tee -a "$LOG"
    echo "$out" | sed 's/^/      /' | tee -a "$LOG"
    status=1
  fi
done
echo "Migration apply exit status: $status" | tee -a "$LOG"

if [ "$status" -ne 0 ]; then
  echo "Migrations failed; skipping suites." >&2
  exit 1
fi

echo "== Installing audit helpers (schema audit)"
psql_db -q -f "$HERE/05_audit_helpers.sql" >/dev/null

for suite in "$HERE"/1*.sql "$HERE"/2*.sql; do
  [ -f "$suite" ] || continue
  name="$(basename "$suite" .sql)"
  echo "== Running $name"
  psql -X -d "$DB" -f "$suite" > "$EVIDENCE/$name.out" 2>&1
  sed -E 's/^psql:[^ ]+ NOTICE:  //; s/^psql:[^ ]+ ERROR:  /ERROR /' "$EVIDENCE/$name.out" | grep -E "^(PASS|FAIL|FINDING|INFO|ERROR)" | sed 's/^/   /'
done

echo "== Catalog inventory"
psql -X -d "$DB" -f "$HERE/91_local_catalog_inventory.sql" > "$EVIDENCE/schema-inventory.out" 2>&1
psql -X -d "$DB" -c "SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.prosecdef AS secdef, array_to_string(p.proconfig, ',') AS config
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND has_function_privilege('anon', p.oid, 'EXECUTE') ORDER BY 1, 2;" > "$EVIDENCE/anon-executable-functions.out" 2>&1
psql -X -d "$DB" -c "SELECT p.proname, p.prosecdef AS secdef, array_to_string(p.proconfig, ',') AS search_path_config
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prosecdef ORDER BY 1;" > "$EVIDENCE/security-definer-search-path.out" 2>&1

echo "== Running 14_concurrency.sh"
AUDIT_DB="$DB" "$HERE/14_concurrency.sh" > "$EVIDENCE/14_concurrency.out" 2>&1
grep -E "^(PASS|FAIL|FINDING|INFO|INCONCLUSIVE)|^ +[0-9]+ (true|false)$" "$EVIDENCE/14_concurrency.out" | sed 's/^/   /'
