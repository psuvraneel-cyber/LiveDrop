# **UI/UX Specification: LiveDrop** 

**Document Version:** 1.0.0 

**Platform Scope:** Mobile Webfront (Next.js) and Native Mobile App (Flutter for Android) 

**Core Objective:** Zero-friction mobile buying without account creation, paired with sub30-second inventory ingestion and dispatch automation for sellers. 

# **1. Design System & Foundational Tokens** 

# **1.1 Color Palette** 

The interface uses high-contrast, accessible palettes engineered for legibility across budget smartphone screens and high-glare environments. 

- **Primary / Confirmation (Emerald Green):** #16A34A — Applied to primary cart triggers, bag buttons, and order submission flows. 

- **WhatsApp Deep Handoff (Teal Green):** #25D366 — Reserved exclusively for final checkout actions that redirect to WhatsApp. 

- **Inventory States:** 

   - **Available:** #22C55E (Light surface: #DCFCE7, text: #15803D). 

   - **Reserved / Hold:** #F59E0B (Light surface: #FEF3C7, text: #B45309). 

   - **Sold Out / Disabled:** #64748B (Light surface: #F1F5F9, text: #94A3B8). 

- **Neutrals & Surfaces:** 

   - Background: #F8FAFC 

   - Card Surface: #FFFFFF 

   - Text Primary: #0F172A 

   - Text Muted: #64748B 

   - Borders / Separators: #E2E8F0 

# **1.2 Typography** 

- **Font Family:** System font stack (system-ui, -apple-system, BlinkMacSystemFont, Roboto, Segoe UI, sans-serif). 

- **Monospace Badges:** ui-monospace, SFMono-Regular, Menlo, monospace for Flash Codes (#A01, #B12) to ensure high distinguishability. 

- **Type Hierarchy:** 

   - **Code Badges:** 16px Bold Monospace (FontWeight.w800). 

   - **Price Display:** 18px Semi-Bold (FontWeight.w700) with INR (₹) formatting. 

   - **Form Inputs:** 16px Regular (FontWeight.w400) to prevent auto-zoom in mobile Safari and embedded webviews. 

`o` **Micro-labels / Status:** 12px Medium (FontWeight.w500). 

# **1.3 Touch Targets & Interaction Rules** 

- **Target Sizes:** Every clickable button, card trigger, and input field adheres to a minimum touch target of **48 × 48 px** . 

- **Corner Radius:** 12px for cards, modals, and text input boxes; 24px (pill) for status and item badges. 

- **Layout Grid:** 8px baseline grid with uniform edge margins of 16px on mobile viewports. 

# **2. Buyer Mobile Webfront UI/UX (Next.js)** 

# **2.1 Screen 1: Drop Catalog Feed (** /drop/[slug] **)** 

- **Environment:** Optimized to load inside Facebook's in-app browser, WhatsApp webview, Chrome, and Safari without app installation or login barriers. 

- **Header Bar:** Displays the boutique's branding, drop session title, and an active indicator. 

- **Filter Bar:** Sticky horizontal chips allowing buyers to view All, Available, or search directly by Flash Code (#...). 

- **Product Tiles (2-Column Grid):** 

   - **Square Thumbnail (1:1):** Optimized WebP images loaded with skeleton placeholding to save mobile bandwidth. 

- **Overlaid Flash Code Badge:** High-contrast badge pinned to the top-left corner of the image matching the physical placards shown on Facebook Live. 

- **Status Badge:** Real-time pill on the top-right showing Available (green), Reserved (amber with a remaining hold countdown), or Sold Out (grey). 

- **Metadata:** Item name/fabric description and bold price (₹1,250). 

- **Cart Trigger:** Direct + Add to Bag button that switches to Added ✓ on tap. 



<!-- Start of picture text -->
┌──────────────────────────────────────────────┐<br>│ [Logo] Mother's Boutique          LIVE DROP │<br>│ drop.store/mothers-boutique                  │<br>──────────────────────────────────────────────<br>├ ┤<br>│   [ Search Flash Code e.g. #A12           ] │<br>│ [ All Items ]  [ Available ]  [ Saree ]      │<br>────────────────────── ───────────────────────<br>├ ┬ ┤<br>│ ┌──────────────────┐ │ ┌───────────────────┐ │<br>│ │ [#A01] AVAILABLE │ │ │ [#A02] RESERVED   │ │<br>│ │                  │ │ │                   │ │<br>│ │  [Image: Saree]  │ │ │  [Image: Kurti]   │ │<br>│ │                  │ │ │                   │ │<br>│ │ Tussar Silk      │ │ │ Chanderi Cotton   │ │<br>│ │ ₹1,850           │ │ │ ₹750              │ │<br>│ │ [+ Add to Bag]   │ │ │ [  Hold (12m)]   │ │<br>│ └──────────────────┘ │ └───────────────────┘ │<br>────────────────────── ┴ ───────────────────────<br>├ ┤<br><!-- End of picture text -->

│ 2 Items Selected • ₹2,600   [Review & Bag]│ 

└──────────────────────────────────────────────┘ 

# **2.2 Screen 2: Sticky Bundle Cart & Delivery Drawer** 

- **Persistent Cart Bar:** Fixed bottom bar displaying the total item count, running subtotal, and an action trigger. 

- **Drawer Expansion:** Tapping expands an interactive bottom sheet containing: 

   - Selected item list with thumbnail, code, price, and a single-tap remove action. 

   - Minimal delivery form requiring only four fields: **Full Name** , **10-Digit WhatsApp Mobile Number** , **6-Digit Pincode** , and **Detailed Address** . 

   - **Form Autofill & Persistence:** Form inputs are stored in localStorage so repeat buyers never need to re-enter their shipping info on subsequent visits. 

- **Submit Action:** A prominent button labeled Confirm & Order via WhatsApp. 

   - Triggers an atomic reservation call to Supabase to hold items for 15 minutes. 

   - Encodes order contents and shipping details into an instant WhatsApp deep link (wa.me) targeting the seller's phone number. 

┌──────────────────────────────────────────────┐ 

- │ Review Selected Items (2)                [X] │ 

- ────────────────────────────────────────────── 

- `├ ┤` 

🗑 │ • [#A01] Handloom Silk Saree       ₹1,850 [ ]│ 

🗑 │ • [#B04] Cotton Printed Kurti        ₹750 [ ]│ 

│ ──────────────────────────────────────────── │ 

│ Total Payable:                       ₹2,600  │ 

────────────────────────────────────────────── `├ ┤` 

│ Delivery Information                         │ 

│ [ Full Name                              ]   │ 

│ [ 10-Digit WhatsApp Mobile Number        ]   │ 

│ [ 6-Digit Delivery Pincode               ]   │ 

│ [ Flat / House No, Street Name, Landmark ]   │ 

────────────────────────────────────────────── `├ ┤` 

│ [ Confirm & Order via WhatsApp (₹2,600) ] │ 

│ Locks selected pieces for 15 minutes      │ 

└──────────────────────────────────────────────┘ 

# **2.3 Screen 3: Order Handshake & Static UPI Fallback (** /order/[id] **)** 

- **Purpose:** Rendered as the fallback/receipt screen if the buyer's browser suppresses the automatic WhatsApp redirect. 

- **Components:** 

   - Clear reference identifier (e.g., #LD-8942). 

   - Direct Open WhatsApp Now button pre-linked with the order text payload. 

   - Seller's static UPI QR code image and UPI ID text box. 

   - One-tap Copy UPI ID button with toast feedback. 

- Explicit helper text: _"Send your UPI payment screenshot directly in the_ . 

- _WhatsApp chat to confirm dispatch"_ 

# **3. Seller Operations Mobile App UI/UX (Flutter)** 

# **3.1 Screen 1: Sub-30-Second Ingestion Viewfinder** 

- **Design Goal:** Allow a seller to photograph, tag, price, and publish an inventory item in under 30 seconds. 

- **Camera Interface:** 

   - Square viewfinder overlay (1:1 aspect ratio) with hardware camera trigger. 

   - Client-side compression converting photos to WebP (< 250 KB). 

   - Auto-incrementing code field pre-filled based on the previous upload (e.g., #A14 → #A15). 

   - Single numeric price input with auto-opened numeric keypad. 

   - Save & Next action button that uploads the item in the background while instantly resetting the camera viewfinder for the next garment. 

┌──────────────────────────────────────────────┐ 

│ [X] Exit Intake         Active Drop: #Drop04 │ 

────────────────────────────────────────────── `├ ┤` 

│                                              │ 

│             [ CAMERA VIEWFINDER ]            │ 

│              (1:1 Square Frame)              │ │                                              │ 

────────────────────────────────────────────── `├ ┤` 

│ Flash Code: [#A15] (Auto-incremented)        │ 

│ Price (₹):  [ 1250                         ] │ 

│ Title/Size: [ Tussar Silk / Free Size      ] │ 

────────────────────────────────────────────── `├ ┤` 

│   [ Retake ]         [ SAVE & NEXT ]   │ └──────────────────────────────────────────────┘ 

# **3.2 Screen 2: Real-Time Live Session Dashboard** 

- **Purpose:** Live broadcast command center providing instant stock visibility while streaming. 

- **Live Counter Banner:** Summarizes Total Items, Active Holds, Confirmed Sold, 

- and Total Revenue in real time. 

- **Quick Inventory Grid:** Interactive item tiles showing current status (Available, Reserved, Sold). 

- **Manual Override:** Long-pressing any item tile opens an action sheet: Mark Sold Offline, Force Release Reservation, or Adjust Price. 

# **3.3 Screen 3: Visual Kanban Order Pipeline** 

- **Pipeline Columns:** Orders are grouped across three clean horizontal tabs or columns: 

   1. **Pending (** pending **):** New orders placed via web awaiting UPI verification; shows hold expiration timer. 

2. **Paid / To Pack (** paid **):** Payment confirmed by seller; shipping slip ready to print. 

3. **Dispatched (** shipped **):** Handed to courier; holds parcel tracking numbers. 

# • **Order Card Actions:** 

- Chat: Opens WhatsApp directly with the customer's phone number. 

- Mark as Paid: Instantly moves the order to the Paid column and sets associated products to permanently sold. 

- Courier Slip: Triggers the 4×6 inch PDF shipping label generator. 



<!-- Start of picture text -->
┌──────────────────────────────────────────────┐<br>│ Orders Pipeline                  [  Search] │<br>─────────────── ─────────────── ──────────────<br>├ ┬ ┬ ┤<br>│ Pending (3)   │ Paid (5)      │ Shipped (12) │<br>─────────────── ┴ ─────────────── ┴ ──────────────<br>├ ┤<br>│ ┌──────────────────────────────────────────┐ │<br>│ │ Order #LD-8942                 11m left  │ │<br>│ │ Sangeeta Mukherjee (Kolkata)             │ │<br>│ │ Items: #A01, #B04 • ₹2,600               │ │<br>│ │ [   WhatsApp ]    [ ✓ Mark as Paid ]    │ │<br>│ └──────────────────────────────────────────┘ │<br>│ ┌──────────────────────────────────────────┐ │<br>│ │ Order #LD-8940                  PAID     │ │<br>│ │ Priya Sharma (Salt Lake)                 │ │<br><!-- End of picture text -->

│ │ Items: #A07 • ₹1,450                     │ │ 

│ │ [ Courier Slip ] [ Dispatched ]    │ │ 

│ └──────────────────────────────────────────┘ │ 

└──────────────────────────────────────────────┘ 

# **3.4 Screen 4: 4×6 Inch Thermal Courier Packing Slip** 

- **Dimensions:** Standard 4 × 6 inches (100 × 150 mm) thermal parcel label layout. 

- **Integrated Engine:** Rendered client-side using Flutter's pdf and printing packages. 

- **Slip Elements:** 

   - **Recipient Section:** Full Name, Large Bold Phone Number, Formatted Multiline Address, and Bold 6-digit Pincode. 

   - **Sender / Return Section:** Boutique Store Name, Contact Phone, and Return Address. 

   - **Contents Breakdown:** Product Flash Codes, Titles, Quantities, and Declared Value. 

   - **Barcode / Tracking:** Standard 1D barcode encoding internal Order ID (#LD-XXXX). 

- **Printing Actions:** Direct output to Bluetooth thermal label printers (ESC/POS) or one-tap PDF share to WhatsApp for local printing. 

┌────────────────────────────────────────────────────────────┐ 

- │ SHIP TO:                                                   │ 

│ Sangeeta Mukherjee                                         │ 

│ Phone: +91 98301-XXXXX                                     │ 

│ Flat 4B, Greenview Apartments, Near South City             │ 

│ Jadavpur, Kolkata - 700032                                 │ 

│ PINCODE: 700032                                            │ 

──────────────────────────────────────────────────────────── `├ ┤` 

│ RETURN TO (SENDER):                                        │ 

│ Mother's Boutique (Phone: +91 98300-XXXXX)                 │ 

│ 12/A Rashbehari Avenue, Kolkata - 700026                   │ 

──────────────────────────────────────────────────────────── `├ ┤` 

│ CONTENTS:                                                  │ 

│ • #A01 Handloom Tussar Saree (1 pc)                        │ 

│ • #B04 Cotton Printed Kurti (1 pc)                         │ 

│ Total Declared Value: ₹2,600 | Mode: Prepaid (UPI)         │ 

──────────────────────────────────────────────────────────── `├ ┤` 

│ ||||| |||| |||||||||||| |||||||||||                        │ 

│ ORDER ID: #LD-8942                                         │ 

└────────────────────────────────────────────────────────────┘ 

# **4. State Transitions & Edge-Case UI Flows** 

# **4.1 Real-Time Stock Collision Handling** 

- **Trigger:** Two buyers submit checkout containing the same single-piece garment simultaneously. 

- **System Action:** Supabase atomic RPC reserves the piece for the faster transaction and rejects the secondary attempt. 

- **Buyer UI Behavior:** 

- Displays a non-blocking modal: _"Item #A01 was just reserved by another buyer."_ 

- Marks the contested garment in red with an inline [Remove] button. 

- Preserves all other cart items and pre-filled address details so the buyer can complete the rest of the order without friction. 

# **4.2 Offline & Poor Connection Scenarios** 

- **Buyer Webfront:** Optimistic UI state updates for cart modifications; image assets utilize browser cache and WebP compression to prevent blank frames on slow 4G. 

- **Seller App:** Upload queue holds snapped images in local storage (SQLite/Hive) if cellular connectivity drops during a broadcast, automatically synchronizing once reconnected. 

# **5. Antigravity IDE Component Directory Tree** 

Plaintext 

buyer-web/ (Next.js) 

- `├` ── components/ 

- │ `├` ── catalog/ 

- │   │ `├` ── ProductCard.tsx       # Flash code badge, price, stock status 

- │   │ `├` ── ProductGrid.tsx       # Responsive 2-column mobile feed 

- │   │   └── SearchBar.tsx         # Flash code search & filter chips 

- │ `├` ── cart/ 

- │   │ `├` ── StickyCartBar.tsx     # Floating bottom sheet trigger 

- │   │ `├` ── CartDrawer.tsx        # Item list, subtotal, address fields 

- │   │   └── WhatsAppCheckout.tsx  # Deep link constructor & RPC caller 

- │   └── order/ 

- │       └── UpiConfirmation.tsx   # Static QR display and Copy UPI ID 

seller-app/ (Flutter) 

`├` ── lib/ 

│ `├` ── presentation/ 

- │   │ `├` ── intake/ 

- │   │   │ `├` ── camera_screen.dart        # Sub-30s photo & code capture 

│   │   │   └── product_form_overlay.dart # Keypad & auto-incrementing code 

- │   │ `├` ── kanban/ 

│   │   │ `├` ── kanban_board_screen.dart  # 3-column order pipeline 

│   │   │   └── order_card.dart           # Order item card & action buttons 

- │   │   └── dispatch/ 

│   │       └── shipping_label_view.dart  # 4x6 inch thermal PDF layout 

