# 05 — Requirements Audit & Reconciliation Matrix: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Complete Adversarial Audit  
**Auditor:** Principal Product Architect & Security Engineer  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  

---

## 1. Executive Audit Summary

An adversarial audit was executed across the four baseline source documents:
1. `Product Brief` (`product_brief.md`)
2. `PRD / Brainstorming Transcript` (`Building an App for Facebook Live Sellers.md`)
3. `UI/UX Specification` (`UI.md`)
4. `Draft Technical Design Document` (`Technical Design Document.md`)

A total of **16 distinct findings** were identified, categorized, and resolved.

| Severity | Count | Resolved in Reconciled Architecture | Pending Human Confirmation |
|---|---|---|---|
| **CRITICAL** | 4 | 4 (100%) | 0 |
| **HIGH** | 5 | 5 (100%) | 0 |
| **MEDIUM** | 5 | 3 (60%) | 2 (Shipping policy & multi-qty) |
| **LOW** | 2 | 2 (100%) | 0 |

---

## 2. Adversarial Findings Catalog

### Finding AUD-01: Decoupled Reservation & Order Creation Price Tampering
* **Classification:** `CRITICAL VULNERABILITY / DATA INTEGRITY RISK`
* **Source Document:** `Technical Design Document.md` §5.1, §5.3
* **Source Statement:** Buyer calls `reserve_order_items(p_product_ids, p_session_id)`, then client executes `POST /rest/v1/orders` with `total_amount`.
* **Problem:** 
  1. A malicious buyer can intercept the network call and post `total_amount = 1.00` regardless of genuine product prices.
  2. If client drops or closes browser between reservation RPC and `POST /orders`, items remain locked for 15 minutes with no order record.
  3. Client can send an order for products it never reserved.
* **Why It Matters:** Enables direct financial fraud, phantom inventory hoarding, and catalog denial of service.
* **Impact:** Loss of revenue, broken seller trust, inventory deadlocks.
* **Severity:** `CRITICAL`
* **Recommended Resolution:** Combine reservation, pricing calculation, and order insertion into a single atomic PostgreSQL function `create_order_with_reservation(...)`. Database computes `total_amount` from authoritative product prices.
* **Decision Required:** No (Fundamental Security/Integrity Mandate).
* **Status:** **Resolved in Spec** ([`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md), [`docs/adr/ADR-002-atomic-reservation-engine.md`](file:///c:/LiveDrop/docs/adr/ADR-002-atomic-reservation-engine.md)).

---

### Finding AUD-02: Public Unauthenticated Orders Table Exposes Customer PII
* **Classification:** `SECURITY RISK / PRIVACY VIOLATION`
* **Source Document:** `Technical Design Document.md` §9.1 (RLS Policies)
* **Source Statement:** `orders` table: "Public insert allowed (unauthenticated buyers creating orders); update/delete restricted exclusively to owning seller."
* **Problem:** To display order confirmation and UPI details on `/order/[id]`, the buyer must read the order. If `orders` has public read, any scraper can query `/rest/v1/orders` and extract customer full names, phone numbers, home addresses, and order histories across all boutiques. If read is restricted to the seller, the buyer's confirmation screen breaks.
* **Why It Matters:** Massive violation of customer privacy and Indian Digital Personal Data Protection (DPDP) Act; enables stalking and competitor harvesting.
* **Impact:** Regulatory non-compliance, severe reputational disaster.
* **Severity:** `CRITICAL`
* **Recommended Resolution:** Implement cryptographic `order_token` (UUIDv4) generated upon order creation and stored in client session. RLS policy permits unauthenticated `SELECT` if and only if matching `order_token` is provided.
* **Decision Required:** No (Mandatory Security Pattern).
* **Status:** **Resolved in Spec** ([`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md), [`docs/adr/ADR-003-unauthenticated-buyer-model-and-order-privacy.md`](file:///c:/LiveDrop/docs/adr/ADR-003-unauthenticated-buyer-model-and-order-privacy.md)).

---

### Finding AUD-03: Expiration Collision When Seller Marks Paid Late
* **Classification:** `CONTRADICTION / DATA INTEGRITY RISK`
* **Source Document:** `Technical Design Document.md` §12 vs `UI.md` §4.1
* **Source Statement:** "Seller forgets to mark order 'Paid': Order remains in pending; hold expires after 15 minutes; Products return to available; seller can still manually mark paid and re-mark items as sold."
* **Problem:** If hold expires at minute 15, Buyer B reserves the item at minute 16. If seller marks Buyer A's order paid at minute 17, the system forcibly overwrites Buyer B's reservation or marks already-sold items as sold twice.
* **Why It Matters:** Results in the exact nightmare LiveDrop was built to solve: two customers promised the same one-of-a-kind saree.
* **Impact:** Customer disputes, angry buyers, seller embarrassment.
* **Severity:** `CRITICAL`
* **Recommended Resolution:** Database RPC `mark_order_paid(p_order_id)` checks if any item was reserved or purchased by another order. If contested, it rejects with `PRODUCT_ALREADY_RECLAIMED` and forces seller review.
* **Decision Required:** No (Core Value Proposition Invariant).
* **Status:** **Resolved in Spec** ([`docs/09-system-state-machines.md`](file:///c:/LiveDrop/docs/09-system-state-machines.md)).

---

### Finding AUD-04: `SECURITY DEFINER` Privilege Escalation Vector
* **Classification:** `SECURITY RISK`
* **Source Document:** `Technical Design Document.md` §5.1
* **Source Statement:** `CREATE OR REPLACE FUNCTION reserve_order_items(...) ... $$ LANGUAGE plpgsql SECURITY DEFINER;`
* **Problem:** The function runs with owner (superuser) privileges but omits `SET search_path = public, pg_temp;`. In PostgreSQL, this allows an attacker to create temporary objects and hijack operators or functions executed inside the procedure.
* **Why It Matters:** Standard textbook PostgreSQL exploit for escalating privileges from anonymous web user to superuser.
* **Impact:** Full database compromise.
* **Severity:** `CRITICAL`
* **Recommended Resolution:** Append `SET search_path = public, pg_temp;` to all `SECURITY DEFINER` functions.
* **Decision Required:** No (Basic Database Hygiene).
* **Status:** **Resolved in Spec** ([`docs/12-database-design.md`](file:///c:/LiveDrop/docs/12-database-design.md)).

---

### Finding AUD-05: Missing Authoritative Shipping Calculation Logic
* **Classification:** `MISSING REQUIREMENT / AMBIGUITY`
* **Source Document:** `product_brief.md` §5 Step 4 vs `Technical Design Document.md` §4.1
* **Source Statement:** WhatsApp text shows `Shipping: ₹80 (Kolkata Local)`. Database schema has only `total_amount` with zero shipping columns or calculation rules.
* **Problem:** How was ₹80 determined? Is shipping flat? Regional? Pincode-based? If client calculates shipping, buyer can alter it to ₹0.
* **Why It Matters:** Unclear financial accounting and potential dispute between buyer and seller.
* **Impact:** Discrepancy between web total and seller expectations.
* **Severity:** `HIGH`
* **Recommended Resolution:** Add `default_shipping_fee` (default ₹80.00) and `free_shipping_threshold` (default ₹2,000.00) to `profiles`. Add `subtotal_amount` and `shipping_amount` to `orders`.
* **Decision Required:** Yes (Business Policy Choice — see Decision DEC-01).
* **Status:** **Reconciled in Architecture, Pending Formal Business Sign-off** ([`docs/37-open-decisions.md`](file:///c:/LiveDrop/docs/37-open-decisions.md)).

---

### Finding AUD-06: Predictable Sequential Order Codes Leaking Business Intelligence
* **Classification:** `SECURITY RISK / INFORMATION DISCLOSURE`
* **Source Document:** `Technical Design Document.md` §5.2
* **Source Statement:** "Trigger on orders INSERT generates sequential LD-XXXX order codes."
* **Problem:** Predictable IDs like `LD-1001`, `LD-1002` allow competitors to observe order volume velocity and enable trivial ID guessing.
* **Why It Matters:** Commercial intelligence leakage; facilitates brute-force scanning.
* **Impact:** Loss of seller competitive confidentiality.
* **Severity:** `HIGH`
* **Recommended Resolution:** Generate cryptographically random 4-character uppercase alphanumeric codes (`LD-7K92`).
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/12-database-design.md`](file:///c:/LiveDrop/docs/12-database-design.md)).

---

### Finding AUD-07: Unverified Free-Tier Inactivity Pausing
* **Classification:** `OPERABILITY RISK / UNVERIFIED EXTERNAL ASSUMPTION`
* **Source Document:** `Technical Design Document.md` §10.1, §16.1
* **Source Statement:** "₹0 forever on Supabase Free Tier."
* **Problem:** Supabase Free Tier automatically pauses projects if inactive for 7 consecutive days. If a boutique takes an 8-day vacation, the backend pauses; when they go live, the app fails with 503 errors.
* **Why It Matters:** Broadcast failure during peak audience attention.
* **Impact:** Total loss of live stream revenue.
* **Severity:** `HIGH`
* **Recommended Resolution:** Schedule an automated daily keepalive health-check request via free GitHub Actions cron or external monitoring service (e.g. cron-job.org).
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/28-deployment-architecture.md`](file:///c:/LiveDrop/docs/28-deployment-architecture.md)).

---

### Finding AUD-08: Storage Egress Bandwidth Exhaustion
* **Classification:** `PERFORMANCE RISK / OPERABILITY RISK`
* **Source Document:** `Technical Design Document.md` §13.3
* **Source Statement:** "Supabase Storage: 1 GB file storage, free tier."
* **Problem:** Supabase free tier limits monthly storage egress bandwidth to 2 GB. 100 viewers browsing 40 images (40 KB each = 1.6 MB) = 160 MB per stream. 15 streams = 2.4 GB egress, exhausting the quota and halting image delivery.
* **Why It Matters:** Images stop rendering mid-month for active sellers.
* **Impact:** Catalog browsing breaks completely.
* **Severity:** `HIGH`
* **Recommended Resolution:** Configure immutable cache headers (`Cache-Control: public, max-age=31536000, immutable`) and route image traffic through Cloudflare Free CDN proxy to absorb 95%+ of repeat image hits.
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/adr/ADR-005-client-side-image-compression-and-storage.md`](file:///c:/LiveDrop/docs/adr/ADR-005-client-side-image-compression-and-storage.md)).

---

### Finding AUD-09: Partial Availability Reservation Response Discrepancy
* **Classification:** `CONTRADICTION`
* **Source Document:** `UI.md` §4.1 vs `Technical Design Document.md` §5.1
* **Source Statement:** `UI.md` requires highlighting the contested item in red and allowing the buyer to proceed with the remaining cart items. `Technical Design Document.md` returns a flat `BOOLEAN` (`FALSE`) with zero indication of which item failed.
* **Problem:** The client cannot highlight the contested item because the server does not disclose which product failed.
* **Why It Matters:** Directly breaks the approved UI collision recovery flow.
* **Impact:** Frustrating user experience; buyer abandons entire cart.
* **Severity:** `HIGH`
* **Recommended Resolution:** Unified RPC returns JSONB containing `'unavailable_product_ids'` array when collision occurs.
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md)).

---

### Finding AUD-10: Single-Piece Assumption vs Rare Multi-Quantity Garments
* **Classification:** `AMBIGUITY / DOMAIN INTEGRITY RISK`
* **Source Document:** `product_brief.md` §2.2 vs `Technical Design Document.md` §4.1
* **Source Statement:** "SKU count = 1 per design/color", but sellers occasionally have 2 pieces. Current schema has no `quantity` field.
* **Problem:** If a seller has 2 identical pieces of a kurti, how do they represent it without breaking single-piece locking?
* **Why It Matters:** Adding a `quantity` column introduces complex partial inventory locking and concurrency debt.
* **Impact:** System complexity explosion vs seller workflow flexibility.
* **Severity:** `MEDIUM`
* **Recommended Resolution:** Strictly maintain 1-to-1 product records in MVP. If a seller has 2 pieces, they snap/code them as `#A14` and `#A15` (or `#A14a`, `#A14b`).
* **Decision Required:** Yes (Business Confirmation — see Decision DEC-02).
* **Status:** **Reconciled in Architecture, Pending Formal Business Sign-off** ([`docs/37-open-decisions.md`](file:///c:/LiveDrop/docs/37-open-decisions.md)).

---

### Finding AUD-11: `localStorage` Privacy Exposure on Shared Family Devices
* **Classification:** `UX RISK / PRIVACY RISK`
* **Source Document:** `UI.md` §2.2
* **Source Statement:** "Form inputs are stored in `localStorage` so repeat buyers never need to re-enter shipping info."
* **Problem:** In tier-2/3 Indian households, family members frequently share smartphones. Next user opening the catalog sees previous user's full name, phone, and address.
* **Why It Matters:** Modest privacy leak within family environments.
* **Impact:** Potential user embarrassment or friction.
* **Severity:** `MEDIUM`
* **Recommended Resolution:** Add a prominent, single-tap `[Clear Saved Info]` button next to the pre-filled address banner in the cart drawer.
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/18-privacy-and-data-handling.md`](file:///c:/LiveDrop/docs/18-privacy-and-data-handling.md)).

---

### Finding AUD-12: WhatsApp URL Parameter Injection & Special Characters
* **Classification:** `TECHNICAL RISK / SECURITY RISK`
* **Source Document:** `Technical Design Document.md` §9.3
* **Source Statement:** `wa.me/${sellerPhone}?text=${encodeURIComponent(text)}`
* **Problem:** Product codes containing `#` (e.g., `#A01`) or addresses with `&`, `+`, or newline characters can break WhatsApp URL schemes on specific mobile webviews (e.g. Facebook In-App Browser on older Android versions) if not systematically sanitized.
* **Why It Matters:** Truncated message text prevents seller from reading buyer address.
* **Impact:** Manual follow-up required over WhatsApp.
* **Severity:** `MEDIUM`
* **Recommended Resolution:** Use a dedicated URI encoder that normalizes newlines to `%0A` and strictly encodes `#`, `+`, `&`, and unicode characters.
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/19-validation-and-business-rules.md`](file:///c:/LiveDrop/docs/19-validation-and-business-rules.md)).

---

### Finding AUD-13: Bluetooth Thermal Printer Driver Incompatibility
* **Classification:** `TECHNICAL RISK / HARDWARE DEPENDENCY`
* **Source Document:** `Technical Design Document.md` §7.4
* **Source Statement:** "Output targets: Bluetooth thermal printer (ESC/POS protocol)."
* **Problem:** Budget Bluetooth thermal printers in India (Everycom, Pos-58, Bluetooth POS) have non-standard ESC/POS implementations and erratic Bluetooth classic/BLE profiles.
* **Why It Matters:** App crashes or unreadable print garbage during packing.
* **Impact:** Seller unable to print labels.
* **Severity:** `MEDIUM`
* **Recommended Resolution:** Make PDF sharing to WhatsApp / Android Print Spooler the primary bulletproof default; ESC/POS direct Bluetooth print is designated as an optional beta convenience.
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/adr/ADR-007-client-side-pdf-shipping-label-engine.md`](file:///c:/LiveDrop/docs/adr/ADR-007-client-side-pdf-shipping-label-engine.md)).

---

### Finding AUD-14: Out-of-Order Realtime Stock Events Over Variable Mobile Data
* **Classification:** `DATA INTEGRITY RISK / CONCURRENCY`
* **Source Document:** `Technical Design Document.md` §5.4
* **Source Statement:** `updateProductStatus(payload.new.id, payload.new.status);`
* **Problem:** Over high-jitter 4G networks, an older `available` WebSocket event can arrive after a newer `reserved` event, overwriting accurate client state.
* **Why It Matters:** Buyer attempts to cart an already-reserved item, causing confusing collision errors.
* **Impact:** Degraded perceived reliability.
* **Severity:** `MEDIUM`
* **Recommended Resolution:** Add `version` integer and `updated_at` to product payloads. Client discards any Realtime message with `version <= current_local_version`.
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/14-realtime-contract.md`](file:///c:/LiveDrop/docs/14-realtime-contract.md)).

---

### Finding AUD-15: Missing Cascade Behavior on Drop Deletion
* **Classification:** `DATA INTEGRITY RISK`
* **Source Document:** `Technical Design Document.md` §4.1
* **Source Statement:** `orders.drop_id UUID REFERENCES drops(id) ON DELETE RESTRICT`.
* **Problem:** If a seller attempts to delete a test drop, does it fail or leave orphaned records?
* **Why It Matters:** Unclear data lifecycle.
* **Impact:** Database foreign key constraint violations.
* **Severity:** `LOW`
* **Recommended Resolution:** Drops with existing orders cannot be hard-deleted; they must transition to status `closed`. Soft deletion flag added to drops.
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/12-database-design.md`](file:///c:/LiveDrop/docs/12-database-design.md)).

---

### Finding AUD-16: Phone Number Formatting Inconsistency
* **Classification:** `AMBIGUITY`
* **Source Document:** `PRD` vs `UI.md` vs `Technical Design Document.md`
* **Source Statement:** Buyer enters 10 digits; WhatsApp deep-link requires international country code (`91`); schema uses raw `TEXT`.
* **Problem:** Missing normalization rules for leading `0`, `+91`, or spaces in buyer and seller phone numbers.
* **Why It Matters:** Malformed `wa.me` links targeting non-existent numbers.
* **Impact:** WhatsApp fails to open or opens invalid chat.
* **Severity:** `LOW`
* **Recommended Resolution:** Database and client validation enforce strict E.164 normalization without leading `+` (e.g. `919830012345`).
* **Decision Required:** No.
* **Status:** **Resolved in Spec** ([`docs/19-validation-and-business-rules.md`](file:///c:/LiveDrop/docs/19-validation-and-business-rules.md)).
