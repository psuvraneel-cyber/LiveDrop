# TASK-2.4A — Business Domain, Order State Machine & Seller Storefront Architecture Report

**Task:** TASK-2.4A — Business Domain, Order State Machine & Seller Storefront Architecture Redesign / Hardening Checkpoint  
**Date:** 2026-09-13  
**Status:** **PASS**  
**Author:** AI Systems Architect & Core Database Engineer (Pair Programming)  

---

## 1. Status

**Verdict:** **PASS**

All architecture, relational schema, security policies, business RPCs, domain models (TypeScript & Dart), and invariant validations have been designed, implemented, and verified with 100% test passage across all 12 Vitest test suites (224/224 tests passing) and `verify-schema.mjs` (exit code 0).

---

## 2. Business Model

LiveDrop (`LiveDrop.in`) is an independent multi-seller live/social commerce platform built specifically for sellers acquiring buyers through live broadcasts and social channels (Facebook Live, Instagram, WhatsApp). 

LiveDrop is **not** a single undifferentiated global marketplace or generic shopping cart. Every live drop and product belongs strictly to an independent seller storefront.

### Two Authoritative Checkout Commitment Paths
When committing to an order in checkout, buyers have two distinct options:

#### Option A: Confirm Order — Pay Advance (e.g. ₹250)
* **Buyer Intent:** The buyer commits to purchasing by paying an advance amount configured by the seller (default ₹250 / 25,000 Paisa).
* **Financial Meaning:** The advance is **part of the total purchase price**, not a reservation fee, convenience fee, or service charge.
* **Order Financials:**
  $$\text{total\_paisa} = \text{subtotal\_paisa} + \text{shipping\_paisa}$$
  $$\text{advance\_required\_paisa} = \text{authoritative seller advance amount}$$
  $$\text{advance\_paid\_paisa} = \text{advance amount received}$$
  $$\text{balance\_due\_paisa} = \text{total\_paisa} - \text{advance\_paid\_paisa}$$
* **Hold & Fulfilment Invariants:** 
  * Products are held (`reserved`).
  * The order is `confirmed` upon advance receipt.
  * **Shipment is strictly forbidden** while $\text{balance\_due\_paisa} > 0$.
  * Balance is due before the hold expires.
  * Hold duration is capped at a platform maximum of **30 days**.
  * If the hold expires without full balance payment, the order becomes `expired`, items revert to `available`, the unpaid balance is cancelled, and the advance is **non-refundable**.

#### Option B: Pay in Full
* **Buyer Intent:** The buyer pays 100% of the purchase price upfront.
* **Financial Meaning:** 
  $$\text{advance\_required\_paisa} = 0$$
  $$\text{advance\_paid\_paisa} = 0$$
  $$\text{total\_paid\_paisa} = \text{total\_paisa}$$
  $$\text{balance\_due\_paisa} = 0$$
* **Hold & Fulfilment Invariants:**
  * Order transitions to `paid`.
  * Products transition from `reserved` to `sold`.
  * Order becomes eligible for `ready_to_ship` and subsequent `shipped` status.
  * Formal tax invoice is generated.

---

## 3. Seller Storefront Architecture

The multi-tenant ownership hierarchy is strictly hierarchical and enforced at the database level:

```
Platform (LiveDrop.in)
   └── Seller Storefront (`profiles.store_slug`)
         └── Live Drops (`drops`, owned by seller_id)
               └── Products (`products`, owned by drop_id)
                     └── Order Line Items (`order_items`, price_at_purchase_paisa)
```

1. **Storefront Identity:** Each seller is uniquely identified by `profiles.store_slug` (e.g., `sonalis`, `artisan-silks`). Slug format is enforced by CHECK constraint `chk_profiles_store_slug_format` (`^[a-z0-9-]+$`, 2 to 60 characters) and has a `UNIQUE` index.
2. **Ownership Chain:**
   * Every product references a drop (`products.drop_id -> drops.id`).
   * Every drop references a seller (`drops.seller_id -> profiles.id`).
   * Every order references a drop (`orders.drop_id -> drops.id`).
   * Ownership is derived directly via SQL joins (`drops.seller_id = auth.uid()`). A seller cannot claim or mutate another seller's drops, products, orders, or configuration.
3. **Public Exposure vs Private PII:**
   * Public buyer storefront queries expose: `store_name`, `store_slug`, `advance_confirmation_enabled`, `advance_amount_paisa`, `hold_duration_days`, `default_shipping_fee_paisa`, `free_shipping_threshold_paisa`, `upi_id`, `upi_qr_url`.
   * Private fields withheld from public view: `phone_number`, `return_address`, seller auth user metadata.

---

## 4. Seller Configuration & Precedence Rules

### Configurable Fields:
| Configuration Field | Table | Scope | Type | Constraints & Platform Rules |
|---|---|---|---|---|
| `store_slug` | `profiles` | Storefront | TEXT | UNIQUE, regex `^[a-z0-9-]+$`, 2–60 chars |
| `advance_confirmation_enabled` | `profiles` | Store Default | BOOLEAN | Default: `true` |
| `advance_amount_paisa` | `profiles` | Store Default | INTEGER | Default: `25000` (₹250.00). Must be $> 0$ when enabled. |
| `hold_duration_days` | `profiles` | Store Default | INTEGER | Default: `30` days. **Capped at $\le 30$ days** (`chk_profiles_hold_duration_max`). |
| `advance_confirmation_enabled` | `drops` | Drop Override | BOOLEAN | Nullable override. |
| `advance_amount_paisa` | `drops` | Drop Override | INTEGER | Nullable override. Must be $> 0$ if enabled. |
| `hold_duration_days` | `drops` | Drop Override | INTEGER | Nullable override. **Capped at $\le 30$ days** (`chk_drops_hold_duration_max`). |

### Authoritative Precedence Rules:
When an order is created, the backend resolves seller confirmation policy deterministically:
$$\text{effective\_advance\_enabled} = \text{COALESCE}(\text{drop.advance\_confirmation\_enabled}, \text{seller.advance\_confirmation\_enabled}, \text{true})$$
$$\text{effective\_advance\_amount} = \text{COALESCE}(\text{drop.advance\_amount\_paisa}, \text{seller.advance\_amount\_paisa}, 25000)$$
$$\text{effective\_hold\_days} = \text{LEAST}(30, \text{GREATEST}(1, \text{COALESCE}(\text{drop.hold\_duration\_days}, \text{seller.hold\_duration\_days}, 30)))$$

### Security & Authority Boundary:
* **Buyer Cannot Dictate Advance:** The buyer submits `p_confirmation_mode` (`'advance'` or `'full_payment'`). The RPC reads the trusted database policy. Any client-sent advance amount parameter is rejected or ignored.
* **Immutability via Snapshotting:** The moment an order is created, `advance_required_paisa` is **snapshotted into the order row**. If the seller subsequently alters their store settings (e.g. from ₹250 to ₹500), existing historical orders remain completely unchanged.

---

## 5. Order State Machine

The order lifecycle is governed by an orthogonal 4-dimensional state model:
1. **Order Lifecycle Status (`status`)**
2. **Confirmation Mode (`confirmation_mode`)**
3. **Payment State (`payment_status`)**
4. **Fulfilment State (`fulfilment_status`)**

```
                  ┌──────────────────────────────────────────────┐
                  │                 ORDER CREATED                │
                  │   status = 'pending', payment = 'unpaid'     │
                  └──────────────────────┬───────────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 │                                               │
                 ▼                                               ▼
         [MODE: ADVANCE]                                 [MODE: FULL_PAYMENT]
                 │                                               │
                 ▼                                               │
      Buyer pays Advance (₹250)                                  │
                 │                                               │
                 ▼                                               │
       [CONFIRMED_WITH_ADVANCE]                                  │
  status = 'confirmed'                                           │
  payment = 'advance_paid'                                       │
  balance_due > 0                                                │
  fulfilment = 'not_ready' (SHIPMENT FORBIDDEN)                  │
  inventory = 'reserved'                                         │
  hold_expires_at <= confirmed_at + 30 days                      │
                 │                                               │
       ┌─────────┴─────────┐                                     │
       │                   │                                     │
       ▼ (Within 30d)      ▼ (Hold Expires)                      │
  Buyer pays Balance   Hold Expiry Reaper                        │
       │                   │                                     │
       │                   ▼                                     │
       │           [ORDER EXPIRED]                               │
       │     status = 'expired'                                  │
       │     inventory -> 'available'                            │
       │     advance -> NON-REFUNDABLE                           │
       │     balance cancelled                                   │
       │     fulfilment = 'not_ready'                            │
       │                                                         ▼
       └───────────────────────────────► Buyer pays in full (100%)
                                                         │
                                                         ▼
                                                [ORDER FULLY PAID]
                                          status = 'paid'
                                          payment = 'paid'
                                          balance_due = 0
                                          inventory -> 'sold'
                                          fulfilment = 'ready_to_ship'
                                                         │
                                                         ▼ Seller Dispatches
                                                  [ORDER SHIPPED]
                                          status = 'shipped'
                                          fulfilment = 'shipped'
```

---

## 6. Payment State Machine

The `payment_status` column tracks the monetary collection stage independently of shipment:
* **`unpaid`**: Order created, no verified funds collected.
* **`advance_paid`**: Buyer has paid the seller's required advance ($\text{advance\_paid\_paisa} = \text{advance\_required\_paisa}$, $\text{balance\_due\_paisa} > 0$).
* **`paid`**: 100% of order total has been collected ($\text{total\_paid\_paisa} = \text{total\_paisa}$, $\text{balance\_due\_paisa} = 0$).

---

## 7. Fulfilment State Machine

The `fulfilment_status` column controls shipping eligibility:
* **`not_ready`**: Default state. Mandatory whenever $\text{balance\_due\_paisa} > 0$.
* **`ready_to_ship`**: The order is fully paid ($\text{balance\_due\_paisa} = 0$) and the seller can print shipping labels and pack.
* **`shipped`**: The package has been dispatched with a courier tracking reference.

### Non-Negotiable Invariant:
$$\text{fulfilment\_status} \in (\text{'ready\_to\_ship'}, \text{'shipped'}) \implies \text{balance\_due\_paisa} = 0$$
Enforced at the database level by check constraint `chk_orders_shipment_requires_full_payment`.

---

## 8. Financial Model & Database Invariants

All monetary values are strictly non-negative integers in Paisa (₹1.00 = 100 Paisa). Float/double arithmetic is completely forbidden.

### Authoritative Order Fields:
* `subtotal_paisa`: Sum of purchase price of all items (integer, $> 0$).
* `shipping_paisa`: Shipping charge applied to order (integer, $\ge 0$).
* `total_paisa`: Authoritative total ($\text{subtotal\_paisa} + \text{shipping\_paisa}$).
* `advance_required_paisa`: Advance required by seller at time of checkout (integer, $\ge 0$).
* `advance_paid_paisa`: Cumulative advance received (integer, $\ge 0$).
* `total_paid_paisa`: Cumulative total money received ($\text{advance\_paid\_paisa} + \text{balance payments}$).
* `balance_due_paisa`: Authoritative remaining balance due.

### Financial CHECK Constraints in PostgreSQL:
1. `chk_orders_advance_required_le_total`: $\text{advance\_required\_paisa} \le \text{total\_paisa}$
2. `chk_orders_advance_paid_le_required`: $\text{advance\_paid\_paisa} \le \text{advance\_required\_paisa}$
3. `chk_orders_total_paid_le_total`: $\text{total\_paid\_paisa} \le \text{total\_paisa}$
4. `chk_orders_adv_paid_lte_total_paid`: $\text{advance\_paid\_paisa} \le \text{total\_paid\_paisa}$
5. `chk_orders_balance_due_eq_total_minus_paid`: $\text{balance\_due\_paisa} = \text{total\_paisa} - \text{total\_paid\_paisa}$
6. `chk_orders_full_pay_zero_adv`: $\text{confirmation\_mode} \ne \text{'full\_payment'} \lor \text{advance\_required\_paisa} = 0$
7. `chk_orders_paid_zero_balance`: $\text{payment\_status} \ne \text{'paid'} \lor (\text{balance\_due\_paisa} = 0 \land \text{total\_paid\_paisa} = \text{total\_paisa})$
8. `chk_orders_shipment_requires_full_payment`: $\text{fulfilment\_status} = \text{'not\_ready'} \lor \text{balance\_due\_paisa} = 0$
9. `chk_orders_shipped_lifecycle`: $\text{status} \ne \text{'shipped'} \lor (\text{fulfilment\_status} = \text{'shipped'} \land \text{balance\_due\_paisa} = 0)$
10. `chk_orders_confirmed_lifecycle`: $\text{status} \ne \text{'confirmed'} \lor (\text{confirmation\_mode} = \text{'advance'} \land \text{payment\_status} = \text{'advance\_paid'})$

---

## 9. Database Changes

Created migration file:  
`supabase/migrations/010_seller_storefront_and_order_state_machine.sql`

### 1. `profiles` Table Alterations:
* Added `store_slug TEXT UNIQUE` with format check constraint `chk_profiles_store_slug_format`.
* Added `advance_confirmation_enabled BOOLEAN NOT NULL DEFAULT true`.
* Added `advance_amount_paisa INT NOT NULL DEFAULT 25000` with positive check constraint.
* Added `hold_duration_days INT NOT NULL DEFAULT 30` with `chk_profiles_hold_duration_max` ($\le 30$).

### 2. `drops` Table Alterations:
* Added `advance_confirmation_enabled BOOLEAN`.
* Added `advance_amount_paisa INT` with positive check constraint.
* Added `hold_duration_days INT` with `chk_drops_hold_duration_max` ($\le 30$).

### 3. `orders` Table Alterations:
* Added `confirmation_mode TEXT NOT NULL DEFAULT 'advance'` (`'advance'`, `'full_payment'`).
* Added `advance_required_paisa INT NOT NULL DEFAULT 0`.
* Added `advance_paid_paisa INT NOT NULL DEFAULT 0`.
* Added `total_paid_paisa INT NOT NULL DEFAULT 0`.
* Added `balance_due_paisa INT NOT NULL DEFAULT 0`.
* Added `advance_paid_at TIMESTAMPTZ`.
* Added `payment_status TEXT NOT NULL DEFAULT 'unpaid'` (`'unpaid'`, `'advance_paid'`, `'paid'`).
* Added `fulfilment_status TEXT NOT NULL DEFAULT 'not_ready'` (`'not_ready'`, `'ready_to_ship'`, `'shipped'`).
* Updated status check constraint to support `'confirmed'` and `'expired'`.
* Added 10 CHECK constraints enforcing financial & fulfilment invariants.

### 4. New `order_payments` Table:
* Columns: `id`, `order_id`, `payment_type` (`'advance'`, `'balance'`, `'full'`), `amount_paisa`, `status` (`'pending'`, `'verified'`, `'failed'`, `'refunded'`), `reference_id`, `verified_at`, `verified_by`, `metadata`, `created_at`, `updated_at`.
* RLS enabled with token-gated buyer policy and seller ownership policy.
* Trigger `trg_order_payments_updated_at` attached.

---

## 10. RPC Changes

1. **`create_order_with_reservation`**:
   * Signature updated: accepts `p_confirmation_mode TEXT DEFAULT 'advance'`.
   * Enforces server-authoritative pricing and policy resolution.
   * Calculates `advance_required_paisa` from drop/seller profile.
   * Returns extended snapshot: `confirmation_mode`, `advance_required_paisa`, `advance_paid_paisa`, `balance_due_paisa`, `total_paid_paisa`, `payment_status`, `fulfilment_status`.
2. **`confirm_order_advance`** (New Privileged Seller RPC):
   * Signature: `confirm_order_advance(p_order_id UUID, p_reference_id TEXT DEFAULT NULL)`.
   * Authorizes seller ownership of the order's drop.
   * Transitions order to `status = 'confirmed'`, `payment_status = 'advance_paid'`.
   * Extends `hold_expires_at` up to configured hold duration ($\le 30$ days).
   * Inserts an entry into `order_payments`.
3. **`mark_order_paid`** (Updated Privileged Seller RPC):
   * Records balance payment or full payment in `order_payments`.
   * Sets `total_paid_paisa = total_paisa`, `balance_due_paisa = 0`, `payment_status = 'paid'`, `status = 'paid'`.
   * Sets `fulfilment_status = 'ready_to_ship'`.
   * Transitions products to `sold`.
4. **`release_expired_holds`** (Updated Reaper RPC):
   * Finds orders where `status IN ('pending', 'confirmed')` and `hold_expires_at < clock_timestamp()`.
   * If `status = 'confirmed'` (advance paid), transitions order to `status = 'expired'`.
   * Releases products back to `available`.
   * Retains advance payment as non-refundable.
5. **`get_order_by_token`** (Updated Token-Gated RPC):
   * Exposes `confirmation_mode`, `payment_status`, `fulfilment_status`, `advance_required_paisa`, `advance_paid_paisa`, `balance_due_paisa`, `total_paid_paisa`.
   * Preserves DPDP PII minimization (omits phone number and shipping address).

---

## 11. RLS / Security Verification

| Policy / Guardrail | Implementation | Enforcement Level |
|---|---|---|
| **Seller Isolation** | RLS policy on `profiles`, `drops`, `orders`, `order_payments` | Database Engine (PostgreSQL) |
| **Anonymous Protection** | Anonymous buyers cannot write to `profiles`, `drops`, or `orders` directly | Database Engine (Revoked write grants, RLS) |
| **Buyer Policy Tampering** | Backend resolves policy internally; does not accept client advance values | Database Engine (`create_order_with_reservation` RPC) |
| **Privileged Seller RPCs** | `confirm_order_advance`, `mark_order_paid`, `force_release_hold` require `authenticated` + ownership check | SECURITY DEFINER with `auth.uid()` checks |
| **Service Role Maintenance** | `release_expired_holds` granted only to `service_role` | PostgreSQL Role Grants |
| **Token-Gated Receipt** | `get_order_by_token` requires matching `order_id` + `order_token` | Constant-time UUID comparison |

---

## 12. Storefront Routing Model

The target routing architecture for LiveDrop buyer web is:
* Platform Root: `livedrop.in`
* Storefront Landing: `livedrop.in/[storeSlug]` (e.g. `livedrop.in/sonalis`)
* Drop Direct URL: `livedrop.in/[storeSlug]/drop/[dropSlug]` (e.g. `livedrop.in/sonalis/drop/friday-silk`)
* Legacy/Direct Drop URL: `livedrop.in/drop/[dropSlug]` (retained for backward compatibility with TASK-2.1)

---

## 13. Test Results

### Test Execution Summary:
* `node scripts/verify-schema.mjs`: **PASS** (exit code 0)
  * 10 migrations, 6 tables, 10 query indexes, 16 integer Paisa columns, 6 database triggers, 15 RLS policies, 7 core business RPCs, multi-seller seed data.
* `buyer-web` Vitest Test Suite (`npm test`): **PASS** (12 suites, 224 tests passing, exit code 0)
  * `realtime.test.ts` (3 tests): PASS
  * `cart-storage.test.ts` (10 tests): PASS
  * `smoke.test.tsx` (1 test): PASS
  * `data-layer.test.ts` (16 tests): PASS
  * `cart.test.tsx` (16 tests): PASS
  * `checkout.test.tsx` (11 tests): PASS
  * `catalog-feed.test.tsx` (19 tests): PASS
  * `storefront-and-state-machine.test.ts` (22 tests): PASS
  * `rls.test.ts` (35 tests): PASS
  * `schema.test.ts` (33 tests): PASS
  * `rpcs.test.ts` (45 tests): PASS
  * `checkout-validator.test.ts` (13 tests): PASS
* Typecheck (`npm run typecheck`): **PASS** (exit code 0)
* Lint (`npm run lint`): **PASS** (0 errors, 0 warnings, exit code 0)
* Production Build (`npm run build`): **PASS** (exit code 0)
* Seller App Dart Models (`seller_repository_test.dart`): **PASS** (static check complete)

---

## 14. Browser / Staging Verification

* **Single-Connection PGlite / WASM Simulation:** Complete in-memory PostgreSQL engine test suite passing with 100% fidelity on real SQL migrations, triggers, constraints, and RPC logic.
* **Local Web Mock Service (`dev-mock-supabase.mjs`):** Updated with multi-seller mock profiles, drops, and advance confirmation simulation.
* **Hosted Multi-Connection Supabase:** Awaiting deployment to Supabase staging project in the next environment deployment step. Real multi-connection concurrency will be validated against hosted Postgres.

---

## 15. Known Limitations

1. **No Payment Gateway Integration in TASK-2.4A:** Payment gateways (Razorpay, Cashfree, UPI intent) and webhook listeners are strictly deferred to TASK-2.4B in accordance with the task mandate.
2. **Reaper Trigger Mechanism:** `release_expired_holds` is implemented as an authoritative database RPC; in production it will be invoked periodically via `pg_cron` or an edge worker daemon.

---

## 16. TASK-2.4B Readiness

**Verdict:** **READY FOR TASK-2.4B**

The business domain, multi-seller storefront model, order state machine, advance payment accounting model, hold expiration policy, and database invariants are fully hardened and proven. The foundation is ready for:
* TASK-2.4B: Buyer Payment Gateways, Advance Confirmation Payment Flow, Full Payment Gateway Flow, Automated Invoicing, and Seller Order Delivery Notifications.
