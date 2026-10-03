# 00 — Executive Summary: LiveDrop Seller App Audit

| | |
|---|---|
| Repository / commit | `psuvraneel-cyber/LiveDrop` @ `94ccfc9a1648270d9c87f9f7f0e6a32428f9069d`; `origin/main` advanced to `e745a0a` during the audit (buyer-web styling, Vercel Analytics, a test-seller script — nothing under `seller-app/`, `supabase/` or `.github/`), so the results apply to `main` too |
| Date | 2026-10-03 |
| Scope | Primary: Flutter seller app. Secondary: Supabase migrations/RPC/RLS/Storage/Realtime, buyer-web and CI only where they affect seller workflows |
| Mode | Audit + improvement discovery. **No product code, migration, configuration, CI or Git-history change was made.** All artifacts are under `audit/seller-app/`. |
| Executed | 33/33 migrations applied to a local PostgreSQL 16 behind a Supabase-compatible shim; SQL proof suites 10–18 (all inside rolled-back transactions; concurrency suite with parallel sessions); 26 audit Flutter tests against the real app code; existing tests (49 Flutter, 655 buyer Vitest); `flutter analyze`; read-only GitHub Actions history |
| Not executed | Hosted Supabase (no credentials, by design — read-only checks provided), Android device/emulator (SDK download blocked, no device), real UPI/courier/printer integrations |

## Verdict: **NOT READY** (hosted state and device behaviour: BLOCKED BY MISSING EVIDENCE)

| | Count |
|---|---|
| Findings | **95** |
| Severity | 7 CRITICAL · 12 HIGH · 50 MEDIUM · 26 LOW |
| Priority | **11 P0** · 47 P1 · 33 P2 · 4 P3 |
| Evidence | 46 proven by execution (local DB, local Flutter, hosted CI history) · 43 established by code/config/history reading · 6 inferred or blocked (device / hosted) |

The seller app has a sound server-side foundation, but it is not safe to put in front of real sellers and buyers yet: one public database object lets anyone change sellers' storefront settings, several payment edge paths record or lose money incorrectly, abandoned reservations stay locked for hours, the app shows no live state and raises no alerts during a live, and the Android release is signed with a debug key.

## P0 — must be fixed before real sellers

| ID | Sev | What | Proof |
|---|---|---|---|
| SA-SEC-001 | CRITICAL | Anyone with the public anon key can UPDATE/DELETE approved sellers' rows through `public_seller_storefronts` (phone, UPI on/off, fees, advance, slug) | 10.3–10.5, 10.9 |
| SA-SEC-002 | CRITICAL | A seller password is in public Git history (commit `0abdaeb`); rotation not evidenced | git history |
| SA-PAY-001 | CRITICAL | A late **advance** claim, when verified, marks the order **fully paid**; the ledger holds only the advance | 13.5c |
| SA-PAY-002 | CRITICAL | Verifying a late claim races new checkouts → **two fully paid orders for one unique piece** | 14.2/14.2b |
| SA-PAY-003 | CRITICAL | A buyer's claimed payment not verified within 24 h is expired, the order cancelled, the piece released — and it disappears from the app | 13.8 |
| SA-PAY-004 | CRITICAL | Verifying a late claim for a resold piece creates a refund obligation that the app ignores and never shows | 13.6, T20 |
| SA-OPS-001 | CRITICAL | The reaper runs ≈5×/day (median gap 5 h 07 min), not every 5 min; checkout has no lazy expiry → abandoned holds lock pieces for hours | GitHub Actions history |
| SA-PAY-005 | HIGH | "Release" cancels an order whose buyer already paid and claimed; the claim can then never be verified | 16.1b |
| SA-INT-001 | HIGH | Product codes like `101`/`SAREE01` are accepted, shown as "Available", and fail silently in the background forever | 12.1, T17 |
| SA-RT-001 | HIGH | No live updates on Home, Products or Payments; the Kanban subscribes only when one drop is selected (default: none) | code |
| SA-AND-001 | HIGH | Release build signed with the debug key; CI produces only a debuggable APK | build.gradle.kts, CI |

## What works (verified) — keep it
- Seller isolation on all base tables, RPCs and storage folders (11.1–11.5a PASS); buyers need the order token (10.8 PASS).
- Lifecycle guards: direct product/order lifecycle updates blocked; direct drop closure blocked; go-live requires approval; ship requires full payment + ready; double ship rejected (12.2a/b, 12.4a, 12.6, 12.8, 12.10b PASS).
- On-time payment verification is correct and idempotent with a unique verified reference (13.1, 13.3b PASS); `close_drop` preserves claimed orders (16.2 PASS); paid/expired orders cannot be deleted (17.2/17.3 PASS).
- 40 concurrent checkouts on one piece → exactly one winner (14.1 PASS).
- 20/20 SECURITY DEFINER functions pin `search_path`; no service-role key in client code; money is integer paisa end-to-end.
- `flutter analyze` clean; 49/49 Flutter and 655/655 buyer tests pass; camera-first multi-angle intake with correct EXIF orientation (T22).

## Documentation vs implementation

| Document claim | Implementation | Active truth | Finding |
|---|---|---|---|
| RTM REQ-FR-S2.1/S2.2: live dashboard + metric counters via Realtime — "Implemented" (`docs/06…:48-49`) | Dashboard loads once; no subscription | Not implemented | SA-RT-001, SA-DOC-001 |
| RTM REQ-FR-S3.1: Kanban via Realtime — "Implemented" (`:51`) | Only when one drop is selected | Partial | SA-RT-001 |
| RTM REQ-FR-S3.2: order actions via `rpc/mark_order_paid` (`:52`) | RPC is service-role only; client method throws | Not available to sellers (by design since F-01) | SA-DOC-001 |
| RTM REQ-FR-S1.5: password reset — "Implemented" (`:57`) | Reset e-mail sent; no way to set a new password | Not completable | SA-AUTH-001 |
| RTM REQ-BLK-1G / ADR-006: SQLite queue, connectivity_plus retries, delete on sync, block go-live until synced | JSON file in cache dir, timer retries, never deleted, go-live not blocked | Partial | SA-OFF-001/002, SA-DROP-004 |
| ADR-005: WebP q80 < 200 KB via `flutter_image_compress`, bucket `products`, Cloudflare CDN | JPEG q85 via pure-Dart `image`, bucket `product-images`, no CDN | Different | SA-PERF-003 |
| docs/09:79-80: closed → live/draft "Strictly Forbidden" | Allowed in DB and offered in UI | Allowed | SA-DROP-001 |
| docs/14:89: channel `seller:{seller_id}:orders` | `seller-orders-<dropId>` per drop | Different | SA-DOC-001 |
| docs/22: seller performance budgets | Unmeasured on device; compression above budget on host | Unverified | SA-PERF-003, SA-AND-005 |
| docs/33: MVP = one "User Zero" boutique | Open self-registration with ₹50 fee exists in the app | Broader than documented scope | informational |
| docs/00 (2026-09-11): "READY FOR CODING" gate report | Stale relative to the implemented system | Stale | SA-DOC-001 |
| RTM REQ-RC-03 and other docs reference `RELEASE-CANDIDATE-INTEGRATION-MATRIX.md`, `FINAL-RELEASE-CANDIDATE-REPORT.md`, `IMPLEMENTATION-LOG.md`, `TASK-2.4A.1-HARDENING-REPORT.md`, `TASK-2.5-PRODUCTION-READINESS-REPORT.md`, `TASK-2.5A-STAGING-VALIDATION-REPORT.md`, `TEST_READY.md` | Files do not exist | Missing evidence | SA-DOC-001 |
| Prior audit AUD-001 (rotate + purge the staging credential) | Removed from HEAD only | Open | SA-SEC-002 |
| Migration 033 "hide seller UPI from public storefronts" | UPI hidden — but the same view is writable by anonymous users | Partially effective | SA-SEC-001 |

## Previously suspected areas (brief section 36) — verified status

| Area | Status at `94ccfc9` | Evidence |
|---|---|---|
| Seller provisioning / registration security | Self-registration via sign-up trigger; unapproved by default; fee proof unstructured; unapproved uploads possible | 04, SA-ONB-001, SA-SEC-003 |
| Seller approval gate | **Server: fixed** (go-live blocked, 12.6). Client: fails open (T07). Suspension: ineffective (12.7) | SA-AUTH-002, SA-ONB-002 |
| Product price mutation restrictions | **Fixed** — direct updates blocked; `update_product` only for available pieces (12.2a/b) | PASS |
| Product editing | **Works** for available pieces; no hide/delete; Mark Sold irreversible | SA-INV-001/006 |
| Camera intake reliability | Functional; orientation correct (T22); invalid input fails late; lifecycle needs device test | SA-INT-001, SA-AND-004 |
| Offline seller intake | **Partial** — queue exists; not durable/idempotent; races (T25) | SA-OFF-001/003 |
| Image persistence | Local copies in cache dir, never pruned; public bucket listable | SA-OFF-002, SA-SEC-008 |
| FCM / background notifications | **Absent** | SA-NOT-001 |
| Payment verification | On-time path **correct**; edge paths broken | SA-PAY-001…006 |
| Late UPI payment recovery | Implemented (023) but **defective** (advance → paid in full, race, refunds invisible, constraint error) | SA-PAY-001/002/004/006 |
| Drop closure and stranded reservations | `close_drop` **correct** (16.2); stranded holds come from reaper cadence and Release | SA-OPS-001, SA-PAY-005 |
| Fulfilment transition enforcement | **Enforced server-side** (12.8); UI shortcuts misleading | SA-ORD-005, SA-SHIP-001 |
| Buyer URL generation | **Correct** (`/drop/<slug>`); product anchors unsupported | SA-DROP-006 |
| Buyer catalogue synchronisation | Buyer side good (Realtime + polling + versions); threshold mismatch; seller side stale | SA-PAY-008, SA-RT-001 |
| Realtime reliability | Seller side minimal | SA-RT-001/002 |
| Admin/operator tooling | **Absent** (SQL only) | SA-OPS-002 |
| Retention/purge | **Absent** | SA-OPS-003 |
| Disaster recovery | **Undocumented/untested** | SA-OPS-004 |
| Observability | **Absent** | SA-OBS-001 |

## Recommended order of work (detail in [22](22-IMPROVEMENT-ROADMAP.md))
1. **Wave 0 (days):** lock the storefront view and storage listing; rotate/purge the credential; create the release keystore.
2. **Wave 1:** payment correctness (late claims, claim expiry, refunds, claim-aware release), in-database hold expiry with lazy expiry, intake validation, DB tests in CI.
3. **Wave 2:** live session store + Live Command Center, push notifications, verification card, fulfilment fixes, durable queue, crash reporting, device validation, then a single-seller pilot.
4. **Wave 3:** remaining P1/P2.

## Artifact index

| Artifact | Purpose |
|---|---|
| [FINAL-SELLER-APP-READINESS.md](FINAL-SELLER-APP-READINESS.md) | Classification, the 25 answers, P0–P3 lists, remaining work by area |
| [FINDINGS.json](FINDINGS.json) | Machine-readable register (95 findings, all required fields) |
| [01](01-REPOSITORY-MAP.md) … [21](21-LIVE-SELLING-SCENARIOS.md) | Area reports |
| [22-IMPROVEMENT-ROADMAP.md](22-IMPROVEMENT-ROADMAP.md) | A–F roadmap with sequencing |
| [02-ARCHITECTURE.mmd](02-ARCHITECTURE.mmd) | Architecture diagram (Mermaid) |
| [README.md](README.md) | How to re-run every test and the hosted read-only checks |
| `tests/sql/`, `tests/flutter/` | Audit-only proof suites |
| `evidence/` | Raw outputs of every run |

## Appendix — full findings register

| ID | Sev | Pri | Category | Summary | Evidence | Report |
|---|---|---|---|---|---|---|
| SA-OPS-001 | CRITICAL | P0 | Reliability | Reaper runs ~5x/day instead of every 5 min; holds last hours | PROVEN-HOSTED | [11-REALTIME-AUDIT.md](11-REALTIME-AUDIT.md) |
| SA-PAY-001 | CRITICAL | P0 | Payments | Late advance verified as full payment (order paid, ledger shows advance) | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-002 | CRITICAL | P0 | Payments | Late-claim verification race sells one piece to two buyers | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-003 | CRITICAL | P0 | Payments | Buyer-claimed payments silently expire after 24 h and vanish | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-004 | CRITICAL | P0 | Payments | Refund-owed late payments are invisible in the app | PROVEN-LOCAL-DB + PROVEN-LOCAL-FLUTTER | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-SEC-001 | CRITICAL | P0 | Security | Anonymous users can rewrite/delete seller storefront rows via public_seller_storefronts | PROVEN-LOCAL-DB | [15-SECURITY-AUDIT.md](15-SECURITY-AUDIT.md) |
| SA-SEC-002 | CRITICAL | P0 | Security | Seller password in public Git history; rotation unverified | PROVEN-CODE (git history); rotation NOT TESTED | [15-SECURITY-AUDIT.md](15-SECURITY-AUDIT.md) |
| SA-AND-001 | HIGH | P0 | Android | Release signed with debug key; CI ships a debug APK | PROVEN-CODE | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-INT-001 | HIGH | P0 | Inventory | Invalid product codes/titles accepted, shown as Available, fail silently | PROVEN-LOCAL-DB + PROVEN-LOCAL-FLUTTER | [06-PRODUCT-INVENTORY-AUDIT.md](06-PRODUCT-INVENTORY-AUDIT.md) |
| SA-PAY-005 | HIGH | P0 | Payments | 'Release' cancels orders whose buyer already paid and claimed | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-RT-001 | HIGH | P0 | Realtime | No live updates on Home/Products/Payments; Kanban only per selected drop | PROVEN-CODE | [11-REALTIME-AUDIT.md](11-REALTIME-AUDIT.md) |
| SA-AUTH-001 | HIGH | P1 | Authentication | Password reset cannot be completed | PROVEN-CODE | [03-AUTH-AUDIT.md](03-AUTH-AUDIT.md) |
| SA-NOT-001 | HIGH | P1 | Notifications | No push or local notifications; settings toggles are fake | PROVEN-CODE | [13-NOTIFICATION-AUDIT.md](13-NOTIFICATION-AUDIT.md) |
| SA-OBS-001 | HIGH | P1 | Observability | No crash reporting/telemetry; 33 swallowed errors | PROVEN-CODE | [19-CODE-QUALITY-AUDIT.md](19-CODE-QUALITY-AUDIT.md) |
| SA-OFF-001 | HIGH | P1 | Offline resilience | Intake queue in cache dir; corrupt manifest loses all items | PROVEN-LOCAL-FLUTTER | [12-OFFLINE-RESILIENCE-AUDIT.md](12-OFFLINE-RESILIENCE-AUDIT.md) |
| SA-PAY-006 | HIGH | P1 | Payments | Late advance on a resold piece cannot be recorded (constraint error) | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-007 | HIGH | P1 | Payments | Any fake UTR locks a piece for 24 hours | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-008 | HIGH | P1 | Payments | Free-shipping threshold computed four ways; drop threshold ignored | PROVEN-LOCAL-DB + PROVEN-CODE | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-SHIP-001 | HIGH | P1 | Shipping | Shipping shortcut ships the first order with a placeholder AWB | PROVEN-LOCAL-FLUTTER | [14-SHIPPING-AUDIT.md](14-SHIPPING-AUDIT.md) |
| SA-AND-003 | MEDIUM | P1 | Android | No deep links / App Links | PROVEN-CODE | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-AND-005 | MEDIUM | P1 | Testing | No physical-device validation evidence | NOT TESTED | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-AUTH-002 | MEDIUM | P1 | Authentication | Approval gate fails open on profile load errors | PROVEN-LOCAL-FLUTTER | [03-AUTH-AUDIT.md](03-AUTH-AUDIT.md) |
| SA-AUTH-003 | MEDIUM | P1 | Authentication | Weak password policy / no e-mail confirmation (local; hosted unknown) | PROVEN-CODE (local config) / NOT TESTED (hosted) | [03-AUTH-AUDIT.md](03-AUTH-AUDIT.md) |
| SA-AUTH-004 | MEDIUM | P1 | Authentication | Payee UPI change without re-auth, notice or audit | PROVEN-CODE | [03-AUTH-AUDIT.md](03-AUTH-AUDIT.md) |
| SA-CI-001 | MEDIUM | P1 | CI/CD | Floating Flutter, no migration job, no secret scan | PROVEN-CODE | [20-TEST-COVERAGE-AUDIT.md](20-TEST-COVERAGE-AUDIT.md) |
| SA-CQ-001 | MEDIUM | P1 | Code quality | No shared state; tabs never refresh after actions | PROVEN-CODE | [19-CODE-QUALITY-AUDIT.md](19-CODE-QUALITY-AUDIT.md) |
| SA-DB-001 | MEDIUM | P1 | Database | Hosted schema state unverifiable | BLOCKED BY MISSING EVIDENCE | [05-DATABASE-INTEGRATION-AUDIT.md](05-DATABASE-INTEGRATION-AUDIT.md) |
| SA-DROP-001 | MEDIUM | P1 | Drops | Closed drops can be reopened (docs forbid); wrong dialog copy | PROVEN-LOCAL-DB + PROVEN-CODE | [07-DROP-AUDIT.md](07-DROP-AUDIT.md) |
| SA-DROP-002 | MEDIUM | P1 | Drops | Drop slug editable while live | PROVEN-LOCAL-DB | [07-DROP-AUDIT.md](07-DROP-AUDIT.md) |
| SA-DROP-004 | MEDIUM | P1 | Drops | No pre-live readiness gate | PROVEN-CODE | [07-DROP-AUDIT.md](07-DROP-AUDIT.md) |
| SA-INT-002 | MEDIUM | P1 | Data integrity | Seller verification and reaper deadlock | PROVEN-LOCAL-DB | [05-DATABASE-INTEGRATION-AUDIT.md](05-DATABASE-INTEGRATION-AUDIT.md) |
| SA-INV-001 | MEDIUM | P1 | Inventory | Mark Sold offered on reserved pieces; no undo | PROVEN-LOCAL-DB + PROVEN-CODE | [06-PRODUCT-INVENTORY-AUDIT.md](06-PRODUCT-INVENTORY-AUDIT.md) |
| SA-INV-002 | MEDIUM | P1 | Inventory | Add Product can silently target a closed drop | PROVEN-CODE | [06-PRODUCT-INVENTORY-AUDIT.md](06-PRODUCT-INVENTORY-AUDIT.md) |
| SA-OFF-003 | MEDIUM | P1 | Offline resilience | Intake queue not idempotent; races and permanent errors loop forever | PROVEN-LOCAL-FLUTTER | [12-OFFLINE-RESILIENCE-AUDIT.md](12-OFFLINE-RESILIENCE-AUDIT.md) |
| SA-ONB-001 | MEDIUM | P1 | Seller onboarding | Onboarding fee UTR only in auth metadata; SQL-only approval | PROVEN-CODE | [04-ONBOARDING-AUDIT.md](04-ONBOARDING-AUDIT.md) |
| SA-ONB-002 | MEDIUM | P1 | Seller onboarding | Suspension does not stop a live drop selling | PROVEN-LOCAL-DB | [04-ONBOARDING-AUDIT.md](04-ONBOARDING-AUDIT.md) |
| SA-OPS-002 | MEDIUM | P1 | Operations | No operator tooling; approvals and refunds need SQL | PROVEN-CODE | [04-ONBOARDING-AUDIT.md](04-ONBOARDING-AUDIT.md) |
| SA-OPS-004 | MEDIUM | P1 | Operations | No tested backup/restore; free-tier pause risk | DOCUMENTED / NOT TESTED | [15-SECURITY-AUDIT.md](15-SECURITY-AUDIT.md) |
| SA-ORD-001 | MEDIUM | P1 | Orders | Times shown in UTC (cards, labels, analytics) | PROVEN-LOCAL-FLUTTER | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-ORD-002 | MEDIUM | P1 | Orders | WhatsApp drops +91 for numbers starting with 91 | PROVEN-LOCAL-FLUTTER | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-ORD-003 | MEDIUM | P1 | Orders | Order details crash on names with double spaces | PROVEN-LOCAL-FLUTTER | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-ORD-004 | MEDIUM | P1 | Orders | Cancelled/expired/refund-owed orders hidden | PROVEN-LOCAL-FLUTTER | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-ORD-005 | MEDIUM | P1 | Orders | UI order actions don't match the server state machine | PROVEN-LOCAL-FLUTTER | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-PAY-009 | MEDIUM | P1 | Payments | Verification card lacks type, garment, deadline and consequences | PROVEN-LOCAL-FLUTTER | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-010 | MEDIUM | P1 | Payments | Reject always releases the hold (no 'ask to fix' path) | PROVEN-LOCAL-FLUTTER + PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-011 | MEDIUM | P1 | Payments | Duplicate-UTR check is case-sensitive and verify-time only | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-012 | MEDIUM | P1 | Payments | UPI disabled still accepts reservations | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-013 | MEDIUM | P1 | Payments | WhatsApp reminder: wrong amount, raw UPI ID, no order link | PROVEN-CODE | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-018 | MEDIUM | P1 | Payments | Refund-owed ledger rows deletable through order deletion | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PERF-001 | MEDIUM | P1 | Performance | Unpaginated nested order downloads (~2.4 MB per season) | PROVEN-LOCAL-DB / INFERRED | [17-PERFORMANCE-AUDIT.md](17-PERFORMANCE-AUDIT.md) |
| SA-RT-002 | MEDIUM | P1 | Realtime | No reconnect/catch-up; full refetch per realtime event | PROVEN-CODE / INFERRED | [11-REALTIME-AUDIT.md](11-REALTIME-AUDIT.md) |
| SA-SEC-003 | MEDIUM | P1 | Security | Unapproved accounts can upload to the public product-images bucket | PROVEN-LOCAL-DB | [15-SECURITY-AUDIT.md](15-SECURITY-AUDIT.md) |
| SA-SEC-004 | MEDIUM | P1 | Security | EXIF (device, GPS) published with product photos | PROVEN-LOCAL-FLUTTER | [15-SECURITY-AUDIT.md](15-SECURITY-AUDIT.md) |
| SA-SEC-008 | MEDIUM | P1 | Security | Anyone can list every stored image, including unpublished drops | PROVEN-LOCAL-DB | [15-SECURITY-AUDIT.md](15-SECURITY-AUDIT.md) |
| SA-SHIP-002 | MEDIUM | P1 | Shipping | Label prints PREPAID on balance-due orders; fake barcode | PROVEN-CODE | [14-SHIPPING-AUDIT.md](14-SHIPPING-AUDIT.md) |
| SA-TEST-001 | MEDIUM | P1 | Testing | Tests don't cover money, inventory, auth or concurrency | PROVEN-LOCAL | [20-TEST-COVERAGE-AUDIT.md](20-TEST-COVERAGE-AUDIT.md) |
| SA-UX-001 | MEDIUM | P1 | UI/UX | No live command view; no global search; LIVE shown green | PROVEN-CODE | [18-UI-UX-AUDIT.md](18-UI-UX-AUDIT.md) |
| SA-UX-002 | MEDIUM | P1 | UI/UX | Placeholder controls fake success | PROVEN-CODE | [18-UI-UX-AUDIT.md](18-UI-UX-AUDIT.md) |
| SA-AND-002 | MEDIUM | P2 | Android | Unused Bluetooth permissions | PROVEN-CODE | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-ANL-001 | MEDIUM | P2 | Analytics | Analytics not ledger-based; UTC days | PROVEN-CODE | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-DOC-001 | MEDIUM | P2 | Documentation | Docs claim features the code lacks | PROVEN-CODE | [00-EXECUTIVE-SUMMARY.md](00-EXECUTIVE-SUMMARY.md) |
| SA-DROP-003 | MEDIUM | P2 | Drops | live->draft bypasses safe closure (API) | PROVEN-LOCAL-DB | [07-DROP-AUDIT.md](07-DROP-AUDIT.md) |
| SA-INV-003 | MEDIUM | P2 | Inventory | Products insertable directly as sold/reserved | PROVEN-LOCAL-DB | [06-PRODUCT-INVENTORY-AUDIT.md](06-PRODUCT-INVENTORY-AUDIT.md) |
| SA-OFF-002 | MEDIUM | P2 | Offline resilience | Local intake files never pruned; Clear Cache is fake | PROVEN-LOCAL-FLUTTER | [12-OFFLINE-RESILIENCE-AUDIT.md](12-OFFLINE-RESILIENCE-AUDIT.md) |
| SA-OPS-003 | MEDIUM | P2 | Operations | No retention/purge of buyer PII | PROVEN-CODE | [05-DATABASE-INTEGRATION-AUDIT.md](05-DATABASE-INTEGRATION-AUDIT.md) |
| SA-ORD-006 | MEDIUM | P2 | Orders | No balance-collection tool for advance orders | PROVEN-CODE | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-PERF-003 | MEDIUM | P2 | Performance | Image output above ADR-005 / docs-22 budgets | PROVEN-LOCAL-FLUTTER / INFERRED | [17-PERFORMANCE-AUDIT.md](17-PERFORMANCE-AUDIT.md) |
| SA-SET-001 | MEDIUM | P2 | Settings | Silent fee fallbacks; profile threshold not editable | PROVEN-CODE | [09-ORDER-FULFILMENT-AUDIT.md](09-ORDER-FULFILMENT-AUDIT.md) |
| SA-UX-004 | MEDIUM | P2 | UI/UX | Small touch targets; actions out of thumb reach | PROVEN-CODE | [18-UI-UX-AUDIT.md](18-UI-UX-AUDIT.md) |
| SA-AND-004 | LOW | P2 | Android | Camera lifecycle needs device validation | INFERRED | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-AND-006 | LOW | P2 | Android | Back exits the app; lost picker data; no orientation lock | PROVEN-CODE / INFERRED | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-AUTH-005 | LOW | P2 | Authentication | Pushed screens survive sign-out | INFERRED | [03-AUTH-AUDIT.md](03-AUTH-AUDIT.md) |
| SA-DB-002 | LOW | P2 | Database | No ledger vs total_paid reconciliation | PROVEN-LOCAL-DB | [05-DATABASE-INTEGRATION-AUDIT.md](05-DATABASE-INTEGRATION-AUDIT.md) |
| SA-DB-003 | LOW | P2 | Database | No order/payment status history | PROVEN-LOCAL-DB | [05-DATABASE-INTEGRATION-AUDIT.md](05-DATABASE-INTEGRATION-AUDIT.md) |
| SA-DROP-005 | LOW | P2 | Drops | close_drop result ignored by the app | PROVEN-CODE | [07-DROP-AUDIT.md](07-DROP-AUDIT.md) |
| SA-DROP-006 | LOW | P2 | Drops | Product #CODE links not honoured; closed drop shows 'not found' | PROVEN-CODE | [07-DROP-AUDIT.md](07-DROP-AUDIT.md) |
| SA-INV-004 | LOW | P2 | Inventory | No price sanity check at intake | PROVEN-CODE | [06-PRODUCT-INVENTORY-AUDIT.md](06-PRODUCT-INVENTORY-AUDIT.md) |
| SA-INV-006 | LOW | P2 | Inventory | No way to hide or delete a mistaken piece | PROVEN-CODE | [06-PRODUCT-INVENTORY-AUDIT.md](06-PRODUCT-INVENTORY-AUDIT.md) |
| SA-ONB-003 | LOW | P2 | Seller onboarding | Registration errors swallowed; slug divergence; placeholder defaults | PROVEN-CODE | [04-ONBOARDING-AUDIT.md](04-ONBOARDING-AUDIT.md) |
| SA-ONB-004 | LOW | P2 | Seller onboarding | Pending screen lacks status; Settings hard-codes 'Verified' | PROVEN-CODE | [04-ONBOARDING-AUDIT.md](04-ONBOARDING-AUDIT.md) |
| SA-PAY-014 | LOW | P2 | Payments | Seller remarks discarded; RPC parameter name drift | PROVEN-LOCAL-FLUTTER + PROVEN-CODE | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-015 | LOW | P2 | Payments | UPI deep link breaks on '#' or '%' in payee name | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-016 | LOW | P2 | Payments | Buyer UTR overwritten without history | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PAY-017 | LOW | P2 | Payments | Unclaimed attempts can be verified with an internal reference | PROVEN-LOCAL-DB | [10-PAYMENT-AUDIT.md](10-PAYMENT-AUDIT.md) |
| SA-PERF-002 | LOW | P2 | Performance | Seven sequential requests on Home | PROVEN-CODE | [17-PERFORMANCE-AUDIT.md](17-PERFORMANCE-AUDIT.md) |
| SA-SEC-005 | LOW | P2 | Security | Cleartext HTTP allowed app-wide | PROVEN-CODE | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-SEC-006 | LOW | P2 | Security | Session refresh token included in Android backups | INFERRED | [16-ANDROID-AUDIT.md](16-ANDROID-AUDIT.md) |
| SA-SEC-007 | LOW | P2 | Security | anon can EXECUTE more functions than buyers need | PROVEN-LOCAL-DB | [15-SECURITY-AUDIT.md](15-SECURITY-AUDIT.md) |
| SA-SHIP-003 | LOW | P2 | Shipping | Courier default/free text; no tracking URL | PROVEN-CODE | [14-SHIPPING-AUDIT.md](14-SHIPPING-AUDIT.md) |
| SA-UX-003 | LOW | P2 | UI/UX | Low-contrast muted text; minimal screen-reader support | PROVEN-CODE | [18-UI-UX-AUDIT.md](18-UI-UX-AUDIT.md) |
| SA-UX-005 | LOW | P2 | UI/UX | Raw exception text shown to sellers | PROVEN-CODE | [18-UI-UX-AUDIT.md](18-UI-UX-AUDIT.md) |
| SA-AUTH-006 | LOW | P3 | Authentication | 'Remember me' does nothing | PROVEN-CODE | [03-AUTH-AUDIT.md](03-AUTH-AUDIT.md) |
| SA-CQ-002 | LOW | P3 | Code quality | Dead/placeholder code; missing mounted checks | PROVEN-CODE | [19-CODE-QUALITY-AUDIT.md](19-CODE-QUALITY-AUDIT.md) |
| SA-CQ-003 | LOW | P3 | Code quality | Admin UPI/WhatsApp/fee compiled into the app | PROVEN-CODE | [19-CODE-QUALITY-AUDIT.md](19-CODE-QUALITY-AUDIT.md) |
| SA-INV-005 | LOW | P3 | UI/UX | Codes rendered with a double hash (##A01) | PROVEN-CODE | [06-PRODUCT-INVENTORY-AUDIT.md](06-PRODUCT-INVENTORY-AUDIT.md) |

