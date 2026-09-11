# 07 — Functional Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  

---

## 1. Functional System Overview

LiveDrop operationalizes live-stream social selling by partitioning capabilities into two distinct user workspaces:
1. **Unauthenticated Buyer Webfront:** High-speed catalog browsing, code search, sticky bundling, atomic 15-minute stock hold, and structured WhatsApp checkout.
2. **Authenticated Seller Native Mobile App:** Sub-30-second camera intake, live broadcast inventory monitoring, 3-stage visual Kanban pipeline, and 1-tap 4×6 inch thermal shipping label generation.

---

## 2. Detailed Buyer Functional Specifications

### 2.1 Catalog Browsing & Search Flow
* **URL Entry:** The buyer navigates to `https://{domain}/drop/[slug]`.
* **State Loading:** 
  * The Next.js Edge SSR server queries Supabase for the drop matching `slug` with `status = 'live'`.
  * If the drop is in `draft` or `closed` status, the server renders a polite waiting/archived screen: *"This drop has concluded. Follow us on Facebook for our next live broadcast!"*.
  * If active, the page renders server-side in `< 1.5s` with full OpenGraph meta tags displaying the boutique store banner.
* **Product Card Presentation:**
  * Displays square 1:1 image thumbnail.
  * Overlaid top-left badge shows Flash Code (e.g. `#A01`).
  * Real-time status indicator:
    * `Available`: Green badge, `+ Add to Bag` button active.
    * `Reserved`: Amber badge showing remaining hold countdown (e.g., `Hold (11m)`), button disabled.
    * `Sold Out`: Muted grey badge, button disabled with text `Sold Out`.
* **Filtering & Search:**
  * Typing into the search input dynamically filters items by matching flash codes (case-insensitive `#A01` or `A01` or `01`).
  * Tapping `Available Only` chip filters out all items with `status != 'available'`.

### 2.2 Cart Bundling & Sticky Drawer
* **Cart State:** Maintained locally in browser memory and mirrored to `localStorage`. Adding an item pushes `{ id, code, title, price, image_url }`.
* **Subtotal Calculation:** Client computes running subtotal: `Subtotal = SUM(item.price)`.
* **Bottom Bar Trigger:** A sticky bar fixed above browser navigation appears when `items.length > 0`:
  * Displays: `"{N} Items Selected • ₹{Subtotal}"` and `[Review & Bag]`.
* **Drawer Modal Interactions:**
  * Tapping `[Review & Bag]` animates an accessible bottom drawer.
  * Displays each item with thumbnail, code, price, and `🗑 Remove` action.
  * Removing an item immediately recalculates the running subtotal. If cart becomes empty, drawer closes automatically.

### 2.3 Checkout Form & Validation Rules
* **Delivery Form Fields:**
  1. **Full Name:** Required, min 3, max 100 characters. Sanitized to remove script/HTML tags.
  2. **WhatsApp Mobile Number:** Required, exactly 10 digits. Validated against Indian mobile prefix rule: `^[6-9]\d{9}$`.
  3. **Delivery Pincode:** Required, exactly 6 digits: `^\d{6}$`.
  4. **Complete Street Address:** Required, min 10, max 500 characters (Flat/House No, Building, Street, Landmark, Area).
* **Local Persistence:**
  * When the buyer submits or types valid details, the client persists `{ name, phone, pincode, address }` to `localStorage['livedrop_buyer_profile']`.
  * On subsequent visits, these fields are pre-filled automatically. A `[Clear Saved Details]` link purges this storage.

### 2.4 Atomic Reservation & Order Creation Transaction
* **Trigger:** Buyer taps `[ Confirm & Order via WhatsApp (₹Total) ]`.
* **Execution:**
  1. Button enters loading state with spinner: *"Securing your pieces..."*.
  2. Client calls PostgreSQL RPC `create_order_with_reservation(...)` passing:
     `{ p_drop_id, p_product_ids, p_buyer_name, p_buyer_phone, p_shipping_address, p_pincode }`.
  3. The database locks all requested items atomically (`SELECT ... FOR UPDATE`).
  4. **Branch A (Success):**
     * Database returns `{ success: true, order_id, order_code, order_token, subtotal, shipping, total, hold_expires_at }`.
     * Client stores `order_token` in `sessionStorage`.
     * Client constructs formatted WhatsApp URL.
     * Browser triggers redirect to `wa.me`.
  5. **Branch B (Stock Collision / Partial Failure):**
     * Database returns `{ success: false, error: 'STOCK_UNAVAILABLE', unavailable_product_ids: [...] }`.
     * Client opens collision modal: *"Item #A01 was just claimed by another buyer."*.
     * The contested item in the drawer is outlined in red with an inline `[Remove]` button.
     * Subtotal is updated; buyer can tap `Confirm` again to check out the remaining items without re-typing their address.

### 2.5 WhatsApp Deep-Link Construction & Receipt Fallback
* **URL Format:** `https://wa.me/{seller_phone}?text={encoded_message}`
* **Normalization:** `seller_phone` is strictly formatted as international E.164 digits without `+` (e.g. `919830012345`).
* **Message Payload:**
  ```text
  🌟 NEW ORDER - MOTHER'S BOUTIQUE 🌟
  ---------------------------------
  Order ID: #LD-8942
  Items:
  1. #A01 Handloom Tussar Saree - ₹1,850
  2. #B04 Cotton Printed Kurti - ₹750
  ---------------------------------
  Subtotal: ₹2,600
  Shipping: ₹80 (Flat Rate)
  TOTAL PAYABLE: ₹2,680

  📦 Delivery Address:
  Sangeeta Mukherjee
  Flat 4B, Greenview Apartments, Near South City
  Jadavpur, Kolkata - 700032
  Phone: 98301XXXXX
  ---------------------------------
  Please share UPI QR code to complete payment!
  ```
* **Confirmation / Fallback Screen (`/order/[id]?token=[order_token]`):**
  * Displayed if popup/redirect is blocked by browser security.
  * Shows Order Code (`#LD-8942`), 15-minute countdown clock.
  * `[ Open WhatsApp Now ]` primary fallback action.
  * Static UPI QR code image and UPI ID text box with 1-tap `[ Copy UPI ID ]` action.

---

## 3. Detailed Seller Functional Specifications

### 3.1 Authentication & Boutique Configuration
* **Authentication:** Supabase Auth using email and password. No self-service buyer registration.
* **Profile Setup:** Boutique Name, WhatsApp Business Number, Return Address, UPI ID (VPA), Default Shipping Fee, and optional Free Shipping Threshold.

### 3.2 Sub-30-Second Ingestion Viewfinder
* **Shutter & Crop:**
  * Direct camera hardware stream with square 1:1 guide box.
  * Tapping shutter captures raw image; client-side isolates square crop.
  * Client-side WebP compression converts image to `< 250 KB`.
* **Auto-Incremented Code Logic:**
  * System tracks highest numeric or alphanumeric code used in current drop (e.g., `#A14`).
  * Pre-populates the code input with `#A15`.
  * Seller can manually tap to edit code if desired.
* **Price Keypad:**
  * Dedicated numeric pad opens automatically.
  * Seller enters digits (e.g., `1250`).
* **Background Queue:**
  * Tapping `[ SAVE & NEXT ]` saves product record and image file to local upload queue.
  * Camera viewfinder resets immediately without waiting for network upload to finish.
  * Background worker uploads image to Supabase Storage and inserts product row.

### 3.3 Live Broadcast Session Controller
* **Drop Status Management:**
  * `Draft`: Ingestion phase; hidden from public.
  * `Live`: Active live stream; catalog link `drop.store/[slug]` publicly accessible.
  * `Closed`: Stream concluded; prevents new reservations.
* **Live Counter Banner:**
  * Top bar displays live-updating metrics: Total Products, Active Reservations (Holds), Confirmed Sold, and Gross Revenue.
* **Long-Press Overrides:**
  * Long-pressing any product tile opens action modal:
    * `Mark Sold Offline`: Immediately sets status to `sold` (for walk-in or comment sales).
    * `Force Release Hold`: Immediately resets status from `reserved` to `available`.
    * `Adjust Price`: Updates price in real time.

### 3.4 Visual Kanban Order Pipeline
* **Columns:**
  1. **Pending Verification (`pending`):**
     * Displays orders submitted via web with active 15-minute hold timer.
     * Actions: `[ WhatsApp Chat ]` (opens pre-filled acknowledgment), `[ ✓ Mark as Paid ]`, `[ Cancel / Release ]`.
  2. **Ready to Pack (`paid`):**
     * Orders verified by seller. Associated products permanently locked as `sold`.
     * Actions: `[ Courier Slip (PDF) ]`, `[ Mark Dispatched ]`.
  3. **Dispatched (`shipped`):**
     * Completed orders. Holds courier tracking number and partner name.
* **Payment Verification Transition:**
  * Seller taps `[ ✓ Mark as Paid ]`.
  * Client invokes `mark_order_paid(order_id)`.
  * Database ensures no items were claimed by another buyer after hold expiry.
  * On success, order moves to `Paid` column; real-time event updates all connected buyer catalogs.

### 3.5 Automated 4×6 Courier Packing Slip Engine
* **Format:** Standard 4×6 inch (100×150 mm) thermal parcel label layout.
* **Generation Engine:** Rendered client-side in Flutter using `pdf` and `printing` packages.
* **Sections:**
  1. **Recipient Block:** Large bold Name, Phone, Formatted multiline Address, Bold 6-digit Pincode.
  2. **Sender Return Block:** Boutique Name, Contact Phone, Return Address.
  3. **Package Manifest:** Item Flash Codes, Titles, Quantities, Declared Value, Mode: `Prepaid (UPI)`.
  4. **Machine-Readable Identifier:** Standard 1D Code-128 barcode encoding the internal Order ID (`#LD-XXXX`).
* **Print Targets:**
  * Bluetooth thermal printer via ESC/POS protocol.
  * System Print Spooler / PDF share to WhatsApp.
