-- Exact row count of every table in schema public, one "table<TAB>count" line each, sorted.
-- Run with: psql -X -A -t -F $'\t' -f table_counts.sql   (read-only)
SELECT c.relname,
       (xpath('/row/n/text()',
              query_to_xml(format('SELECT count(*) AS n FROM public.%I', c.relname), false, true, '')))[1]::text::bigint
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
 ORDER BY c.relname;
