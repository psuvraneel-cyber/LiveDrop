# LiveDrop — TASK-1.2 RLS Security & Access Control Matrix
# Final Security Policy Specifications

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Task Authority:** Phase 1 / TASK-1.2  
**Parent Access Matrix:** [`docs/RLS-ACCESS-MATRIX.md`](file:///c:/LiveDrop/docs/RLS-ACCESS-MATRIX.md)  
**Governing Architecture:** [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)  

---

## 1. Table-by-Table Policy Inventory

### 1.1 Table: `profiles`
* **RLS Enabled:** `ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;`

| Policy Name | Target Role | Command | `USING` Expression | `WITH CHECK` Expression | Notes |
|---|---|---|---|---|---|
| `profiles_public_read` | `public` (anon & authenticated) | `SELECT` | `true` | N/A | Public can read store branding, business WhatsApp, and UPI ID for payments. |
| `profiles_seller_insert` | `authenticated` | `INSERT` | N/A | `auth.uid() = id` | Seller can insert only their own profile record. |
| `profiles_seller_update` | `authenticated` | `UPDATE` | `auth.uid() = id` | `auth.uid() = id` | Seller can update only their own profile. |

*No DELETE policy:* Profiles cannot be deleted via direct client call.

---

### 1.2 Table: `drops`
* **RLS Enabled:** `ALTER TABLE drops ENABLE ROW LEVEL SECURITY;`

| Policy Name | Target Role | Command | `USING` Expression | `WITH CHECK` Expression | Notes |
|---|---|---|---|---|---|
| `drops_public_read_live` | `anon` | `SELECT` | `status = 'live'` | N/A | Anonymous buyers can only see active live drops; draft and closed drops are completely hidden. |
| `drops_seller_manage` | `authenticated` | `ALL` | `seller_id = auth.uid()` | `seller_id = auth.uid()` | Seller can perform SELECT, INSERT, UPDATE, DELETE on their own drops across all states (`draft`, `live`, `closed`). |

---

### 1.3 Table: `products`
* **RLS Enabled:** `ALTER TABLE products ENABLE ROW LEVEL SECURITY;`

| Policy Name | Target Role | Command | `USING` Expression | `WITH CHECK` Expression | Notes |
|---|---|---|---|---|---|
| `products_public_read_live` | `anon` | `SELECT` | `EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.status = 'live')` | N/A | Anonymous buyers can read products belonging to active live drops. Products in draft/closed drops are hidden. |
| `products_seller_manage` | `authenticated` | `ALL` | `EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.seller_id = auth.uid())` | `EXISTS (SELECT 1 FROM drops WHERE drops.id = products.drop_id AND drops.seller_id = auth.uid())` | Seller can perform SELECT, INSERT, UPDATE, DELETE on products belonging to their drops. |

*Direct anonymous writes:* 100% blocked. Status updates occur strictly via `SECURITY DEFINER` RPCs.

---

### 1.4 Table: `orders`
* **RLS Enabled:** `ALTER TABLE orders ENABLE ROW LEVEL SECURITY;`

| Policy Name | Target Role | Command | `USING` Expression | `WITH CHECK` Expression | Notes |
|---|---|---|---|---|---|
| `orders_buyer_read_with_token` | `anon` | `SELECT` | `order_token::text = (CASE WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> '' THEN current_setting('request.headers', true)::json->>'x-order-token' ELSE NULL END)` | N/A | Unauthenticated buyer can read their order ONLY if they supply the exact secret `x-order-token` header. Open enumeration is completely blocked. |
| `orders_seller_select` | `authenticated` | `SELECT` | `EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid())` | N/A | Seller can view orders for their own drops. |
| `orders_seller_update` | `authenticated` | `UPDATE` | `EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid())` | `EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid())` | Seller can update orders (e.g. status, tracking details) for their own drops. |
| `orders_seller_delete` | `authenticated` | `DELETE` | `EXISTS (SELECT 1 FROM drops WHERE drops.id = orders.drop_id AND drops.seller_id = auth.uid())` | N/A | Seller can delete unfinalized orders for their own drops (finalized orders protected by trigger). |

*Direct REST INSERT:* 100% blocked for all roles (anon & authenticated). All order creation is delegated to the atomic `create_order_with_reservation` RPC.

---

### 1.5 Table: `order_items`
* **RLS Enabled:** `ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;`

| Policy Name | Target Role | Command | `USING` Expression | `WITH CHECK` Expression | Notes |
|---|---|---|---|---|---|
| `order_items_buyer_read_with_token` | `anon` | `SELECT` | `EXISTS (SELECT 1 FROM orders WHERE orders.id = order_items.order_id AND orders.order_token::text = (CASE WHEN current_setting('request.headers', true) IS NOT NULL AND current_setting('request.headers', true) <> '' THEN current_setting('request.headers', true)::json->>'x-order-token' ELSE NULL END))` | N/A | Buyer can read line items for their token-verified order. |
| `order_items_seller_select` | `authenticated` | `SELECT` | `EXISTS (SELECT 1 FROM orders JOIN drops ON drops.id = orders.drop_id WHERE orders.id = order_items.order_id AND drops.seller_id = auth.uid())` | N/A | Seller can view line items for orders under their drops. |

*Direct mutation (INSERT/UPDATE/DELETE):* 100% blocked for all roles (anon & authenticated). Line items are inserted exclusively by the atomic order creation RPC and are strictly immutable.

---

## 2. Policy Verification Matrix

| Policy Identifier | Table | Role | Target Command | Positive Assertion | Negative Assertion |
|---|---|---|---|---|---|
| `POL-PROF-01` | `profiles` | `anon` | `SELECT` | Public can view boutique details | Cannot view when table is unpopulated |
| `POL-PROF-02` | `profiles` | `anon` | `INSERT` | N/A | Anon INSERT rejected by RLS |
| `POL-PROF-03` | `profiles` | `anon` | `UPDATE` | N/A | Anon UPDATE rejected by RLS |
| `POL-PROF-04` | `profiles` | `authenticated` | `UPDATE` | Seller A can update Profile A | Seller A CANNOT update Profile B |
| `POL-DROP-01` | `drops` | `anon` | `SELECT` | Public can view live drops | Public CANNOT view draft or closed drops |
| `POL-DROP-02` | `drops` | `anon` | `INSERT` | N/A | Anon INSERT rejected by RLS |
| `POL-DROP-03` | `drops` | `authenticated` | `SELECT` | Seller A can view own draft/live/closed | Seller A CANNOT view Seller B's draft drops |
| `POL-DROP-04` | `drops` | `authenticated` | `UPDATE` | Seller A can update own drop | Seller A CANNOT update Seller B's drop |
| `POL-DROP-05` | `drops` | `authenticated` | `DELETE` | Seller A can delete own empty drop | Seller A CANNOT delete Seller B's drop |
| `POL-PROD-01` | `products` | `anon` | `SELECT` | Public can view items in live drops | Public CANNOT view items in draft drops |
| `POL-PROD-02` | `products` | `anon` | `UPDATE` | N/A | Anon cannot change status or price |
| `POL-PROD-03` | `products` | `authenticated` | `SELECT` | Seller A can view own drop products | Seller A CANNOT view Seller B's draft drop products |
| `POL-PROD-04` | `products` | `authenticated` | `INSERT` | Seller A can insert into own drop | Seller A CANNOT insert into Seller B's drop |
| `POL-PROD-05` | `products` | `authenticated` | `UPDATE` | Seller A can update own drop products | Seller A CANNOT update Seller B's products |
| `POL-ORD-01` | `orders` | `anon` | `SELECT` (No Token) | N/A | Anon query without token returns 0 rows |
| `POL-ORD-02` | `orders` | `anon` | `SELECT` (Valid Token) | Buyer can read order matching `x-order-token` | Buyer CANNOT read other orders with invalid token |
| `POL-ORD-03` | `orders` | `anon` | `INSERT` | N/A | Direct REST INSERT rejected by RLS |
| `POL-ORD-04` | `orders` | `anon` | `UPDATE` | N/A | Direct REST UPDATE rejected by RLS |
| `POL-ORD-05` | `orders` | `authenticated` | `SELECT` | Seller A can view orders for Drop A | Seller A CANNOT view orders for Drop B (Seller B) |
| `POL-ORD-06` | `orders` | `authenticated` | `UPDATE` | Seller A can update orders for Drop A | Seller A CANNOT update orders for Drop B (Seller B) |
| `POL-ITEM-01` | `order_items` | `anon` | `SELECT` | Buyer with token can read line items | Buyer without token cannot read line items |
| `POL-ITEM-02` | `order_items` | `authenticated` | `SELECT` | Seller A can read line items for Drop A | Seller A CANNOT read line items for Drop B (Seller B) |
| `POL-ITEM-03` | `order_items` | `anon` | `INSERT` | N/A | Direct line-item INSERT rejected by RLS |
