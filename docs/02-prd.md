# 02 — Product Requirements Document (PRD): LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Brief:** [`docs/01-product-brief.md`](file:///c:/LiveDrop/docs/01-product-brief.md)  

---

## 1. Executive Summary & Goals

### 1.1 Product Purpose
LiveDrop is a specialized two-tier commerce operating system tailored for independent home boutique sellers on Facebook Live. It decouples the commerce interaction into a zero-friction, zero-download buyer webfront and an automated, camera-first seller native mobile application, unified by a real-time PostgreSQL cloud backend running within permanent free-tier limits.

### 1.2 Target Success Metrics (KPIs)
* **Checkout Velocity:** A buyer completes selection, enters shipping details, and routes to WhatsApp in under **45 seconds**.
* **Ingestion Speed:** A seller can photograph, tag with a flash code, price, and publish an inventory item in under **30 seconds**.
* **Zero Inventory Collisions:** **100% elimination** of double-sold single-piece inventory through atomic database-level reservation logic.
* **Dispatch Time Reduction:** Post-live parcel labeling time reduced from 3+ hours to under **20 minutes** via automated 4×6 inch PDF thermal label generation.
* **Zero Operating Cost:** Base platform operates entirely within free cloud tier allowances (**₹0** compute, storage, and payment gateway fees).

---

## 2. System Scope & Boundaries

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             SYSTEM BOUNDARIES                               │
├──────────────────────────────────────┬──────────────────────────────────────┤
│ 1. Buyer Webfront (Next.js)          │ 2. Seller Operations App (Flutter)   │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ • Zero app download (runs in browser)│ • Native Android APK (Direct install)│
│ • No buyer authentication/passwords  │ • Supabase Email/Password Auth       │
│ • Large flash-code product cards     │ • Rapid camera ingestion (<30s)      │
│ • Real-time stock availability badge │ • Real-time Kanban order pipeline    │
│ • Sticky bundle cart & WhatsApp link │ • 1-tap 4x6 courier slip PDF engine  │
│ • Static UPI QR display screen       │ • Bluetooth thermal printer support  │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

---

## 3. Buyer Webfront Functional Requirements (Next.js)

### 3.1 Target Platform & Execution Environment
* **Platform:** Responsive Mobile Web (Edge SSR on Cloudflare Pages or Vercel).
* **Target Browsers:** Facebook In-App Browser, WhatsApp In-App Webview, Chrome Mobile (Android), Safari Mobile (iOS).
* **Zero-Download Constraint:** No native app install prompts, no PWA install modals, no mandatory account creation or phone OTPs prior to browsing.

### 3.2 Feature Matrix

#### REQ-FR-B1: Drop Catalog Feed (`/drop/[slug]`)
* **FR-B1.1 — Feed Display:** High-density 2-column mobile grid displaying all products associated with the active live drop.
* **FR-B1.2 — Product Card Elements:**
  * High-contrast Flash Code badge (`#A01`, `#B12`) pinned to top-left of image (16px Bold Monospace).
  * 1:1 Square thumbnail served with auto-WebP compression and skeleton loading placeholder.
  * Short title/fabric description (optional, max 40 chars).
  * Price formatted in INR (`₹1,250`).
  * Real-time status pill: `Available` (Green), `Reserved` (Amber with hold countdown), `Sold Out` (Muted Grey).
* **FR-B1.3 — Sticky Filter Bar:** Horizontal sticky chips: `All`, `Available Only`, and text search input matching flash codes (`#...`).
* **FR-B1.4 — Cart Interaction:** Tap `+ Add to Bag` adds item to client session cart and switches button state to `Added ✓`.

#### REQ-FR-B2: Multi-Item Sticky Cart
* **FR-B2.1 — Persistent Bottom Bar:** Sticky bar fixed to the bottom viewport displaying:
  * Count badge: `"X items selected"`.
  * Running Subtotal: `"₹X,XXX"`.
  * Primary CTA: `Review & Bag` (Emerald Green `#16A34A`, min 48×48px touch target).
* **FR-B2.2 — Bundle Drawer:** Tapping expands an interactive bottom sheet modal showing selected items, individual prices, thumbnail previews, and single-tap `🗑 Remove` action.

#### REQ-FR-B3: Zero-Friction Checkout & Delivery Form
* **FR-B3.1 — Minimal Input Fields:**
  1. `Full Name` (Text, required, min 3 chars, max 100 chars).
  2. `WhatsApp Number` (Numeric, required, exactly 10 digits, regex: `^[6-9]\d{9}$`).
  3. `Delivery Pincode` (Numeric, required, exactly 6 digits, regex: `^\d{6}$`).
  4. `Detailed Address` (Textarea, required, min 10 chars, max 500 chars: House/Flat, Street, Landmark).
* **FR-B3.2 — Client Persistence:** Form fields automatically persist to browser `localStorage` so repeat buyers never re-type details on subsequent visits. A clear button allows purging saved data.

#### REQ-FR-B4: Atomic Stock Reservation & WhatsApp Handoff
* **FR-B4.1 — Atomic Transaction Call:** Tapping `Confirm & Order via WhatsApp` calls the unified database RPC `create_order_with_reservation(...)`.
  * **Success:** Locks items for 15 minutes, creates order record with `pending` status, returns internal `order_code` (`#LD-XXXX`) and secure `order_token`.
  * **Collision:** If any item is claimed concurrently, returns specific unavailable item IDs. The UI displays an inline modal: *"Item #A01 was just reserved by another buyer. Please remove it to proceed."*, preserving all other cart items and entered address details.
* **FR-B4.2 — WhatsApp Deep Link:** On success, constructs and launches URL: `https://wa.me/{seller_phone}?text={encoded_order_summary}`.
* **FR-B4.3 — Confirmation & UPI Fallback Screen (`/order/[id]`):** If WhatsApp auto-redirect fails or buyer returns, displays:
  * Order ID reference (`#LD-XXXX`) and countdown timer.
  * Explicit `Open WhatsApp Now` button.
  * Seller's static UPI QR code image and UPI VPA ID (`store@upi`) with 1-tap `Copy UPI ID` toast action.
  * Clear instructions: *"Please share your UPI payment screenshot directly in the WhatsApp chat to confirm dispatch."*

---

## 4. Seller Mobile App Functional Requirements (Flutter Android)

### 4.1 Target Platform & Constraints
* **Platform:** Flutter 3.x for Android (compiled as release APK, direct USB/Drive distribution).
* **Target OS:** Android 11.0+ (API level 30+), single-hand handheld operation.
* **Authentication:** Supabase Auth (Email/Password) restricted strictly to the boutique owner.

### 4.2 Feature Matrix

#### REQ-FR-S1: Rapid Camera Ingestion Engine
* **FR-S1.1 — Hardware Camera Integration:** Native camera viewfinder with 1:1 square guide overlay.
* **FR-S1.2 — Sub-30-Second Capture Loop:**
  1. Shutter tap captures image.
  2. Client-side auto-crop to 1:1 square and WebP compression to `< 250 KB`.
  3. Auto-suggested flash code (e.g., if last was `#A14`, auto-fills `#A15`).
  4. Single numeric keypad opens automatically for price entry (`₹`).
  5. Tap `Save & Next` queues background image upload and resets viewfinder instantly without closing camera.
* **FR-S1.3 — Bulk Drop Publishing:** Group items under a named Drop (e.g., *"Friday Silk Special"*) and toggle status between `Draft`, `Live`, and `Closed`.

#### REQ-FR-S2: Real-Time Live Session Monitor
* **FR-S2.1 — Live Inventory Grid:** Real-time grid reflecting live status of all items during stream.
* **FR-S2.2 — Live Metric Counters:** Top banner displaying: Total Items, Active Holds, Confirmed Sold, and Total Revenue.
* **FR-S2.3 — Manual Overrides:** Long-press item tile opens bottom sheet: `Mark Sold Offline`, `Force Release Reservation`, or `Adjust Price`.

#### REQ-FR-S3: Visual Kanban Order Management
* **FR-S3.1 — Three-Stage Pipeline:**
  1. **Pending (`pending`):** Orders placed on web awaiting UPI verification; shows hold timer countdown. Actions: `WhatsApp Chat`, `Mark as Paid`, `Cancel / Release Hold`.
  2. **Paid / To Pack (`paid`):** Payment confirmed; items permanently `sold`. Actions: `Print / Share Courier Label`, `Mark as Dispatched`.
  3. **Dispatched (`shipped`):** Archived orders holding courier tracking number and partner name.
* **FR-S3.2 — Customer Quick Chat:** Tapping WhatsApp icon launches chat with customer's number with pre-filled acknowledgment.

#### REQ-FR-S4: Automated 4×6 Courier Packing Slip Engine
* **FR-S4.1 — Formatting:** Standard 4×6 inch (100×150 mm) thermal shipping label layout rendered client-side using `pdf` and `printing` packages.
* **FR-S4.2 — Label Content:**
  * **Recipient:** Full Name, Large Bold Phone Number, Formatted Multiline Address, Bold 6-digit Pincode.
  * **Sender / Return:** Boutique Store Name, Contact Phone, Return Address.
  * **Package Breakdown:** Flash Codes, Descriptions, Quantities, Declared Value.
  * **Reference:** 1D Code-128 Barcode containing Order ID (`#LD-XXXX`).
* **FR-S4.3 — Printing Targets:** Direct output to ESC/POS Bluetooth thermal printers or shareable PDF to WhatsApp / Android Print Spooler.

---

## 5. Non-Functional Requirements Summary

* **NFR-01 (Latency):** Buyer catalog First Contentful Paint (FCP) `< 1.5s` on 4G networks.
* **NFR-02 (Bundle Weight):** Buyer web initial JS payload `< 300 KB` gzipped.
* **NFR-03 (Concurrency):** Zero double-allocations under simultaneous checkout bursts.
* **NFR-04 (Realtime Latency):** Stock updates delivered to connected clients in `< 1.5 seconds`.
* **NFR-05 (Availability):** Core catalog and order checkout functional 99.9% during scheduled live drops.
* **NFR-06 (Cost):** 100% operational within cloud free tiers for initial 6 months.
