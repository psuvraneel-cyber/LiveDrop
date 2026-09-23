# LiveDrop — Phase 1 Security Architecture & Remediation Report

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-22  
**Governing Roles:** Security Architect & Senior Database Reliability Engineer  
**Authoritative Index:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Operating Guardrails:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)  
**Compliance Standards:** SEC-01 (Provisioning), SEC-02 (Data Isolation), SEC-03 (Trigger Hardening), SEC-04 (Credential Isolation), SEC-05 (Fulfillment Auth)

---

## 1. Security Baseline & Vulnerability Overview

During the Phase 0 Security Audit ([`docs/PHASE-0-SECURITY-AUDIT.md`](file:///c:/LiveDrop/docs/PHASE-0-SECURITY-AUDIT.md)), several critical vulnerabilities were documented:
1. **Unrestricted Seller Provisioning (SEC-01):** Migration 020 automatically created a seller profile with full privileges upon signup. An attacker could register an account, supply an arbitrary UTR for the ₹50 onboarding fee, and immediately broadcast fraudulent drops to buyers.
2. **PostgREST Permission Rejection on Anonymous Storefront (SEC-02):** Revoking raw `SELECT` on `profiles` (Migration 016) broke the anonymous buyer catalog loader (`buyer-catalog.ts`), which performed nested joins on the raw `profiles` table.
3. **Potential Direct SQL Injection / State Tampering (SEC-03):** Direct UPDATE attempts on sensitive business state (`orders.payment_status`, `products.price_paisa`, `profiles.is_approved`) required trigger-level blocking to prevent privilege escalation even if an authenticated JWT acquired table-level write access.
4. **Unregulated Fulfillment Dispatch (SEC-05):** Orders could theoretically be marked shipped directly from an unpaid or unpacked state without enforcing drop ownership or checking payment settlement.

---

## 2. SEC-01: Seller Provisioning & Admin Approval Gate

### 2.1 Threat Description
Any user could sign up via Supabase Auth and publish a live drop, accepting buyer UPI payments without identity verification or admin review.

### 2.2 Implemented Countermeasures (`021_seller_provisioning_security.sql`)
1. **Default Unapproved State:**
   ```sql
   ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_approved BOOLEAN NOT NULL DEFAULT false;
   ```
2. **Approval Immutability Trigger (`trg_enforce_profiles_approval_immutability`):**
   Blocks any client or authenticated seller from modifying their own `is_approved` status directly. Only superuser/service-role migrations or dedicated RPCs can alter this field.
   ```sql
   IF NEW.is_approved IS DISTINCT FROM OLD.is_approved THEN
       IF current_user NOT IN ('postgres', 'service_role') THEN
           RAISE EXCEPTION 'FORBIDDEN: Only administrators can modify seller approval status'
               USING ERRCODE = '42501';
       END IF;
   END IF;
   ```
3. **Drop Publication Enforcement Trigger (`trg_enforce_drops_seller_approval`):**
   Prevents unapproved sellers from setting a drop to `active` or `scheduled`. Unapproved sellers may only create or edit `draft` drops.
   ```sql
   IF NEW.status IN ('active', 'scheduled') THEN
       SELECT is_approved INTO v_is_approved FROM profiles WHERE id = NEW.seller_id;
       IF NOT v_is_approved THEN
           RAISE EXCEPTION 'UNAUTHORIZED: Seller account is pending administrative approval'
               USING ERRCODE = '42501';
       END IF;
   END IF;
   ```
4. **Administrative Approval RPC (`admin_approve_seller`):**
   A `SECURITY DEFINER` function with `search_path = public, pg_temp` restricted strictly to service_role / administrative callers.
5. **Client UI State Integration (`seller_pending_approval_screen.dart`):**
   Sellers without `is_approved = true` are routed to a persistent pending approval holding screen featuring a direct WhatsApp concierge link for admin onboarding.

---

## 3. SEC-02: Public Projections & Anonymous Data Isolation

### 3.1 Threat Description
Direct table queries on `profiles` and `products` expose internal seller metadata, financial configurations (advance amounts, default shipping rates), and buyer reservation UUIDs (`reserved_by_order_id`).

### 3.2 Implemented Countermeasures (`016_public_projection_views.sql` & `buyer-catalog.ts`)
1. **Public Projection Views:**
   - `public_seller_storefronts`: Masks `phone_number` and `return_address`, exposing only `store_name`, `store_slug`, `instagram_handle`, and `avatar_url`.
   - `public_products_catalog`: Masks `reserved_by_order_id`, exposing only public catalog attributes (`id`, `drop_id`, `title`, `price_paisa`, `size`, `image_url`, `status`, `version`).
2. **Strict Privilege Revocation:**
   ```sql
   REVOKE SELECT ON profiles FROM anon;
   REVOKE SELECT ON products FROM anon;
   GRANT SELECT ON public_seller_storefronts TO anon, authenticated;
   GRANT SELECT ON public_products_catalog TO anon, authenticated;
   ```
3. **Catalog Data Layer Rewiring:**
   `buyer-catalog.ts` refactored to query `drops` joined with `public_seller_storefronts` instead of the restricted `profiles` table, completely eliminating `42501 permission denied` errors during anonymous browsing.

---

## 4. SEC-03: Trigger-Level Direct Mutation Defense

### 4.1 Threat Description
If an attacker exploits a compromised JWT or misconfigured RLS policy, raw SQL `UPDATE` queries could forge payment status or modify reserved inventory prices.

### 4.2 Implemented Defenses
1. **Order Payment Immutability (`trg_enforce_orders_payment_immutability`):**
   Direct `UPDATE` on `payment_status`, `advance_paid_paisa`, `total_paid_paisa`, or `balance_due_paisa` raises SQLSTATE `42501`. State transitions must occur through audited RPCs (`record_verified_payment`, `verify_manual_upi_payment`, `reject_manual_upi_payment`).
2. **Inventory Stock Immutability (`trg_enforce_products_inventory_immutability`):**
   Direct `UPDATE` on product `status`, `reserved_by_order_id`, or `hold_expires_at` is strictly blocked unless executed from within approved transactional RPCs.
3. **Product Price & Attribute Hardening (`025_product_editing.sql`):**
   Direct modification of `price_paisa`, `title`, or `size` on products in `reserved` or `sold` status is blocked at the database trigger layer with SQLSTATE `42501`.

---

## 5. SEC-04: Credential Isolation & Service-Role Quarantine

### 5.1 Verification Protocol
The entire codebase is audited against regex patterns for high-entropy secrets and Supabase service keys:
```powershell
rg "service_role|supabase_service_key|eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" --glob "!node_modules" --glob "!.git"
```

### 5.2 Verification Results
- **Buyer Web:** Zero references to `SUPABASE_SERVICE_ROLE_KEY` in `src/` or `public/`. Client-side environment strictly binds `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- **Seller App:** Zero embedded service keys. Communication with Supabase occurs entirely over authenticated user sessions via Dart Supabase client.
- **Automated Verification:** Scenario 29 in `test-failure-injections.mjs` runs continuous static analysis on client artifacts and passed with zero leaks.

---

## 6. SEC-05: Fulfillment State & Access Control

### 6.1 Threat Description
A seller could mark an order as shipped before it was packed, or before payment was settled, or Seller B could mark Seller A's order as shipped.

### 6.2 Implemented Countermeasures (`026_fulfillment_state_machine.sql`)
1. **Drop Ownership Assertion:**
   Both `mark_order_ready_to_ship` and `mark_order_shipped` query `drops.seller_id` against `auth.uid()`. If mismatched, execution halts immediately with `FORBIDDEN`.
2. **Payment Settlement Requirement:**
   `mark_order_ready_to_ship` requires `payment_status = 'paid'` and `balance_due_paisa = 0`. Orders with pending balances cannot enter the packing stage.
3. **Strict Transition Order:**
   `mark_order_shipped` requires `fulfilment_status = 'ready_to_ship'`. Attempting to ship directly from `not_ready` throws `ORDER_NOT_READY_TO_SHIP`.
