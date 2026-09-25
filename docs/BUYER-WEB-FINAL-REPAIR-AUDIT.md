# LiveDrop — Final Buyer Website Production Repair & Root Cause Audit

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-26  
**Governing Documents:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md), [`docs/03-ui-ux-specification.md`](file:///c:/LiveDrop/docs/03-ui-ux-specification.md), [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)  
**Status:** Audit & Diagnostic Baseline (Phase 1 Deliverable — No Code Modifications)

---

## Executive Summary

This document performs an exhaustive, component-by-component, architectural, and data-flow audit of the LiveDrop buyer web application (`buyer-web`). It directly incorporates the visual and operational defects evidenced in the live deployment screenshots (`livedrop-in.vercel.app`), browser device emulations, and PostgreSQL/PostgREST database queries.

The primary finding is that the buyer web application has suffered from an accumulation of experimental UI paradigms, CSS bloat, and most critically: **a total absence of legitimate published staging/production products in the database coupled with an over-broad string-matching blacklist**, which caused the entire buyer storefront to collapse into empty states ("0 pieces available"), while the cart retained invalid test images and a confusing ₹0 checkout state.

---

## A. Current Visual Architecture

The buyer web application currently structures its screens and layouts through the following components:

| Feature / Region | Current Controlling Component(s) | File Path | Architectural Role & Responsibilities |
|---|---|---|---|
| **Header** | `LuxuryTopHeader` | [`buyer-web/src/components/navigation/LuxuryTopHeader.tsx`](file:///c:/LiveDrop/buyer-web/src/components/navigation/LuxuryTopHeader.tsx) | Sticky scroll-reactive header (64–72px height target); displays LiveDrop crest logo (`✦`), subtitle ("INDIAN LUXURY LIVE"), search expansion toggle, and shopping bag button with count badge. |
| **Hero** | `HomeStorefront` (inline `<section aria-label="LiveDrop Spotlight Hero">`) | [`buyer-web/src/components/HomeStorefront.tsx`](file:///c:/LiveDrop/buyer-web/src/components/HomeStorefront.tsx#L177-L250) | Renders either active live drop banner (State 1: `● LIVE NOW` with boutique name, drop title, and "Shop Live Drop" button) or calm fallback (State 2: "BOUTIQUE COMMERCE", "No Live Drop Right Now", "Explore Collections"). |
| **Categories** | `HomeStorefront` (`CATEGORY_CHIPS` rail) & `ShopCategoryDirectory` (`CATEGORY_TABS`) | [`buyer-web/src/components/HomeStorefront.tsx`](file:///c:/LiveDrop/buyer-web/src/components/HomeStorefront.tsx#L253-L281), [`buyer-web/src/components/shop/ShopCategoryDirectory.tsx`](file:///c:/LiveDrop/buyer-web/src/components/shop/ShopCategoryDirectory.tsx#L136-L157) | Horizontal scrolling pill/chip list (`All`, `Sarees`, `Kurtis`, `Lehengas`, `Dupattas`, `Jewelry`, `Accessories`). Currently in normal document flow on homepage. |
| **Products** | `ProductCard`, `ProductDetailModal`, `ProductSection` | [`buyer-web/src/components/ProductCard.tsx`](file:///c:/LiveDrop/buyer-web/src/components/ProductCard.tsx), [`buyer-web/src/components/ProductDetailModal.tsx`](file:///c:/LiveDrop/buyer-web/src/components/ProductDetailModal.tsx) | 2-column mobile / 4-column desktop product grid (`.ld-product-grid`). Product card displays 1:1 image/carousel, flash code badge (`#A01`), availability badge (`AVAILABLE`, `RESERVED`, `SOLD OUT`), title, size, integer-Paisa price formatted to INR, and add-to-bag action. |
| **Boutiques** | `HomeStorefront` (`<section id="boutiques">`) & `ShopCategoryDirectory` | [`buyer-web/src/components/HomeStorefront.tsx`](file:///c:/LiveDrop/buyer-web/src/components/HomeStorefront.tsx#L387-L454), [`buyer-web/src/components/shop/ShopCategoryDirectory.tsx`](file:///c:/LiveDrop/buyer-web/src/components/shop/ShopCategoryDirectory.tsx#L200-L235) | Horizontal discovery rail on mobile, 2/3 column grid on desktop. Displays avatar letter monogram, store name, verified checkmark (`✓`), boutique sublabel, "Visit →" link, and direct WhatsApp concierge trigger. |
| **Footer** | `HomeStorefront` (inline `<footer>`) & `BoutiqueStorefrontView` | [`buyer-web/src/components/HomeStorefront.tsx`](file:///c:/LiveDrop/buyer-web/src/components/HomeStorefront.tsx#L471-L476) | Compact text footer with LiveDrop branding, Indian fashion live-commerce tagline, and copyright year. |
| **Mobile Navigation** | `MobileBottomDock` | [`buyer-web/src/components/navigation/MobileBottomDock.tsx`](file:///c:/LiveDrop/buyer-web/src/components/navigation/MobileBottomDock.tsx) | 5-tab fixed dock at screen bottom: `Home`, `Live` (hash link `#live-drops`), `Shop` (`/shop`), `Orders` (`/order`), `Bag` (triggers `CartDrawer` or links to `/cart`). Height ~60px + `env(safe-area-inset-bottom)`. |
| **Shop Catalog** | `ShopCategoryDirectory`, `app/shop/page.tsx` | [`buyer-web/src/app/shop/page.tsx`](file:///c:/LiveDrop/buyer-web/src/app/shop/page.tsx), [`buyer-web/src/components/shop/ShopCategoryDirectory.tsx`](file:///c:/LiveDrop/buyer-web/src/components/shop/ShopCategoryDirectory.tsx) | Standalone catalog page with breadcrumbs, title, category filter tabs, sort dropdown (`Featured`, `Price: Low to High`, `Price: High to Low`), product grid, and verified boutique discovery. |
| **Cart** | `CartDrawer`, `CartItemRow`, `CartEmptyState`, `app/cart/page.tsx` | [`buyer-web/src/components/cart/CartDrawer.tsx`](file:///c:/LiveDrop/buyer-web/src/components/cart/CartDrawer.tsx), [`buyer-web/src/app/cart/page.tsx`](file:///c:/LiveDrop/buyer-web/src/app/cart/page.tsx) | Slide-over drawer modal and dedicated `/cart` page. Reconciles items against catalog stock, computes subtotal and shipping in integer Paisa, renders optional order notes, and transitions to `/checkout`. |

---

## B. Current Design Systems & CSS Audit

An inspection of [`buyer-web/src/app/globals.css`](file:///c:/LiveDrop/buyer-web/src/app/globals.css) (5,034 lines) and Tailwind configuration reveals multiple generations of overlapping styling:

### 1. Duplicate & Conflicting Color Tokens
* **Gold Tokens:** Three overlapping gold systems exist simultaneously:
  - Canonical tokens: `--ld-gold: #C79A45`, `--ld-gold-soft: #E2C27A`
  - Legacy luxury tokens: `--champagne-gold: var(--ld-gold)`, `--champagne-muted: rgba(199, 154, 69, 0.16)`
  - Legacy boutique tokens: `--gold-primary: var(--ld-gold)`, `--gold-secondary: #B58632`, `--gold-light: var(--ld-gold-soft)`
  - Hardcoded gradient definitions in components (`from-[#E2C27A] via-[#C79A45] to-[#B58632]`, `from-[#F5D78E] via-[#D4AF37] to-[#C88A24]`, `linear-gradient(135deg, #F5D78E 0%, #D4AF37 50%, #8C5E13 100%)`).
* **Background & Surface Tokens:**
  - Canonical: `--ld-bg: #090909`, `--ld-surface: #121211`, `--ld-surface-2: #181715`
  - Legacy aliases: `--noir-black`, `--noir-card`, `--noir-elevated`, `--obsidian`, `--obsidian-surface`, `--obsidian-elevated`, `--bg-page`, `--surface-card`, `--surface-elevated`
  - Inline Tailwind mixing: `bg-[#090909]`, `bg-[#121211]`, `bg-[#08080A]`, `bg-[#101014]`, `bg-black/70`.

### 2. Dead & Obsolete Systems in `globals.css`
* **Story Circle System:** Lines 200–246 define `.ld-story-circle-item`, `.ld-story-circle-avatar`, `.ld-story-circle-inner`, `.ld-story-circle-label`. These were removed from the homepage in favor of the horizontal category rail, but the CSS classes remain.
* **Legacy Navigation Classes:** Both `.ld-navbar` (from pre-v1 navigation) and `.ld-luxury-header` exist.
* **Bottom Sheet / Modal Duplication:** `.ld-sheet-*` classes (lines 1900–2100) duplicate modal logic handled by `ProductDetailModal` and `CartDrawer`.
* **Sticky Cart Styles:** Multiple variations of sticky checkout bars (`.ld-sticky-cart-bar`, `.ld-floating-checkout-bar`, `.ld-cart-dock`) coexist.

### 3. Inline Tailwind vs Global CSS Conflicts
* Components use hardcoded Tailwind utility classes (e.g. `bg-[#090909] text-[#F4F1EA] font-sans`) right alongside custom `.ld-*` class names (`ld-product-card`, `ld-luxury-header`, `ld-bottom-dock`), leading to CSS specificity ambiguities and unnecessary bundle size.

---

## C. Current Data Flow & End-to-End Pipeline

The live data flow from Supabase down to the rendered browser DOM follows this trace:

```
┌────────────────────────────────────────────────────────────────────────┐
│                          1. SUPABASE DATABASE                          │
│  Tables: profiles, drops, products, orders, order_items                │
│  Views: public_products_catalog, public_seller_storefronts             │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   2. BUYER DATA LAYER (buyer-catalog.ts)               │
│  getLiveDropBySlug()                                                   │
│  getAllActiveLiveDrops()                                               │
│  getAllVerifiedStorefronts()                                           │
│  getFeaturedProducts() / getAllProducts()                              │
│  createOrderWithReservation() [RPC]                                    │
│  getOrderByToken() [RPC]                                               │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 3. SERVER COMPONENT PAGES (Next.js SSR)                │
│  app/page.tsx (Home) ──> getFeaturedProducts(), getAllActiveLiveDrops()│
│  app/shop/page.tsx ────> getAllProducts({ limit: 80 })                 │
│  app/drop/[slug]/page.tsx ─> getLiveDropBySlug(), getPublicProducts()  │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                 4. CLIENT COMPONENT STOREFRONTS & UI                   │
│  HomeStorefront ───────> filterProductionStorefronts()                 │
│  ShopCategoryDirectory ─> filterProductionProducts()                   │
│  ProductCard ──────────> formatPaisaToINR(), Image with Fallback       │
│  CartContext ──────────> getReconciledItems(), Subtotal in Paisa       │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          5. VISIBLE BUYER UI                           │
│  Rendered DOM: Clean Indian Boutique Fashion & Live Commerce           │
└────────────────────────────────────────────────────────────────────────┘
```

### Specific Data Entity Tracing:

1. **Drops:**
   - Database: `drops` table filtered by `status = 'live'` (or `status = 'closed'` with available items).
   - View: `public_products_catalog` joins `products`, `drops`, and `profiles`.
   - Data Layer: `getAllActiveLiveDrops()` fetches live drops where `profiles.is_approved = true`.
   - Page: `app/page.tsx` retrieves active drops and passes them to `HomeStorefront`.
   - UI: If an active drop exists, `HomeStorefront` renders the `● LIVE NOW` hero. If zero active drops exist, it renders the concise `No Live Drop Right Now` atmosphere card.

2. **Products:**
   - Database: `products` table (`id`, `drop_id`, `code`, `title`, `price_paisa`, `size`, `image_url`, `image_urls`, `status`).
   - View: `public_products_catalog` filters `d.status IN ('live', 'closed') AND pr.is_approved = TRUE AND (d.status = 'live' OR p.status = 'available')`.
   - Data Layer: `getFeaturedProducts()` and `getAllProducts()` query `public_products_catalog`.
   - Hygiene Filter: `filterProductionProducts()` runs `isLegitimateProduct()` checks.
   - UI: `ProductCard` renders image, flash code `#A01`, price, status, and add-to-bag button.

3. **Storefronts:**
   - Database: `public_seller_storefronts` view projecting approved seller profile details (`store_name`, `store_slug`, `phone_number`, `upi_vpa`, `default_shipping_fee_paisa`, etc.).
   - Data Layer: `getAllVerifiedStorefronts()` queries `public_seller_storefronts` and runs `filterProductionStorefronts()`.
   - UI: `HomeStorefront` and `ShopCategoryDirectory` render the boutique discovery cards with store name, avatar initial, and WhatsApp action.

4. **Images:**
   - Ingestion: Seller uploads via Flutter seller app (`SellerRepository.uploadProductImage`) to Supabase Storage bucket `product-images/{seller_id}/{drop_id}/{filename}`.
   - Database: URL stored in `products.image_url` and `products.image_urls`.
   - Buyer UI: `ProductCard` renders `<img>` with `onError` fallback to branded crest placeholder (`✦ LiveDrop #A01`).

5. **Availability & Realtime:**
   - Statuses: `'available'`, `'reserved'`, `'sold'`.
   - Reservation: Mediated exclusively by database RPC `create_order_with_reservation` which updates status atomically.
   - Cart Reconciliation: `useCart.getReconciledItems()` cross-checks local cart items against latest catalog status. If an item is reserved or sold, it flags `isAvailable: false`.

6. **Cart & Orders:**
   - Cart state: Local storage synchronized in `CartContext`.
   - Total Calculation: Authoritative integer Paisa computation in `payableSubtotalPaisa` derived strictly from items where `isAvailable === true`.
   - Checkout: Calls `create_order_with_reservation` RPC with `p_product_ids`. Returns token-gated `order_token` and `order_id`.
   - Payment: Token-gated `initiate_payment_attempt` and `submit_buyer_payment_claim` RPCs record UTR for seller verification.

---

## D. Current Problems & Root Cause Analysis

Every item called out in the specification has been inspected and verified against the live environment and codebase:

### 1. Empty Catalog Caused by Over-Filtering & Absence of Legitimate Staging Data (CRITICAL)
* **Symptom:** The live buyer site currently displays "0 pieces available", "New collection pieces dropping soon from verified boutiques", and "No pieces found" on `/shop`.
* **Root Cause:** A direct query against Supabase reveals that all 20 existing products in `public_products_catalog` are automated race-test fixtures (`#R1816`, `#R2754`, `Concurrent Race Piece #...`) or early test submissions (`djsjd`, `shejdh`, `Drop`). The blacklist filter in `isLegitimateProduct()` correctly flags all 20 of these as non-production, leaving **0 products**.
* **Resolution:** In accordance with the prompt mandate, we must not rely indefinitely on string blacklists. We need to create a legitimate boutique storefront and drop with authentic Indian garment items (sarees, kurtis, lehengas) and genuine image URLs, while establishing clean database criteria (e.g. approved seller drop with legitimate inventory) so that legitimate items are displayed and test fixtures are cleanly separated.

### 2. Confusing Cart State When Items Become Sold Out (CRITICAL)
* **Symptom:** As seen in `media_1790367978839.png`, when a cart contains an item that has become sold out (`#A02 djsjd` SOLD OUT), the cart displays:
  - Red notice: *"One or more items in your cart were claimed offline or by another buyer. Please remove them to proceed."*
  - The sold-out item card with a trash icon.
  - An **Order Summary** showing:
    - Subtotal: `₹0`
    - Shipping: `₹0`
    - Total: `₹0`
  - A giant disabled button: `PROCEED TO CHECKOUT →`.
* **Root Cause:** In [`CartDrawer.tsx`](file:///c:/LiveDrop/buyer-web/src/components/cart/CartDrawer.tsx#L257-L298) and [`app/cart/page.tsx`](file:///c:/LiveDrop/buyer-web/src/app/cart/page.tsx#L228-L270), the component checks `if (items.length === 0)` to show `CartEmptyState`. When `items.length > 0` but `availableItems.length === 0`, it still renders the entire Order Summary with ₹0 and the disabled checkout CTA.
* **Resolution:** When `items.length > 0` but `availableItems.length === 0`:
  1. Clearly display the unavailable item alert and the item row with an explicit "Remove" or "Remove Unavailable Item" action.
  2. **Do NOT render the ₹0 Order Summary** or the disabled checkout button.
  3. Instead, render a clean call-to-action: *"Your bag has no available pieces remaining."* with a prominent `[ Continue Shopping ]` button. Once the buyer removes the item, the drawer immediately reflects the standard `CartEmptyState`.

### 3. Unsupported Trust Claims in Cart
* **Symptom:** In earlier iterations (as shown in `media_1790363591538.jpg`), the cart rendered icons for:
  - `100% AUTHENTIC`
  - `INSURED DELIVERY`
  - `EASY RETURNS`
* **Root Cause:** Hardcoded decorative badges in `CartDrawer.tsx` that made claims LiveDrop's operational model does not guarantee (independent boutiques manage their own stock and fulfillment; returns are policy-dependent).
* **Status:** These badges were pruned from the current `CartDrawer.tsx` and must never be reintroduced. Only truthful, platform-verified assurances ("Direct UPI", "Instant Reservation", "Independent Boutiques") are permitted.

### 4. Excessive Hero Height on Mobile
* **Symptom:** Hero banner occupied near full-screen viewport height, pushing products off-screen.
* **Root Cause:** Previous height was `h-[420px]` to `h-[520px]`.
* **Status in Code:** In [`HomeStorefront.tsx`](file:///c:/LiveDrop/buyer-web/src/components/HomeStorefront.tsx#L178), it has been adjusted to `h-[280px] sm:h-[320px] md:h-[360px]`. We must verify that no extra vertical padding or margin expands this in the rendered DOM.

### 5. Sticky Category Rail Overlap
* **Symptom:** In `media_1790363587805.jpg` and `media_1790363594670.jpg`, the category chip bar was fixed/sticky (`sticky top-16`), floating over the product titles and boutique list when the user scrolled.
* **Root Cause:** A `sticky top-16` or `sticky top-14` class on the category `<section>` collided with `LuxuryTopHeader` during scroll transitions.
* **Status in Code:** Category rail was removed from sticky positioning and placed in normal document flow (`px-4 sm:px-8 py-3.5 border-b border-white/5 bg-[#121211]`). Must be maintained in normal flow permanently.

### 6. Bottom Navigation Collision & Safe-Area Clearance
* **Symptom:** Fixed bottom dock (`MobileBottomDock`) overlaying or clipping the footer and last product cards on small mobile viewports (e.g. 360×800, 375×812).
* **Root Cause:** Layout containers lacked measured bottom padding accommodating `60px` dock height plus `env(safe-area-inset-bottom)`.
* **Status:** `.ld-has-bottom-dock` class adds `padding-bottom: calc(72px + env(safe-area-inset-bottom, 0px))`. Must ensure all pages (`/`, `/shop`, `/cart`, `/[slug]`) include this container class.

### 7. Internal Storefront Slugs Shown to Buyers
* **Symptom:** As seen in `media_1790363587805.jpg`, boutique cards explicitly rendered `/suv-s`, `/suvraneel-boutique`, and `/livedrop-staging-boutique` in monospace under the boutique title.
* **Root Cause:** Decorative subtitle in `BoutiqueCard` rendered `/{storefront.store_slug}`.
* **Status in Code:** In [`HomeStorefront.tsx`](file:///c:/LiveDrop/buyer-web/src/components/HomeStorefront.tsx#L423-L425), the slug display was replaced with the clean semantic label `Independent Atelier`.

### 8. Oversized Product Cards & Excessive Card Height
* **Symptom:** Product cards were excessively tall due to full-width "Add to Bag" buttons, multiple stacked badges, and large title line clamps.
* **Resolution:** Product card density must remain compact:
  - 1:1 image thumbnail dominating the card.
  - Compact top-left flash code `#A01` and top-right status pill (`AVAILABLE`, `RESERVED`, `SOLD OUT`).
  - Single-line code & size row (`#A01 • Size M`).
  - Max 2-line title.
  - Bottom row with price in INR integer format and a compact icon-based cart button (`[🛒 +]` / `[✓ In Cart]`).

### 9. Broken Image URLs & Fallback Layout Collapse
* **Symptom:** If a product image URL was invalid or failed to load (e.g., `https://example.com/test.jpg`), the card previously displayed a broken image icon or black void.
* **Status in Code:** [`ProductCard.tsx`](file:///c:/LiveDrop/buyer-web/src/components/ProductCard.tsx#L106-L114) includes `onError` state tracking and renders `.ld-image-fallback` with the LiveDrop brand crest (`✦ LiveDrop #A01`). The fallback must maintain the 1:1 aspect ratio and dark neutral surface without layout shifting.

### 10. Excessive Gold & Visual Noise
* **Symptom:** Early versions featured gold borders on every card, gold text for all subtitles, glowing halos, and serif fonts on every UI micro-label.
* **Consolidation Direction:**
  - Background: Deep Charcoal / Black (`#090909`).
  - Surface: Subtle low-contrast cards (`#121211`, `#181715`).
  - Primary Typography: Ivory (`#F4F1EA`).
  - Secondary Typography: Muted Sand (`#AAA49A`).
  - Gold (`#C79A45`, `#E2C27A`): Strictly an accent reserved for primary CTAs, price highlights, active navigation state, and the brand crest.
  - Serif font (`Cormorant Garamond`): Reserved for brand title, hero headline, and major section titles. Sans font (`Plus Jakarta Sans`) for all operational UI, titles, codes, prices, and forms.

---

## E. Architectural Safety & Compliance Verification

| Guardrail (from `AGENTS.md`) | Compliance Audit Status |
|---|---|
| **NO Requirement Invention** | Verified. No wishlist, buyer account dashboard, reviews, social feeds, or fake stats added. |
| **NO Weakening of RLS / Security** | Verified. All catalog queries read from `public_products_catalog` view with RLS preserved. |
| **NO Service-Role Credential Leakage** | Verified. Only `NEXT_PUBLIC_SUPABASE_ANON_KEY` is referenced in client bundles. |
| **NO Client-Only Validation** | Verified. Order reservations, item availability, and total amounts are enforced by server RPCs. |
| **NO Floating-Point Currency** | Verified. All monetary values are integer Paisa (`formatPaisaToINR`). |
| **NO Direct UI Database Mutations** | Verified. Orders are placed strictly via `create_order_with_reservation` RPC. |

---

## F. Implementation Plan & Sequenced Milestones

Now that this audit is complete, the repair proceeds strictly through the designated phases:

1. **Phase 2 — Catalog Data & Staging Ingestion Correctness:**
   - Create one legitimate boutique storefront ("Aheli Heritage") with an authentic live drop and genuine Indian garments (sarees, kurtis) using real photography in Supabase Storage.
   - Verify that `public_products_catalog` projects these items and `filterProductionProducts` accepts them, populating the buyer homepage and `/shop` with authentic commerce inventory.
2. **Phase 3 — Cart UX State Repair:**
   - Update [`CartDrawer.tsx`](file:///c:/LiveDrop/buyer-web/src/components/cart/CartDrawer.tsx) and [`app/cart/page.tsx`](file:///c:/LiveDrop/buyer-web/src/app/cart/page.tsx): When all items in the cart are unavailable, hide the ₹0 summary and disabled button; show clear removal action and empty state CTA (`Continue Shopping`).
3. **Phase 4 — Design System & CSS Consolidation:**
   - Clean up [`globals.css`](file:///c:/LiveDrop/buyer-web/src/app/globals.css), removing dead story circle classes, legacy navbar classes, and duplicate token definitions into one cohesive design system.
4. **Phase 5 — Layout & Header/Nav Polish:**
   - Verify header height (64–72px), compact hero (280–320px), normal flow category rail, and bottom dock clearance.
5. **Phase 6 — Testing & Browser Device QA:**
   - Execute TypeScript typecheck, ESLint, Vitest test suite, Next.js production build, and multi-viewport Playwright browser screenshots.
6. **Phase 7 — Final Reporting:**
   - Produce `docs/BUYER-WEB-FINAL-IMPLEMENTATION-REPORT.md`.
