# Implementation Plan — LiveDrop Final Buyer UI Refinement & UX Freeze

**Goal:** Make 7 precise, high-impact UX and visual corrections to the existing LiveDrop buyer website to eliminate repetition, reduce cognitive load, elevate product-first hierarchy, and freeze the buyer UI for launch.

**Architecture & Baseline:**
- **Theme Baseline:** Frozen black/charcoal (`#090909`, `#121211`) + ivory typography (`#F4F1EA`, `#AAA49A`) + restrained gold accents (`#C79A45`, `#E2C27A`) + red live indicators (`#E5484D`).
- **Data Flow Authority:** Supabase RPCs (`get_all_active_live_drops`, `get_featured_products`, `get_all_verified_storefronts`, `create_order_with_reservation`, `get_order_by_token`) remain the authoritative backend foundation. Integer Paisa calculations are preserved. Token verification is never bypassed.
- **Tech Stack:** Next.js 16 (App Router), React 19, TypeScript 5, Tailwind CSS v4 / Vanilla CSS design tokens in `globals.css`, Vitest, Playwright.

---

## 7 Core Targeted Changes

### 1. Remove Duplicate Large Live Drop Section
- **File**: `buyer-web/src/components/HomeStorefront.tsx`
- Eliminate duplicate `<section id="live-drops">` below categories.
- Assign `id="live-drops"` to the Hero spotlight section so navigation anchors directly to the live hero.
- Immediate next major section after Category Rail is `Featured Pieces` (`#featured-products`).
- Data strictly reflects backend state (`primaryLiveDrop.title`, `primaryLiveDrop.profiles?.store_name`).

### 2. Compact Mobile Hero Height & Content
- **File**: `buyer-web/src/components/HomeStorefront.tsx`
- Target mobile height: 280–320px for standard phones (`h-[280px] sm:h-[310px] md:h-[360px]`).
- Clean, concise content: `● LIVE NOW` + Drop Title + Boutique Attribution + `[ Shop Live Drop → ]`.
- Above the fold at 390×844: Header + Hero + Categories + top of Featured Pieces.

### 3. Product Card Refinement & Badge Noise Reduction
- **Files**: `buyer-web/src/components/ProductCard.tsx`, `buyer-web/src/app/globals.css`
- Image overlay: Keep only `#A04` flash code on top-left. Remove large green `AVAILABLE` badge overlay from image.
- Card body: Remove redundant `#A04` code from below the image.
- Title: Update clamp from 1 line to 2 lines (`-webkit-line-clamp: 2; line-clamp: 2; height: 36px;`).
- Availability & Size: Restrained indicator below image (`data-testid="status-badge-${product.id}"`).
- Prominent price and compact bag action button.
- Consistent 1:1 aspect ratio media container.

### 4. Live Boutiques Horizontal Mobile Rail
- **File**: `buyer-web/src/components/HomeStorefront.tsx`
- Mobile: Horizontal scroll-snap rail (`overflow-x: auto; scroll-snap-type: x mandatory`).
- Clean card hierarchy: Boutique Name, "Independent Boutique", `LIVE` badge strictly if active live drop, `Visit →`.
- Page itself has no horizontal overflow (`document.documentElement.scrollWidth <= window.innerWidth`).

### 5. Redesign Order Lookup UX (Buyer Mental Model)
- **Files**: `buyer-web/src/app/order/page.tsx`, `buyer-web/src/lib/cart/cart-storage.ts`, `buyer-web/src/app/checkout/page.tsx`
- Remove implementation jargon ("UUID", "Security Token") from buyer UI.
- Recent Orders on this device displayed prominently with order code, boutique, amount, status, and direct `View Receipt →` link.
- Manual lookup provides intuitive "Order Number or Link" input.
- Backend token verification remains 100% strictly enforced.

### 6. Simplify Empty Cart
- **Files**: `buyer-web/src/components/cart/CartEmptyState.tsx`, `buyer-web/src/app/cart/page.tsx`, `buyer-web/src/components/cart/CartDrawer.tsx`
- Visually centered in usable content area (`🛍 Your bag is empty / Discover unique pieces from independent boutiques / [ Explore Shop ]`).
- Wire `onBrowse={() => router.push('/shop')}` in both full page and drawer.

### 7. Simplify Unavailable Cart State
- **Files**: `buyer-web/src/app/cart/page.tsx`, `buyer-web/src/components/cart/CartDrawer.tsx`
- All items unavailable: Suppress yellow notice; show one clean alert with item row + `[ Remove ]`, followed by "No available pieces remain in your bag. [ Explore Collections → ]"; remove disabled checkout button.
- Partial availability: Clean indicator "N items available · M unavailable" with `[ Remove unavailable ]` action; checkout CTA reflects valid items.

---

## Verification & QA
1. Automated tests:
   ```bash
   npm --prefix buyer-web run typecheck
   npm --prefix buyer-web run lint
   npm --prefix buyer-web test
   npm --prefix buyer-web run build
   ```
2. Responsive checks across all 9 target viewports (360×800 to 1920×1080).
3. Generate final freeze report at `docs/BUYER-WEB-FINAL-UI-FREEZE-REPORT.md`.
