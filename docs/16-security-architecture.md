# 16 — Security Architecture & Access Control Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Threat Model Reference:** [`docs/17-threat-model.md`](file:///c:/LiveDrop/docs/17-threat-model.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Security Architecture Principles

1. **Principle of Least Privilege:** Public unauthenticated buyers have zero direct write access to database tables. All mutating interactions must traverse hardened PostgreSQL RPC functions.
2. **Cryptographic Receipt Isolation:** Unauthenticated buyers access order confirmations exclusively through high-entropy UUIDv4 `order_token` credentials.
3. **No Privileged Client Secrets:** The Supabase `service_role` key is strictly prohibited from client bundles (Next.js client code, Flutter APK binaries). Only the public `anon` key is distributed.
4. **Authoritative Server Calculation:** Financial totals and inventory state transitions are calculated strictly within database transactions, completely ignoring client-side price or state parameters.

---

## 2. Authentication & Session Management

### 2.1 Seller Authentication
* **Provider:** Supabase Auth (GoTrue).
* **Strategy:** Email and Password authentication restricted strictly to the boutique owner. Self-service registration is disabled; seller accounts are provisioned via administrative invite.
* **Token Lifecycle:**
  * JWT Access Token: 1-hour expiration.
  * Refresh Token: 30-day sliding expiration stored in Android EncryptedSharedPreferences (via `flutter_secure_storage`).
* **Session Termination:** Tapping "Logout" in the mobile app immediately revokes the active session token and purges local encryption keys.

### 2.2 Buyer Identity Model
* **Zero-Login Mandate:** Buyers are unauthenticated. No passwords, SMS OTPs, or social logins.
* **Session Verification:** Order creation issues a client-stored `order_token` (UUIDv4) that acts as an unforgeable bearer credential for accessing `/order/[id]`.

---

## 3. Authorization & Row-Level Security (RLS) Policies

All PostgreSQL tables have Row-Level Security explicitly enabled (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`). Direct table access without an explicit policy is denied by default.

```sql
-- Ensure standard Supabase roles exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO anon, authenticated;

-- ============================================================================
-- 1. TABLE: profiles
-- ============================================================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- 1.1 Public read: Anyone can read public boutique seller profiles (store branding, UPI ID, business WhatsApp)
CREATE POLICY profiles_public_read ON profiles
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- 1.2 Seller insert: Authenticated sellers can only create their own profile matching auth.uid()
CREATE POLICY profiles_seller_insert ON profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (id = auth.uid());

-- 1.3 Seller update: Authenticated sellers can only update their own profile matching auth.uid()
CREATE POLICY profiles_seller_update ON profiles
    FOR UPDATE
    TO authenticated
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

-- ============================================================================
-- 2. TABLE: drops
-- ============================================================================
ALTER TABLE drops ENABLE ROW LEVEL SECURITY;

-- 2.1 Public read: Anonymous buyers can only view active 'live' drops
CREATE POLICY drops_public_read_live ON drops
    FOR SELECT
    TO anon
    USING (status = 'live');

-- 2.2 Seller manage: Authenticated sellers can view, insert, update, and delete their own drops
CREATE POLICY drops_seller_manage ON drops
    FOR ALL
    TO authenticated
    USING (seller_id = auth.uid())
    WITH CHECK (seller_id = auth.uid());

-- ============================================================================
-- 3. TABLE: products
-- ============================================================================
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- 3.1 Public read: Anonymous buyers can only view products belonging to active 'live' drops
CREATE POLICY products_public_read_live ON products
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = products.drop_id
              AND drops.status = 'live'
        )
    );

-- 3.2 Seller manage: Authenticated sellers can manage products for drops they own
CREATE POLICY products_seller_manage ON products
    FOR ALL
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = products.drop_id
              AND drops.seller_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = products.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- ============================================================================
-- 4. TABLE: orders
-- ============================================================================
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- 4.1 Token-gated read: Anonymous buyers can read their order ONLY if they supply the exact secret x-order-token
CREATE POLICY orders_buyer_read_with_token ON orders
    FOR SELECT
    TO anon
    USING (
        order_token::text = (
            CASE 
                WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> ''
                THEN current_setting('request.headers', true)::json->>'x-order-token'
                ELSE NULL
            END
        )
    );

-- 4.2 Seller SELECT: Authenticated sellers can read orders for their own drops
CREATE POLICY orders_seller_select ON orders
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- 4.3 Seller UPDATE: Authenticated sellers can update orders (e.g. status, tracking) for their own drops
CREATE POLICY orders_seller_update ON orders
    FOR UPDATE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- 4.4 Seller DELETE: Authenticated sellers can delete unfinalized orders for their own drops (finalized deletion guarded by trigger)
CREATE POLICY orders_seller_delete ON orders
    FOR DELETE
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM drops
            WHERE drops.id = orders.drop_id
              AND drops.seller_id = auth.uid()
        )
    );

-- Direct REST INSERT on orders is strictly blocked for all roles (order creation occurs exclusively via atomic RPC).

-- ============================================================================
-- 5. TABLE: order_items
-- ============================================================================
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- 5.1 Token-gated read: Anonymous buyers can view order items ONLY for their token-verified order
CREATE POLICY order_items_buyer_read_with_token ON order_items
    FOR SELECT
    TO anon
    USING (
        EXISTS (
            SELECT 1 FROM orders
            WHERE orders.id = order_items.order_id
              AND orders.order_token::text = (
                  CASE 
                      WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> ''
                      THEN current_setting('request.headers', true)::json->>'x-order-token'
                      ELSE NULL
                  END
              )
        )
    );

-- 5.2 Seller read: Authenticated sellers can view line items for orders under their drops
CREATE POLICY order_items_seller_select ON order_items
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM orders
            JOIN drops ON drops.id = orders.drop_id
            WHERE orders.id = order_items.order_id
              AND drops.seller_id = auth.uid()
        )
    );

-- Direct mutation (INSERT/UPDATE/DELETE) on order_items is strictly blocked for all roles (line items are immutable financial records).

-- ============================================================================
-- 6. GRANT TABLE PERMISSIONS TO ROLES
-- ============================================================================
-- Revoke all default public permissions
REVOKE ALL ON profiles FROM PUBLIC;
REVOKE ALL ON drops FROM PUBLIC;
REVOKE ALL ON products FROM PUBLIC;
REVOKE ALL ON orders FROM PUBLIC;
REVOKE ALL ON order_items FROM PUBLIC;

-- Anon permissions (Read-only on public/token-scoped surfaces)
GRANT SELECT ON profiles TO anon;
GRANT SELECT ON drops TO anon;
GRANT SELECT ON products TO anon;
GRANT SELECT ON orders TO anon;
GRANT SELECT ON order_items TO anon;

-- Authenticated permissions (Management permissions on seller-owned surfaces)
GRANT SELECT, INSERT, UPDATE ON profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON drops TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON products TO authenticated;
GRANT SELECT, UPDATE, DELETE ON orders TO authenticated;
GRANT SELECT ON order_items TO authenticated;
```

---

### 3.1 Public View Privilege Lockdown (migration 034, SA-SEC-001)
The seller-app audit (commit 94ccfc9) found that `anon` could `UPDATE`/`DELETE` seller profiles through the auto-updatable owner-rights view `public_seller_storefronts`, because Supabase's default privileges had granted every privilege on new views to `anon` and `authenticated`. The view runs with its owner's rights, so base-table RLS did not protect it.

Rules since migration 034:
* Every view in `public` has `REVOKE ALL FROM PUBLIC, anon, authenticated`; `SELECT` is granted back only to roles that had it. `public_seller_storefronts` and `public_products_catalog` get explicit `GRANT SELECT TO anon, authenticated, service_role`.
* Views stay owner-rights views (switching to `security_invoker` would break them, because `anon` has no `SELECT` on `profiles`).
* Default privileges: `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM anon;` and `... REVOKE TRUNCATE, REFERENCES, TRIGGER ON TABLES FROM authenticated;` (TRUNCATE bypasses RLS).
* `TRUNCATE`, `REFERENCES` and `TRIGGER` are revoked from `PUBLIC`, `anon` and `authenticated` on every existing public table.
* RLS policies are unchanged.
* **Any new view must be granted SELECT only.** Checked locally by SQL 10.3–10.9 and 19.20a–c; on hosted by `audit/seller-app/tests/sql/90_hosted_readonly_checks.sql` H1 and H14.

### 3.2 Product Image Storage (migration 038, SA-SEC-003 / SA-SEC-008)
* The `product-images` bucket is public: photos are served by public object URL, which no RLS policy governs.
* Listing/searching objects is limited to the owning seller's folder (`product_images_seller_read`, `authenticated` only). Anonymous visitors can no longer enumerate seller IDs, draft-drop photos or other uploads.
* Uploading and overwriting require the caller's own folder **and** an approved seller (`public.is_seller_approved(auth.uid())`), so self-registered, unapproved accounts cannot use the bucket as free public hosting.
* On a hosted project the deploy role may be refused when changing policies on `storage.objects` (owned by `supabase_storage_admin`). Migration 038 then logs a WARNING instead of failing, and post-deploy check H21 fails until section 1 of 038 is run in the Supabase SQL editor.

### 3.3 Seller Suspension (migration 038, SA-ONB-002)
Revoking approval (`admin_approve_seller(id, false)` or a direct update of `profiles.is_approved`) closes the seller's live drops through the safe-closure path, and checkout and new payment requests return `SELLER_SUSPENDED`. Buyers who already paid can still submit their UTR, and the seller can still verify it or record a refund.

### 3.4 Payee Details Need a Recent Password Sign-In (migration 039, SA-AUTH-004)
The payee UPI ID decides where every buyer's money goes. Since migration 039:
* A seller can change `upi_id`, `upi_vpa` or `phone_number` only within 10 minutes of signing in with their password. The access token's `amr` claim is checked by a database trigger, so a stolen session token alone is not enough.
* Every change, by the seller or by LiveDrop staff, is written to `payee_change_log`. Sellers can read it but not change it, and the app shows recent changes in Payment settings.
* The app asks for the password and shows the new UPI ID for checking before it saves. While a drop is live, it also warns that the change applies to payments buyers start from then on.

## 4. Database Security Definer Hardening

PostgreSQL functions declared with `SECURITY DEFINER` execute with the privileges of the database owner.
* **Privilege Escalation Vulnerability:** If `search_path` is not explicitly pinned, an attacker can manipulate temporary schema search paths to execute malicious functions under superuser privileges.
* **Mandatory Hardening Standard:** Every `SECURITY DEFINER` function in LiveDrop must include:
  ```sql
  SECURITY DEFINER SET search_path = public, pg_temp;
  ```
* **Revocation of Public Execution:** Functions intended exclusively for authenticated sellers must revoke execution permissions from the `anon` and `public` roles:
  ```sql
  REVOKE EXECUTE ON FUNCTION mark_order_paid(UUID) FROM PUBLIC, anon;
  GRANT EXECUTE ON FUNCTION mark_order_paid(UUID) TO authenticated;
  ```
* **Internal helpers (migration 035):** `release_stale_hold`, `apply_upi_payment_transition`, `upi_verification_response` and the trigger function `prevent_finalized_order_deletion` have EXECUTE revoked from `PUBLIC`, `anon` and `authenticated` (the three helpers also from `service_role`). `record_refund` is granted to `authenticated` and `service_role` only. Verified by SQL 19.3 and 19.9a; hosted check H16. Since migration 038, `close_drop_safely` and the trigger function `close_live_drops_on_suspension` are revoked the same way (SQL 20.30, hosted H22).

---

## 5. URL & WhatsApp Deep-Link Security

The checkout handshake relies on generating standard `https://wa.me/{seller_phone}?text={encoded_message}` links.

### 5.1 Injection & Malformed Payload Defenses
1. **Phone Number Normalization:**
   * Raw input is cleaned to strictly retain digits: `phone.replace(/[^0-9]/g, '')`.
   * Strips leading `0` or `+`. If exactly 10 digits starting with `6–9`, prepends Indian country code `91`.
   * Prevents protocol injection or dialer exploits.
2. **Text Payload Sanitization:**
   * Line breaks normalized strictly to `%0A`.
   * Characters `#`, `&`, `+`, `=`, and unicode emojis are encoded using `encodeURIComponent`.
   * Payload length capped at **2,000 characters** to prevent browser address-bar truncation crashes in embedded webviews.

---

## 6. Secrets & Environment Classification

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SECRETS CLASSIFICATION                           │
├────────────────────┬──────────────────┬─────────────────────────────────────┤
│ Credential         │ Permitted Scope  │ Forbidden Deployment Locations      │
├────────────────────┼──────────────────┼─────────────────────────────────────┤
│ `SUPABASE_ANON_KEY`│ Public (Web/APK) │ Never use for administrative tasks  │
│ `SUPABASE_URL`     │ Public (Web/APK) │ N/A                                 │
│ `SERVICE_ROLE_KEY` │ Backend / CI Only│ NEVER in Next.js Client, NEVER in   │
│                    │                  │ Flutter APK, NEVER in public repos  │
│ `DATABASE_URL`     │ CI / Migrations  │ NEVER in client source or build APK │
└────────────────────┴──────────────────┴─────────────────────────────────────┘
```

* **Git Secret Defense:** Pre-commit hooks (`git-secrets` / `trufflehog`) scan for Supabase service role tokens and private keys prior to any commit.
* **CI Secret Scanning (SA-SEC-002, since 2026-10-03):** `.github/workflows/secret-scan.yml` runs gitleaks (config `.gitleaks.toml`) on every push and pull request over the new commits only; findings are redacted in the log. History is not rescanned, because it still contains a staging seller credential leaked in commit 0abdaeb (`scripts/seed-legitimate-staging-drop.mjs`). That credential must be rotated by the owner, and purging the history is a separate decision: see `docs/ops/credential-rotation-runbook.md`.

### 6.0 Operator Console and Backups (SA-OPS-002, SA-OPS-004, ADR-016)
* `/admin` uses the anon key and a normal user session kept in memory only. Authorisation is entirely server-side:
  * `platform_admins` membership is checked by every `admin_*` RPC.
  * Writes need a password sign-in within 10 minutes.
  * Every write is logged in `admin_actions`.
  * `platform_admins` and `admin_actions` have RLS on and no client privileges (post-check H27).
* Nightly database backups are encrypted with `BACKUP_PASSPHRASE` before upload. The unencrypted dumps exist only on the CI runner and are shredded after encryption.

### 6.1 Android Release Signing (SA-AND-001, ADR-012)
* Release builds of the seller app are signed only with the owner's upload/release key, from `seller-app/android/key.properties` (gitignored) or the env vars `LIVEDROP_KEYSTORE_PATH`, `LIVEDROP_KEYSTORE_PASSWORD`, `LIVEDROP_KEY_ALIAS`, `LIVEDROP_KEY_PASSWORD`. Without them a release task fails with a `GradleException`; there is no silent fallback to the debug key.
* CI (`seller-app-ci.yml`): pull requests run analyze, test and a debug build. On push to main or manual dispatch a release job builds a signed AAB and APK from the secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, checks that the certificate is not the Android debug certificate (and matches `vars.ANDROID_RELEASE_CERT_SHA256` when set), and deletes the keystore afterwards. Without the secrets the job is skipped with a notice.
* The keystore, its passwords and `key.properties` never enter the repository, the APK assets or `NEXT_PUBLIC_*`. Setup: `docs/ops/android-release-signing.md`.
