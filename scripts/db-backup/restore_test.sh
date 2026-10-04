#!/usr/bin/env bash
# =============================================================================
# LiveDrop — restore test for the nightly backup (SA-OPS-004)
#
# Rebuilds the schema from supabase/migrations in a throwaway database, loads the
# backup's public data into it and checks that every table has exactly the row
# count recorded when the backup was taken. Never point this at a hosted database.
#
# Usage: restore_test.sh <public.dump> <counts.tsv>
#   PGHOST / PGPORT / PGUSER / PGPASSWORD   the throwaway server (superuser)
#   RESTORE_DB                              database to (re)create (default livedrop_restore_check)
# =============================================================================
set -euo pipefail
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"

DUMP="$1"
EXPECTED="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
DB="${RESTORE_DB:-livedrop_restore_check}"

psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB;"
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$REPO/audit/seller-app/tests/sql/00_supabase_shim.sql" >/dev/null
for f in $(ls "$REPO"/supabase/migrations/*.sql | sort); do
  psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" >/dev/null
done
echo "schema rebuilt from $(ls "$REPO"/supabase/migrations/*.sql | wc -l) migrations"

# Migrations seed a few rows (config); the backup's rows replace them.
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" <<'SQL'
DO $$
DECLARE t text;
BEGIN
  SELECT string_agg(format('public.%I', c.relname), ', ') INTO t
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p');
  IF t IS NOT NULL THEN EXECUTE 'TRUNCATE ' || t || ' RESTART IDENTITY CASCADE'; END IF;
END $$;
SQL

# Foreign keys to auth.users are not checked here (accounts live in the separate auth dump).
pg_restore --data-only --disable-triggers --no-owner --no-privileges --schema=public \
  --exit-on-error -d "$DB" "$DUMP"

ACTUAL="$(mktemp)"
psql -X -A -t -F $'\t' -d "$DB" -f "$HERE/table_counts.sql" > "$ACTUAL"
if diff -u "$EXPECTED" "$ACTUAL"; then
  echo "PASS restore test: $(wc -l < "$EXPECTED") tables, $(awk -F'\t' '{s+=$2} END {print s+0}' "$EXPECTED") rows, all counts match"
else
  echo "FAIL restore test: row counts differ (expected = backup, actual = restored)" >&2
  exit 1
fi
