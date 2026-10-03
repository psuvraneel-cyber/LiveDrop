#!/usr/bin/env bash
# =============================================================================
# Suite 14 — multi-session concurrency checks (AUDIT-ONLY, local Postgres only)
#   14.1  N buyers race for one unique piece        -> exactly one order expected
#   14.2  late-claim verification vs a new checkout -> no double allocation; the late
#         payment is recorded as refund-required and the new buyer keeps the piece
#   14.3  seller verify vs reaper on a claimed order -> no deadlock; verification succeeds
#   14.4  seller verify waits while the reaper releases the same unclaimed order
#         (opposite lock order before migration 035)  -> no deadlock
#   14.5  N buyers race for a piece behind an expired, unclaimed hold (lazy expiry)
#         -> exactly one order, stale hold cancelled
# Creates database ${CONC_DB:-livedrop_conc} from the migrated audit database.
# Result lines: PASS / FAIL (expected behaviour), FINDING (defect reproduced),
# INCONCLUSIVE (setup did not complete).
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_DB="${AUDIT_DB:-livedrop_audit}"
DB="${CONC_DB:-livedrop_conc}"
N="${RACERS:-40}"
Q() { psql -X -q -t -A -d "$DB" "$@"; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ld_conc.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

SELLER_A='11111111-1111-1111-1111-111111111111'
SELLER_B='22222222-2222-2222-2222-222222222222'
DROP_A='aaaa0000-0000-0000-0000-000000000001'
DROP_B='bbbb0000-0000-0000-0000-000000000001'
P_A01='a1000000-0000-0000-0000-000000000001'
P_A02='a1000000-0000-0000-0000-000000000002'
P_A03='a1000000-0000-0000-0000-000000000003'
P_B01='b1000000-0000-0000-0000-000000000001'

psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB TEMPLATE $SRC_DB;" >/dev/null
Q -c "SELECT audit.seed();" >/dev/null

# Orders whose total_paid_paisa differs from the sum of their verified ledger rows.
ledger_mismatches() {
  Q -c "SELECT count(*) FROM orders o
         WHERE o.total_paid_paisa <> (SELECT coalesce(sum(op.amount_paisa), 0) FROM order_payments op
                                       WHERE op.order_id = o.id AND op.status = 'verified');"
}

echo "== 14.1 $N concurrent checkouts for one piece (#A01)"
seq 1 "$N" | xargs -P "$N" -I{} psql -X -q -t -A -d "$DB" -c \
  "SELECT audit.as_anon(); SELECT create_order_with_reservation('$DROP_A', ARRAY['$P_A01']::uuid[], 'Racer {}', '98' || lpad('{}', 8, '0'), '1 Race Course Road, Kolkata', '700027', 'full_payment', 'race-{}')->>'success';" \
  2>/dev/null | grep -E "^(true|false)$" | sort | uniq -c
orders=$(Q -c "SELECT count(*) FROM order_items WHERE product_id = '$P_A01';")
state=$(Q -c "SELECT status || '/' || coalesce(reserved_by_order_id::text,'none') FROM products WHERE id = '$P_A01';")
if [ -z "$orders" ]; then echo "INCONCLUSIVE 14.1 database unavailable";
elif [ "$orders" = "1" ]; then echo "PASS 14.1 exactly one order holds the piece (order_items=$orders, product=$state)";
else echo "FAIL 14.1 order_items for piece = $orders (product=$state)"; fi

echo "== 14.2 late-claim verification racing a fresh checkout of the same piece (#A02)"
read -r X_ORDER X_TOKEN X_ATTEMPT < <(Q -F ' ' <<SQL | grep -E '^[0-9a-f-]{36} ' | tail -1
BEGIN;
SELECT audit.as_anon();
WITH o AS (SELECT create_order_with_reservation('$DROP_A', ARRAY['$P_A02']::uuid[], 'Late Payer', '9830055555', '9 Rashbehari Avenue, Kolkata', '700026', 'full_payment', 'late-x') r),
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
echo "   setup: order X=$X_ORDER is $(Q -c "SELECT status FROM orders WHERE id='$X_ORDER'"), attempt is $(Q -c "SELECT status FROM payment_attempts WHERE id='$X_ATTEMPT'"), piece is $(Q -c "SELECT status FROM products WHERE id='$P_A02'")"
# Session B: new buyer reserves the piece inside a transaction that stays open for 3s.
( Q <<SQL > "$TMP/b.out" 2>&1
BEGIN;
SELECT audit.as_anon();
SELECT create_order_with_reservation('$DROP_A', ARRAY['$P_A02']::uuid[], 'Fresh Buyer', '9830066666', '4 Elgin Road, Kolkata', '700020', 'full_payment', 'late-y')->>'success';
SELECT pg_sleep(3);
COMMIT;
SQL
) &
B_PID=$!
sleep 1
# Session S: seller verifies the late claim while B's reservation is in flight.
V=$(Q <<SQL 2>&1
BEGIN;
SELECT audit.as_seller('$SELLER_A');
SELECT verify_manual_upi_payment('$X_ATTEMPT')::text;
COMMIT;
SQL
)
wait $B_PID
echo "   session B checkout success: $(grep -E '^(true|false)$' "$TMP/b.out")"
echo "   seller verify result: $(echo "$V" | grep -o '"message": "[^"]*"' | head -1) $(echo "$V" | grep -o '"error": "[^"]*"' | head -1) $(echo "$V" | grep -o 'ERROR: .*' | head -1)"
Y_ORDER=$(Q -c "SELECT id FROM orders WHERE idempotency_key='late-y'")
if [ -z "${X_ORDER:-}" ] || [ -z "${Y_ORDER:-}" ]; then
  echo "INCONCLUSIVE 14.2 setup failed (X_ORDER='${X_ORDER:-}' Y_ORDER='${Y_ORDER:-}')"
else
  SUMMARY=$(Q -F ' | ' -c "SELECT 'X=' || x.status || '/' || x.payment_status || ' refund=' || coalesce(to_jsonb(x)->>'refund_status', 'n/a') || ':' || coalesce(to_jsonb(x)->>'refund_amount_paisa', 'n/a') || ' total=' || x.total_paisa,
                                   'Y=' || y.status || '/' || y.payment_status,
                                   'piece=' || p.status || ' reserved_by=' || CASE WHEN p.reserved_by_order_id = y.id THEN 'Y' WHEN p.reserved_by_order_id = x.id THEN 'X' ELSE coalesce(p.reserved_by_order_id::text,'NULL') END
                              FROM orders x, orders y, products p WHERE x.id='$X_ORDER' AND y.id='$Y_ORDER' AND p.id='$P_A02'")
  echo "   $SUMMARY"
  X_OK=$(Q -c "SELECT coalesce(x.status = 'cancelled' AND to_jsonb(x)->>'refund_status' = 'required'
                       AND (to_jsonb(x)->>'refund_amount_paisa')::int = x.total_paisa
                       AND x.total_paid_paisa = x.total_paisa, false)
                 FROM orders x WHERE x.id = '$X_ORDER'")
  Y_OK=$(Q -c "SELECT (y.status = 'pending' AND p.status = 'reserved' AND p.reserved_by_order_id = y.id)
                 FROM orders y, products p WHERE y.id = '$Y_ORDER' AND p.id = '$P_A02'")
  if echo "$SUMMARY" | grep -q "X=paid" && echo "$SUMMARY" | grep -q "Y=pending"; then
    echo "FINDING 14.2 double allocation: late claim marked piece sold for order X while order Y still holds it as a pending reservation"
  elif [ "$X_OK" = "t" ] && [ "$Y_OK" = "t" ]; then
    echo "PASS 14.2 late claim recorded as refund-required on cancelled order X; order Y keeps the piece (no overwrite)"
  else
    echo "FAIL 14.2 unexpected outcome (X ok=$X_OK, Y ok=$Y_OK)"
  fi
  # Follow-through: buyer Y pays and the seller verifies Y as well.
  Y_TOKEN=$(Q -c "SELECT order_token FROM orders WHERE id='$Y_ORDER'")
  Q >/dev/null 2>&1 <<SQL2
BEGIN;
SELECT audit.as_anon();
SELECT submit_buyer_payment_claim('$Y_ORDER', '$Y_TOKEN', (initiate_payment_attempt('$Y_ORDER', '$Y_TOKEN', NULL)->>'payment_attempt_id')::uuid, '515151515151');
COMMIT;
BEGIN;
SELECT audit.as_seller('$SELLER_A');
SELECT verify_manual_upi_payment((SELECT id FROM payment_attempts WHERE order_id='$Y_ORDER' ORDER BY created_at DESC LIMIT 1));
COMMIT;
SQL2
  LIVE=$(Q -c "SELECT count(*) FROM orders o JOIN order_items oi ON oi.order_id=o.id WHERE oi.product_id='$P_A02' AND o.status IN ('confirmed','paid','shipped')")
  PAID_ANY=$(Q -c "SELECT count(*) FROM orders o JOIN order_items oi ON oi.order_id=o.id WHERE oi.product_id='$P_A02' AND o.payment_status='paid'")
  Y_PAID=$(Q -c "SELECT (y.status = 'paid' AND p.status = 'sold') FROM orders y, products p WHERE y.id='$Y_ORDER' AND p.id='$P_A02'")
  MISMATCH=$(ledger_mismatches)
  echo "   after buyer Y pays and seller verifies: live orders owning #A02 = $LIVE (paid money on $PAID_ANY orders; X is refund-required) | Y paid & piece sold = $Y_PAID | ledger mismatches = $MISMATCH"
  if [ "$LIVE" -ge 2 ] 2>/dev/null; then
    echo "FINDING 14.2b one unique garment is now attached to $LIVE fully paid / confirmed orders"
  elif [ "$LIVE" = "1" ] && [ "$Y_PAID" = "t" ] && [ "$MISMATCH" = "0" ]; then
    echo "PASS 14.2b exactly one live paid order owns #A02 (Y); X's money is tracked as a refund"
  else
    echo "FAIL 14.2b unexpected follow-through (live=$LIVE y_paid=$Y_PAID ledger_mismatches=$MISMATCH)"
  fi
fi

echo "== 14.3 seller verify (claimed order) vs reaper holding the order lock"
read -r Z_ORDER Z_TOKEN Z_ATTEMPT < <(Q -F ' ' <<SQL | grep -E '^[0-9a-f-]{36} ' | tail -1
BEGIN;
SELECT audit.as_anon();
WITH o AS (SELECT create_order_with_reservation('$DROP_A', ARRAY['$P_A03']::uuid[], 'Deadlock Test', '9830088888', '8 Camac Street, Kolkata', '700017', 'full_payment', 'dl-z') r),
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
( Q <<SQL > "$TMP/r3.out" 2>&1
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
SELECT audit.as_seller('$SELLER_A');
SELECT verify_manual_upi_payment('$Z_ATTEMPT')::text;
COMMIT;
SQL
)
wait $R_PID
R_DL=$(grep -c "deadlock detected" "$TMP/r3.out")
S_DL=$(echo "$S_OUT" | grep -c "deadlock detected")
Z_STATE=$(Q -c "SELECT o.status || '/' || a.status || '/' || p.status FROM orders o, payment_attempts a, products p WHERE o.id='$Z_ORDER' AND a.id='$Z_ATTEMPT' AND p.id='$P_A03'")
echo "   reaper session deadlock errors: $R_DL ; seller verify deadlock errors: $S_DL ; order/attempt/piece after both = $Z_STATE"
if [ -z "${Z_ORDER:-}" ]; then
  echo "INCONCLUSIVE 14.3 setup failed"
elif [ "$R_DL" -gt 0 ] || [ "$S_DL" -gt 0 ]; then
  echo "FINDING 14.3 deadlock between seller verification and the reaper (opposite lock order); aborted side: $([ "$R_DL" -gt 0 ] && echo reaper-transaction || echo seller-verify)"
elif [ "$Z_STATE" = "paid/verified/sold" ]; then
  echo "PASS 14.3 no deadlock; reaper left the claimed order alone and the seller's verification succeeded"
else
  echo "FAIL 14.3 no deadlock but unexpected state $Z_STATE ($(echo "$S_OUT" | grep -o '"error": "[^"]*"' | head -1))"
fi

echo "== 14.4 seller verify waits on an order the reaper is releasing (unclaimed attempt, expired hold)"
read -r W_ORDER W_TOKEN W_ATTEMPT < <(Q -F ' ' <<SQL | grep -E '^[0-9a-f-]{36} ' | tail -1
BEGIN;
SELECT audit.as_anon();
WITH o AS (SELECT create_order_with_reservation('$DROP_B', ARRAY['$P_B01']::uuid[], 'Lock Order Test', '9830077777', '3 Park Lane, Kolkata', '700016', 'full_payment', 'dl-w') r),
     a AS (SELECT initiate_payment_attempt((r->>'order_id')::uuid, r->>'order_token', NULL) j, r FROM o)
SELECT r->>'order_id', r->>'order_token', j->>'payment_attempt_id' FROM a;
COMMIT;
SQL
)
Q -c "UPDATE orders SET hold_expires_at = now() - interval '1 second' WHERE id = '$W_ORDER';" >/dev/null
( Q <<SQL > "$TMP/r4.out" 2>&1
BEGIN;
SELECT audit.as_service();
SELECT id FROM orders WHERE id = '$W_ORDER' FOR UPDATE;
SELECT pg_sleep(2);
SELECT release_expired_holds();
COMMIT;
SQL
) &
R_PID=$!
sleep 0.5
S_OUT=$(Q <<SQL 2>&1
BEGIN;
SELECT audit.as_seller('$SELLER_B');
SELECT verify_manual_upi_payment('$W_ATTEMPT')::text;
COMMIT;
SQL
)
wait $R_PID
R_DL=$(grep -c "deadlock detected" "$TMP/r4.out")
S_DL=$(echo "$S_OUT" | grep -c "deadlock detected")
W_STATE=$(Q -c "SELECT o.status || '/' || a.status || '/' || p.status FROM orders o, payment_attempts a, products p WHERE o.id='$W_ORDER' AND a.id='$W_ATTEMPT' AND p.id='$P_B01'")
S_ERR=$(echo "$S_OUT" | grep -o '"error": "[^"]*"' | head -1)
echo "   reaper deadlock errors: $R_DL ; seller verify deadlock errors: $S_DL ; order/attempt/piece = $W_STATE ; verify -> ${S_ERR:-$(echo "$S_OUT" | grep -o '"success": [a-z]*' | head -1)}"
if [ -z "${W_ORDER:-}" ]; then
  echo "INCONCLUSIVE 14.4 setup failed"
elif [ "$R_DL" -gt 0 ] || [ "$S_DL" -gt 0 ]; then
  echo "FINDING 14.4 deadlock: verify locked the attempt before the order while the reaper held the order"
elif [ "$W_STATE" = "cancelled/expired/available" ] && echo "$S_ERR" | grep -q "INVALID_ORDER_STATE"; then
  echo "PASS 14.4 no deadlock; reaper released the unclaimed hold first, verify then saw the cancelled order (INVALID_ORDER_STATE)"
else
  echo "FAIL 14.4 no deadlock but unexpected state $W_STATE / ${S_ERR:-no error}"
fi

echo "== 14.5 $N concurrent checkouts for a piece behind an expired, unclaimed hold (#B02, lazy expiry)"
P_B02='b1000000-0000-0000-0000-000000000002'
Q -c "INSERT INTO products (id, drop_id, code, title, price_paisa, size, image_url) VALUES ('$P_B02', '$DROP_B', '#B02', 'Lazy Expiry Test', 100000, 'Free Size', 'https://x.supabase.co/b2.jpg');" >/dev/null
read -r V_ORDER V_ATTEMPT < <(Q -F ' ' <<SQL | grep -E '^[0-9a-f-]{36} ' | tail -1
BEGIN;
SELECT audit.as_anon();
WITH o AS (SELECT create_order_with_reservation('$DROP_B', ARRAY['$P_B02']::uuid[], 'Abandoned Cart', '9830044444', '6 Lake View Road, Kolkata', '700029', 'full_payment', 'stale-v') r),
     a AS (SELECT initiate_payment_attempt((r->>'order_id')::uuid, r->>'order_token', NULL) j, r FROM o)
SELECT r->>'order_id', j->>'payment_attempt_id' FROM a;
COMMIT;
SQL
)
Q >/dev/null <<SQL
UPDATE orders SET hold_expires_at = now() - interval '1 minute' WHERE id = '$V_ORDER';
UPDATE payment_attempts SET expires_at = now() - interval '1 minute' WHERE id = '$V_ATTEMPT';
SQL
seq 1 "$N" | xargs -P "$N" -I{} psql -X -q -t -A -d "$DB" -c \
  "SELECT audit.as_anon(); SELECT create_order_with_reservation('$DROP_B', ARRAY['$P_B02']::uuid[], 'Lazy Racer {}', '97' || lpad('{}', 8, '0'), '2 Race Course Road, Kolkata', '700027', 'full_payment', 'lazy-{}')->>'success';" \
  2>/dev/null | grep -E "^(true|false)$" | sort | uniq -c | tee "$TMP/r5.out"
WINS=$(awk '$2=="true"{print $1}' "$TMP/r5.out"); WINS=${WINS:-0}
V_STATE=$(Q -c "SELECT o.status || '/' || a.status FROM orders o, payment_attempts a WHERE o.id='$V_ORDER' AND a.id='$V_ATTEMPT'")
HOLDER=$(Q -c "SELECT CASE WHEN p.status='reserved' AND o.status='pending' AND o.idempotency_key LIKE 'lazy-%' THEN 'new-buyer' ELSE p.status || '/' || coalesce(o.idempotency_key,'none') END
                 FROM products p LEFT JOIN orders o ON o.id = p.reserved_by_order_id WHERE p.id='$P_B02'")
LIVE=$(Q -c "SELECT count(*) FROM orders o JOIN order_items oi ON oi.order_id=o.id WHERE oi.product_id='$P_B02' AND o.status='pending'")
echo "   successes=$WINS ; stale order/attempt = $V_STATE ; piece holder = $HOLDER ; pending orders on #B02 = $LIVE"
if [ -z "${V_ORDER:-}" ]; then
  echo "INCONCLUSIVE 14.5 setup failed"
elif [ "$WINS" = "0" ]; then
  echo "FINDING 14.5 nobody could buy the piece: the expired, unclaimed hold still blocks it until the reaper runs"
elif [ "$WINS" = "1" ] && [ "$V_STATE" = "cancelled/expired" ] && [ "$HOLDER" = "new-buyer" ] && [ "$LIVE" = "1" ]; then
  echo "PASS 14.5 lazy expiry released the stale hold once; exactly one racer reserved the piece"
else
  echo "FAIL 14.5 successes=$WINS stale=$V_STATE holder=$HOLDER pending=$LIVE"
fi

MISMATCH=$(ledger_mismatches)
if [ "$MISMATCH" = "0" ]; then
  echo "PASS 14.6 ledger invariant after all concurrent cases: total_paid_paisa = verified ledger sum for every order"
else
  echo "FAIL 14.6 $MISMATCH order(s) whose total_paid_paisa differs from the verified ledger sum"
fi
