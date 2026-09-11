# 03 — UI/UX Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  

---

## 1. Design System & Foundational Tokens

### 1.1 Color Palette
Engineered for maximum legibility on budget Android screens under high-glare lighting conditions (e.g. ring lights, outdoor sunlight).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             COLOR PALETTE TOKENS                            │
├────────────────────┬───────────┬────────────────────────────────────────────┤
│ Token Name         │ Hex Value │ Application & Semantic Meaning             │
├────────────────────┼───────────┼────────────────────────────────────────────┤
│ primary-emerald    │ #16A34A   │ Primary cart actions, CTA buttons, badges  │
│ whatsapp-teal      │ #25D366   │ WhatsApp checkout trigger & chat buttons   │
│ stock-available    │ #22C55E   │ Available inventory status pill            │
│ stock-reserved     │ #F59E0B   │ Reserved / 15-min hold status pill (Amber) │
│ stock-sold         │ #64748B   │ Sold out / disabled item state (Muted Slate│
│ bg-page            │ #F8FAFC   │ Global background neutral                  │
│ surface-card       │ #FFFFFF   │ High-elevation surface cards & modals      │
│ text-primary       │ #0F172A   │ High-contrast primary typography           │
│ text-muted         │ #64748B   │ Secondary labels, descriptions, metadata   │
│ border-subtle      │ #E2E8F0   │ Hairline dividers and card borders         │
│ error-crimson      │ #EF4444   │ Form validation errors & collision alerts  │
└────────────────────┴───────────┴────────────────────────────────────────────┘
```

### 1.2 Typography Hierarchy
* **System Font Stack:** `system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif` (zero network font download latency).
* **Monospace Badging:** `ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace` reserved strictly for Flash Codes (`#A01`, `#B12`) to ensure high contrast against dress patterns.
* **Scale:**
  * **Hero / Header:** 20px Bold (`font-weight: 700`), line-height 1.25.
  * **Flash Code Badge:** 16px ExtraBold Monospace (`font-weight: 800`), tracking `0.05em`.
  * **Price Display:** 18px Semi-Bold (`font-weight: 700`) with INR symbol (`₹`).
  * **Body / Form Inputs:** 16px Regular (`font-weight: 400`) — prevents mobile Safari/Chrome auto-zoom.
  * **Micro-labels / Badges:** 12px Medium (`font-weight: 500`), uppercase tracking `0.04em`.

### 1.3 Mobile Touch Ergonomics
* **Minimum Touch Targets:** Every interactive element adheres strictly to **48 × 48 px**.
* **Corner Radii:** `12px` for cards, inputs, and drawers; `24px` (full pill) for status badges.
* **Layout Grid:** 8px baseline grid with uniform 16px screen edge margins.
* **Bottom Sheet Constraints:** Sticky checkout bars positioned above native mobile browser navigation chrome.

---

## 2. Buyer Mobile Webfront Screens (Next.js)

### 2.1 Catalog Feed Screen (`/drop/[slug]`)
* **Header:** Boutique store logo, boutique title, and blinking "LIVE NOW" badge.
* **Sticky Filter Bar:** Horizontal pill buttons (`All`, `Available`, `Sarees`, `Kurtis`) and code search input (`Search #A01...`).
* **2-Column Product Grid:**
  * Square 1:1 image thumbnail.
  * Top-Left Badge: `#A01` (Black background, white bold monospace).
  * Top-Right Badge: `Available` (Green) or `Reserved (12m)` (Amber).
  * Price: `₹1,850`.
  * CTA: `+ Add to Bag` ➔ `Added ✓`.

```
┌──────────────────────────────────────────────┐
│ [Logo] Mother's Boutique          ● LIVE NOW │
│ drop.store/mothers-boutique                  │
├──────────────────────────────────────────────┤
│ [ 🔍 Search Flash Code e.g. #A12           ] │
│ [ All Items ]  [ Available ]  [ Saree ]      │
├──────────────────────────────────────────────┤
│ ┌──────────────────┐    ┌──────────────────┐ │
│ │ [#A01] AVAILABLE │    │ [#A02] HOLD (11m)│ │
│ │                  │    │                  │ │
│ │  [Image: Saree]  │    │  [Image: Kurti]  │ │
│ │                  │    │                  │ │
│ │ Tussar Silk      │    │ Chanderi Cotton  │ │
│ │ ₹1,850           │    │ ₹750             │ │
│ │ [+ Add to Bag]   │    │ [  Hold (11m) ]  │ │
│ └──────────────────┘    └──────────────────┘ │
├──────────────────────────────────────────────┤
│ 2 Items Selected • ₹2,600     [Review & Bag] │
└──────────────────────────────────────────────┘
```

### 2.2 Sticky Bundle Cart & Delivery Drawer
* **Floating Bottom Bar:** Fixed bottom bar displaying running total and `[Review & Bag]` CTA.
* **Bottom Drawer Modal:**
  * Selected items with thumbnail, flash code, title, price, and `🗑 Remove` action.
  * Delivery Form (Name, 10-digit Phone, 6-digit Pincode, Full Street Address).
  * `localStorage` autofill indicator: *"Saved address loaded [Clear]"*.
  * Primary Button: `[ Confirm & Order via WhatsApp (₹2,680) ]` (Teal `#25D366`).
  * Micro-text: *"Locks selected pieces for 15 minutes while you confirm over WhatsApp."*

```
┌──────────────────────────────────────────────┐
│ Review Selected Items (2)                [X] │
├──────────────────────────────────────────────┤
│ 🗑 • [#A01] Handloom Silk Saree       ₹1,850 │
│ 🗑 • [#B04] Cotton Printed Kurti        ₹750 │
├──────────────────────────────────────────────┤
│ Subtotal:                            ₹2,600  │
│ Shipping:                               ₹80  │
│ Total Payable:                       ₹2,680  │
├──────────────────────────────────────────────┤
│ Delivery Information                         │
│ [ Full Name                              ]   │
│ [ 10-Digit WhatsApp Mobile Number        ]   │
│ [ 6-Digit Delivery Pincode               ]   │
│ [ Flat / House No, Street Name, Landmark ]   │
├──────────────────────────────────────────────┤
│ [ Confirm & Order via WhatsApp (₹2,680) ]    │
│ 🔒 Locks selected pieces for 15 minutes      │
└──────────────────────────────────────────────┘
```

### 2.3 Order Confirmation & Static UPI Screen (`/order/[id]`)
* **Purpose:** Rendered as receipt and fallback if WhatsApp auto-redirect fails.
* **Elements:**
  * Order Reference Badge: `#LD-8942`.
  * Hold Countdown: *"14:22 remaining to verify payment"*.
  * Action: `[ Open WhatsApp Now ]` (Teal).
  * Seller Static UPI QR code image and VPA (`mothersboutique@okhdfcbank`).
  * Action: `[ Copy UPI ID ]` with toast alert.
  * Explicit helper: *"Send UPI payment screenshot in WhatsApp chat to complete dispatch."*

---

## 3. Seller Operations Mobile App Screens (Flutter)

### 3.1 Sub-30-Second Ingestion Viewfinder
* **Design Goal:** Shutter tap ➔ auto-crop ➔ auto-code ➔ price keypad ➔ background upload in `< 20s`.
* **Viewfinder:** 1:1 square guide overlay.
* **Form Overlay:**
  * Flash Code field pre-filled with auto-incremented value (`#A15`).
  * Numeric price input with auto-opened numpad (`₹1250`).
  * Optional fabric / size field.
  * CTA: `[ Retake ]` and `[ SAVE & NEXT ]` (resets camera instantly).

```
┌──────────────────────────────────────────────┐
│ [X] Exit Intake         Active Drop: #Drop04 │
├──────────────────────────────────────────────┤
│                                              │
│             [ CAMERA VIEWFINDER ]            │
│              (1:1 Square Frame)              │
│                                              │
├──────────────────────────────────────────────┤
│ Flash Code: [#A15] (Auto-incremented)        │
│ Price (₹):  [ 1250                         ] │
│ Title/Size: [ Tussar Silk / Free Size      ] │
├──────────────────────────────────────────────┤
│   [ Retake ]         [ SAVE & NEXT (Upload) ]│
└──────────────────────────────────────────────┘
```

### 3.2 Live Session Command Dashboard
* **Metrics Banner:** Total Items (45) | Holds (3) | Sold (18) | Revenue (₹32,400).
* **Inventory Grid:** Real-time colored tiles (`Available`, `Reserved`, `Sold`).
* **Long-Press Action Sheet:** `Mark Sold Offline`, `Force Release Reservation`, `Adjust Price`.

### 3.3 Visual Kanban Order Pipeline
* **Columns / Tabs:**
  1. **Pending (3):** Shows countdown timer (e.g., `11m left`), buyer name, items, total. Actions: `WhatsApp Chat`, `✓ Mark as Paid`.
  2. **Paid (5):** Confirmed orders. Actions: `Courier Slip (PDF)`, `Dispatched`.
  3. **Shipped (12):** Archived orders with tracking code.

```
┌──────────────────────────────────────────────┐
│ Orders Pipeline                     [Search] │
├───────────────┬───────────────┬──────────────┤
│ Pending (3)   │ Paid (5)      │ Shipped (12) │
├───────────────┴───────────────┴──────────────┤
│ ┌──────────────────────────────────────────┐ │
│ │ Order #LD-8942                 11m left  │ │
│ │ Sangeeta Mukherjee (Kolkata)             │ │
│ │ Items: #A01, #B04 • ₹2,680               │ │
│ │ [   WhatsApp ]    [ ✓ Mark as Paid ]     │ │
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ Order #LD-8940                  PAID     │ │
│ │ Priya Sharma (Salt Lake)                 │ │
│ │ Items: #A07 • ₹1,450                     │ │
│ │ [ Courier Slip ]  [ Dispatched ]         │ │
│ └──────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

### 3.4 4×6 Inch Thermal Courier Packing Slip Layout
Standard 4×6 inch (100×150 mm) layout rendered client-side via Flutter `pdf`:

```
┌────────────────────────────────────────────────────────────┐
│ SHIP TO:                                                   │
│ Sangeeta Mukherjee                                         │
│ Phone: +91 98301-XXXXX                                     │
│ Flat 4B, Greenview Apartments, Near South City             │
│ Jadavpur, Kolkata - 700032                                 │
│ PINCODE: 700032                                            │
├────────────────────────────────────────────────────────────┤
│ RETURN TO (SENDER):                                        │
│ Mother's Boutique (Phone: +91 98300-XXXXX)                 │
│ 12/A Rashbehari Avenue, Kolkata - 700026                   │
├────────────────────────────────────────────────────────────┤
│ CONTENTS:                                                  │
│ • #A01 Handloom Tussar Saree (1 pc)                        │
│ • #B04 Cotton Printed Kurti (1 pc)                         │
│ Subtotal: ₹2,600 | Shipping: ₹80 | Total: ₹2,680           │
│ Mode: Prepaid (UPI)                                        │
├────────────────────────────────────────────────────────────┤
│ ||||| |||| |||||||||||| |||||||||||                        │
│ ORDER ID: #LD-8942                                         │
└────────────────────────────────────────────────────────────┘
```

---

## 4. Edge-Case UI Flows

### 4.1 Stock Collision Inline Modal
When two buyers check out the same piece simultaneously:
1. Modal appears: *"Item #A01 was just reserved by another buyer."*
2. Contested garment is highlighted with red border and inline `[Remove]` button.
3. Subtotal updates automatically.
4. All remaining cart items and entered address details remain preserved.

### 4.2 Offline Ingestion Feedback
When seller shoots garments offline:
1. Pill badge indicates: *"Offline Mode — 4 uploads queued locally"*.
2. Viewfinder continues operating without blocking.
3. Upon network restoration, subtle toast displays: *"Synced 4 items to live catalog"*.
