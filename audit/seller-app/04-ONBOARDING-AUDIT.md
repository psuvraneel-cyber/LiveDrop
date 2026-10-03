# 04 — Seller Onboarding Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Registration, profile provisioning, onboarding fee, approval, suspension, pending state |
| Executed | Code trace (registration screen, trigger 020/021, `admin_approve_seller`); SQL suites 11/12 (approval gate, suspension, storage); Flutter T06/T07 |
| Not executed | Hosted sign-up (would create real accounts), e-mail confirmation on hosted |

## 1. How sellers are actually provisioned

Self-registration **is** the provisioning path (verified, not assumed):

1. `SellerRegistrationScreen` — 3 in-memory steps: (1) e-mail + password (client min 8), (2) store name, phone (`^(?:91)?[6-9]\d{9}$`), UPI ID, return address, (3) pay the ₹50 onboarding fee to the admin's personal UPI (`upi://pay` intent or QR asset) and type the UTR + tick "I have completed the payment".
2. `auth.signUp(email, password, data: {store_name, store_slug, phone_number, upi_id, return_address, utr_number})` (`seller_registration_screen.dart:116-127`).
3. Trigger `handle_new_seller_signup` (021:195-252) creates the profile with `is_approved = FALSE`, derives/deduplicates the slug, copies phone/UPI/address (placeholder defaults if missing). **`utr_number` is not copied anywhere.**
4. If a session is returned (confirmations off), the client also upserts the profile; any error is swallowed (`:136-147`).
5. Operator approves in SQL: `SELECT admin_approve_seller('<uuid>', true)` (021:124). No UI, no queue.
6. The app shows `SellerPendingApprovalScreen` (refresh, WhatsApp support, sign out) until a successful profile load returns `is_approved = true`.

| Aspect | Current implementation | Gap |
|---|---|---|
| Account creation | E-mail/password; sign-up open (`config.toml:175`) | Hosted confirmation/password policy unknown (SA-AUTH-003) |
| Boutique profile creation | DB trigger (authoritative) + redundant client upsert | Two paths; client errors hidden (SA-ONB-003) |
| Seller approval | `profiles.is_approved`, immutable by the seller (trigger), set by `admin_approve_seller` | SQL-only (SA-OPS-002) |
| Onboarding status | Boolean only | No "fee received / under review / rejected" states (SA-ONB-001) |
| Onboarding fee | ₹50 to a personal UPI (`admin_config.dart`, dart-define overridable) | UTR only in `auth.users.raw_user_meta_data`; no reconciliation |
| Fee verification | Manual, out of band | — |
| Required documents | None (no KYC, GST, ID, bank proof) | Product decision; note for scale |
| UPI configuration | Registration UPI → `upi_id`/`upi_vpa`; editable in Payment settings | VPA change without re-auth (SA-AUTH-004) |
| Phone / e-mail | Phone required, not verified (no OTP); e-mail confirmation off locally | Buyers are told to contact this number |
| Boutique slug | Derived from store name; collision → `-<6 chars of uuid>` | Seller is never shown the final slug (SA-ONB-003) |
| Profile image / logo | Not supported | Storefront uses a generated emblem |
| Business information | Store name, return address | No GSTIN/legal name |
| Completion state | `is_approved` | — |

## 2. Interruption testing (code-level)

| Interruption | Behaviour | Risk |
|---|---|---|
| App closed mid-form | All three steps are in memory → everything lost, including the typed UTR | Re-entry friction |
| Network lost before `signUp` | Error message shown (`AuthException`/generic) | OK |
| Network lost after `signUp` succeeded, before upsert | Trigger already created the profile; upsert failure swallowed | OK in effect, but silent |
| Server timeout | `signUp` has **no timeout** (login has 15 s); spinner can hang | LOW |
| Duplicate submission | Button replaced by a spinner while loading — no double submit | OK |
| Same e-mail again | "An account with this email already exists." → must sign in → pending screen | No way to correct a mistyped UTR in-app (only via WhatsApp to the admin) |
| Back navigation | In-form "Back" keeps state; system Back pops the screen and loses input | LOW |
| Invalid input | Client validators on every field; server CHECKs on phone/slug | OK |
| Partially completed onboarding | Account exists, fee unpaid → pending screen indefinitely; operator has no list | SA-ONB-001 |
| Retry | Re-login works; re-registration blocked by unique e-mail | — |

## 3. Questions from the brief

| Question | Answer | Evidence |
|---|---|---|
| Can the seller accidentally create duplicate accounts? | Not with the same e-mail. With a different e-mail, yes — phone and UPI are not unique; the slug is auto-suffixed, so two near-identical storefronts can exist. | 021:219-221 |
| Can a seller gain operational access without approval? | **Partly.** Server: cannot go live (PASS 12.6) but can create drops/products and upload public images (11.5b, SA-SEC-003). Client: if the profile request fails, the full dashboard opens (T07, SA-AUTH-002). | 12.6, 11.5b, T07 |
| Can incomplete onboarding reach production workflows? | Not buyer-facing workflows (no live drop, storefront view filters `is_approved`). Storage abuse is possible. | 033 view `WHERE is_approved`; 11.5b |
| Can an incomplete profile create a public storefront? | No — `public_seller_storefronts` only lists approved sellers (10.2: 3 approved rows; unapproved seller hidden). But see SA-SEC-001: approved storefronts are writable by anyone. | 10.2 |
| Does onboarding explain what to do next? | Partly. The pending screen says "Account Under Review" and offers WhatsApp support and refresh, but shows no status, no fee confirmation and no ETA; Settings later claims "Active Verified Boutique" regardless of status (SA-ONB-004). | `seller_pending_approval_screen.dart`, `seller_settings_screen.dart:350` |
| Does suspension work? | **No.** `admin_approve_seller(id,false)` hides catalogue rows, but the drop stays live and checkout still succeeds. | 12.7 FINDING (SA-ONB-002) |

## 4. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-ONB-001 | MEDIUM | P1 | Onboarding-fee proof only in auth metadata; SQL-only approval |
| SA-ONB-002 | MEDIUM | P1 | Suspension does not stop a live drop from selling |
| SA-ONB-003 | LOW | P2 | Swallowed upsert errors, slug divergence, placeholder defaults in trigger |
| SA-ONB-004 | LOW | P2 | Pending screen lacks status; Settings hard-codes "Active Verified Boutique" |
| SA-OPS-002 | MEDIUM | P1 | No operator tooling (approvals, refunds, stuck holds) |
| SA-SEC-003 | MEDIUM | P1 | Unapproved accounts can upload to the public bucket |
| SA-AUTH-002 | MEDIUM | P1 | Approval gate fails open on load errors |
| SA-CQ-003 | LOW | P3 | Admin UPI/WhatsApp/fee are build-time constants |
