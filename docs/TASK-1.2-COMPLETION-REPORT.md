# TASK-1.2 Completion Report
# Row-Level Security & Database Access Control

## Status
PASS

---

## RLS Enabled
PostgreSQL catalog metadata inspection (`pg_tables.rowsecurity = true` and `pg_class.relrowsecurity = true`) verified across all 5 core tables:
- `profiles`: `rowsecurity = true`
- `drops`: `rowsecurity = true`
- `products`: `rowsecurity = true`
- `orders`: `rowsecurity = true`
- `order_items`: `rowsecurity = true`

Default table privileges granted to `PUBLIC` have been explicitly revoked via `REVOKE ALL ON ... FROM PUBLIC;`.

---

## Policy Matrix

A total of 13 hardened RLS policies and least-privilege role permissions have been implemented in `supabase/migrations/008_enable_rls_and_policies.sql` and verified:

| Table | Policy Name | Role Target | Command | Predicate / Action Summary |
|---|---|---|---|---|
| `profiles` | `profiles_public_read` | `anon, authenticated` | `SELECT` | `USING (true)` — Public boutique store branding, UPI ID, phone |
| `profiles` | `profiles_seller_insert` | `authenticated` | `INSERT` | `WITH CHECK (id = auth.uid())` |
| `profiles` | `profiles_seller_update` | `authenticated` | `UPDATE` | `USING (id = auth.uid()) WITH CHECK (id = auth.uid())` |
| `drops` | `drops_public_read_live` | `anon` | `SELECT` | `USING (status = 'live')` — Draft/closed drops hidden |
| `drops` | `drops_seller_manage` | `authenticated` | `ALL` | `USING / WITH CHECK (seller_id = auth.uid())` |
| `products` | `products_public_read_live` | `anon` | `SELECT` | `USING (EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.status = 'live'))` |
| `products` | `products_seller_manage` | `authenticated` | `ALL` | `USING / WITH CHECK (EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.seller_id = auth.uid()))` |
| `orders` | `orders_buyer_read_with_token` | `anon` | `SELECT` | `USING (order_token::text = (CASE WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> '' THEN current_setting('request.headers', true)::json->>'x-order-token' ELSE NULL END))` |
| `orders` | `orders_seller_select` | `authenticated` | `SELECT` | `USING (EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid()))` |
| `orders` | `orders_seller_update` | `authenticated` | `UPDATE` | `USING / WITH CHECK (EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid()))` |
| `orders` | `orders_seller_delete` | `authenticated` | `DELETE` | `USING (EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid()))` (guarded by `trg_orders_no_delete_finalized`) |
| `order_items` | `order_items_buyer_read_with_token` | `anon` | `SELECT` | `USING (EXISTS (SELECT 1 FROM orders WHERE orders.id = order_items.order_id AND orders.order_token::text = ...))` |
| `order_items` | `order_items_seller_select` | `authenticated` | `SELECT` | `USING (EXISTS (SELECT 1 FROM orders JOIN drops ON drops.id = orders.drop_id WHERE orders.id = order_items.order_id AND drops.seller_id = auth.uid()))` |

---

## Anonymous Buyer Security
- **Catalog Browsing:** Anonymous buyers can view ONLY live drops (`drops.status = 'live'`) and products linked to live drops.
- **Draft/Closed Inventory Protection:** Unlaunched drops and closed drops are 100% invisible to anonymous visitors.
- **Write Prohibitions:** Anonymous buyers are strictly denied all direct `INSERT`, `UPDATE`, and `DELETE` actions on `profiles`, `drops`, and `products`.
- **Public Profile Surface:** Profiles expose only public business identity (store name, WhatsApp support phone, UPI ID, QR URL).

---

## Seller Isolation
The central multi-tenancy invariant (**SELLER A MUST NEVER ACCESS SELLER B'S PRIVATE DATA**) is strictly enforced at the database level:
- Seller A querying `drops` receives only drops where `seller_id = auth.uid()`. Seller B's draft and closed drops are completely invisible.
- Seller A cannot `UPDATE` or `DELETE` Seller B's drops (0 rows affected).
- Seller A cannot `INSERT`, `UPDATE`, or `DELETE` products belonging to Seller B's drops (`WITH CHECK` violation / 0 rows affected).
- Seller A cannot `UPDATE` Seller B's boutique profile (0 rows affected).
- Seller A querying `orders` or `order_items` receives only orders belonging to drops owned by Seller A.
- Seller A cannot transfer an order to a drop owned by Seller B (`WITH CHECK` policy violation).

---

## Order Privacy
In full compliance with ADR-003 and the India Digital Personal Data Protection (DPDP) Act 2023:
- **No Open Enumeration:** An unauthenticated visitor running `SELECT * FROM orders` or `SELECT * FROM order_items` receives **ZERO rows**.
- **No ID Guessing Vulnerability:** Querying orders with an invalid or guessed token returns **ZERO rows**.
- **Token-Gated Receipt Access:** Customers view order details and line items exclusively by supplying the cryptographically unguessable UUIDv4 `order_token` via the `x-order-token` HTTP header.
- **Direct REST Mutation Blocked:** Direct `INSERT`, `UPDATE`, and `DELETE` on `orders` and `order_items` is completely blocked for anonymous visitors.
- **Order Placement Architecture:** Order creation and inventory hold acquisition will occur exclusively via the future `create_order_with_reservation` atomic RPC (`SECURITY DEFINER`), preventing client-side price tampering or unheld order insertion.

---

## Negative Tests
Negative assertions verified across all tables and roles:
1. `anon` attempting `INSERT INTO profiles` -> **DENIED** (`permission denied for table profiles`)
2. `anon` attempting `UPDATE profiles` -> **DENIED** (`permission denied for table profiles`)
3. `anon` attempting `INSERT/UPDATE/DELETE drops` -> **DENIED** (`permission denied for table drops`)
4. `anon` attempting `INSERT/UPDATE/DELETE products` -> **DENIED** (`permission denied for table products`)
5. `anon` attempting `INSERT INTO orders` -> **DENIED** (`permission denied for table orders`)
6. `anon` attempting `UPDATE orders` -> **DENIED** (`permission denied for table orders`)
7. `anon` attempting `DELETE FROM orders` -> **DENIED** (`permission denied for table orders`)
8. `anon` attempting `INSERT/UPDATE/DELETE order_items` -> **DENIED** (`permission denied for table order_items`)
9. `authenticated` Seller A attempting `INSERT INTO products` for Seller B drop -> **DENIED** (`violates row-level security policy`)
10. `authenticated` Seller A attempting `UPDATE orders` to transfer to Seller B drop -> **DENIED** (`violates row-level security policy`)
11. `authenticated` Seller A attempting direct REST `INSERT INTO orders` -> **DENIED** (`permission denied for table orders`)
12. `authenticated` Seller A attempting direct REST `INSERT/UPDATE/DELETE order_items` -> **DENIED** (`permission denied for table order_items`)
13. `authenticated` Seller A attempting `DELETE FROM orders` on a finalized (`paid` / `shipped`) order -> **DENIED** (`Cannot delete finalized order ... with status "paid"`)

---

## Test Results
1. **Schema & RLS Verification (`node scripts/verify-schema.mjs`):**
   - 8 Migrations applied sequentially: **PASS**
   - 5 Tables verified: **PASS**
   - 8 Indexes verified: **PASS**
   - 9 Paisa columns verified: **PASS**
   - 5 Triggers verified: **PASS**
   - 5 Tables verified with `rowsecurity = true`: **PASS**
   - 13 Policies verified in `pg_policies`: **PASS**
2. **Vitest Unit & Security Suite (`npm --prefix buyer-web test`):**
   - `src/test/smoke.test.tsx`: 1 test passed
   - `src/test/schema.test.ts`: 33 tests passed
   - `src/test/rls.test.ts`: 35 tests passed
   - Total: **69 tests passed, 0 failed**
3. **TypeScript Typecheck (`npm --prefix buyer-web run typecheck`):** **0 errors**
4. **ESLint Code Quality (`npm --prefix buyer-web run lint`):** **0 warnings/errors**

---

## Findings
1. **Direct REST Insertion Threat on Orders:** Permitting direct REST `INSERT` on `orders` or `order_items` creates severe security risks (price tampering, inventory hold bypassing, artificial order generation). By revoking `INSERT` grants on `orders` and `order_items` from both `anon` and `authenticated`, and defining no permissive `INSERT` RLS policies, order creation is completely locked down until the future atomic `create_order_with_reservation` RPC (`SECURITY DEFINER`) is built in TASK-1.3.
2. **PostgreSQL RLS Bypass Caveat for Table Owners:** In PostgreSQL, table owners (`postgres` role) bypass RLS by default. In production Supabase, client queries are executed by unprivileged roles (`anon` and `authenticated`). The test suite successfully simulates this by switching PostgreSQL session roles (`SET ROLE anon;`, `SET ROLE authenticated;`), ensuring 100% test validity and parity with Supabase PostgREST.

---

## Remaining Risks
- **Order Placement Blocked Until RPC Implementation:** Because direct REST `INSERT` on `orders` and `order_items` is deliberately denied for security, orders cannot be created until the `create_order_with_reservation` RPC is implemented in TASK-1.3. This is an intentional architectural boundary, fully documented in ADR-003 and the RLS Access Matrix.
- **Session Header Delivery:** In production, PostgREST forwards the `x-order-token` header to PostgreSQL's `request.headers` GUC. Frontend clients must ensure the header is transmitted on receipt queries.

---

## Readiness for TASK-1.3

READY FOR TASK-1.3
