# 26 — Comprehensive Test Case Catalog: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Testing Strategy:** [`docs/25-testing-strategy.md`](file:///c:/LiveDrop/docs/25-testing-strategy.md)  

---

## 1. Test Case Structure Standard

Every test case adheres to the following specification:
* **Test Case ID:** Unique identifier (`TC-[CAT]-[NUM]`)
* **Category:** Buyer, Seller, Security, Concurrency, or Recovery
* **Preconditions:** Initial database and client state
* **Test Steps:** Sequential actions executed by actor or automated runner
* **Expected Result:** Explicit database mutation, HTTP status, and UI presentation
* **Assertion Criteria:** Concrete SQL query or DOM selector verification

---

## 2. Buyer Journey Test Cases (`TC-BUY`)

| ID | Title & Scenario | Preconditions | Steps | Expected Result | Pass Assertion |
|---|---|---|---|---|---|
| **TC-BUY-01** | Browse active live drop catalog | Drop exists with `status = 'live'`, has 10 products | Navigate to `/drop/[slug]` | Page renders 10 product cards in 2-column grid in < 1.5s with OpenGraph metadata | `$$('.product-card').length === 10` |
| **TC-BUY-02** | Search products by Flash Code | Catalog contains items `#A01`, `#A02`, `#B12` | Type `A02` into search input | Feed filters instantly to show only product card `#A02` | `$$('.product-card').length === 1` |
| **TC-BUY-03** | Filter by Available items only | 5 products available, 3 reserved, 2 sold | Tap `Available Only` chip | Displays only the 5 available items; hides reserved and sold | All rendered cards have green `Available` pill |
| **TC-BUY-04** | Add and remove item from cart | Buyer viewing item `#A01` | Tap `+ Add to Bag` ➔ Open drawer ➔ Tap `🗑 Remove` | Cart subtotal updates to ₹1,850 then reverts to ₹0; drawer closes | Local cart count matches actions |
| **TC-BUY-05** | Delivery form local persistence | Form filled on prior visit | Re-open cart drawer | Fields pre-populated from `localStorage` | Inputs match saved test values |
| **TC-BUY-06** | Form validation on malformed phone | Cart has 1 item | Enter phone `12345` (invalid) | Highlights phone input in red: *"Enter valid 10-digit mobile number starting with 6-9"*; checkout button disabled | Form submission blocked |
| **TC-BUY-07** | Successful single-item reservation | Item `#A01` is `available` | Fill valid form ➔ Tap `Confirm via WhatsApp` | `create_order_with_reservation` returns success; `#A01` becomes `reserved`; redirect triggered | `products.status = 'reserved' WHERE code = '#A01'` |
| **TC-BUY-08** | Stock collision on checkout | Item `#A01` reserved by another buyer | Submit cart containing `#A01` | Returns `STOCK_UNAVAILABLE`; UI modal prompts: *"Item #A01 was just reserved by another buyer."* | Modal displays red `#A01` card |
| **TC-BUY-09** | WhatsApp deep-link generation | Valid checkout submitted | Inspect constructed URL | URL contains `wa.me/919830012345?text=...` with order code, items, subtotal, shipping, address | URL contains encoded payload |
| **TC-BUY-10** | Order confirmation & UPI fallback | Navigate to `/order/[id]?token=[token]` | Load fallback screen | Displays Order Reference `#LD-XXXX`, 15-min countdown timer, static UPI QR code, and Copy UPI ID button | DOM elements visible |

---

## 3. Seller Journey Test Cases (`TC-SEL`)

| ID | Title & Scenario | Preconditions | Steps | Expected Result | Pass Assertion |
|---|---|---|---|---|---|
| **TC-SEL-01** | Seller email/password login | Seller user provisioned in Supabase Auth | Enter valid email & pass ➔ Tap Login | Authenticated JWT stored; routes to Drops Dashboard | Session token exists in secure storage |
| **TC-SEL-02** | Create new drop session | Authenticated seller | Enter title *"Silk Drop"* ➔ Tap Save | Drop inserted with `status = 'draft'` and unique slug | `drops.status = 'draft' WHERE title = 'Silk Drop'` |
| **TC-SEL-03** | Rapid camera garment capture | Camera viewfinder open | Snap photo ➔ Enter price `1450` ➔ Tap Save & Next | Photo compressed to WebP < 250KB; product record created; viewfinder resets in < 1s | `products.price = 1450` in database |
| **TC-SEL-04** | Auto-incremented flash code | Previous upload was `#A14` | Open viewfinder for next dress | Code input pre-filled with `#A15` | `controller.text === '#A15'` |
| **TC-SEL-05** | Publish drop live | Drop in `draft` with 5 items | Tap "Go Live" | Drop status transitions to `live`; public catalog accessible | `drops.status = 'live'` |
| **TC-SEL-06** | Realtime incoming order notification | Seller viewing Kanban board | Buyer submits web order | Order appears dynamically in "Pending" column with countdown without manual refresh | Order card rendered in Pending column |
| **TC-SEL-07** | Mark order Paid | Order in Pending; payment verified | Tap `✓ Mark as Paid` | Order moves to "Ready to Pack"; all bundled products set to `sold` | `orders.status = 'paid'`, `products.status = 'sold'` |
| **TC-SEL-08** | Generate 4×6 courier PDF | Order in "Ready to Pack" | Tap `Courier Slip` | Flutter renders 4×6 inch PDF with recipient address, return address, and 1D barcode | PDF document generated < 1s |
| **TC-SEL-09** | Dispatch order with tracking | Order in "Ready to Pack" | Enter tracking `DTDC123` ➔ Tap Dispatched | Order transitions to `shipped`; archived in Dispatched tab | `orders.status = 'shipped'`, `tracking_number = 'DTDC123'` |
| **TC-SEL-10** | Manual offline sale override | Item `#A05` is `available` | Long-press tile ➔ "Mark Sold Offline" | Status changes to `sold` immediately; removed from live catalog | `products.status = 'sold'` |

---

## 4. Security & RLS Test Cases (`TC-SEC`)

| ID | Title & Scenario | Actor | Test Execution | Expected Result |
|---|---|---|---|---|
| **TC-SEC-01** | Cross-seller drop data access | Seller A | Query drops belonging to Seller B via PostgREST | Query returns empty array `[]` (RLS blocks read) |
| **TC-SEC-02** | Public buyer attempts direct order read | Anonymous | `GET /rest/v1/orders` without `order_token` | Request returns empty array `[]` (PII protected) |
| **TC-SEC-03** | Public buyer attempts direct order insertion | Anonymous | `POST /rest/v1/orders` with raw JSON payload | Blocked by RLS (403 Forbidden). Must use RPC. |
| **TC-SEC-04** | Client price manipulation attack | Anonymous | Call RPC with client-side forged subtotal | Server RPC ignores client price; computes from DB rows |
| **TC-SEC-05** | `SECURITY DEFINER` search-path exploit | Anonymous | Attempt search-path hijack inside RPC | Blocked by `SET search_path = public, pg_temp;` |
| **TC-SEC-06** | Stored XSS injection in address | Anonymous | Submit address: `<script>alert(1)</script>` | Escaped and stored as raw text; renders harmlessly in PDF |
| **TC-SEC-07** | Order code brute-force enumeration | Attacker | Loop 1,000 requests guessing random order codes | Randomized 4-char suffix prevents guessing (0 hits) |
| **TC-SEC-08** | Unauthorized `mark_order_paid` call | Anonymous | Call `POST /rpc/mark_order_paid` | 401 Unauthorized / 403 Forbidden |

---

## 5. Concurrency & Stress Test Cases (`TC-CON`)

| ID | Concurrency Scenario | Test Setup | Execution Method | Expected Invariant |
|---|---|---|---|---|
| **TC-CON-01** | **2 Buyers / 1 Single-Piece Garment** | Item `#A01` is `available` | 2 concurrent RPC calls at $t_0$ | Exactly **1 success**, exactly **1 conflict failure** (`STOCK_UNAVAILABLE`) |
| **TC-CON-02** | **5 Buyers / 1 Single-Piece Garment** | Item `#A01` is `available` | 5 concurrent RPC calls | Exactly **1 success**, **4 conflict failures** |
| **TC-CON-03** | **20 Buyers / 1 Garment (Flash Crowd)** | Item `#A01` is `available` | 20 concurrent threads in k6 | Exactly **1 success**, **19 failures**. Zero deadlocks. |
| **TC-CON-04** | **Multi-item partial collision** | Buyer A: `[#A1, #A2]`, Buyer B: `[#A2, #A3]` | Simultaneous checkout | One buyer gets `#A2`; other receives partial collision prompt |
| **TC-CON-05** | **Deadlock prevention under reverse order** | Buyer A: `[#A1, #A2]`, Buyer B: `[#A2, #A1]` | Simultaneous checkout | Sorted locking (`ORDER BY id`) executes without deadlock |
| **TC-CON-06** | **Duplicate IDs in single request** | Payload: `[#A1, #A1]` | RPC invocation | Sanitizer deduplicates array; single hold succeeds |

---

## 6. Failure Recovery Test Cases (`TC-REC`)

| ID | Failure & Recovery Scenario | Injected Fault | System Recovery Action | Expected Final State |
|---|---|---|---|---|
| **TC-REC-01** | WhatsApp closed immediately after checkout | Buyer closes app without sending text | Order remains `pending`; seller sees contact info in Kanban | Seller contacts buyer or hold expires after 15m |
| **TC-REC-02** | 15-Minute hold expiration | Order placed at $t_0$; no payment | Cron fires at $t_0 + 15\text{m}$ | Order ➔ `cancelled`; products ➔ `available` in catalog |
| **TC-REC-03** | Seller marks paid after item reclaimed | Hold expired; Buyer B bought item; Seller marks Buyer A paid | `mark_order_paid` executed | Aborts with `PRODUCT_ALREADY_RECLAIMED`; double-sale blocked |
| **TC-REC-04** | Network cut during seller photo intake | Airplane mode toggled during upload | Local queue caches WebP image in SQLite/Hive | Resumes upload automatically when airplane mode disabled |
| **TC-REC-05** | Realtime WebSocket dropped | Kill WebSocket connection | Client displays reconnecting; fetches full snapshot upon reconnect | Local catalog re-synced with DB truth |
| **TC-REC-06** | Bluetooth printer battery dies | Disconnect printer mid-print | App prompts alert dialog with `[ Share PDF to WhatsApp ]` | Seller prints via WhatsApp share |
