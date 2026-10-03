# 15 — Security Audit (defensive)

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Authentication, authorisation, RLS, isolation, IDOR/BOLA, direct mutations, RPC authorisation, secrets, local storage, PII/UPI exposure, Storage, deep links, WebView, Android components, backup/debug/release configuration |
| Method | Safe proofs of concept on a **local** database only (suites 10–18, all inside rolled-back transactions); code review; read-only GitHub API. No hosted writes, no use of leaked credentials, no destructive testing. |
| Not executed | Hosted probes (provided as read-only/non-destructive scripts), device-level checks |

## 1. Checklist

| Area | Result | Evidence / finding |
|---|---|---|
| Authentication | GoTrue e-mail/password, PKCE; good error mapping; weak local policy (min 6, no confirmation); reset flow broken | SA-AUTH-003, SA-AUTH-001 |
| Authorisation (RPC) | Every seller RPC checks drop ownership; foreign objects rejected | 11.4 PASS |
| RLS | Enabled on all 7 business tables; seller-scoped policies; buyer access only with order token | `schema-inventory.out`; 10.8, 11.1 PASS |
| Seller isolation | Holds for tables/RPCs/storage folders; **broken through the storefront view** | 11.x PASS; 10.5 FINDING → **SA-SEC-001** |
| IDOR/BOLA | No IDOR via IDs in RPCs (ownership checked); view DML is a BOLA on profiles | SA-SEC-001 |
| Direct table mutation | Products/order lifecycle/ledger protected; gaps: drop slug/status, product insert status, cancelled-order deletion with ledger | SA-DROP-002/003, SA-INV-003, SA-PAY-018 |
| Service-role exposure | None in seller app or buyer-web source; `EnvConfig.validate` rejects keys containing `service_role`; service key only in GitHub Actions secrets for the reaper | `env_config.dart:82`; `reaper-cron.yml:25-26` — PASS (AGENTS rule 3) |
| Committed secrets | Seller credential in public history; rotation unverified | **SA-SEC-002** |
| Local token storage | SharedPreferences (library default); backup not disabled | SA-SEC-006 |
| Sensitive data exposure | Seller phone is public by design (storefront); seller UPI VPA removed from public view (033) — PASS; VPA still sent in WhatsApp reminders by the seller (intentional) | 10.2; SA-PAY-013 |
| Log leakage | Two `debugPrint` of init errors (no tokens); no remote logging | OK |
| Screenshot / clipboard | No `FLAG_SECURE` (acceptable for this use case); UTR/address copied to clipboard (readable by other apps on Android < 13) | Informational |
| UPI data exposure | Payee VPA reaches buyers only via payment attempts (by necessity) | OK |
| Buyer PII | Sellers see their own buyers' name/phone/address (11.6, required for fulfilment); anon sees nothing without token (10.8) | PASS |
| Order PII | Order token capability (028/030); not re-tested in depth (buyer scope) | — |
| Storage access | Cross-folder writes blocked (11.5a); unapproved uploads allowed (11.5b); **anonymous listing of every object, including draft-drop photos** | SA-SEC-003, **SA-SEC-008** |
| Malicious file upload | Bucket MIME allow-list (jpeg/png/webp) + 5 MB limit; content not inspected; EXIF/GPS kept | SA-SEC-004 |
| Insecure deep links | None exist (no attack surface; also no functionality) | SA-AND-003 |
| WebView risks | No WebView in the seller app; buyer FB live player builds an encoded plugin URL | OK |
| Exported Android components | Only `MainActivity` (launcher, required) | OK |
| Backup configuration | Default (allowBackup true) | SA-SEC-006 |
| Debug configuration | `usesCleartextTraffic=true`; CI ships a debuggable APK artifact | SA-SEC-005, SA-CI-001 |
| Release configuration | Signed with the debug key | SA-AND-001 |
| SECURITY DEFINER hygiene | 20/20 pin `search_path`; EXECUTE wider than needed | `security-definer-search-path.out`; SA-SEC-007 |
| Suspension as a security control | Ineffective for live drops | SA-ONB-002 |
| Sensitive setting changes | UPI VPA change without re-auth/notification | SA-AUTH-004 |

## 2. Most important issue: SA-SEC-001 (writable public view)

```
Attacker (no account) ──anon key from buyer-web bundle──► PATCH /rest/v1/public_seller_storefronts?id=eq.<seller>
     body: {"phone_number":"<attacker>", "upi_enabled": false, "advance_amount_paisa": 100, "store_slug": "x"}
PostgREST ► UPDATE public_seller_storefronts … ► auto-updatable view, owner = postgres, security_invoker = off
          ► UPDATE profiles (RLS of profiles not applied to the owner) ► 1 row changed
```
Proven locally with Supabase's default privileges reproduced (10.3/10.4/10.5/10.9). Seller ids are public (storefront rows, drop rows, storage paths — SA-SEC-008), so targeting is trivial. **Fix before anything else** (one migration: revoke DML, `security_invoker = true`, default-privilege hardening, catalog test). Hosted confirmation: `tests/sql/90_hosted_readonly_checks.sql` H1–H3 and the zero-UUID PATCH probe.

## 3. Hosted checks to run (read-only / non-destructive)
1. H1–H3 (view grants/updatability/options), H4 (default privileges), H5 (anon-executable functions).
2. PATCH probe against the all-zero UUID (expects 401/403; 200 `[]` means vulnerable).
3. Storage list with the anon key and empty prefix (expects `[]`).
4. Auth settings in the dashboard: password length, leaked-password protection, e-mail confirmation, sign-up enabled, Site URL/redirects.
5. Auth audit log for the leaked account since 2026-09-26; confirm rotation (SA-SEC-002).

## 4. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-SEC-001 | CRITICAL | P0 | Anonymous/cross-seller writes through `public_seller_storefronts` |
| SA-SEC-002 | CRITICAL | P0 | Seller credential in public Git history; rotation unverified |
| SA-AND-001 | HIGH | P0 | Release signed with debug key; debuggable CI artifact |
| SA-SEC-003 | MEDIUM | P1 | Unapproved accounts can upload to the public bucket |
| SA-SEC-004 | MEDIUM | P1 | EXIF/GPS published with product photos |
| SA-SEC-008 | MEDIUM | P1 | Anyone can list every stored image, incl. unpublished drops |
| SA-AUTH-004 | MEDIUM | P1 | UPI VPA change without re-auth/notification/audit |
| SA-OPS-004 | MEDIUM | P1 | No tested backup/restore; free-tier pause risk |
| SA-AND-002 | MEDIUM | P2 | Unused Bluetooth permissions |
| SA-SEC-005 | LOW | P2 | Cleartext traffic allowed |
| SA-SEC-006 | LOW | P2 | Session in backups |
| SA-SEC-007 | LOW | P2 | Over-broad EXECUTE grants |
