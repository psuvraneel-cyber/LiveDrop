# LiveDrop — Mobile Buyer Website Visual Design Specification

**Document Version:** 1.0.0  
**Status:** Authoritative Design Specification (Phase A Gate)  
**Primary Design Target:** Mobile Viewport (390 × 844 px — iPhone 14/15/16 Pro)  
**Secondary Responsive Viewports:** 360 × 800, 375 × 812, 412 × 915, 430 × 932, and Desktop extension (min-width: 1024px)  
**Primary Visual Source of Truth:** User-Provided 11-Screen Reference Image (`media_1790450082820.jpg`)  
**Functional & Architectural Source of Truth:** Existing LiveDrop Repository (`docs/SOURCE-OF-TRUTH.md`, Supabase Schema, RPCs, Anonymous Buyer Session, Direct UPI Engine)

---

## 1. Global Visual Language

The visual system embodies **Haute Couture Indian Luxury Live Commerce**:
- **Atmosphere:** Deep obsidian nocturnal palette (`#08080A`, `#0E0E12`), evoking a private luxury salon.
- **Accents:** Warm champagne and antique gold (`#D4AF37`, `#F5D78E`, `#C88A24`), conveying precious metal craftsmanship without gaudy neon reflection.
- **Text & Accents:** Warm ivory typography (`#FBFBFB`, `#F4F1EA`, `#AAA49A`) with serene readability.
- **Editorial Typography:** Display serif typography (`Cormorant Garamond`) for brand emblems, headlines, and luxury product titles, paired with clean, geometric sans-serif (`Plus Jakarta Sans`) for prices, forms, metadata, and interactive states.
- **Micro-Geometry:** Restrained corner radii (10px–16px), fine 1px hairline borders (`rgba(255, 255, 255, 0.08)` and `rgba(212, 175, 55, 0.25)`), and soft elevation shadows.
- **Restraint:** No generic SaaS styling, no oversized pill containers, no loud gradients, no system emojis, and zero layout shift.

---

## 2. Color Tokens

The visual language maps 1:1 to the existing Phase 1 tokens in `buyer-web/src/app/globals.css`:

| Token Name | Value | Usage in Reference UI |
|---|---|---|
| `--ld-bg` | `#08080A` | Global canvas background |
| `--ld-surface` | `#0E0E12` | Navigation docks, cards, sheet surfaces |
| `--ld-surface-elevated` | `#16161C` | Form inputs, elevated cards, search boxes |
| `--ld-surface-subtle` | `#121217` | Card headers, subtle background panels |
| `--ld-border` | `rgba(255, 255, 255, 0.08)` | Structural dividers, inactive card borders |
| `--ld-border-gold` | `rgba(212, 175, 55, 0.25)` | Gold accent borders, active cards, badge outlines |
| `--ld-border-gold-strong` | `rgba(212, 175, 55, 0.45)` | Focused inputs, highlighted active states |
| `--ld-text-primary` | `#FBFBFB` | Primary headings, product titles, prices |
| `--ld-text-secondary` | `rgba(244, 241, 234, 0.72)` | Descriptions, secondary labels, subtitles |
| `--ld-text-muted` | `#AAA49A` | Metadata, breadcrumbs, placeholder text |
| `--ld-gold` | `#D4AF37` | Primary action buttons, active navigation, star monogram |
| `--ld-gold-soft` | `#F5D78E` | Subtle gold highlights, tags, active borders |
| `--ld-gold-deep` | `#C88A24` | Pressed button states, dark gold badges |
| `--ld-live` | `#EF4444` | Live broadcast badge, pulsing live dot |
| `--ld-success` | `#10B981` | Available stock status, payment verified badge |
| `--ld-warning` | `#F59E0B` | Hold reserved status, order placed badge |
| `--ld-sold` | `#6B7280` | Sold out status, inactive timeline nodes |

---

## 3. Typography

- **Display Serif:** Cormorant Garamond (`var(--font-display)`)
  - Hero Headline: 26px / 1.15 line-height / Weight 600
  - Section Titles ("Featured Pieces", "Boutique Collections"): 20px–24px / 1.2 line-height / Weight 600
  - Product Detail Title: 22px–24px / 1.2 line-height / Weight 600
  - Empty Bag Heading: 20px–22px / Weight 500
- **Body & Functional Sans:** Plus Jakarta Sans (`var(--font-sans)`)
  - Primary CTA Text: 14px / Weight 600 / Tracking wide
  - Card Product Titles: 13px / Weight 500 / Line-clamp 1
  - Prices: 15px–22px / Weight 700 / Tabular numbers
  - Subtitles & Hints: 12px–13px / Weight 400
  - Navigation Labels: 10px–11px / Weight 500
  - Flash Codes (`#A01`, `#A03`): 11px / Font-mono / Weight 700 / Uppercase

---

## 4. Spacing Scale

Strict 4px/8px modular rhythm:
- Page Horizontal Margins: 14px–16px (mobile)
- Section Vertical Gaps: 20px–24px
- Product Grid Gaps: 10px–12px
- Card Internal Padding: 8px–12px
- Input Field Padding: 12px 14px
- Button Internal Padding: 12px 20px (Primary CTA), 8px 8px (Compact 36×36px Bag Button)
- Safe Area Insets: `env(safe-area-inset-bottom)` applied to mobile dock and sticky CTAs.

---

## 5. Border & Radius Rules

- Large Feature / Hero Cards: `16px` radius
- Product Cards: `12px` radius
- Filter Sheet & Modal Sheets: `20px` top radius
- Buttons (Primary CTAs): `10px`–`12px` radius (never oversized pills)
- Category Square Icon: `12px` radius
- Category Avatars: `9999px` (circular 52×52px)
- Compact Action Buttons (Card Bag Button): `8px` radius (36×36px)
- Chips & Filter Pills: `9999px` (pill shape, height ~32px)
- Hairline Borders: Exactly `1px solid` with transparent RGBA alphas.

---

## 6. Shadow & Elevation Rules

- Flat Surface (Level 0): `#08080A` (canvas)
- Surface 1 (Cards, Modals): `#0E0E12`, shadow `0 4px 16px rgba(0, 0, 0, 0.5)`
- Surface 2 (Inputs, Dropdowns): `#16161C`, subtle border `rgba(255, 255, 255, 0.08)`
- Gold Glow Accent: `0 4px 20px rgba(212, 175, 55, 0.22)` reserved solely for primary gold action hovers and active focus states.

---

## 7. Header (Screens 01 & 02)

- **Geometry:** Height 56px, fixed/sticky with `backdrop-filter: blur(16px)` and background `rgba(8, 8, 10, 0.92)`.
- **Left:** Four-pointed gold sparkle icon (`✦`, 18px) + Brand text "LiveDrop" in Cormorant Garamond (20px, `#FBFBFB`) + Subtitle "INDIAN LUXURY LIVE" (8px uppercase, tracking-widest, `#AAA49A`).
- **Right:**
  - Search trigger icon (20px)
  - Shopping bag icon (20px) with circular gold badge (`#D4AF37`, 18px diameter, bold black number).
- **Behavior:** Zero flicker, zero layout shift, stable across all scroll offsets.

---

## 8. Bottom Navigation Dock (Screens 01, 02, 03)

- **Geometry:** Fixed bottom container, height 60px + `env(safe-area-inset-bottom)`, background `#0E0E12`, top border 1px `rgba(255, 255, 255, 0.08)`.
- **Tabs (5 items):**
  1. **Home:** Home icon + "Home" label (Active: `#D4AF37` gold)
  2. **Live:** Live signal/broadcast icon + "Live" label
  3. **Shop:** Shopping bag / storefront icon + "Shop" label
  4. **Orders:** Receipt icon + "Orders" label
  5. **Bag:** Shopping bag icon with small gold badge count + "Bag" label
- **Active State:** Rich gold icon and text with gold underline bar or dot. Inactive state: `#AAA49A`.
- **Rule:** The dock renders on Home, Shop, Orders, Cart, and Live Drop Room (matching reference Screen 03).

---

## 9. Product Card (Screens 01, 02)

- **Geometry:** 2-column mobile grid. Media aspect ratio strictly 3:4.
- **Top Overlays:**
  - Top-Left: Flash code badge (e.g. `#A01`, `#A03`) in dark translucent container with gold border and gold text.
  - Top-Right: Heart outline icon (favorite button, 18px).
- **Body Info:**
  - Product Title: Line-clamp 1, 13px, `#FBFBFB`.
  - Price: Bold 15px `#FBFBFB` (tabular INR formatting: `₹3,100`).
  - Size: 11px muted `#AAA49A` (`Free Size` / `M`).
  - Availability: Subtle green dot (`#10B981`) + "Available" text (11px).
- **Card Action:**
  - Bottom-Right: 36×36px gold button (`#D4AF37`) with black shopping bag icon, rounded 8px.
  - Preserves accessibility `aria-label` and `data-testid="cart-btn-[id]"`.

---

## 10. Buttons

- **Primary CTA:** Background `#D4AF37` (gold), text `#08080A` (deep black), font-sans weight 600, radius 10px–12px, padding 12px 20px. Used for: "Shop Live Drop →", "Show X Pieces →", "Proceed to Checkout →", "Continue to Payment →", "Verify Payment →", "Buy Now →".
- **Secondary CTA:** Background `#16161C`, border 1px `rgba(212, 175, 55, 0.35)`, text `#FBFBFB`, radius 10px–12px. Used for: "Add to Bag", "Filter", "Clear All".
- **Compact Icon Button:** 36×36px or 40×40px, rounded 8px–10px, accessible touch target padding.

---

## 11. Form Inputs

- **Container:** Background `#16161C`, border 1px `rgba(255, 255, 255, 0.1)`, radius 10px, padding 12px 14px, text 14px `#FBFBFB`, placeholder `#AAA49A`.
- **Focus State:** Border 1px `rgba(212, 175, 55, 0.6)`, outline none.
- **Labels:** 12px font-sans weight 500, uppercase or sentence case, `#AAA49A`.
- **Validation Errors:** 11px red `#EF4444` below input with alert role.

---

## 12. Badges & Status Indicators

- **Live Now Badge:** Red dot (`#EF4444`) + "LIVE NOW" text on translucent dark/red pill (`rgba(239, 68, 68, 0.16)`).
- **Available Badge:** Emerald green dot (`#10B981`) + "Available" text (`#10B981`).
- **Reserved Badge:** Amber dot (`#F59E0B`) + "Reserved" text (`#F59E0B`).
- **Sold Out Badge:** Gray dot (`#6B7280`) + "Sold Out" text (`#9CA3AF`).
- **Flash Code Badge:** `#D4AF37` gold monospace text, dark translucent background.

---

## 13. Screen 01 — HOME

- **Structure:**
  1. `LuxuryTopHeader`: Logo monogram + Search + Bag with badge
  2. `Cinematic Live Hero`:
     - Real live drop / verified seller banner
     - Red "● LIVE NOW" badge
     - Serif title ("Festive Silk & Handloom Collection")
     - Boutique name ("Sonali's Boutique")
     - Feature pills ("✦ Live shopping", "✦ Exclusive pieces", "✦ Handpicked")
     - Primary gold CTA: "Shop Live Drop →"
     - Dots indicator "● ○ ○" with counter "1/4"
  3. `Category Discovery Rail`:
     - Yellow square icon for "All"
     - Circular photo avatars for "Sarees", "Kurtis", "Lehengas", "Dupattas", "Jewellery"
  4. `Featured Pieces Section`:
     - Title "Featured Pieces" + "4 pieces available" + "View All →"
     - 2-Column 3:4 product grid
  5. `MobileBottomDock`: Home active

---

## 14. Screen 02 — SHOP / CATALOG

- **Structure:**
  1. `LuxuryTopHeader`
  2. `Breadcrumb`: "Home > Shop Catalog"
  3. `Page Title`: "Boutique Collections" (serif 24px)
  4. `Subtitle`: "Discover handcrafted pieces from verified boutiques."
  5. `Search Input`: Full-width search bar with magnifying glass icon and placeholder "Search collection or flash code (e.g. #A01)..."
  6. `Control Bar`:
     - "Filter" button (with sliders icon, opens Filter Sheet)
     - "Sort: Featured v" dropdown/pill
  7. `Category Chips`: Horizontal scrollable chips ("All" in gold, "Sarees", "Kurtis", "Lehengas", "Dupattas")
  8. `2-Column Product Grid`: Immediate high-density browsing with 3:4 cards
  9. `MobileBottomDock`: Shop active

---

## 15. Screen 03 — LIVE DROP ROOM

- **Structure:**
  1. `Top Bar`: Back button + Boutique avatar + Boutique name ("Sonali's Boutique") + Red "● LIVE" badge (and viewer count if available)
  2. `Immersive Media Viewport`: Video stream / broadcast container
  3. `Floating Right Interactions`: Heart + count, Comments + count, Share
  4. `Live Chat Overlay`: Transparent message bubbles on bottom-left
  5. `Spotlight Product Card`: Compact docked card above chat input with thumbnail, `#A03`, title, price, size, and gold bag button
  6. `Chat Input`: Smiley trigger, "Say something..." input, gold paper-plane send button
  7. `MobileBottomDock`: Live active

---

## 16. Screen 04 — PRODUCT DETAIL

- **Structure:**
  1. `Top Bar`: Back button + Heart outline + Share icon
  2. `Media Section`: Large 3:4 portrait image with "1/5" counter + horizontal 5-thumbnail strip below
  3. `Metadata Row`: Flash code badge ("#A03") on left, "● AVAILABLE" on right
  4. `Title & Pricing`: Serif title ("Handloom Tussar Silk Saree") + "₹3,100" (bold large) + "Free Size" pill
  5. `Description`: Editorial boutique description
  6. `Craftsmanship Attribute Badges`: 4 badges in a row with icons (Handloom, Pure Silk, Single Piece, Festive Wear)
  7. `Collapsible Accordions`:
     - Product Details `>`
     - Atelier Information `>`
     - Delivery & Returns `>`
  8. `Sticky Purchase Bar`:
     - "Add to Bag" (dark with gold border)
     - "Buy Now →" (solid gold)

---

## 17. Screen 05 — FILTERS SHEET

- **Structure:**
  1. Bottom drawer modal with top center drag handle
  2. Header: Close "✕" on left, "Filters" title (serif) in center, "Clear All" (gold link) on right
  3. Filter Sections:
     - **Category:** Chips ("All" active gold, "Sarees", "Kurtis", "Lehengas", "Dupattas", "Jewellery", "Accessories")
     - **Price Range:** Min/Max slider with labels "₹0" and "₹50,000", gold track and thumb
     - **Availability:** Chips ("All" active gold, "Available", "Reserved", "Sold")
     - **Size:** Chips ("Free Size", "XS", "S", "M", "L", "XL", "XXL")
  4. Sticky CTA: "Show [X] Pieces →" (large gold button)

---

## 18. Screen 06 — CART WITH ITEM

- **Structure:**
  1. Header: Back button + "Your Cart (1)" + "Clear" (gold link)
  2. Information Banner: Dark card with gold border and sparkle icon: *"Items are not reserved until checkout. Live drops are single-piece limited editions."*
  3. Item Row: 3:4 thumbnail, title, price, "Size: Free Size • #A03", quantity stepper, trash icon, "Add a note (optional)"
  4. Order Summary: Subtotal, Shipping (FREE), Total
  5. Sticky CTA: "Proceed to Checkout →" (gold button)

---

## 19. Screen 07 — EMPTY CART

- **Structure:**
  1. Header: Back button + "Your Cart"
  2. Illustration: Centered gold shopping bags vector asset with glowing sparkles (no emoji)
  3. Heading: "Your bag is empty" (serif 22px)
  4. Subtitle: "Discover unique pieces from independent boutiques."
  5. CTA: "Explore Shop →" (gold button)

---

## 20. Screen 08 — CHECKOUT

- **Structure:**
  1. Header: Back button + "Checkout"
  2. Step Indicator: "1 Details" (active gold 1), "2 Payment" (2), "3 Confirm" (3) with connecting lines
  3. Delivery Details Form:
     - Full Name input
     - Phone Number input
     - Street Address input
     - 2-Column row: City + PIN Code
  4. Sticky CTA: "Continue to Payment →" (gold button)

---

## 21. Screen 09 — PAYMENT

- **Structure:**
  1. Header: Back button + "Payment"
  2. Amount Display: "Pay ₹3,100" (bold large) + "Scan this QR using any UPI app"
  3. QR Code Container: Clean white square box with live generated UPI QR code
  4. UPI ID Box: "livedrop@upi" (or seller UPI) with "Copy" button
  5. Divider: "────── OR ──────"
  6. UTR Input: Label "Enter UTR / Transaction ID" + input with placeholder "e.g. 123456789012"
  7. Sticky CTA: "Verify Payment →" (gold button)

---

## 22. Screen 10 — ORDERS

- **Structure:**
  1. Header: Back button + "LiveDrop" + Subtitle "ORDERS"
  2. Tabs: "Recent Orders" (active gold underline) and "Saved (3)" (inactive)
  3. Order List Cards:
     - Thumbnail on left
     - Order ID in bold (e.g. `#LD2FA77E`), Boutique name, Total amount
     - Status Badge: "Order Placed" (gold), "Payment Verified" (green), "In Preparation" (amber)
     - Token-safe receipt navigation

---

## 23. Screen 11 — ORDER TRACKING

- **Structure:**
  1. Header: Back button + "Track Your Order" + Subtitle "#LD2FA77E • Independent Boutique"
  2. Reserved Item Summary: Thumbnail, title, price, size
  3. Vertical Timeline:
     - Step 1: Payment Verified (gold checkmark circle, timestamp)
     - Step 2: In Preparation (active gold pulsing circle, "Being packed by the boutique")
     - Step 3: Shipped (gray circle, "Tracking details will be shared soon")
     - Step 4: Out for Delivery (gray circle)
     - Step 5: Delivered (gray circle)

---

## 24. Responsive Rules

1. **Mobile First:** All layouts, typography, and card proportions are designed and optimized for mobile viewports (390×844 primary; 360×800 to 430×932 secondary).
2. **Fluid Adaptability:**
   - 2-column mobile product grid shifts to 3 columns on tablet (min-width: 768px) and 4 columns on desktop (min-width: 1024px).
   - Drawers and sheets render as bottom sheets on mobile (`max-h-[90vh]`) and centered dialogs on desktop (`max-w-lg`).
   - Sticky action bars are anchored to the bottom viewport with safe-area padding on mobile, and centered inside the container on desktop.
3. **No Horizontal Overflow:** All containers enforce `max-w-full overflow-x-hidden` or `overflow-x-clip`.
