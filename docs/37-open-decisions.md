# LiveDrop — Open Decisions & Product Recommendations Register

## 1. Overview
This register records non-trivial architectural, product, and operational decisions that require formal human sign-off or document the recommended baseline adopted during the pre-implementation phase.

---

## 2. Decision Items

### DEC-001: Shipping Fee Policy & Computation Model
* **Question**: How should shipping fees be calculated for buyer checkout in the MVP?
* **Context**: Indian boutique e-commerce typically uses flat-rate pan-India shipping or free shipping above a threshold. Complex weight-based calculation adds buyer friction and requires scale integrations.
* **Options**:
  1. *Option A (Dynamic Weight-Based)*: Calculate per-gram shipping using courier APIs. (High complexity, external API dependency).
  2. *Option B (Flat Rate per Drop)*: Seller configures a flat shipping fee (e.g., ₹80) on the Drop entity, with optional free shipping threshold.
  3. *Option C (Hardcoded Global Flat Rate ₹80)*: Fixed across all sellers in MVP.
* **Recommendation**: **Option B (Flat Rate per Drop)**. Store `shipping_fee_paisa` (default ₹80 / 8000 paisa) and `free_shipping_threshold_paisa` (optional) on `drops`.
* **Consequences**: Minimal seller effort, zero external courier API latency during checkout, predictable buyer total.
* **Status**: **PROPOSED (Accepted as pre-implementation baseline)**.

---

### DEC-002: Contested Expired Order "Mark Paid" Resolution
* **Question**: What happens if a buyer's 15-minute reservation expires, the item is reclaimed by Buyer B in a new order, and Seller attempts to mark Buyer A's expired order as "Paid"?
* **Context**: In live commerce, bank transfer delays can cause a buyer to pay at minute 16 while the system auto-released the hold.
* **Options**:
  1. *Option A (Force Overwrite / Double-Sell)*: Allow seller to mark paid, leaving Buyer B with a cancelled order. (Severe buyer trust degradation).
  2. *Option B (Strict State Guard)*: Database RPC `mark_order_paid` checks if any item in the order has already been reclaimed (`product.status = 'reserved' AND product.reserved_by_order_id != current_order_id` or `product.status = 'sold'`). If contested, transaction aborts with `PRODUCT_ALREADY_RECLAIMED`. Seller UI displays an explicit modal: *"Item #04 was reclaimed by Order #1042. Please refund Buyer A or fulfill with alternate stock."*
* **Recommendation**: **Option B (Strict State Guard)**. Protects inventory integrity above all else.
* **Consequences**: Guarantees single-piece inventory is never double-allocated. Forces seller to resolve payment dispute manually via WhatsApp.
* **Status**: **ACCEPTED**.

---

### DEC-003: Seller Offline Image Queue Storage Technology
* **Question**: Which local storage engine should the Flutter seller app use for offline product ingestion and image queuing?
* **Context**: Flutter supports SQLite (`sqflite`), Hive / Isar (NoSQL key-value), and ObjectBox.
* **Options**:
  1. *Option A (`sqflite`)*: Relational, rock-solid ACID transactions, easily inspected via SQL tools, zero risk of schema corruption.
  2. *Option B (`hive_ce` / `isar`)*: Pure Dart, fast key-value store, slightly lighter setup.
* **Recommendation**: **Option A (`sqflite`)**. Transactional safety is paramount when persisting queued product metadata and file paths on low-end Android storage.
* **Consequences**: Standard relational tables for `queued_products` and `upload_chunks` with deterministic status flags (`pending`, `uploading`, `failed`).
* **Status**: **ACCEPTED**.

---

### DEC-004: Thermal Shipping Label Format & Printer Connectivity
* **Question**: What physical label dimensions and printer protocol should LiveDrop target in MVP?
* **Context**: Indian logistics aggregators (Delhivery, Shiprocket, India Post) standardly use **4×6 inch (100×150mm)** thermal sticker rolls.
* **Options**:
  1. *Option A (Direct ESC/POS Bluetooth Streaming)*: Communicate directly via Bluetooth RFCOMM to 2-inch and 3-inch thermal receipt printers. (High device fragmentation, flaky Bluetooth stacks).
  2. *Option B (Vector PDF 4×6 inch + Android System Print / Share)*: Generate standard 4×6 inch vector PDF client-side using `pdf` Flutter package. Send directly to Android Print Framework (supports Wi-Fi/Bluetooth thermal printers natively) or share to WhatsApp/Email.
* **Recommendation**: **Option B (Vector PDF 4×6 inch + Android Print Framework)**. Zero device-specific driver code, 100% reliable output on any standard printer, shareable to desktop.
* **Consequences**: Eliminates 80% of printer integration bugs while delivering carrier-compliant labels.
* **Status**: **ACCEPTED**.

---

### DEC-005: Supabase Free-Tier Inactivity Mitigation
* **Question**: How do we prevent Supabase free-tier project auto-pausing after 7 days of seller inactivity between weekly live shows?
* **Context**: Free tier projects pause if no queries occur within 7 days. Unpausing takes several minutes, which would break an active live stream.
* **Options**:
  1. *Option A (Paid Supabase Plan)*: Upgrade to $25/mo Pro plan. (Violates ₹0 bootstrap constraint).
  2. *Option B (Automated GitHub Action Keepalive)*: A lightweight GitHub Action scheduled via cron (`0 0 * * *`) that executes a `SELECT 1;` health check against the Supabase REST endpoint daily.
* **Recommendation**: **Option B (GitHub Action Daily Keepalive)** with clear documentation that exceeding limits or requiring SLAs requires Pro plan upgrade.
* **Consequences**: Maintains zero-cost operations while guaranteeing the database stays warm and ready for weekend live drops.
* **Status**: **ACCEPTED**.

---

### DEC-006: Flash-Code Scope & Format
* **Question**: What is the scope and format of product flash-codes?
* **Context**: Live streamers show physical cards like "D1", "01", "A12" on camera.
* **Options**:
  1. *Option A (Global Sequential Integer)*: Across all sellers. (Confusing for buyers, reveals business volume).
  2. *Option B (Scoped to Drop, 2-4 Alphanumeric)*: Unique per drop (e.g., `01`, `02` ... `99` or `A1`, `B2`). Regex `^[A-Z0-9]{1,6}$`.
* **Recommendation**: **Option B (Scoped to Drop)**. Database constraint: `UNIQUE (drop_id, flash_code)`.
* **Consequences**: Natural for sellers, easy for buyers to search during live streams.
* **Status**: **ACCEPTED**.
