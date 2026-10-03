#!/usr/bin/env bash
# =============================================================================
# Suite 14 — multi-session concurrency checks (AUDIT-ONLY, local Postgres only)
#   14.1  N buyers race for one unique piece        -> exactly one order expected
#   14.2  late-claim verification vs a new checkout -> double allocation check
#   14.3  seller verify vs reaper lock ordering     -> deadlock check
# Creates database ${CONC_DB:-livedrop_conc} from the migrated audit database.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_DB="${AUDIT_DB:-livedrop_audit}"
DB="${CONC_DB:-livedrop_conc}"
N="${RACERS:-40}"
Q() { psql -X -q -t -A -d "$DB" "$@"; }

psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB TEMPLATE $SRC_DB;" >/dev/null
Q -c "SELECT audit.seed();" >/dev/null

echo "== 14.1 $N concurrent checkouts for one piece (#A01)"
seq 1 "$N" | xargs -P "$N" -I{} psql -X -q -t -A -d "$DB" -c \
  "SELECT audit.as_anon(); SELECT create_order_with_reservation('aaaa0000-0000-0000-0000-000000000001', ARRAY['a1000000-0000-0000-0000-000000000001']::uuid[], 'Racer {}', '98300{}0000', '1 Race Course Road, Kolkata', '700027', 'full_payment', 'race-{}')->>'success';" \
  2>/dev/null | grep -E "^(true|false)$" | sort | uniq -c
orders=$(Q -c "SELECT count(*) FROM order_items WHERE product_id = 'a1000000-0000-0000-0000-000000000001';")
state=$(Q -c "SELECT status || '/' || coalesce(reserved_by_order_id::text,'none') FROM products WHERE id = 'a1000000-0000-0000-0000-000000000001';")
if [ -z "$orders" ]; then echo "INCONCLUSIVE 14.1 database unavailable";
elif [ "$orders" = "1" ]; then echo "PASS 14.1 exactly one order holds the piece (order_items=$orders, product=$state)";
else echo "FAIL 14.1 order_items for piece = $orders (product=$state)"; fi

echo "== 14.2 late-claim verification racing a fresh checkout of the same piece (#A02)"
read -r X_ORDER X_TOKEN X_ATTEMPT < <(Q -F ' ' <<'SQL' | grep -E '^[0-9a-f-]{36} ' | tail -1
BEGIN;
SELECT audit.as_anon();
WITH o AS (SELECT create_order_with_reservation('aaaa0000-0000-0000-0000-000000000001', ARRAY['a1000000-0000-0000-0000-000000000002']::uuid[], 'Late Payer', '9830055555', '9 Rashbehari Avenue, Kolkata', '700026', 'full_payment', 'late-x') r),
     a AS (SELECT initiate_payment_attempt((r->>'order_id')::uuid, r->>'order_token', NULL) j, r FROM o)
SELECT r->>'order_id', r->>'order_token', j->>'payment_attempt_id' FROM a;
COMMIT;
SQL
)
Q >/dev/null <<SQL
BEGIN;
UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = '$X_ORDER';
UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = '$X_ATTEMPT';
SELECT audit.as_service(); SELECT release_expired_holds(); SELECT audit.as_postgres();
SELECT audit.as_anon(); SELECT submit_buyer_payment_claim('$X_ORDER', '$X_TOKEN', '$X_ATTEMPT', '313131313131');
COMMIT;
SQL
echo "   setup: order X=$X_ORDER is $(Q -c "SELECT status FROM orders WHERE id='$X_ORDER'"), attempt is $(Q -c "SELECT status FROM payment_attempts WHERE id='$X_ATTEMPT'"), piece is $(Q -c "SELECT status FROM products WHERE id='a1000000-0000-0000-0000-000000000002'")"
# Session B: new buyer reserves the piece inside a transaction that stays open for 3s.
( Q <<'SQL' > /tmp/ld_conc_b.out 2>&1
BEGIN;
SELECT audit.as_anon();
SELECT create_order_with_reservation('aaaa0000-0000-0000-0000-000000000001', ARRAY['a1000000-0000-0000-0000-000000000002']::uuid[], 'Fresh Buyer', '9830066666', '4 Elgin Road, Kolkata', '700020', 'full_payment', 'late-y')->>'success';
SELECT pg_sleep(3);
COMMIT;
SQL
) &
B_PID=$!
sleep 1
# Session S: seller verifies the late claim while B's reservation is in flight.
V=$(Q <<SQL 2>&1
BEGIN;
SELECT audit.as_seller('11111111-1111-1111-1111-111111111111');
SELECT verify_manual_upi_payment('$X_ATTEMPT')::text;
COMMIT;
SQL
)
wait $B_PID
echo "   session B checkout success: $(grep -E '^(true|false)$' /tmp/ld_conc_b.out)"
echo "   seller verify result: $(echo "$V" | grep -o '"message": "[^"]*"' | head -1)"
Y_ORDER=$(Q -c "SELECT id FROM orders WHERE idempotency_key='late-y'")
SUMMARY=$(Q -F ' | ' -c "SELECT 'X=' || x.status || '/' || x.payment_status, 'Y=' || y.status || '/' || y.payment_status, 'piece=' || p.status || ' reserved_by=' || coalesce(p.reserved_by_order_id::text,'NULL') FROM orders x, orders y, products p WHERE x.id='$X_ORDER' AND y.id='$Y_ORDER' AND p.id='a1000000-0000-0000-0000-000000000002'")
echo "   $SUMMARY"
if [ -z "${X_ORDER:-}" ] || [ -z "${Y_ORDER:-}" ]; then
  echo "INCONCLUSIVE 14.2 setup failed (X_ORDER='${X_ORDER:-}' Y_ORDER='${Y_ORDER:-}')"
elif echo "$SUMMARY" | grep -q "X=paid" && echo "$SUMMARY" | grep -q "Y=pending"; then
  echo "FINDING 14.2 double allocation: late claim marked piece sold for order X while order Y still holds it as a pending reservation"
  # Follow-through: buyer Y pays and the seller verifies Y as well.
  Y_TOKEN=$(Q -c "SELECT order_token FROM orders WHERE id='$Y_ORDER'")
  Q >/dev/null <<SQL2
BEGIN;
SELECT audit.as_anon();
SELECT submit_buyer_payment_claim('$Y_ORDER', '$Y_TOKEN', (initiate_payment_attempt('$Y_ORDER', '$Y_TOKEN', NULL)->>'payment_attempt_id')::uuid, '515151515151');
COMMIT;
BEGIN;
SELECT audit.as_seller('11111111-1111-1111-1111-111111111111');
SELECT verify_manual_upi_payment((SELECT id FROM payment_attempts WHERE order_id='$Y_ORDER' ORDER BY created_at DESC LIMIT 1));
COMMIT;
SQL2
  PAID=$(Q -c "SELECT count(*) FROM orders o JOIN order_items oi ON oi.order_id=o.id WHERE oi.product_id='a1000000-0000-0000-0000-000000000002' AND o.payment_status='paid'")
  echo "   after buyer Y pays and seller verifies: paid orders containing the single piece #A02 = $PAID"
  [ "$PAID" -ge 2 ] && echo "FINDING 14.2b one unique garment is now attached to $PAID fully paid orders"
else
  echo "PASS 14.2 no double allocation observed"
fi

echo "== 14.3 seller verify (locks attempt -> order) vs reaper (locks order -> attempt)"
read -r Z_ORDER Z_TOKEN Z_ATTEMPT < <(Q -F ' ' <<'SQL' | grep -E '^[0-9a-f-]{36} ' | tail -1
BEGIN;
SELECT audit.as_anon();
WITH o AS (SELECT create_order_with_reservation('aaaa0000-0000-0000-0000-000000000001', ARRAY['a1000000-0000-0000-0000-000000000003']::uuid[], 'Deadlock Test', '9830088888', '8 Camac Street, Kolkata', '700017', 'full_payment', 'dl-z') r),
     a AS (SELECT initiate_payment_attempt((r->>'order_id')::uuid, r->>'order_token', NULL) j, r FROM o)
SELECT r->>'order_id', r->>'order_token', j->>'payment_attempt_id' FROM a;
COMMIT;
SQL
)
Q >/dev/null <<SQL
BEGIN;
SELECT audit.as_anon(); SELECT submit_buyer_payment_claim('$Z_ORDER', '$Z_TOKEN', '$Z_ATTEMPT', '414141414141');
SELECT audit.as_postgres();
UPDATE orders SET hold_expires_at = now() - interval '1 second' WHERE id = '$Z_ORDER';
COMMIT;
SQL
# Session R: reaper path — lock the expired order first (as the reaper's FOR UPDATE does), then run the real reaper.
( Q <<SQL > /tmp/ld_conc_r.out 2>&1
BEGIN;
SELECT audit.as_service();
SELECT id FROM orders WHERE id = '$Z_ORDER' FOR UPDATE;
SELECT pg_sleep(2);
SELECT release_expired_holds();
COMMIT;
SQL
) &
R_PID=$!
sleep 0.5
S_OUT=$(Q <<SQL 2>&1
BEGIN;
SELECT audit.as_seller('11111111-1111-1111-1111-111111111111');
SELECT verify_manual_upi_payment('$Z_ATTEMPT')::text;
COMMIT;
SQL
)
wait $R_PID
R_DL=$(grep -c "deadlock detected" /tmp/ld_conc_r.out)
S_DL=$(echo "$S_OUT" | grep -c "deadlock detected")
echo "   reaper session deadlock errors: $R_DL ; seller verify deadlock errors: $S_DL"
if [ -z "${Z_ORDER:-}" ]; then
  echo "INCONCLUSIVE 14.3 setup failed"
elif [ "$R_DL" -gt 0 ] || [ "$S_DL" -gt 0 ]; then
  echo "FINDING 14.3 deadlock between seller verification and the reaper (opposite lock order); aborted side: $([ "$R_DL" -gt 0 ] && echo reaper-transaction || echo seller-verify)"
else
  echo "PASS 14.3 no deadlock observed"
fi
