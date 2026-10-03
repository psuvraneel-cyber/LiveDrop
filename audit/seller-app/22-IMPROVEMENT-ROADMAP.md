# 22 — Improvement Roadmap

| | |
|---|---|
| Based on | 95 findings in [FINDINGS.json](FINDINGS.json) (7 CRITICAL, 12 HIGH, 50 MEDIUM, 26 LOW; 11 P0) |
| Date | 2026-10-03 |
| Rule | Nothing here was implemented during the audit. Items reference finding IDs; priority P0 (before real sellers) … P3 (optional). Every item states Problem, Current behaviour, Proposed behaviour, Seller benefit, Technical complexity, Dependencies, Risk, Priority. |
| Design constraints honoured | Keep direct UPI + manual verification; keep Supabase/Postgres as the authority; add infrastructure only where a finding requires it; seller efficiency over decoration; keep the premium visual identity. |

## Sequencing

| Wave | Goal | Items | Exit criterion |
|---|---|---|---|
| **0 — Emergency (days)** | Close what anyone on the internet can exploit today | A1, A2, A9 (keystore decision), A14 (storage listing) | Hosted H1–H3/H12 secure; credential rotated; release keystore created |
| **1 — Money & inventory correctness** | No double sale, no lost or mis-recorded payment | A3, A4, A5, A6, A7, A8, B4 | Suites 13/14/16/17 flipped to PASS in CI; hosted H9–H11/H13 clean |
| **2 — Live operations** | Seller sees and acts on live state in time | B1, C1, C2, D1, A10–A13, C5, C7, B2, B3, B7 | Device plan D1–D18 passed; pilot live with one seller |
| **3 — Hardening & polish** | Production quality | Remaining P1/P2 | Readiness re-audit |

---

## A. BUG FIXES

#### A1. Lock down `public_seller_storefronts` — P0 (SA-SEC-001, SA-SEC-007)
| Field | |
|---|---|
| Problem | Anyone with the public anon key can update/delete approved sellers' storefront rows |
| Current behaviour | Simple auto-updatable view, `security_invoker` off, ALL privileges to anon/authenticated (10.3–10.5, 10.9) |
| Proposed behaviour | `REVOKE ALL … FROM anon, authenticated; GRANT SELECT`; recreate `WITH (security_invoker = true)` or as a read-only function; same for `public_products_catalog`; `ALTER DEFAULT PRIVILEGES` so DML/EXECUTE are not granted by default; CI catalog test |
| Seller benefit | Nobody can redirect buyers to another phone number, switch off payments or hijack the store link mid-live |
| Technical complexity | Low (one migration + test) |
| Dependencies | Hosted H1–H3 to confirm; buyer-web only reads the view |
| Risk | Low — confirm buyer pages still load |
| Priority | P0 |

#### A2. Rotate and purge the leaked seller credential — P0 (SA-SEC-002)
| Field | |
|---|---|
| Problem | A seller password has been in public Git history since 2026-09-26 |
| Current behaviour | Removed from HEAD only; no rotation record |
| Proposed behaviour | Rotate password, revoke sessions, review Auth logs, purge history (filter-repo + coordinated force-push), enable secret scanning + push protection, gitleaks in CI |
| Seller benefit | Account, buyer data and payee details cannot be taken over |
| Technical complexity | Low |
| Dependencies | Repository admin; contributors re-clone after purge |
| Risk | Low (history rewrite needs coordination) |
| Priority | P0 |

#### A3. Rewrite late-claim verification — P0 (SA-PAY-001, SA-PAY-002, SA-PAY-006)
| Field | |
|---|---|
| Problem | Late advance becomes "paid in full"; a race re-sells one piece to two buyers; a late advance on a resold piece cannot be recorded |
| Current behaviour | `verify_manual_upi_payment` late branch (023:348-505): unlocked availability check, unconditional `sold` update, hard-coded totals |
| Proposed behaviour | Lock products first and re-check under the lock; `UPDATE … WHERE status='available'` with row-count check; same per-type transition as on-time verification; unavailable → refund-required path with consistent balances; assert `total_paid = Σ verified ledger` |
| Seller benefit | No double sales, no shipping against a ₹250 advance, every received payment recordable |
| Technical complexity | Medium (one function; suites 13.5–13.7 and 14.2 are ready-made regression tests) |
| Dependencies | A5 (refund state) |
| Risk | Medium (payment code) — mitigated by the audit suites |
| Priority | P0 |

#### A4. Never auto-expire money in flight — P0 (SA-PAY-003)
| Field | |
|---|---|
| Problem | A claimed payment not verified within 24 h is expired, the order cancelled, and it vanishes from the app |
| Current behaviour | Reaper expires `awaiting_seller_verification` attempts (014:560-565); queue filter excludes `expired` |
| Proposed behaviour | Reaper releases only unclaimed holds; overdue claims move to a review state that stays in the queue (hold policy decided explicitly) |
| Seller benefit | No buyer payment is silently dropped |
| Technical complexity | Low–Medium |
| Dependencies | A7, C2 |
| Risk | Low |
| Priority | P0 |

#### A5. Refund state and visibility — P0 (SA-PAY-004, SA-PAY-018)
| Field | |
|---|---|
| Problem | Refund obligations exist only as an RPC flag and a note; the orders are hidden; the ledger row can be deleted with the order |
| Current behaviour | `cancelled` + `paid` orders shown nowhere; `orders_seller_delete` + `ON DELETE CASCADE` on `order_payments` |
| Proposed behaviour | `refund_status` (`none/required/refunded`), `refund_amount_paisa`, `refund_reference` set atomically; red "Refund owed" items in the Exception Center with "Record refund"; block deletion of orders that have ledger rows; FK `RESTRICT` |
| Seller benefit | Knows exactly whom to refund and can prove it |
| Technical complexity | Medium (migration + small UI) |
| Dependencies | A3 |
| Risk | Low |
| Priority | P0 |

#### A6. Claim-aware hold release — P0 (SA-PAY-005)
| Field | |
|---|---|
| Problem | "Release" cancels an order whose buyer has already paid and claimed |
| Current behaviour | `force_release_hold` (009) ignores attempts; Release offered on every pending card |
| Proposed behaviour | RPC refuses with `PAYMENT_CLAIM_PENDING` (or an explicit "reject claim & release" flow); card shows "Claim submitted — verify first" and hides Release |
| Seller benefit | One tap can no longer destroy a paid order |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low |
| Priority | P0 |

#### A7. Reliable hold expiry — P0 (SA-OPS-001, SA-INT-002)
| Field | |
|---|---|
| Problem | Abandoned carts lock unique pieces for hours; the reaper deadlocks with verification |
| Current behaviour | GitHub Actions `*/5` runs ≈5×/day; one transaction for all orders; opposite lock order; no lazy expiry |
| Proposed behaviour | `pg_cron` every minute (check H8) or a Supabase scheduled function; per-order transactions; one lock order (order → products → attempts); lazy expiry in checkout; alert when H9 > 0 for 2 min |
| Seller benefit | Pieces return to sale 15 minutes after an abandoned checkout, during the live |
| Technical complexity | Medium |
| Dependencies | pg_cron availability on the plan |
| Risk | Medium (concurrency) — covered by suite 14 |
| Priority | P0 |

#### A8. Intake input validation and queue error classes — P0/P1 (SA-INT-001, SA-OFF-003)
| Field | |
|---|---|
| Problem | Invalid codes/titles fail silently later; lost responses and the T25 race create permanent "failed" items |
| Current behaviour | Free-text code; retries forever; no idempotency; camera screen re-initialises the shared queue |
| Proposed behaviour | Code field with auto `#`, uppercase, ≤6 `[A-Z0-9]`; title ≤100; client-generated product UUID; classify 23505/23514 as `already_exists`/`needs_edit`; edit/discard queued items; initialise the shared queue once |
| Seller benefit | Every photographed garment is either live or clearly flagged with a fix action |
| Technical complexity | Medium |
| Dependencies | B2 |
| Risk | Low |
| Priority | P0 (validation) / P1 (queue classes) |

#### A9. Release signing and distribution — P0 (SA-AND-001)
| Field | |
|---|---|
| Problem | Release builds use the debug key; CI produces a debuggable APK |
| Current behaviour | `signingConfigs.getByName("debug")`; `flutter build apk --debug` artifact |
| Proposed behaviour | Release keystore in CI secrets, signed release artifact, version codes, Play internal testing |
| Seller benefit | Updates install cleanly without losing local data |
| Technical complexity | Low |
| Dependencies | Google Play developer account (recommended) |
| Risk | Low — the first distributed signature is permanent; decide before first hand-out |
| Priority | P0 |

#### A10. Shipping shortcut, label and fulfilment actions — P1 (SA-SHIP-001, SA-SHIP-002, SA-SHIP-003, SA-ORD-005)
| Field | |
|---|---|
| Problem | Home "Shipping" ships a random order with a fake AWB; labels say PREPAID on balance-due orders; actions not state-aware |
| Current behaviour | `orders.firstOrNull`, prefilled `DVA123456789`, "Generate & Share Label" ships; Dispatch shown for advance-paid orders |
| Proposed behaviour | "Shipping due" list (ready orders only); empty tracking; separate Pack / Print / Ship; PREPAID only when balance is 0; barcode only with a real AWB; one courier picker with tracking URL |
| Seller benefit | No fake tracking reaches buyers; no uncollectable balances |
| Technical complexity | Low–Medium |
| Dependencies | — |
| Risk | Low |
| Priority | P1 |

#### A11. One free-shipping rule — P1 (SA-PAY-008, SA-SET-001)
| Field | |
|---|---|
| Problem | Drop threshold ignored by checkout; buyer UI shows three rules; hidden ₹2,000 profile default |
| Current behaviour | RPC uses the profile threshold only |
| Proposed behaviour | Precedence `drop ?? profile ?? none` in one SQL quote function used by checkout and buyer UI; profile threshold editable in Settings |
| Seller benefit | Buyers pay exactly what the seller announced |
| Technical complexity | Low–Medium |
| Dependencies | buyer-web change |
| Risk | Low |
| Priority | P1 |

#### A12. Approval gate fail-closed; effective suspension — P1 (SA-AUTH-002, SA-ONB-002)
| Field | |
|---|---|
| Problem | Profile errors open the dashboard; suspended sellers keep selling |
| Current behaviour | `_profile == null` treated as approved; checkout ignores approval |
| Proposed behaviour | Loading/error/loaded states; checkout and payment RPCs require `is_seller_approved`; suspension closes live drops via the safe-closure path |
| Seller benefit | Clear account state; platform can stop fraud |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low |
| Priority | P1 |

#### A13. Orders: crash, timezone, WhatsApp number — P1 (SA-ORD-001, SA-ORD-002, SA-ORD-003)
| Field | |
|---|---|
| Problem | RangeError for some names; UTC times; wrong WhatsApp recipient for numbers starting 91 |
| Current behaviour | T01, T04/T05, T02 demonstrate each |
| Proposed behaviour | Safe initials; convert to IST at the model boundary; single phone normaliser (10 digits → prefix 91) |
| Seller benefit | Correct times and contacts; no broken order screens |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low |
| Priority | P1 |

#### A14. Storage hygiene — P1 (SA-SEC-008, SA-SEC-003, SA-SEC-004)
| Field | |
|---|---|
| Problem | Anyone can list all images incl. unpublished drops; unapproved accounts can upload; GPS EXIF published |
| Current behaviour | Public SELECT policy on the bucket; insert checks folder only; EXIF retained |
| Proposed behaviour | Drop the anon SELECT policy (public URLs keep working); require approval for uploads; strip EXIF before encoding |
| Seller benefit | Pre-launch pieces and home location stay private |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low (confirm buyer images still load) |
| Priority | P1 (Wave 0 recommended) |

#### A15. Drop rules — P1/P2 (SA-DROP-001, SA-DROP-002, SA-DROP-003, SA-DROP-005, SA-DROP-006)
| Field | |
|---|---|
| Problem | Reopen allowed contrary to docs; slug editable while live; live→draft bypass; close result ignored; product anchors/ended page missing |
| Current behaviour | 12.4b/12.4c/12.5 accepted; `rpc<void>('close_drop')`; buyer page queries live only |
| Proposed behaviour | ADR decision on reopen; slug lock trigger; status changes only via RPCs; parse `close_drop` result; buyer anchors + "drop ended" page |
| Seller benefit | Shared links keep working; predictable drop state |
| Technical complexity | Low |
| Dependencies | Product decision on reopen |
| Risk | Low |
| Priority | P1 (slug, reopen) / P2 (rest) |

#### A16. Claim hygiene — P1/P2 (SA-PAY-007, SA-PAY-011, SA-PAY-015, SA-PAY-016, SA-PAY-017)
| Field | |
|---|---|
| Problem | Fake UTRs lock pieces for 24 h; case-variant UTR reuse; broken UPI URI for some names; UTR overwritten; unclaimed attempts verifiable |
| Current behaviour | 13.2, 13.3c, 13.9, 13.12, 13.11 |
| Proposed behaviour | Cap claim-extended holds during live drops; normalise UTRs + unique index; full URI encoding; append-only claim history; require a claim or explicit bank reference to verify |
| Seller benefit | Less griefing, fewer reconciliation mistakes |
| Technical complexity | Low–Medium |
| Dependencies | A3 |
| Risk | Low |
| Priority | P1 (SA-PAY-007/011) / P2 (rest) |

#### A17. UI truthfulness — P1 (SA-INV-001, SA-INV-005, SA-UX-002, SA-AUTH-006, SA-PAY-014, SA-ONB-004)
| Field | |
|---|---|
| Problem | Controls that do nothing or say the wrong thing |
| Current behaviour | Fake notification/haptic toggles, cache clear, remember me, screenshot, share/download, remarks; Mark Sold on reserved; `##A01`; hard-coded "Active Verified Boutique" |
| Proposed behaviour | Remove or implement each; disable Mark Sold for reserved; render codes once; bind status to data |
| Seller benefit | Every visible control works |
| Technical complexity | Low |
| Dependencies | D1 for real notification toggles |
| Risk | Low |
| Priority | P1 |

#### A18. Password recovery — P1 (SA-AUTH-001, SA-AND-003)
| Field | |
|---|---|
| Problem | Reset links cannot be completed |
| Current behaviour | `resetPasswordForEmail` without `redirectTo`; no deep link; no reset page |
| Proposed behaviour | App Link for `type=recovery` + "Set new password" screen (or hosted page); `redirectTo` + allowed URLs configured |
| Seller benefit | Self-service recovery, even right before a live |
| Technical complexity | Medium (domain verification) |
| Dependencies | Seller domain / `assetlinks.json` |
| Risk | Low |
| Priority | P1 |

#### A19. Block checkout when payments are off — P1 (SA-PAY-012)
| Field | |
|---|---|
| Problem | Buyers reserve pieces they cannot pay for |
| Current behaviour | Checkout succeeds with `upi_enabled=false`; payment attempt refused (13.13) |
| Proposed behaviour | Checkout refuses when UPI is disabled; warning in Payment settings during a live |
| Seller benefit | No phantom reservations |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low |
| Priority | P1 |

#### A20. WhatsApp reminders with the right amount and link — P1 (SA-PAY-013)
| Field | |
|---|---|
| Problem | Reminder asks for the total, shares the raw UPI ID, has no order link |
| Current behaviour | `order_card.dart:82-97` |
| Proposed behaviour | Amount due + the buyer's order link (token URL) |
| Seller benefit | Payments arrive through the trackable claim flow |
| Technical complexity | Low |
| Dependencies | RPC returning the buyer link for the seller |
| Risk | Low (link goes to the same buyer) |
| Priority | P1 |

## B. RELIABILITY IMPROVEMENTS

#### B1. Live session store with Realtime — P0/P1 (SA-RT-001, SA-RT-002, SA-CQ-001)
| Field | |
|---|---|
| Problem | Seller works on stale data; claims invisible; tabs never refresh |
| Current behaviour | Only the Kanban subscribes, only for a selected drop; full refetch per event |
| Proposed behaviour | App-level store subscribed to orders, payment_attempts and products of the active drop; incremental updates; catch-up on (re)subscribe/resume; "updates paused" banner; feeds every tab's counters |
| Seller benefit | Sees reservations and claims within seconds without touching the phone |
| Technical complexity | Medium |
| Dependencies | B8 (summary RPC) |
| Risk | Medium (new state layer) — keep it small and tested |
| Priority | P0 (claims/reservations visible) / P1 (rest) |

#### B2. Durable intake queue — P1 (SA-OFF-001, SA-OFF-002)
| Field | |
|---|---|
| Problem | Intake work can be lost or stuck |
| Current behaviour | Cache-dir JSON manifest, silently discarded when corrupt, not processed at start, never pruned; "Clear cache" fake |
| Proposed behaviour | App support directory + atomic writes (or SQLite per ADR-006); process on start/resume/connectivity; delete files after success; real cache clear |
| Seller benefit | Intake work is never lost |
| Technical complexity | Medium |
| Dependencies | A8 |
| Risk | Low–Medium (migrate existing local queue) |
| Priority | P1 |

#### B3. Crash reporting and honest error states — P1 (SA-OBS-001, SA-UX-005)
| Field | |
|---|---|
| Problem | Failures invisible to seller and operator |
| Current behaviour | 33 `catch (_)`, no crash SDK, raw exception text |
| Proposed behaviour | Crash SDK with symbols; typed error handling; error code → message map; visible error/retry states |
| Seller benefit | Knows when something failed; problems get fixed |
| Technical complexity | Low–Medium |
| Dependencies | Privacy notice (no buyer PII in logs) |
| Risk | Low |
| Priority | P1 |

#### B4. CI that tests money and inventory — P1 (SA-TEST-001, SA-CI-001)
| Field | |
|---|---|
| Problem | No DB tests in CI; floating Flutter; no secret scanning |
| Current behaviour | 49 rendering/parsing tests; migrations never applied in CI |
| Proposed behaviour | Postgres job (shim + migrations + suites 10–18); Flutter audit tests; pinned Flutter; gitleaks; signed release artifact |
| Seller benefit | Fixes stay fixed |
| Technical complexity | Low–Medium (harness exists in `audit/seller-app/tests`) |
| Dependencies | — |
| Risk | Low |
| Priority | P1 (start in Wave 1) |

#### B5. Hosted verification and migration pipeline — P1 (SA-DB-001)
| Field | |
|---|---|
| Problem | Hosted schema state unknown |
| Current behaviour | Manual migrations; no drift check |
| Proposed behaviour | Run H1–H13 now; `supabase db push` from CI with drift detection |
| Seller benefit | Production behaves like the tested code |
| Technical complexity | Low |
| Dependencies | Supabase access token in CI |
| Risk | Medium (first automated push) — dry run on staging |
| Priority | P1 |

#### B6. Backup and restore drill — P1 (SA-OPS-004)
| Field | |
|---|---|
| Problem | Data loss/outage risk without a rehearsed restore |
| Current behaviour | Free tier, keep-alive ping, no documented restore |
| Proposed behaviour | Nightly encrypted `pg_dump`, written restore runbook, quarterly drill; consider a paid tier before volume |
| Seller benefit | Orders and payments survive incidents |
| Technical complexity | Low |
| Dependencies | Storage for dumps |
| Risk | Low |
| Priority | P1 |

#### B7. Device validation — P1 (SA-AND-005, SA-AND-004, SA-AND-006)
| Field | |
|---|---|
| Problem | No evidence on real phones |
| Current behaviour | Host-only tests; Back exits the app; lost picker data; no portrait lock |
| Proposed behaviour | Run D1–D18 on a low-end and a mid-range phone; PopScope, `retrieveLostData`, portrait lock |
| Seller benefit | Works on the phones sellers own |
| Technical complexity | Low |
| Dependencies | Devices |
| Risk | Low |
| Priority | P1 |

#### B8. Scoped queries and summary RPC — P1/P2 (SA-PERF-001, SA-PERF-002)
| Field | |
|---|---|
| Problem | Unbounded nested downloads; 7 sequential calls on Home |
| Current behaviour | `getAllOrders` ≈2.4 MB per season; dashboard sequential awaits |
| Proposed behaviour | `seller_live_summary(drop)` RPC; paginated history; JSON parsing off the UI isolate |
| Seller benefit | Fast, smooth app during busy lives on 4G |
| Technical complexity | Low–Medium |
| Dependencies | B1 |
| Risk | Low |
| Priority | P1 (summary) / P2 (pagination) |

#### B9. Ledger reconciliation and history — P2 (SA-DB-002, SA-DB-003)
| Field | |
|---|---|
| Problem | Totals can diverge from the ledger; no status history |
| Current behaviour | Denormalised totals; rows overwritten |
| Proposed behaviour | Invariant check + nightly H11 alert; append-only `order_events` written by RPCs |
| Seller benefit | Disputes resolved with evidence |
| Technical complexity | Low–Medium |
| Dependencies | A3, A5 |
| Risk | Low |
| Priority | P2 |

#### B10. Retention and purge — P2 (SA-OPS-003)
| Field | |
|---|---|
| Problem | Buyer PII kept forever |
| Current behaviour | No retention job |
| Proposed behaviour | Retention policy (anonymise cancelled orders after N days; keep financial records as legally required), scheduled purge, orphaned-image cleanup |
| Seller benefit | Compliance (DPDP Act 2023) and lower storage |
| Technical complexity | Low |
| Dependencies | Legal decision on periods |
| Risk | Low |
| Priority | P2 |

## C. UX IMPROVEMENTS

#### C1. Live Command Center + action queue — P1 (SA-UX-001)
| Field | |
|---|---|
| Problem | Live state spread over four static tabs |
| Current behaviour | Home with total counts and a 5-item activity list; LIVE pill green |
| Proposed behaviour | [18 §4.2](18-UI-UX-AUDIT.md#42-live-command-center-replaces-home-during-a-live): live counters, urgency-sorted queue (claims, late claims, refunds, expiring holds, failed uploads), red LIVE pill, link share |
| Seller benefit | One glance answers "what needs me now" |
| Technical complexity | Medium |
| Dependencies | B1, B8 |
| Risk | Low |
| Priority | P1 |

#### C2. Payment verification card — P1 (SA-PAY-009, SA-PAY-010)
| Field | |
|---|---|
| Problem | Card lacks type, garment, deadline, consequences; reject always releases |
| Current behaviour | "Advance Payment" for every claim, placeholder screenshot, generic icon |
| Proposed behaviour | Card spec in [18 §4.6](18-UI-UX-AUDIT.md#46-payment-verification-queue-card-spec); "Ask to fix (keep hold)" |
| Seller benefit | Faster, safer verification with fewer app switches |
| Technical complexity | Low–Medium |
| Dependencies | A3–A5 |
| Risk | Low |
| Priority | P1 |

#### C3. Rapid intake upgrades — P2
| Field | |
|---|---|
| Problem | 3–5 taps + typing per garment; no batch mode |
| Current behaviour | One sheet per garment, size chips, free-text price |
| Proposed behaviour | Price-first sheet with quick chips, remembered size, batch "shoot now, price later", duplicate-photo hint, per-item sync state |
| Seller benefit | 30 garments in a few minutes with fewer errors |
| Technical complexity | Medium |
| Dependencies | A8, B2 |
| Risk | Low |
| Priority | P2 |

#### C4. Code pad and global search — P1/P2
| Field | |
|---|---|
| Problem | Code lookup needs a tab switch and keyboard search |
| Current behaviour | Separate searches in Products and Orders |
| Proposed behaviour | Thumb-zone FAB code pad; global search over pieces, orders, buyers, phones, UTRs with inline next action |
| Seller benefit | "Is A17 available?" answered in two taps while talking |
| Technical complexity | Low–Medium |
| Dependencies | B1 |
| Risk | Low |
| Priority | P1 (code pad) / P2 (global search) |

#### C5. Orders pipeline that matches the server — P1 (SA-ORD-004, SA-ORD-005)
| Field | |
|---|---|
| Problem | Hidden closed orders; impossible actions; no pack step |
| Current behaviour | Four tabs; actions from `status` only |
| Proposed behaviour | Actions derived from `(status, payment_status, fulfilment_status, attempt)`; Closed tab with reasons; Pack → Print → Ship |
| Seller benefit | No dead-end taps; complete history |
| Technical complexity | Low–Medium |
| Dependencies | A5, A10 |
| Risk | Low |
| Priority | P1 |

#### C6. Ergonomics and accessibility — P2 (SA-UX-003, SA-UX-004)
| Field | |
|---|---|
| Problem | Small targets, top-placed controls, low-contrast text, no semantics |
| Current behaviour | 38–44 dp buttons; 40 % white muted text (≈3.8:1); 6 tooltips |
| Proposed behaviour | 48 dp minimum, bottom action bars, swipe + undo, ≥ 4.5:1 text, semantic labels |
| Seller benefit | Reliable one-handed use in bright light |
| Technical complexity | Low |
| Dependencies | C1 |
| Risk | Low |
| Priority | P2 |

#### C7. Drop Control Center — P1 (SA-DROP-004)
| Field | |
|---|---|
| Problem | No pre-live checks |
| Current behaviour | GO LIVE dialog only |
| Proposed behaviour | Checklist (pieces synced, UPI on, link ready) → Go Live → share → monitor → close summary |
| Seller benefit | Lives start correctly every time |
| Technical complexity | Low |
| Dependencies | B2 |
| Risk | Low |
| Priority | P1 |

#### C8. Honest settings — P2 (SA-ONB-004, SA-SET-001)
| Field | |
|---|---|
| Problem | Hard-coded "Verified"; silent fee fallbacks |
| Current behaviour | Parse failure saves ₹80/₹250; threshold not editable |
| Proposed behaviour | Bind to real status; inline validation; editable threshold with precedence text |
| Seller benefit | Settings mean what they say |
| Technical complexity | Low |
| Dependencies | A11 |
| Risk | Low |
| Priority | P2 |

## D. FUNCTIONAL IMPROVEMENTS

#### D1. Push notifications — P1 (SA-NOT-001)
| Field | |
|---|---|
| Problem | Seller is blind while streaming from another app |
| Current behaviour | No FCM/local notifications; fake toggles |
| Proposed behaviour | FCM via one Edge Function triggered by claim/late-claim/refund/expiring events; Android 13 permission flow; App Link routing; batched order alerts |
| Seller benefit | Never misses money in flight |
| Technical complexity | Medium |
| Dependencies | A18 (App Links), Firebase project |
| Risk | Low–Medium (delivery on OEM-modified Android) |
| Priority | P1 |

#### D2. Operator console — P1 (SA-OPS-002, SA-ONB-001)
| Field | |
|---|---|
| Problem | Approvals, fee checks, refunds and stuck orders need SQL |
| Current behaviour | `admin_approve_seller` via SQL editor; UTR only in auth metadata |
| Proposed behaviour | `seller_applications` table + minimal admin UI or service-role scripts: pending sellers with UTR, approve/suspend, refunds owed, stuck holds, late claims |
| Seller benefit | Faster onboarding and support |
| Technical complexity | Medium |
| Dependencies | A12 |
| Risk | Low (strict admin auth required) |
| Priority | P1 |

#### D3. Re-authentication for sensitive changes — P1 (SA-AUTH-004)
| Field | |
|---|---|
| Problem | Payee VPA changeable with just a session |
| Current behaviour | Direct profile update |
| Proposed behaviour | Password re-entry, e-mail notification, audit log, warning during a live |
| Seller benefit | Payments cannot be silently redirected |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low |
| Priority | P1 |

#### D4. Undo for "sold elsewhere" — P2 (SA-INV-001)
| Field | |
|---|---|
| Problem | Mis-taps are permanent |
| Current behaviour | One-way `mark_product_sold_offline` |
| Proposed behaviour | Undo RPC within N minutes when no order references the piece; 5-second undo snackbar |
| Seller benefit | Safe quick actions mid-live |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low |
| Priority | P2 |

#### D5. Balance collection — P2 (SA-ORD-006)
| Field | |
|---|---|
| Problem | No tool to collect balances of advance orders |
| Current behaviour | Balance shown, no action |
| Proposed behaviour | "Request balance" with order link and amount; reminder before the advance hold expires |
| Seller benefit | Fewer forfeited advances and disputes |
| Technical complexity | Low |
| Dependencies | A20 |
| Risk | Low |
| Priority | P2 |

#### D6. Hold for a commenter — P2
| Field | |
|---|---|
| Problem | Buyers who struggle with the link lose pieces to faster buyers |
| Current behaviour | Only buyer self-checkout |
| Proposed behaviour | Seller enters buyer phone → server reservation + WhatsApp order link |
| Seller benefit | Converts comment buyers faster |
| Technical complexity | Medium |
| Dependencies | A6, A7 |
| Risk | Medium (abuse limits, rate limiting) |
| Priority | P2 |

#### D7. Hide/delete mistaken pieces — P2 (SA-INV-006)
| Field | |
|---|---|
| Problem | Only irreversible Mark Sold removes a wrong piece |
| Current behaviour | No hide/delete UI |
| Proposed behaviour | RPC to hide/delete pieces never referenced by orders |
| Seller benefit | Clean catalogue, honest analytics |
| Technical complexity | Low |
| Dependencies | — |
| Risk | Low |
| Priority | P2 |

#### D8. Ledger-based insights — P2 (SA-ANL-001)
| Field | |
|---|---|
| Problem | Analytics not tied to money received |
| Current behaviour | Client aggregation by order status, UTC days |
| Proposed behaviour | SQL aggregates in IST: cash received, to collect, refunds owed, sell-through, time-to-pay |
| Seller benefit | Trustworthy business numbers |
| Technical complexity | Low–Medium |
| Dependencies | A5 |
| Risk | Low |
| Priority | P2 |

## E. ARCHITECTURAL IMPROVEMENTS
Only changes a finding requires; no new services.

| # | Proposed change | Problem (evidence) | Current behaviour | Seller benefit | Complexity | Dependencies | Risk | Priority |
|---|---|---|---|---|---|---|---|---|
| E1 | Scheduled work inside the database (pg_cron) or a Supabase scheduled function; GitHub Actions only as a monitor | SA-OPS-001 (≈5 runs/day observed) | Best-effort CI cron | Holds expire on time | Medium | Plan supports pg_cron | Medium | P0 |
| E2 | One SQL transition/invariant layer for payments (on-time and late paths share it) with assertions | SA-PAY-001/002/006, SA-DB-002 | Duplicated, divergent branches | Correct money state | Medium | A3/A5 | Medium | P0 |
| E3 | A single app-level live store in Flutter (no app-wide framework migration) | SA-RT-001, SA-CQ-001 | Per-screen `initState` loads | Live, consistent tabs | Medium | B8 | Medium | P1 |
| E4 | DB event → Edge Function → FCM (outbox table if guaranteed delivery is needed) | SA-NOT-001 | Nothing | Alerts while streaming | Medium | Firebase | Low–Medium | P1 |
| E5 | Default-privilege hardening + catalog tests as a migration convention | SA-SEC-001/007/008 | Supabase defaults | Fewer exposure regressions | Low | — | Low | P0 |

Not recommended now (no evidence they solve a finding): payment-gateway replacement of direct UPI, microservices, a separate backend server, Redis/Kafka (suite 15 shows SQL is fast; the problems are correctness and freshness).

## F. FUTURE FEATURES (do not block launch)

| # | Proposed behaviour | Problem | Current behaviour | Seller benefit | Complexity | Dependencies | Risk | Priority |
|---|---|---|---|---|---|---|---|---|
| F1 | Payment reconciliation assist (bank SMS/statement import or PSP collect links) | Manual UTR checking | Seller checks bank app | Faster, safer verification | High | PSP/regulatory choice | Medium | P3 |
| F2 | Courier API (AWB generation, tracking webhooks) | Manual tracking entry | Typed AWB | Less typing, live tracking | Medium | Courier partner | Low | P3 |
| F3 | Staff accounts with roles (packer, verifier) | One phone does everything | Single seller login | Parallel work during lives | Medium | RLS role model | Medium | P3 |
| F4 | Waitlist for reserved pieces | Demand lost when holds lapse | None | More conversions | Medium | A7 | Low | P3 |
| F5 | Social comment integration (Graph APIs) | Manual comment reading | None | Claims from comments | High | Platform approvals | High | P3 |
| F6 | Bluetooth thermal printing | Print dialog friction | System print/share | One-tap labels | Medium | Then add Bluetooth perms with `neverForLocation` | Low | P3 |
| F7 | Hindi/Bengali localisation | Language barrier | English only | Wider seller base | Low–Medium | Copy review | Low | P3 |
| F8 | Buyer history / repeat-buyer tags | Recognising regulars | None | Better service | Medium | Privacy policy | Medium | P3 |
| F9 | Scheduled drops / countdown pages | Pre-live marketing | Draft → live only | Hype before lives | Low | A15 | Low | P3 |
| F10 | Viewer counts / stream health | Live context | None | Situational awareness | High | Platform APIs | Medium | P3 |

## What must NOT be changed yet
- Do not replace direct UPI or add a payment gateway before the late-claim and refund model (A3–A5) is correct and tested — it would hide, not fix, the state-machine defects.
- Do not introduce microservices, Redis, Kafka or a separate backend; the fixes are SQL functions, policies and a small client store.
- Do not migrate the whole seller app to a new state-management framework; add one live store.
- Do not loosen RLS or add public write grants to "fix" errors (AGENTS rule 2); the guards that PASS (suites 11, 12.2/12.4a/12.6/12.8, 13.1, 14.1, 16.2, 17.2/17.3) must stay as they are.
- Do not change the visual identity; change information architecture and interaction.
- Do not ship the redesign before Waves 0–1 — a faster UI on top of incorrect payment logic only makes errors faster.
