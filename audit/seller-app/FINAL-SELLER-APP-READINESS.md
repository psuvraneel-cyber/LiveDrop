# FINAL — Seller App Readiness

| | |
|---|---|
| Audited commit | `94ccfc9a1648270d9c87f9f7f0e6a32428f9069d` (`origin/main` is now `e745a0a`; its changes touch buyer-web styling and scripts only — no seller-app, supabase or CI changes, so this verdict applies to `main` as well) |
| Date | 2026-10-03 |
| Evidence base | Local PostgreSQL with all 33 migrations + Supabase shim (suites 10–18), 26 audit Flutter tests, 49 existing Flutter tests, 655 buyer Vitest tests, `flutter analyze`, read-only GitHub Actions history. **No hosted database access and no Android device** were available. |
| Register | [FINDINGS.json](FINDINGS.json) — 95 findings: 7 CRITICAL, 12 HIGH, 50 MEDIUM, 26 LOW; P0 11 · P1 47 · P2 33 · P3 4 |

## Classification

# NOT READY

with two areas **BLOCKED BY MISSING EVIDENCE**: (1) hosted Supabase state (grants, migrations, auth settings, storage policies — scripts provided in `tests/sql/90_hosted_readonly_checks.sql`), and (2) physical-device behaviour (plan D1–D18 in [16](16-ANDROID-AUDIT.md)).

Why: anyone holding the public anon key can rewrite sellers' storefront settings (phone, UPI on/off, fees, slug); several payment paths record money wrongly or lose it (late advance marked fully paid, double sale race, claimed payments expiring silently, invisible refunds, Release destroying paid orders); abandoned holds stay locked for hours because the reaper actually runs about five times a day; the seller app shows no live state and sends no alerts during a live; release builds are signed with a debug key; and a seller credential sits in public Git history.

What is already solid (and must be preserved): server-side seller isolation on tables, RPCs and storage folders; product/order lifecycle immutability triggers; go-live approval gate; fulfilment prerequisites; idempotent on-time verification with a unique verified-reference ledger; a single winner among 40 concurrent checkouts; `close_drop` preserving buyer claims; 20/20 SECURITY DEFINER functions with pinned `search_path`; integer-paisa money everywhere; clean static analysis; camera-first multi-angle intake with correct orientation.

## The 25 questions

| # | Question | Answer |
|---|---|---|
| 1 | Can a real seller safely log in? | **Yes, with caveats.** E-mail/password login works and handles errors and timeouts well (code-verified). Caveats: password reset cannot be completed (SA-AUTH-001); local auth config allows 6-character passwords and no e-mail confirmation — hosted settings unverified (SA-AUTH-003); one seller credential is exposed in public history until rotated (SA-SEC-002). |
| 2 | Is authentication reliable? | **Partly.** Sessions persist and refresh via supabase_flutter. The approval gate fails open on any profile error (T07, SA-AUTH-002); pushed screens survive sign-out (SA-AUTH-005); no deep links. Isolation is enforced by the server, not the UI (suite 11 PASS). |
| 3 | Is onboarding safe and complete? | **No.** Self-registration works and new sellers cannot go live until approved (12.6 PASS), but fee proof lives only in auth metadata with SQL-only approval (SA-ONB-001), unapproved accounts can upload public files (SA-SEC-003), suspension does not stop a live drop (SA-ONB-002), and the pending/verified status shown is not trustworthy (SA-ONB-004). |
| 4 | Can sellers create products reliably? | **Not yet.** The happy path works, but any code that is not `#` + 1–6 letters/digits (e.g. `101`, `SAREE01`) or a title over 100 characters is accepted, shown as "Available", and fails silently in the background forever (SA-INT-001); the queue loses progress if intake is reopened during a sync (T25) and turns lost responses into permanent failures (SA-OFF-003). |
| 5 | Can sellers rapidly intake many garments? | **Mostly, by design; not reliably, by implementation.** 3–5 taps + price per garment (≈8–15 s estimated) fits the 30 s budget, but the queue sits in the cache directory, can be wiped by a corrupt manifest, is not processed at app start, and has no connectivity trigger (SA-OFF-001). Compression time on target phones is unverified (0.4–3.0 s on a dev host, SA-PERF-003). |
| 6 | Can sellers create and publish drops reliably? | **Yes for the core path** (create, go live with approval and one-live rule, safe close). Gaps: slug editable while live breaks shared links (SA-DROP-002), closed drops can be reopened contrary to the docs (SA-DROP-001), no pre-live checklist (SA-DROP-004), `close_drop` failures reported as success (SA-DROP-005). |
| 7 | Does the public buyer URL work correctly? | **Yes** — `{BUYER_BASE_URL}/drop/<slug>` matches the buyer route; storefront URLs are unit-tested. Caveats: `BUYER_BASE_URL` defaults to `livedrop-in.vercel.app` and is not passed by the build script; product `#CODE` links don't scroll to the piece and closed drops show "not found" (SA-DROP-006). End-to-end not run against a deployment. |
| 8 | Does seller inventory accurately propagate to buyers? | **Buyer side yes, seller side no.** Synced pieces reach buyers with Realtime + 3 s polling + version gating. Failed intake items look available only in the seller app (SA-INT-001); the seller's own Products tab is not live (SA-RT-001); expired holds stay "reserved" on both sides for hours (SA-OPS-001). |
| 9 | Can the seller manage live reservations efficiently? | **No.** No live updates outside one Kanban mode, no notifications, no attention queue, Release is unsafe when a claim exists, and abandoned holds linger for hours (SA-RT-001, SA-NOT-001, SA-PAY-005, SA-OPS-001; scenarios C–G, J). |
| 10 | Does payment verification work correctly? | **On-time path: yes** (13.1 PASS, idempotent). **Edge paths: no** — late advance marked fully paid (SA-PAY-001), late-claim race double-sells (SA-PAY-002), claimed payments expire silently after 24 h (SA-PAY-003), refunds owed invisible (SA-PAY-004), Release breaks claimed orders (SA-PAY-005), late advance on resold piece cannot be recorded (SA-PAY-006). |
| 11 | Is payment verification secure? | **Authorisation is sound** (only the owning seller can verify; ledger writes revoked; 11.4 PASS). Weaknesses: any fake UTR locks a piece for 24 h (SA-PAY-007), case-variant UTR reuse (SA-PAY-011), refund-owed ledger rows deletable via order deletion (SA-PAY-018), payee VPA changeable without re-auth (SA-AUTH-004), and payment settings (UPI on/off, advance amount) writable by anonymous users through the view (SA-SEC-001). |
| 12 | Are order states correct? | **The server state machine is mostly correct** (immutability triggers, ready/ship guards, double-ship protection). Incorrect states arise from late-claim verification (paid totals ≠ ledger; cancelled-but-paid orders) and the claim-blind Release. The UI misrepresents state: UTC times, hidden cancelled/expired/refund orders, claimed and unclaimed pending orders look identical (SA-ORD-001/004). |
| 13 | Can sellers fulfil orders without invalid transitions? | **Yes at the server** (12.8 PASS: no ship before full payment and ready). The UI offers impossible actions (Dispatch on balance-due orders, "Mark as Ready" that ships) and a shortcut that ships the wrong order with a fake AWB if it is shippable (SA-ORD-005, SA-SHIP-001). |
| 14 | Does shipping work correctly? | **Partly.** Dispatch with tracking works; labels print as 4×6 PDFs. Labels say "PREPAID – DO NOT COLLECT CASH" even with balance due and use a fake barcode without an AWB (SA-SHIP-002); the Home shortcut and "Auto" tracking produce fake tracking numbers (SA-SHIP-001); printing on real thermal printers untested. |
| 15 | Does Realtime behave correctly? | **Insufficiently.** Only order INSERT/UPDATE for a selected drop; no products/claims subscription; no reconnect/catch-up handling; full refetch per event (SA-RT-001/002). Buyer-side realtime is well designed. |
| 16 | What happens during network loss? | Intake keeps queueing (good) but sync resumes only on its own timer or when intake is reopened; other screens show zeros/empty lists or raw errors without an offline banner; a cold start offline opens an empty "approved" dashboard; actions retried after reconnect give confusing errors (except verify, which is idempotent). See [12](12-OFFLINE-RESILIENCE-AUDIT.md). |
| 17 | Are there crashes? | **One reproducible crash**: Order details throws `RangeError` for buyer names with consecutive spaces (T01, SA-ORD-003). Two `setState`-after-await paths without `mounted` checks (log errors). No crash reporting exists, so production crash rates are unknown (SA-OBS-001). Camera lifecycle needs device validation (SA-AND-004). |
| 18 | Are there security vulnerabilities? | **Yes.** CRITICAL: anonymous writes through `public_seller_storefronts` (SA-SEC-001); seller credential in public history (SA-SEC-002). Also: debug-key release signing (SA-AND-001), public listing of all images incl. unpublished drops (SA-SEC-008), unapproved uploads (SA-SEC-003), GPS EXIF in photos (SA-SEC-004), VPA change without re-auth (SA-AUTH-004), and lower-severity configuration issues. |
| 19 | Are there data integrity risks? | **Yes.** Double sale under the late-claim race (SA-PAY-002); totals diverging from the ledger (SA-PAY-001, SA-DB-002); ledger rows deletable via order cascade (SA-PAY-018); products insertable as sold/reserved (SA-INV-003); verify/reaper deadlock (SA-INT-002); no status history (SA-DB-003). |
| 20 | Are there performance bottlenecks? | **Client-side, yes**: unpaginated nested order downloads (≈2.4 MB for a seasoned seller, refetched on every realtime event), 7 sequential requests on Home, analytics over full history, slow pure-Dart image compression (SA-PERF-001/002/003). SQL itself is fast (suite 15). Device timings unmeasured. |
| 21 | Are current tests sufficient? | **No.** 49 seller tests cover rendering/parsing; none covers money, inventory, authorisation or concurrency; migrations are never applied in CI (SA-TEST-001, SA-CI-001). The audit suites (SQL 10–18, Flutter T01–T25) are ready to become CI regression tests. |
| 22 | What must be fixed before real sellers use the app? | The **11 P0 items** below: SA-SEC-001, SA-SEC-002, SA-PAY-001, SA-PAY-002, SA-PAY-003, SA-PAY-004, SA-PAY-005, SA-OPS-001, SA-INT-001, SA-RT-001, SA-AND-001 — plus running the hosted checks (H1–H13) and the device plan, which may add items. |
| 23 | What should be redesigned? | Information architecture for live selling: a Live Command Center with an urgency-sorted action queue, code pad, state-aware quick actions, a payment verification card with full context, a pipeline that shows closed/refund orders, and a Drop Control Center with a pre-live checklist ([18](18-UI-UX-AUDIT.md)). Server-side: one payment transition layer, claim-aware release, in-database scheduling. Visual identity stays. |
| 24 | What should be added? | Push notifications (claims, late claims, expiring windows, refunds); refund state and workflow; operator console (approvals, fee checks, refunds, stuck holds); re-authentication for payee changes; crash reporting; durable idempotent intake queue; undo for "sold elsewhere"; balance collection; hosted verification and migration pipeline; backups/restore drill. |
| 25 | What can wait until after launch? | P2/P3 items: analytics rebuild, retention/purge, ledger reconciliation job and status history, batch intake, global search, accessibility polish, courier/PSP integrations, staff roles, localisation, waitlists, comment integration ([22 §F](22-IMPROVEMENT-ROADMAP.md#f-future-features-do-not-block-launch)). |

## Blockers and improvements by priority

### P0 (11)

| ID | Sev | Area | Finding |
|---|---|---|---|
| SA-OPS-001 | CRITICAL | Reliability | Reaper runs ~5x/day instead of every 5 min; holds last hours |
| SA-PAY-001 | CRITICAL | Payments | Late advance verified as full payment (order paid, ledger shows advance) |
| SA-PAY-002 | CRITICAL | Data integrity | Late-claim verification race sells one piece to two buyers |
| SA-PAY-003 | CRITICAL | Payments | Buyer-claimed payments silently expire after 24 h and vanish |
| SA-PAY-004 | CRITICAL | Payments | Refund-owed late payments are invisible in the app |
| SA-SEC-001 | CRITICAL | Security | Anonymous users can rewrite/delete seller storefront rows via public_seller_storefronts |
| SA-SEC-002 | CRITICAL | Security | Seller password in public Git history; rotation unverified |
| SA-AND-001 | HIGH | Security | Release signed with debug key; CI ships a debug APK |
| SA-INT-001 | HIGH | Inventory | Invalid product codes/titles accepted, shown as Available, fail silently |
| SA-PAY-005 | HIGH | Payments | 'Release' cancels orders whose buyer already paid and claimed |
| SA-RT-001 | HIGH | Live selling | No live updates on Home/Products/Payments; Kanban only per selected drop |

### P1 (47)

| ID | Sev | Area | Finding |
|---|---|---|---|
| SA-AUTH-001 | HIGH | Authentication | Password reset cannot be completed |
| SA-NOT-001 | HIGH | Live selling | No push or local notifications; settings toggles are fake |
| SA-OBS-001 | HIGH | Observability | No crash reporting/telemetry; 33 swallowed errors |
| SA-OFF-001 | HIGH | Reliability | Intake queue in cache dir; corrupt manifest loses all items |
| SA-PAY-006 | HIGH | Payments | Late advance on a resold piece cannot be recorded (constraint error) |
| SA-PAY-007 | HIGH | Live selling | Any fake UTR locks a piece for 24 hours |
| SA-PAY-008 | HIGH | Payments | Free-shipping threshold computed four ways; drop threshold ignored |
| SA-SHIP-001 | HIGH | Shipping | Shipping shortcut ships the first order with a placeholder AWB |
| SA-AND-003 | MEDIUM | Authentication | No deep links / App Links |
| SA-AND-005 | MEDIUM | Reliability | No physical-device validation evidence |
| SA-AUTH-002 | MEDIUM | Authentication | Approval gate fails open on profile load errors |
| SA-AUTH-003 | MEDIUM | Authentication | Weak password policy / no e-mail confirmation (local; hosted unknown) |
| SA-AUTH-004 | MEDIUM | Security | Payee UPI change without re-auth, notice or audit |
| SA-CI-001 | MEDIUM | Reliability | Floating Flutter, no migration job, no secret scan |
| SA-CQ-001 | MEDIUM | Reliability | No shared state; tabs never refresh after actions |
| SA-DB-001 | MEDIUM | Reliability | Hosted schema state unverifiable |
| SA-DROP-001 | MEDIUM | Live selling | Closed drops can be reopened (docs forbid); wrong dialog copy |
| SA-DROP-002 | MEDIUM | Live selling | Drop slug editable while live |
| SA-DROP-004 | MEDIUM | Live selling | No pre-live readiness gate |
| SA-INT-002 | MEDIUM | Data integrity | Seller verification and reaper deadlock |
| SA-INV-001 | MEDIUM | Inventory | Mark Sold offered on reserved pieces; no undo |
| SA-INV-002 | MEDIUM | Inventory | Add Product can silently target a closed drop |
| SA-OFF-003 | MEDIUM | Data integrity | Intake queue not idempotent; races and permanent errors loop forever |
| SA-ONB-001 | MEDIUM | Seller onboarding | Onboarding fee UTR only in auth metadata; SQL-only approval |
| SA-ONB-002 | MEDIUM | Seller onboarding | Suspension does not stop a live drop selling |
| SA-OPS-002 | MEDIUM | Observability | No operator tooling; approvals and refunds need SQL |
| SA-OPS-004 | MEDIUM | Reliability | No tested backup/restore; free-tier pause risk |
| SA-ORD-001 | MEDIUM | Orders | Times shown in UTC (cards, labels, analytics) |
| SA-ORD-002 | MEDIUM | Orders | WhatsApp drops +91 for numbers starting with 91 |
| SA-ORD-003 | MEDIUM | Orders | Order details crash on names with double spaces |
| SA-ORD-004 | MEDIUM | Orders | Cancelled/expired/refund-owed orders hidden |
| SA-ORD-005 | MEDIUM | Orders | UI order actions don't match the server state machine |
| SA-PAY-009 | MEDIUM | Payments | Verification card lacks type, garment, deadline and consequences |
| SA-PAY-010 | MEDIUM | Payments | Reject always releases the hold (no 'ask to fix' path) |
| SA-PAY-011 | MEDIUM | Payments | Duplicate-UTR check is case-sensitive and verify-time only |
| SA-PAY-012 | MEDIUM | Payments | UPI disabled still accepts reservations |
| SA-PAY-013 | MEDIUM | Payments | WhatsApp reminder: wrong amount, raw UPI ID, no order link |
| SA-PAY-018 | MEDIUM | Data integrity | Refund-owed ledger rows deletable through order deletion |
| SA-PERF-001 | MEDIUM | Performance | Unpaginated nested order downloads (~2.4 MB per season) |
| SA-RT-002 | MEDIUM | Reliability | No reconnect/catch-up; full refetch per realtime event |
| SA-SEC-003 | MEDIUM | Security | Unapproved accounts can upload to the public product-images bucket |
| SA-SEC-004 | MEDIUM | Security | EXIF (device, GPS) published with product photos |
| SA-SEC-008 | MEDIUM | Security | Anyone can list every stored image, including unpublished drops |
| SA-SHIP-002 | MEDIUM | Shipping | Label prints PREPAID on balance-due orders; fake barcode |
| SA-TEST-001 | MEDIUM | Reliability | Tests don't cover money, inventory, auth or concurrency |
| SA-UX-001 | MEDIUM | Live selling | No live command view; no global search; LIVE shown green |
| SA-UX-002 | MEDIUM | UI/UX | Placeholder controls fake success |

### P2 (33)

| ID | Sev | Area | Finding |
|---|---|---|---|
| SA-AND-002 | MEDIUM | Security | Unused Bluetooth permissions |
| SA-ANL-001 | MEDIUM | Orders | Analytics not ledger-based; UTC days |
| SA-DOC-001 | MEDIUM | Documentation | Docs claim features the code lacks |
| SA-DROP-003 | MEDIUM | Data integrity | live->draft bypasses safe closure (API) |
| SA-INV-003 | MEDIUM | Data integrity | Products insertable directly as sold/reserved |
| SA-OFF-002 | MEDIUM | Reliability | Local intake files never pruned; Clear Cache is fake |
| SA-OPS-003 | MEDIUM | Data integrity | No retention/purge of buyer PII |
| SA-ORD-006 | MEDIUM | Payments | No balance-collection tool for advance orders |
| SA-PERF-003 | MEDIUM | Performance | Image output above ADR-005 / docs-22 budgets |
| SA-SET-001 | MEDIUM | UI/UX | Silent fee fallbacks; profile threshold not editable |
| SA-UX-004 | MEDIUM | UI/UX | Small touch targets; actions out of thumb reach |
| SA-AND-004 | LOW | Reliability | Camera lifecycle needs device validation |
| SA-AND-006 | LOW | Reliability | Back exits the app; lost picker data; no orientation lock |
| SA-AUTH-005 | LOW | Authentication | Pushed screens survive sign-out |
| SA-DB-002 | LOW | Data integrity | No ledger vs total_paid reconciliation |
| SA-DB-003 | LOW | Data integrity | No order/payment status history |
| SA-DROP-005 | LOW | Reliability | close_drop result ignored by the app |
| SA-DROP-006 | LOW | Live selling | Product #CODE links not honoured; closed drop shows 'not found' |
| SA-INV-004 | LOW | Inventory | No price sanity check at intake |
| SA-INV-006 | LOW | Inventory | No way to hide or delete a mistaken piece |
| SA-ONB-003 | LOW | Seller onboarding | Registration errors swallowed; slug divergence; placeholder defaults |
| SA-ONB-004 | LOW | Seller onboarding | Pending screen lacks status; Settings hard-codes 'Verified' |
| SA-PAY-014 | LOW | Payments | Seller remarks discarded; RPC parameter name drift |
| SA-PAY-015 | LOW | Payments | UPI deep link breaks on '#' or '%' in payee name |
| SA-PAY-016 | LOW | Payments | Buyer UTR overwritten without history |
| SA-PAY-017 | LOW | Payments | Unclaimed attempts can be verified with an internal reference |
| SA-PERF-002 | LOW | Performance | Seven sequential requests on Home |
| SA-SEC-005 | LOW | Security | Cleartext HTTP allowed app-wide |
| SA-SEC-006 | LOW | Security | Session refresh token included in Android backups |
| SA-SEC-007 | LOW | Security | anon can EXECUTE more functions than buyers need |
| SA-SHIP-003 | LOW | Shipping | Courier default/free text; no tracking URL |
| SA-UX-003 | LOW | UI/UX | Low-contrast muted text; minimal screen-reader support |
| SA-UX-005 | LOW | UI/UX | Raw exception text shown to sellers |

### P3 (4)

| ID | Sev | Area | Finding |
|---|---|---|---|
| SA-AUTH-006 | LOW | UI/UX | 'Remember me' does nothing |
| SA-CQ-002 | LOW | Documentation | Dead/placeholder code; missing mounted checks |
| SA-CQ-003 | LOW | Seller onboarding | Admin UPI/WhatsApp/fee compiled into the app |
| SA-INV-005 | LOW | UI/UX | Codes rendered with a double hash (##A01) |


## Remaining work by area

### Security (11)

- **SA-SEC-001** (P0) Anonymous users can rewrite/delete seller storefront rows via public_seller_storefronts → New migration: REVOKE ALL ON public.public_seller_storefronts FROM anon, authenticated.
- **SA-SEC-002** (P0) Seller password in public Git history; rotation unverified → Rotate the password and revoke all sessions for that user now (Supabase dashboard → Authentication → Users).
- **SA-AND-001** (P0) Release signed with debug key; CI ships a debug APK → Create an upload/release keystore (stored as CI secrets), sign release builds in CI, version codes, distribute via Play internal testing.
- **SA-AUTH-004** (P1) Payee UPI change without re-auth, notice or audit → Re-enter password (reauthenticate) for VPA/phone changes, e-mail notification, audit log table, warn while a drop is live.
- **SA-SEC-003** (P1) Unapproved accounts can upload to the public product-images bucket → Add AND public.is_seller_approved(auth.uid()) to insert/update policies.
- **SA-SEC-004** (P1) EXIF (device, GPS) published with product photos → Clear EXIF before encoding (orientation is already baked during decode, see T22).
- **SA-SEC-008** (P1) Anyone can list every stored image, including unpublished drops → Drop the anon/public SELECT policy (public object URLs keep working).
- **SA-AND-002** (P2) Unused Bluetooth permissions → Remove until a Bluetooth printer integration exists.
- **SA-SEC-005** (P2) Cleartext HTTP allowed app-wide → Remove usesCleartextTraffic (or restrict via network_security_config to 10.0.2.2/localhost for debug).
- **SA-SEC-006** (P2) Session refresh token included in Android backups → android:allowBackup="false" or dataExtractionRules excluding shared_prefs.
- **SA-SEC-007** (P2) anon can EXECUTE more functions than buyers need → REVOKE EXECUTE ... FROM anon (and PUBLIC) on seller/admin functions.

### Reliability (13)

- **SA-OPS-001** (P0) Reaper runs ~5x/day instead of every 5 min; holds last hours → Run the reaper inside Postgres (pg_cron every minute) or a Supabase scheduled Edge Function.
- **SA-OFF-001** (P1) Intake queue in cache dir; corrupt manifest loses all items → Move to the app documents/support directory with atomic writes (write-temp-then-rename) or SQLite as ADR-006 specifies.
- **SA-AND-005** (P1) No physical-device validation evidence → Run the 16-ANDROID-AUDIT device checklist on a low-end and a mid-range phone before real sellers.
- **SA-CI-001** (P1) Floating Flutter, no migration job, no secret scan → Pin Flutter version.
- **SA-CQ-001** (P1) No shared state; tabs never refresh after actions → A small app-level store (ChangeNotifier/Riverpod) fed by Realtime (SA-RT-001) with invalidation after mutations.
- **SA-DB-001** (P1) Hosted schema state unverifiable → supabase db push from CI with a migration ledger check.
- **SA-OPS-004** (P1) No tested backup/restore; free-tier pause risk → Scheduled logical dumps (pg_dump via GitHub Action to encrypted storage), documented and rehearsed restore, consider Pro tier before real volume.
- **SA-RT-002** (P1) No reconnect/catch-up; full refetch per realtime event → Track channel status, show a 'Live updates paused' banner, refetch on SUBSCRIBED after reconnect/resume.
- **SA-TEST-001** (P1) Tests don't cover money, inventory, auth or concurrency → Adopt the audit suites (tests/sql, tests/flutter) into CI with a disposable Postgres.
- **SA-OFF-002** (P2) Local intake files never pruned; Clear Cache is fake → Delete local files on 'completed' and compact the manifest.
- **SA-AND-004** (P2) Camera lifecycle needs device validation → Null the controller and flag on inactive, guard build, await re-init, handle errors.
- **SA-AND-006** (P2) Back exits the app; lost picker data; no orientation lock → PopScope on the shell (Back → Home tab, confirm exit while live).
- **SA-DROP-005** (P2) close_drop result ignored by the app → Parse the JSON result and throw on success=false (same pattern as other RPC wrappers).

### Data integrity (9)

- **SA-PAY-002** (P0) Late-claim verification race sells one piece to two buyers → Lock products FOR UPDATE (ORDER BY id) before evaluating availability.
- **SA-INT-002** (P1) Seller verification and reaper deadlock → Adopt one lock order (order → products → attempts) everywhere.
- **SA-OFF-003** (P1) Intake queue not idempotent; races and permanent errors loop forever → Generate the product UUID client-side (insert with id) or send an idempotency key.
- **SA-PAY-018** (P1) Refund-owed ledger rows deletable through order deletion → Block deletion of any order that has order_payments rows (or payment_status <> 'unpaid').
- **SA-DROP-003** (P2) live->draft bypasses safe closure (API) → Route all status changes through RPCs (go_live, close_drop, unpublish with the same claim-preserving rules).
- **SA-INV-003** (P2) Products insertable directly as sold/reserved → BEFORE INSERT trigger or CHECK forcing status='available', reserved_* NULL on insert by authenticated.
- **SA-OPS-003** (P2) No retention/purge of buyer PII → Define retention (e.g. cancelled/expired orders anonymised after N days).
- **SA-DB-002** (P2) No ledger vs total_paid reconciliation → Constraint trigger or nightly reconciliation (H11) with alerting.
- **SA-DB-003** (P2) No order/payment status history → Append-only order_events table written by the RPCs.

### Authentication (5)

- **SA-AUTH-001** (P1) Password reset cannot be completed → Deep link (App Link) handling for type=recovery with an in-app 'Set new password' screen, or a hosted reset page.
- **SA-AND-003** (P1) No deep links / App Links → Verified App Links for a seller domain path + route handling.
- **SA-AUTH-002** (P1) Approval gate fails open on profile load errors → Three states: loading, error (retry), loaded.
- **SA-AUTH-003** (P1) Weak password policy / no e-mail confirmation (local; hosted unknown) → Hosted: min length ≥ 10 with leaked-password protection, e-mail confirmation on, rate limits.
- **SA-AUTH-005** (P2) Pushed screens survive sign-out → On signedOut, popUntil(isFirst) / rebuild a fresh Navigator.

### Seller onboarding (5)

- **SA-ONB-001** (P1) Onboarding fee UTR only in auth metadata; SQL-only approval → seller_applications table (fee UTR, amount, status, reviewer, timestamps) + operator view/script.
- **SA-ONB-002** (P1) Suspension does not stop a live drop selling → Checkout and payment RPCs must require is_seller_approved.
- **SA-ONB-003** (P2) Registration errors swallowed; slug divergence; placeholder defaults → Single server-side provisioning path.
- **SA-ONB-004** (P2) Pending screen lacks status; Settings hard-codes 'Verified' → Bind to is_approved/application status.
- **SA-CQ-003** (P3) Admin UPI/WhatsApp/fee compiled into the app → Serve from a platform_settings table.

### Live selling (8)

- **SA-RT-001** (P0) No live updates on Home/Products/Payments; Kanban only per selected drop → One app-level live session store subscribed to orders, payment_attempts and products for the active drop (seller-scoped), driving Home, Products, Orders and Payments b….
- **SA-NOT-001** (P1) No push or local notifications; settings toggles are fake → FCM (data messages) triggered by DB events (Edge Function/webhook) for new claim, late claim, new order and claim-expiring.
- **SA-PAY-007** (P1) Any fake UTR locks a piece for 24 hours → During a live drop cap the claim-extended hold (e.g. 60-120 min) and escalate to the seller.
- **SA-DROP-001** (P1) Closed drops can be reopened (docs forbid); wrong dialog copy → Decide the rule (ADR): either forbid reopen in the trigger or document it.
- **SA-DROP-002** (P1) Drop slug editable while live → Lock slug once live (trigger + read-only field), or keep old slugs as redirects.
- **SA-DROP-004** (P1) No pre-live readiness gate → Pre-flight sheet: N pieces live, M syncing/failed, UPI ON with VPA, link ready (copy/share) — block or warn.
- **SA-UX-001** (P1) No live command view; no global search; LIVE shown green → Live Command Center (see 18-UI-UX-AUDIT.md redesign): exception queue, code search, claim queue inline, one-handed bottom actions.
- **SA-DROP-006** (P2) Product #CODE links not honoured; closed drop shows 'not found' → Give product cards id=<code> (and scroll/highlight on load).

### Inventory (5)

- **SA-INT-001** (P0) Invalid product codes/titles accepted, shown as Available, fail silently → Normalise and validate the code at entry (auto-prefix '#', uppercase, max 6, A-Z/0-9) with inline error.
- **SA-INV-001** (P1) Mark Sold offered on reserved pieces; no undo → Disable Mark Sold for reserved pieces with an explanation.
- **SA-INV-002** (P1) Add Product can silently target a closed drop → Never target a closed drop: prompt to create a new drop or pick a draft.
- **SA-INV-004** (P2) No price sanity check at intake → Show the formatted price prominently, warn when > N× drop median, optional quick price chips.
- **SA-INV-006** (P2) No way to hide or delete a mistaken piece → 'Hide from buyers' / 'Delete draft piece' via an RPC that refuses pieces referenced by orders.

### Orders (6)

- **SA-ORD-001** (P1) Times shown in UTC (cards, labels, analytics) → Convert to local (or explicit Asia/Kolkata) at the model boundary.
- **SA-ORD-002** (P1) WhatsApp drops +91 for numbers starting with 91 → If 10 digits → prefix 91.
- **SA-ORD-003** (P1) Order details crash on names with double spaces → split(RegExp(r'\s+')) with empty-part filtering.
- **SA-ORD-004** (P1) Cancelled/expired/refund-owed orders hidden → 'Closed' tab or filter with reasons (expired, released, rejected, refund owed).
- **SA-ORD-005** (P1) UI order actions don't match the server state machine → Derive actions from (status, payment_status, fulfilment_status) exactly as the RPCs do.
- **SA-ANL-001** (P2) Analytics not ledger-based; UTC days → Ledger-based SQL aggregation in IST.

### Payments (16)

- **SA-PAY-001** (P0) Late advance verified as full payment (order paid, ledger shows advance) → In the late branch apply the same per-type transition as the on-time path (advance → confirmed/advance_paid with balance due).
- **SA-PAY-003** (P0) Buyer-claimed payments silently expire after 24 h and vanish → Never auto-expire an attempt with a buyer UTR: move it to late_claim_pending_review (or a 'needs_review' state) and keep it in the queue.
- **SA-PAY-004** (P0) Refund-owed late payments are invisible in the app → Add refund_status/refund_amount_paisa (or a refunds table) set atomically by the RPC.
- **SA-PAY-005** (P0) 'Release' cancels orders whose buyer already paid and claimed → In force_release_hold refuse (or require an explicit override) when an attempt is buyer_claimed/awaiting_seller_verification/late_claim_pending_review.
- **SA-PAY-006** (P1) Late advance on a resold piece cannot be recorded (constraint error) → Fix together with SA-PAY-001/004: compute balances per type, mark refund_required, never violate the balance invariant.
- **SA-PAY-008** (P1) Free-shipping threshold computed four ways; drop threshold ignored → Define precedence (drop ?? profile ?? none) once in the RPC and return the computed shipping in a quote RPC that all buyer components use.
- **SA-PAY-009** (P1) Verification card lacks type, garment, deadline and consequences → Show payment type, amount expected vs order total, garment thumbnail + code, buyer phone, time remaining, late/refund consequence.
- **SA-PAY-010** (P1) Reject always releases the hold (no 'ask to fix' path) → Two explicit actions: 'Ask buyer to fix UTR (keep hold N min)' and 'Reject & release'.
- **SA-PAY-011** (P1) Duplicate-UTR check is case-sensitive and verify-time only → Normalise UTRs (upper, strip spaces) at claim and verify.
- **SA-PAY-012** (P1) UPI disabled still accepts reservations → Reject checkout when UPI is disabled (or a payment method is not configured).
- **SA-PAY-013** (P1) WhatsApp reminder: wrong amount, raw UPI ID, no order link → Send the buyer's order link (token URL) and the amount actually due.
- **SA-ORD-006** (P2) No balance-collection tool for advance orders → 'Request balance' action sending the order link with the due amount.
- **SA-PAY-014** (P2) Seller remarks discarded; RPC parameter name drift → Wire remarks to a notes column (or drop the field).
- **SA-PAY-015** (P2) UPI deep link breaks on '#' or '%' in payee name → Use a complete RFC 3986 encoder for every parameter.
- **SA-PAY-016** (P2) Buyer UTR overwritten without history → Append-only claim history (attempt_claims table) and show 'UTR changed' to the seller.
- **SA-PAY-017** (P2) Unclaimed attempts can be verified with an internal reference → Require a claimed state or an explicit seller-entered bank reference (p_utr) for verification.

### Shipping (3)

- **SA-SHIP-001** (P1) Shipping shortcut ships the first order with a placeholder AWB → Remove the shortcut or make it open a 'Ready to ship' list.
- **SA-SHIP-002** (P1) Label prints PREPAID on balance-due orders; fake barcode → Only print PREPAID when balance_due=0 (block otherwise).
- **SA-SHIP-003** (P2) Courier default/free text; no tracking URL → Single courier picker (remember last used) with tracking URL templates.

### Performance (3)

- **SA-PERF-001** (P1) Unpaginated nested order downloads (~2.4 MB per season) → Drop-scoped and status-scoped pagination.
- **SA-PERF-003** (P2) Image output above ADR-005 / docs-22 budgets → Native compression (flutter_image_compress) to WebP/JPEG q75-80, 1080-1200 px.
- **SA-PERF-002** (P2) Seven sequential requests on Home → Single summary RPC or Future.wait.

### UI/UX (7)

- **SA-UX-002** (P1) Placeholder controls fake success → Remove or implement each.
- **SA-SET-001** (P2) Silent fee fallbacks; profile threshold not editable → Validate inline.
- **SA-UX-004** (P2) Small touch targets; actions out of thumb reach → 48 dp minimum, bottom action bars, swipe actions with undo snackbars, destructive actions separated and confirmed.
- **SA-UX-003** (P2) Low-contrast muted text; minimal screen-reader support → Raise to ≥60% white (≈6:1) for text.
- **SA-UX-005** (P2) Raw exception text shown to sellers → Map error codes to plain, actionable text (Hindi/English later).
- **SA-AUTH-006** (P3) 'Remember me' does nothing → Remove it or implement (non-persistent session).
- **SA-INV-005** (P3) Codes rendered with a double hash (##A01) → Render the code as stored.

### Observability (2)

- **SA-OBS-001** (P1) No crash reporting/telemetry; 33 swallowed errors → Add crash reporting with release symbols, a small logger that records error codes, and visible error states.
- **SA-OPS-002** (P1) No operator tooling; approvals and refunds need SQL → Minimal operator console (or a few service-role scripts) for: pending sellers with UTR, approve/suspend, stuck holds, refund-owed list, late claims.

### Documentation (2)

- **SA-DOC-001** (P2) Docs claim features the code lacks → Mark RTM rows by evidence level.
- **SA-CQ-002** (P3) Dead/placeholder code; missing mounted checks → Delete dead code.


## Conditions for re-classification
- **READY WITH CONDITIONS** requires: all P0 items fixed and their audit tests flipped to PASS in CI; hosted checks H1–H13 clean; device plan D1–D18 passed on a low-end phone; push notifications (SA-NOT-001) and claim-aware Release in place; a single-seller pilot live completed without manual SQL.
- **READY** additionally requires the P1 list closed or explicitly accepted by the owner, crash reporting live, and a rehearsed restore.
