# 19 — Authoritative Validation & Business Rules: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Three-Tier Validation Architecture

To guarantee security, data integrity, and excellent user experience, all business rules are enforced across three distinct layers:
1. **Tier 1: Client-Side Convenience Validation:** Instant feedback on form inputs (preventing wasted network requests and bad UX).
2. **Tier 2: Server-Side Mandatory Validation (RPC / PostgREST):** Unbypassable business logic verification inside database functions and API endpoints.
3. **Tier 3: Database Constraints:** Hard relational guarantees (PostgreSQL `CHECK`, `NOT NULL`, `FOREIGN KEY`, `UNIQUE`).

> [!CRITICAL]
> Client-side validation is strictly an ergonomic convenience. The system **never** relies on client validation for security or data correctness.

---

## 2. Comprehensive Business Rules Catalog

### 2.1 Product & Flash-Code Invariants

| Rule ID | Domain Rule Description | Tier 1: Client UI | Tier 2: Server RPC | Tier 3: Database Constraint |
|---|---|---|---|---|
| **RULE-PRD-01** | Flash Code must start with `#` followed by 1–6 uppercase alphanumeric chars (e.g., `#A01`, `#12`). | Regex mask on keypad: `^#[A-Z0-9]{1,6}$` | Verified in ingestion endpoint | `CHECK (code ~ '^#[A-Z0-9]{1,6}$')` |
| **RULE-PRD-02** | Flash Code must be strictly unique within the same Drop. | Suggested code checks local drop list | Verified before insert | `UNIQUE(drop_id, code)` |
| **RULE-PRD-03** | Product Price must be a positive integer in Paisa (`> 0`). | Numeric keypad only; rejects `0` or negative | Verified in RPC | `CHECK (price_paisa > 0)` |
| **RULE-PRD-04** | Product Image must be a 1:1 square WebP format `< 250 KB`. | Client-side auto-crop & compression | Storage bucket MIME filter | Storage policy / CDN headers & `CHECK (char_length(image_url) BETWEEN 1 AND 2048)` |
| **RULE-PRD-05** | Product Status must strictly belong to permitted lifecycle set. | UI only permits valid state actions | Verified in state machine RPC | `CHECK (status IN ('available', 'reserved', 'sold'))` |
| **RULE-PRD-06** | A sold product cannot be deleted if referenced in an order. | UI hides delete for sold items | Verified before DELETE | `order_items.product_id ON DELETE RESTRICT` |

---

### 2.2 Drop Lifecycle Invariants

| Rule ID | Domain Rule Description | Tier 1: Client UI | Tier 2: Server RPC | Tier 3: Database Constraint |
|---|---|---|---|---|
| **RULE-DRP-01** | Drop Slug must be lowercase alphanumeric with hyphens, min 3, max 60 chars. | Auto-generated from title | Sanitized on API | `CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' AND char_length(slug) BETWEEN 3 AND 60)` |
| **RULE-DRP-02** | Drop Slug must be globally unique across all boutiques. | Pre-check on typing | Unique validation | `slug TEXT UNIQUE NOT NULL` |
| **RULE-DRP-03** | A seller may have at most **ONE** drop in `live` status at any time. | UI disables "Go Live" if another drop is active | RPC checks active drops for seller | Partial Unique Index: `idx_drops_one_live_per_seller ON drops(seller_id) WHERE status = 'live'` |
| **RULE-DRP-04** | A closed drop cannot be reopened to `live`. | UI hides "Reopen" button | Status transition check | RPC checks `old.status != 'closed'` |
| **RULE-DRP-05** | Closing a drop leaves existing active reservations intact until their 15-minute expiry. | UI shows "Closing drop" notice | Only stops new checkouts | Orders maintain independent expiry timestamps |

---

### 2.3 Buyer & Delivery Input Invariants

| Rule ID | Domain Rule Description | Tier 1: Client UI | Tier 2: Server RPC | Tier 3: Database Constraint |
|---|---|---|---|---|
| **RULE-BYR-01** | Full Name must be between 3 and 100 characters, trimmed. | Inline error if `< 3` chars | Sanitized and trimmed | `CHECK (char_length(trim(buyer_name)) BETWEEN 3 AND 100)` |
| **RULE-BYR-02** | WhatsApp Mobile Number must be valid 10-digit Indian mobile starting with 6–9. | Regex: `^[6-9]\d{9}$` | Normalized to E.164: `91[6-9]\d{9}` | `CHECK (buyer_phone ~ '^[6-9]\d{9}$' OR buyer_phone ~ '^91[6-9]\d{9}$')` |
| **RULE-BYR-03** | Delivery Pincode must be exactly 6 numeric digits. | Numeric keypad, max 6 digits | Regex check: `^\d{6}$` | `CHECK (pincode ~ '^\d{6}$')` |
| **RULE-BYR-04** | Complete Address must be between 10 and 500 characters. | Textarea counter, min 10 chars | Trimmed & validated | `CHECK (char_length(trim(shipping_address)) BETWEEN 10 AND 500)` |
| **RULE-BYR-05** | Delivery details in `localStorage` must be purgable by user. | `[Clear Saved Details]` link | Client local operation | N/A (Client Browser State) |

---

### 2.4 Order & Financial Invariants

| Rule ID | Domain Rule Description | Tier 1: Client UI | Tier 2: Server RPC | Tier 3: Database Constraint |
|---|---|---|---|---|
| **RULE-ORD-01** | Subtotal must equal the exact sum of purchase prices in Paisa of bundled garments. | Client displays preview | Server computes `SUM(price_paisa)` | `CHECK (subtotal_paisa > 0)` |
| **RULE-ORD-02** | Shipping fee is determined authoritatively by drop policy (with fallback to seller profile). | Client estimates shipping | Server calculates from `drops`/`profiles` | Server inserts `shipping_paisa` |
| **RULE-ORD-03** | Total Amount must exactly equal Subtotal + Shipping. | Client displays total | Server computes `subtotal_paisa + shipping_paisa` | `CHECK (total_paisa = subtotal_paisa + shipping_paisa)` |
| **RULE-ORD-04** | Order must contain at least 1 item and at most 10 items per bundle. | Cart limits addition to 10 | RPC validates array length | Checked in RPC logic |
| **RULE-ORD-05** | Order Code must follow non-sequential pattern `LD-[A-Z0-9]{6}`. | Formatted in UI | Generated via random crypto | `CHECK (order_code ~ '^LD-[A-Z0-9]{6}$')` |
| **RULE-ORD-06** | 15-minute hold expires automatically unless marked paid. | Countdown timer in UI | `release_expired_holds` cron | `hold_expires_at TIMESTAMPTZ` |
| **RULE-ORD-07** | Paid order is terminal; cannot transition to pending or cancelled. | UI hides reversal button | RPC guards against invalid status | RPC check `old.status != 'paid'` |
