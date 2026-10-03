#!/usr/bin/env bash
# =============================================================================
# Runs the audit-only Flutter tests against a SCRATCH COPY of seller-app so the
# product tree is never modified. Requires Flutter 3.41.6 (seller-app/.metadata).
#
# Usage: FLUTTER=/path/to/flutter WORK=/tmp/ld-seller ./run_flutter_audit_tests.sh
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
FLUTTER="${FLUTTER:-flutter}"
WORK="${WORK:-$(mktemp -d)/seller-app}"
EVIDENCE="$REPO/audit/seller-app/evidence"
mkdir -p "$EVIDENCE"

rm -rf "$WORK" && mkdir -p "$(dirname "$WORK")"
cp -r "$REPO/seller-app" "$WORK"
mkdir -p "$WORK/test/audit"
cp "$HERE"/*.dart "$WORK/test/audit/"

cd "$WORK"
"$FLUTTER" pub get --enforce-lockfile > /dev/null
TZ=Asia/Kolkata "$FLUTTER" test --no-pub --reporter expanded test/audit 2>&1 | tee "$EVIDENCE/flutter-audit-tests.out"
exit "${PIPESTATUS[0]}"
