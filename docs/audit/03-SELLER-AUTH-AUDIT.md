# 03 — Seller authentication and authorization audit

**Confidence: PARTIALLY VERIFIED.** Login calls Supabase Auth; `SupabaseService` uses PKCE and exposes auth-state changes/session persistence through `supabase_flutter`. Login, password reset, registration, and a pending-approval screen exist. New signups include boutique metadata; migration 021 provisions an unapproved profile and prevents unapproved sellers from making drops live.

| Boundary | Static result | Can an attacker bypass it? |
|---|---|---|
| Sign-in/session | Supabase-managed; session refresh/revocation behavior not exercised | Not proven at runtime. |
| Profile approval | trigger rejects direct approval-field mutations; service-role-only `admin_approve_seller` | Direct self-approval appears blocked statically; admin path is operationally missing. |
| Live drop publish | `enforce_drops_seller_approval` trigger checks profile approval | Appears blocked statically; not runtime-tested. |
| Tenant data | seller repository scopes by `auth.uid`; RLS and RPC ownership checks exist | Not proven without multi-seller RLS test. |
| Registration | UI calls `auth.signUp`, then directly upserts `profiles` and suppresses any error | Approval fields are trigger protected, but failed provisioning can be hidden from the seller. |

Onboarding is **self-registration plus manual approval**, with a UI fee/UTR claim. The UTR is sent as Auth metadata (`seller_registration_screen.dart:116-126`); no durable onboarding-payment review entity or admin UI was found. This is AUD-006. Invalid credentials, expired/revoked session, offline restore, deep-link guard, duplicate seller, and approval end-to-end scenarios were not safely runnable.
