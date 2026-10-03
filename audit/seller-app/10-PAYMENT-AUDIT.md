# 10 — Payment Verification Audit (direct UPI, manual verification)

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Payment attempt model, buyer claim, UTR, seller verification, ledger, order/hold interaction, expiry, late payments, duplicates, rejection, refunds |
| Executed | SQL suite 13 (13.1–13.13), 14 (concurrency 14.2/14.3), 16 (release with claim), 17 (ledger deletion); Flutter T09–T13, T20 |
| Not executed | Hosted data checks H9–H11 (provided); real UPI apps |

## 1. Model as implemented

| Element | Implementation |
|---|---|
| Attempt | `payment_attempts` row per payment intent: type `advance`/`balance`/`full`, `expected_amount_paisa`, `payee_vpa_snapshot`, internal `transaction_reference` (`LD-<code>-FUL-xxxx`), `expires_at` (= order hold), status |
| UPI intent | `generate_upi_payment_uri` → `upi://pay?pa=…&pn=…&am=…&tr=…&tn=…` (13.9: `pn` not fully encoded) |
| Buyer claim | `submit_buyer_payment_claim(order, token, attempt, utr)`: 6–35 chars `[A-Za-z0-9_-]`; normal path → `awaiting_seller_verification`, `verification_expires_at = now()+24h`, **order hold extended to 24 h**; late path (order cancelled/expired or attempt expired) → `late_claim_pending_review` |
| UTR storage | `payment_attempts.buyer_submitted_utr` — single mutable column (overwritten on re-claim, 13.12) |
| Seller verification | `verify_manual_upi_payment(attempt, p_utr default null)`: owner check; idempotent on verified attempts; reference reuse check (exact match) against verified ledger; per-type transitions; late-claim branch |
| Ledger | `order_payments` (amount, type, reference_id, verified_by/at, metadata); unique index on verified `reference_id`; INSERT/UPDATE/DELETE revoked from authenticated; FK `ON DELETE CASCADE` from orders |
| Rejection | `reject_manual_upi_payment(attempt, reason, p_release_hold)` — app always passes `true` |
| Expiry | `release_expired_holds()` (service role) cancels pending orders past `hold_expires_at`, expires their attempts **including `awaiting_seller_verification`**, expires advance-paid orders past their N-day hold |
| Refunds | Not modelled (only a note + RPC response flag) |

## 2. Lifecycle results

| Path | Result | Evidence |
|---|---|---|
| Full payment, on time | PASS: order paid/paid/not_ready, 1 ledger row, piece sold | 13.1b |
| Second verify | PASS: idempotent, still 1 ledger row | 13.1c |
| Fake UTR | Accepted; hold 15 min → 24 h | 13.2 FINDING (SA-PAY-007) |
| Same UTR on two orders | Accepted at claim; exact duplicate rejected at verify; lower-case variant **accepted** | 13.3 (SA-PAY-011) |
| Reject | Order cancelled, piece released; no "keep hold" path in UI | 13.4, T11 (SA-PAY-010) |
| Late advance, piece available | Order marked **fully paid** with only the advance in the ledger | 13.5c (SA-PAY-001) |
| Late full payment, piece resold | RPC success + `refund_required`; order `cancelled`/`paid`; app ignores it; invisible | 13.6, T20 (SA-PAY-004) |
| Late advance, piece resold | Exception 23514 — cannot be recorded | 13.7 (SA-PAY-006) |
| Claim not verified within 24 h | Attempt expired, order cancelled, piece released, gone from queue | 13.8 (SA-PAY-003) |
| Late claim racing a new checkout | Two fully paid orders for one piece | 14.2/14.2b (SA-PAY-002) |
| Verify vs reaper | Deadlock; reaper batch aborted | 14.3 (SA-INT-002) |
| Release with claim in flight | Order cancelled; claim unverifiable (`INVALID_ORDER_STATE`) | 16.1 (SA-PAY-005) |
| Close drop with claim in flight | Claim and hold preserved | 16.2 PASS |
| Delete refund-owed order | Ledger row cascades away | 17.1 (SA-PAY-018) |
| UPI disabled | Reservations still accepted; attempts refused | 13.13 (SA-PAY-012) |
| Unclaimed attempt verify | Allowed; ledger stores internal reference | 13.11 (SA-PAY-017) |
| UPI URI with `#`/`%` in name | Broken URI (fragment truncates amount) | 13.9 (SA-PAY-015) |
| Free-shipping threshold | Drop threshold ignored by RPC; 4 different rules; ₹2,000 default hidden | 13.10 (SA-PAY-008) |

## 3. The ten questions (brief section 13)

| # | Question | Answer |
|---|---|---|
| 1 | Can the seller accidentally verify twice? | **No.** Attempt-level idempotency + row lock; second verify returns `idempotent: true`, no second ledger row (13.1c). UI disables the button while processing. |
| 2 | Can the buyer submit the same UTR twice? | **Yes**, on the same attempt (idempotent) and on other orders (no claim-time check). An exact duplicate is rejected at verification (13.3b), but a variant differing only in letter case is verified on the second order (13.3c); purely numeric bank UTRs are protected by the exact match. |
| 3 | Can a seller verify an unrelated UTR? | **Yes, by design of manual verification** — the server cannot see the bank. The app shows only the UTR and amount; nothing prevents verifying a claim whose money never arrived. Mitigation is process + better context (SA-PAY-009), not code. The RPC also verifies attempts that were never claimed (13.11). |
| 4 | Can a seller forge payment state through the client? | **No** for direct writes: order payment/lifecycle fields and the ledger are protected (12.10b; INSERT/UPDATE/DELETE revoked on `order_payments`). **But** a seller can delete a cancelled order together with its verified ledger row (17.1, SA-PAY-018), and anyone can alter seller payment *settings* exposed by the storefront view (`upi_enabled`, advance amount, fees — SA-SEC-001). |
| 5 | Can payment verification happen after inventory release? | **Yes**, through the late-claim path: if the piece is still available it is re-sold to the late payer (racy — 14.2), if not, a refund obligation is created that nobody sees (13.6). A non-late claim on an order released by the seller cannot be verified at all (16.1). |
| 6 | Does buyer state update correctly? | Buyer order page reads `get_order_by_token` (030) — shows the server state, including the wrong "paid in full" for late advances (13.5c). Not executed end-to-end in a browser here. |
| 7 | Does seller state update correctly? | **No live update**: the Payments queue and Orders refresh only manually (SA-RT-001); verification success snackbar ignores `refund_required`; expired claims vanish (13.8). |
| 8 | What happens during network failure? | Verify/reject are single RPC calls; a failure shows "Verification failed: …"; retry is safe (idempotent verify). If the response is lost after commit, the next refresh shows the claim gone — no confirmation of what happened. |
| 9 | What happens on retry? | Verify: idempotent (safe). Reject: a repeated call succeeds again (only verified attempts are protected — `CANNOT_REJECT_VERIFIED`, 015); harmless because the order is already cancelled. Release: second call `ONLY_PENDING_CAN_BE_RELEASED`. Dispatch: `ALREADY_SHIPPED`. No client-side retry logic exists. |
| 10 | Is the payment ledger immutable where intended? | **Partly.** Direct writes by sellers are revoked and the unique verified-reference index works (13.3b). Gaps: cascade deletion with the order (SA-PAY-018); `total_paid_paisa` can diverge from the ledger (SA-PAY-001, SA-DB-002); UTR history is overwritten (SA-PAY-016); no status history (SA-DB-003). |

## 4. Recommended target model (minimal, keeps direct UPI)
1. **Never expire money in flight**: claimed attempts move to a review state instead of `expired`; reaper only expires unclaimed holds (SA-PAY-003).
2. **One transition function** used by on-time and late paths, per payment type; invariants `total_paid = Σ verified ledger` and `balance = total − paid` asserted in SQL (SA-PAY-001/006, SA-DB-002).
3. **Lock-then-check** for any re-allocation of inventory; a unique constraint so a piece belongs to at most one non-cancelled order (SA-PAY-002).
4. **Refund state**: `refund_status` + amount + reference on orders (or a `refunds` table), surfaced as an exception queue (SA-PAY-004/006/018).
5. **Claim-aware release**: `force_release_hold` refuses while a claim exists (SA-PAY-005).
6. **Claim hygiene**: normalised UTR, append-only claim history, cap claim-extended holds during live drops, numeric-UTR hint (SA-PAY-007/011/016).
7. **One quote function** for shipping/threshold used by RPC and buyer UI (SA-PAY-008).
8. UI: verification card with garment, type, amount due vs total, time left, late/refund consequences; reject with "keep hold" option; WhatsApp reminders carry the order link and amount due (SA-PAY-009/010/013).

## 5. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-PAY-001 | CRITICAL | P0 | Late advance verified as full payment |
| SA-PAY-002 | CRITICAL | P0 | Late-claim race → two paid orders for one piece |
| SA-PAY-003 | CRITICAL | P0 | Claimed payments silently expire after 24 h |
| SA-PAY-004 | CRITICAL | P0 | Refund-owed late payments invisible |
| SA-PAY-005 | HIGH | P0 | Release cancels orders with a claim in flight |
| SA-PAY-006 | HIGH | P1 | Late advance on resold piece → constraint error |
| SA-PAY-007 | HIGH | P1 | Fake UTR locks a piece for 24 h |
| SA-PAY-008 | HIGH | P1 | Free-shipping threshold computed four ways |
| SA-PAY-009 | MEDIUM | P1 | Verification card lacks decision context |
| SA-PAY-010 | MEDIUM | P1 | Reject always releases the hold |
| SA-PAY-011 | MEDIUM | P1 | Duplicate-UTR check case-sensitive, verify-time only |
| SA-PAY-012 | MEDIUM | P1 | UPI disabled still accepts reservations |
| SA-PAY-013 | MEDIUM | P1 | WhatsApp reminder: wrong amount, raw UPI, no order link |
| SA-PAY-018 | MEDIUM | P1 | Refund-owed ledger rows deletable via order cascade |
| SA-PAY-014 | LOW | P2 | Remarks dropped; RPC parameter drift |
| SA-PAY-015 | LOW | P2 | UPI URI encoding |
| SA-PAY-016 | LOW | P2 | UTR overwritten without history |
| SA-PAY-017 | LOW | P2 | Unclaimed attempts verifiable |
| SA-ORD-006 | MEDIUM | P2 | No balance-collection tool |
