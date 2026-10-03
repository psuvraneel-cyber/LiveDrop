# 03 — Seller Authentication Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Login → Supabase Auth → session → route protection → refresh → logout; seller isolation |
| Executed | Code trace; audit Flutter tests T06/T07; SQL isolation suite 11 and exposure suite 10 (local DB) |
| Not executed | Hosted GoTrue settings, real token expiry on a device, process death, device restart |

## 1. Lifecycle as implemented

| Step | Implementation | Evidence |
|---|---|---|
| Credential submission | `signInWithPassword(email, password)` with a 15 s timeout; empty-field check; maps timeout/socket/auth errors to messages | `seller_login_screen.dart:41-122` |
| Supabase Auth | GoTrue e-mail/password, PKCE flow | `supabase_service.dart:34-40` |
| Session creation/persistence | supabase_flutter persists the session (default SharedPreferences storage) and refreshes tokens automatically | library default; no custom storage |
| Authenticated state | `SellerAuthGate` reads `isAuthenticated` once, then listens to `authStateChanges` and flips between login and home | `main.dart:103-169` |
| Route protection | Only the root widget switches; pushed routes are not guarded or cleared | `main.dart:156-167` (SA-AUTH-005) |
| Approval gate | Pending screen only if the profile *loaded* and `is_approved=false`; errors fall through to the dashboard | `main.dart:199-210, 310-317`; T07 (SA-AUTH-002) |
| Server-side authorisation | Repository requires `currentUser` (`_requireSellerId`); RLS + RPC ownership checks on every object | `seller_repository.dart:28-36`; suite 11 |
| Session refresh | Library auto-refresh; no app handling of refresh failure beyond the auth stream | — |
| Logout | `SupabaseService.signOut()` from Settings / pending screen; local intake queue and caches are **not** cleared | `main.dart:313-315`; `seller_settings_screen.dart:99-100` |
| Password reset | `resetPasswordForEmail(email)` without `redirectTo`; no deep link; no reset page | SA-AUTH-001 |

## 2. Test matrix (brief section 5)

| # | Case | Result | How verified |
|---|---|---|---|
| 1 | Valid login | Works (navigates to home) | Code trace; existing `seller_auth_registration_test.dart` (widget level, fake auth) — PROVEN-CODE |
| 2 | Invalid password | "Invalid email or password…" | Code trace (`:96-108`) — PROVEN-CODE |
| 3 | Unknown seller | Same message as invalid password (no account enumeration) — good | GoTrue behaviour + code — INFERRED |
| 4 | Expired session | Library refresh; if refresh fails `authStateChanges` emits signedOut → login screen; pushed screens stay open | INFERRED (device test needed) |
| 5 | Expired access token | Auto-refreshed before requests by supabase_flutter | INFERRED |
| 6 | Refresh token | Rotated by GoTrue; revoked/invalid refresh → signed out | INFERRED |
| 7 | App restart | Session restored from storage → home without login | INFERRED (library default) |
| 8 | Device restart | Same as 7 | NOT TESTED (no device) |
| 9 | Temporary network loss | Login shows network/timeout message; inside the app most screens show empty/zero states silently (`catch (_)`); the approval gate fails open | T07 (PROVEN-LOCAL-FLUTTER); SA-OBS-001 |
| 10 | Network recovery | No automatic refetch; user must pull to refresh each tab | PROVEN-CODE (SA-CQ-001) |
| 11 | Logout | Root returns to login | PROVEN-CODE |
| 12 | Logout + back navigation | Root swap means Back on the login screen exits the app; screens pushed before logout remain on the stack | INFERRED (SA-AUTH-005) |
| 13 | Protected deep link | No deep links exist at all | PROVEN-CODE (SA-AND-003) |
| 14 | Unauthorized route access | Not applicable in UI; server enforces RLS/RPC ownership | Suite 11 PASS |
| 15 | Disabled (suspended) seller | `is_approved=false` shows pending screen on next profile load; **live drop keeps selling** | Suite 12.7 FINDING (SA-ONB-002) |
| 16 | Incomplete onboarding | Unapproved: can create drafts/products and upload images; cannot go live | Suite 12.6 PASS, 11.5b FINDING |
| 17 | Revoked account (user deleted) | Profile row cascades from `auth.users`; app shows dashboard with errors (fail-open) | INFERRED |
| 18 | Malformed session state | Library discards invalid stored sessions; not tested | NOT TESTED |

## 3. Can authentication state become…

| State | Possible? | Path |
|---|---|---|
| Stale | **Yes** | Pushed routes survive sign-out (SA-AUTH-005); tabs never refresh (SA-CQ-001) |
| Inconsistent | **Yes** | Profile load error → treated as approved (SA-AUTH-002) |
| Duplicated | No evidence | Single `authStateChanges` subscription, cancelled in `dispose` |
| Silently unauthenticated | Partly | Requests after refresh failure surface as `UnauthorizedException`/empty screens rather than a login prompt on pushed routes |
| Incorrectly authenticated | No | The server is authoritative (RLS/RPC) |
| Stuck on a loading screen | Unlikely | `_isChecking` resolves synchronously; init failure shows `ConfigurationErrorScreen` with retry |

## 4. Can one seller ever access another seller's data?

| Channel | Result | Evidence |
|---|---|---|
| Base tables (read) | **No** — orders, items, attempts, ledger, products of another seller's draft drops: 0 rows | 11.1 PASS |
| Live drop rows of other sellers | Readable by design (public catalogue) | 11.1b INFO |
| Base tables (write) | **No** — UPDATE/DELETE 0 rows; product INSERT into another seller's drop rejected by RLS | 11.2, 11.3, 10.6 PASS |
| RPCs | **No** — verify/reject/release/sold-offline/update_product/close/ready/ship all reject foreign objects | 11.4 PASS |
| Storage | **No** cross-folder writes | 11.5a PASS |
| Public storefront view | **YES (write)** — a seller (or anonymous user) can rewrite another approved seller's public profile fields, including the slug | 10.5 FINDING, 10.3 FINDING → **SA-SEC-001** |
| Client code | Repository filters by `auth.uid()` but correctness does not depend on it | PROVEN-CODE |

Conclusion: seller isolation is enforced server-side on every table and RPC the app uses; the single break is the writable `public_seller_storefronts` view (CRITICAL, P0).

## 5. Additional observations
- Login error mapping is good (no enumeration, timeouts handled).
- Password policy and e-mail confirmation in `supabase/config.toml` are weak (min 6, no confirmation); hosted values unknown (SA-AUTH-003).
- The payee UPI VPA can be changed without re-authentication or notification (SA-AUTH-004) — the most valuable target after an account takeover (see SA-SEC-002).
- Logout leaves the device's intake queue in place; if another seller logs in on the same phone, the queued items of the first seller are retried under the second account and fail permanently (RLS) — an edge case, folded into SA-OFF-003's error-classification fix.

## 6. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-SEC-001 | CRITICAL | P0 | Anonymous/cross-seller writes through `public_seller_storefronts` |
| SA-SEC-002 | CRITICAL | P0 | Seller credential in public Git history; rotation unverified |
| SA-AUTH-001 | HIGH | P1 | Password reset cannot be completed |
| SA-AUTH-002 | MEDIUM | P1 | Approval gate fails open on profile load errors |
| SA-AUTH-003 | MEDIUM | P1 | Weak password / no e-mail confirmation (local config; hosted unknown) |
| SA-AUTH-004 | MEDIUM | P1 | UPI VPA change without re-auth/notification/audit |
| SA-AUTH-005 | LOW | P2 | Pushed routes survive sign-out |
| SA-AUTH-006 | LOW | P3 | "Remember me" does nothing |
| SA-AND-003 | MEDIUM | P1 | No deep links (blocks recovery and notification routing) |
