# LiveDrop — TASK-1.2 RLS Test Report
# Comprehensive Database Security & Access Control Test Execution

**Document Version:** 1.0.0  
**Test Date:** 2026-09-11  
**Execution Environment:** Node.js v22.14.0 / PostgreSQL 18.3 WASM (PGlite) / Vitest v5.0.0  
**Task Authority:** Phase 1 / TASK-1.2  
**Governing Documents:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md), [`docs/RLS-ACCESS-MATRIX.md`](file:///c:/LiveDrop/docs/RLS-ACCESS-MATRIX.md), [`docs/TASK-1.2-RLS-SECURITY-MATRIX.md`](file:///c:/LiveDrop/docs/TASK-1.2-RLS-SECURITY-MATRIX.md), [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)

---

## 1. Executive Summary

Row-Level Security (RLS) policies and database access control permissions were implemented in migration [`supabase/migrations/008_enable_rls_and_policies.sql`](file:///c:/LiveDrop/supabase/migrations/008_enable_rls_and_policies.sql). A dedicated, rigorous test suite of 35 security test cases was authored in [`buyer-web/src/test/rls.test.ts`](file:///c:/LiveDrop/buyer-web/src/test/rls.test.ts) testing three separate security contexts:
1. **`Anonymous Buyer` (`anon`):** Unauthenticated client without JWT.
2. **`Seller A` (`authenticated`):** Boutique owner Priya (`a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11`).
3. **`Seller B` (`authenticated`):** Boutique owner Ananya (`b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22`).

**Final Test Execution Status:** **100% PASS (69/69 total tests across suite, 35/35 dedicated RLS tests passed).**

---

## 2. Test Identities & Fixture Matrix

| Identity | Role | Auth Identifier (`auth.uid()`) | JWT Claims / Session Context | Fixtures Owned |
|---|---|---|---|---|
| **Table Owner / Superuser** | `postgres` | Superuser | System maintenance context | Seed records |
| **Seller A** | `authenticated` | `a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11` | `request.jwt.claim.sub = 'a0eebc99...'` | Profile A, Drops A1 (live), A2 (draft), A3 (closed), Products A1, A2, Order A1, OrderItem A1 |
| **Seller B** | `authenticated` | `b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22` | `request.jwt.claim.sub = 'b0eebc99...'` | Profile B, Drops B1 (live), B2 (draft), Products B1, B2, Order B1, OrderItem B1 |
| **Anonymous Buyer (Public)** | `anon` | NULL | Empty sub, empty headers | Public browse context |
| **Anonymous Buyer (Token)** | `anon` | NULL | `x-order-token = 'fa000000-0000-0000-0000-000000000001'` | Receipt view for Order A1 |

---

## 3. Detailed Test Case Execution Log

### 3.1 Catalog RLS Enforcement Verification
| Test ID | Test Description | Role Context | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|
| `RLS-CAT-01` | Verify `rowsecurity = true` for `profiles`, `drops`, `products`, `orders`, `order_items` in `pg_tables` | `postgres` | 5 tables confirmed | 5 tables confirmed with `rowsecurity = true` | **PASS** |
| `RLS-CAT-02` | Verify `relrowsecurity = true` for all 5 core tables in `pg_class` | `postgres` | 5 tables confirmed | 5 tables confirmed with `relrowsecurity = true` | **PASS** |

### 3.2 Seller Isolation & Multi-Tenancy Boundary
| Test ID | Policy Tested | Role Context | Action | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|---|
| `RLS-SEL-01` | `POL-DROP-03` | `authenticated` (Seller A) | `SELECT FROM drops` | Only Drops A1, A2, A3 returned; Seller B drops hidden | 3 rows returned, 0 Seller B rows | **PASS** |
| `RLS-SEL-02` | `POL-DROP-04` | `authenticated` (Seller A) | `UPDATE drops (Drop B1)` | 0 rows affected | 0 rows updated, title untampered | **PASS** |
| `RLS-SEL-03` | `POL-DROP-05` | `authenticated` (Seller A) | `DELETE FROM drops (Drop B2)` | 0 rows affected | 0 rows deleted, drop preserved | **PASS** |
| `RLS-SEL-04` | `POL-PROF-04` | `authenticated` (Seller A) | `UPDATE profiles (Profile A vs B)` | Profile A updated; Profile B update returns 0 rows | Profile A updated, Profile B untampered | **PASS** |
| `RLS-SEL-05` | `POL-PROD-03` | `authenticated` (Seller A) | `SELECT FROM products` | Only Products A1, A2 returned; Seller B products hidden | 2 rows returned, 0 Seller B products | **PASS** |
| `RLS-SEL-06` | `POL-PROD-04` | `authenticated` (Seller A) | `INSERT INTO products (Drop B1)` | Denied by RLS WITH CHECK policy | Threw: `violates row-level security policy` | **PASS** |
| `RLS-SEL-07` | `POL-PROD-05` | `authenticated` (Seller A) | `UPDATE products (Product B1)` | 0 rows affected | 0 rows updated, price untampered | **PASS** |
| `RLS-SEL-08` | `POL-PROD-05` | `authenticated` (Seller A) | `DELETE FROM products (Product B2)` | 0 rows affected | 0 rows deleted, product preserved | **PASS** |
| `RLS-SEL-09` | `POL-ORD-05` | `authenticated` (Seller A) | `SELECT FROM orders` | Only Order A1 returned; Order B1 hidden | 1 row returned (Order A1), Order B1 invisible | **PASS** |
| `RLS-SEL-10` | `POL-ORD-06` | `authenticated` (Seller A) | `UPDATE orders (Order B1)` | 0 rows affected | 0 rows updated, status untampered | **PASS** |
| `RLS-SEL-11` | `POL-ITEM-02` | `authenticated` (Seller A) | `SELECT FROM order_items` | Only OrderItem A1 returned; OrderItem B1 hidden | 1 row returned (OrderItem A1) | **PASS** |

### 3.3 Public Buyer Catalog Access (Anonymous Role)
| Test ID | Policy Tested | Role Context | Action | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|---|
| `RLS-BUY-01` | `POL-DROP-01` | `anon` | `SELECT FROM drops` | Only live drops (A1, B1) visible; draft/closed hidden | 2 rows returned (`status = 'live'`) | **PASS** |
| `RLS-BUY-02` | `POL-PROD-01` | `anon` | `SELECT FROM products` | Only products in live drops visible | 2 rows returned (A1, B1), draft products hidden | **PASS** |
| `RLS-BUY-03` | `POL-PROF-01` | `anon` | `SELECT FROM profiles` | Store branding & UPI info visible | 2 boutique profiles returned | **PASS** |
| `RLS-BUY-04` | `POL-PROF-02` | `anon` | `INSERT INTO profiles` | Rejected (No INSERT privilege / policy) | Threw: `permission denied for table profiles` | **PASS** |
| `RLS-BUY-05` | `POL-PROF-03` | `anon` | `UPDATE profiles` | Rejected (No UPDATE privilege / policy) | Threw: `permission denied for table profiles` | **PASS** |
| `RLS-BUY-06` | `POL-DROP-02` | `anon` | `INSERT/UPDATE/DELETE drops` | Rejected (No write privileges / policies) | All three operations threw `permission denied` | **PASS** |
| `RLS-BUY-07` | `POL-PROD-02` | `anon` | `INSERT/UPDATE/DELETE products` | Rejected (No write privileges / policies) | All three operations threw `permission denied` | **PASS** |

### 3.4 Order Privacy & Token-Gated Receipts (India DPDP Act 2023)
| Test ID | Policy Tested | Role Context | Action | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|---|
| `RLS-ORD-01` | `POL-ORD-01` | `anon` (No token) | `SELECT FROM orders` | 0 rows returned (Open enumeration blocked) | 0 rows returned | **PASS** |
| `RLS-ORD-02` | `POL-ORD-01` | `anon` (Guessed token) | `SELECT FROM orders` with fake UUID | 0 rows returned | 0 rows returned | **PASS** |
| `RLS-ORD-03` | `POL-ORD-02` | `anon` (Token A) | `SELECT FROM orders` with Order A token | Only Order A1 returned; Order B1 completely hidden | 1 row returned (Order A1), Order B1 hidden | **PASS** |
| `RLS-ORD-04` | `POL-ITEM-01` | `anon` (No token) | `SELECT FROM order_items` | 0 rows returned | 0 rows returned | **PASS** |
| `RLS-ORD-05` | `POL-ITEM-01` | `anon` (Token A) | `SELECT FROM order_items` with Order A token | Only OrderItem A1 returned | 1 row returned (OrderItem A1) | **PASS** |
| `RLS-ORD-06` | `POL-ORD-03` | `anon` | `INSERT INTO orders` via REST | Rejected (Direct REST INSERT blocked) | Threw: `permission denied for table orders` | **PASS** |
| `RLS-ORD-07` | `POL-ORD-04` | `anon` (Token A) | `UPDATE orders` even with valid token | Rejected (Direct REST UPDATE blocked) | Threw: `permission denied for table orders` | **PASS** |
| `RLS-ORD-08` | `POL-ORD-04` | `anon` (Token A) | `DELETE FROM orders` even with valid token | Rejected (Direct REST DELETE blocked) | Threw: `permission denied for table orders` | **PASS** |
| `RLS-ORD-09` | `POL-ITEM-03` | `anon` (Token A) | `INSERT/UPDATE/DELETE order_items` | Rejected (Financial line items immutable) | All three operations threw `permission denied` | **PASS** |

### 3.5 Seller Order Management & Defense-in-Depth
| Test ID | Policy / Trigger | Role Context | Action | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|---|
| `RLS-MGT-01` | Role Privilege | `authenticated` (Seller A) | `INSERT INTO orders` via REST | Rejected (Direct REST INSERT blocked; RPC only) | Threw: `permission denied for table orders` | **PASS** |
| `RLS-MGT-02` | Role Privilege | `authenticated` (Seller A) | `INSERT/UPDATE/DELETE order_items` | Rejected (Direct mutation blocked; line items immutable) | All three operations threw `permission denied` | **PASS** |
| `RLS-MGT-03` | `orders_seller_update` | `authenticated` (Seller A) | `UPDATE orders (Order A1)` tracking number | Updated successfully | 1 row updated (`tracking_number = 'DELHIVERY12345'`) | **PASS** |
| `RLS-MGT-04` | `orders_seller_update` | `authenticated` (Seller A) | `UPDATE orders SET drop_id = Drop B1` | Rejected by WITH CHECK policy (Cross-drop transfer blocked) | Threw: `violates row-level security policy` | **PASS** |
| `RLS-MGT-05` | `trg_orders_no_delete_finalized` | `authenticated` (Seller A) | `DELETE FROM orders WHERE status = 'paid'` | Denied by finalized protection trigger | Threw: `Cannot delete finalized order ... with status "paid"` | **PASS** |
| `RLS-MGT-06` | `orders_seller_delete` | `authenticated` (Seller A) | `DELETE FROM orders WHERE status = 'pending'` | Allowed for unfinalized seller order | 1 row deleted | **PASS** |

---

## 4. Defect Findings & Remediations During Test Execution

1. **Initial Issue:** UUID parsing failed for product IDs containing 'p' (`p1000000-...`).  
   **Remediation:** Corrected fixture IDs in `buyer-web/src/test/rls.test.ts` to strictly valid hexadecimal UUIDv4 values (`ca000000-...`, `cb000000-...`).
2. **Initial Issue:** Product insertion failed `products_code_check` regex constraint (`^#[A-Z0-9]{1,6}$`).  
   **Remediation:** Corrected product flash codes in fixtures to properly include the mandatory `#` prefix (`'#01'`, `'#02'`, `'#03'`, `'#04'`, `'#91'`, `'#99'`).
3. **Initial Issue:** Order insertion failed `orders_order_code_check` regex constraint (`^LD-[A-Z0-9]{6}$`).  
   **Remediation:** Adjusted order codes to exactly 6 uppercase alphanumeric characters after prefix (`'LD-A00001'`, `'LD-B00001'`).
4. **Initial Issue:** Order insertion failed `orders_status_check` (`pending`, `paid`, `shipped`, `cancelled`).  
   **Remediation:** Adjusted test status from non-existent `pending_payment` to valid canonical state `pending`.

---

## 5. Verification Commands Output Summary

- **Standalone Script:** `node scripts/verify-schema.mjs` -> **Exit Code 0** (All 8 migrations, 5 tables, 8 indexes, 9 paisa columns, 5 triggers, 5 tables with RLS enabled, 13 policies verified).
- **Vitest Suite:** `npm --prefix buyer-web test` -> **Exit Code 0** (3 test files, 69 tests passed).
- **TypeScript Check:** `npm --prefix buyer-web run typecheck` -> **Exit Code 0** (Zero errors).
- **ESLint Check:** `npm --prefix buyer-web run lint` -> **Exit Code 0** (Zero warnings/errors).

---

## 6. Final Status

**TASK-1.2 Test Verdict:** **PASS**  
All RLS security boundaries, seller isolation invariants, buyer catalog boundaries, order privacy controls, and defense-in-depth privilege denials are verified and enforced.
