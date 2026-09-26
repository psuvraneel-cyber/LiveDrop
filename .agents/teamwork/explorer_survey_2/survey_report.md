# Survey & Forensic Audit Report: Screens 01–05 (Phases C, D, E, F)
**Author:** Explorer 2 (Teamwork Explorer Agent)  
**Date:** 2026-09-27  
**Scope:** Buyer Webfront Visual Reconstruction (Home Storefront, Shop Directory, Live Drop Room, Product Detail, and Filter Sheet)  
**Reference Design Specification:** `docs/BUYER-REFERENCE-DESIGN-SPEC.md` & `media_1790450082820.jpg`  
**Governing Documents:** `AGENTS.md`, `docs/SOURCE-OF-TRUTH.md`, `docs/07-functional-specification.md`

---

## 1. Executive Summary & Baseline System Health

A comprehensive read-only survey of the LiveDrop buyer web application (`buyer-web`) was conducted to evaluate existing components, routes, data flows, and state management hooks supporting **Phases C, D, E, and F** (Screens 01 through 05 of the reference design).

### Current Codebase Baseline Health:
- **Test Suite (`npm --prefix buyer-web test`):** **31 test files passed, 474 tests passed, 0 failures**.
- **Type Checking (`npm --prefix buyer-web run typecheck`):** **Exit code 0** (clean, zero TypeScript diagnostics).
- **Core Architecture Compliance:** Integer Paisa currency modeling is strictly maintained; PostgreSQL RLS policies and atomic RPCs (`create_order_with_reservation`, `get_order_by_token`, `initiate_payment_attempt`, `submit_buyer_payment_claim`) remain intact.

### Key Visual & Component Findings:
1. **Screen 01 (Home Storefront):** Solid functional base in `HomeStorefront.tsx`, but visual presentation requires alignment with Screen 01: category rail is currently flat pill buttons instead of the required **square gold "All" card + circular photo avatars**; hero lacks feature pills ("✦ Live shopping", etc.) and pagination dots ("● ○ ○ 1/4"); product cards lack top-right heart favorite buttons; mobile cart button is 44×44px rather than 36×36px.
2. **Screen 02 & 05 (Shop Directory & Filter Sheet):** `ShopCategoryDirectory.tsx` exists with basic category tabs and sort select, but **`FilterSheet.tsx` does NOT exist**. The control bar lacks the dedicated "Filter" button with sliders icon to trigger the bottom sheet.
3. **Screen 03 (Live Drop Room):** `CinematicLiveRoomView.tsx` provides video streaming and pinned product support, but **does not render `MobileBottomDock`** (in fact, `MobileBottomDock.tsx` explicitly suppresses itself on `/drop/*`). Furthermore, Screen 03's bottom chat input bar is completely missing.
4. **Screen 04 (Product Detail):** Two competing components exist: `ProductDetailModal.tsx` and `ProductQuickViewDrawer.tsx`. Neither currently satisfies the full Screen 04 reference: image frame is set to 1:1 instead of 3:4 portrait; missing image counter badge ("1/5"); missing the 4 craftsmanship attribute badges; missing 3 expandable details accordions; and lacks dual sticky buttons in `ProductQuickViewDrawer`.

---

## 2. Component Survey: Screen 01 — Home Storefront

### 2.1 File Locations & Routes
- **Route:** `buyer-web/src/app/page.tsx` (Server Component)
  - Fetches `getAllActiveLiveDrops`, `getAllVerifiedStorefronts`, and `getFeaturedProducts(client, 12)` via `buyer-catalog.ts`.
- **Client Component:** `buyer-web/src/components/HomeStorefront.tsx`
- **Sub-components:**
  - `buyer-web/src/components/navigation/LuxuryTopHeader.tsx` (wraps `GlobalBuyerHeader.tsx`)
  - `buyer-web/src/components/ProductCard.tsx`
  - `buyer-web/src/components/navigation/MobileBottomDock.tsx`

### 2.2 Props & State Contracts
```typescript
export interface HomeStorefrontProps {
  activeDrops?: PublicDropCatalog[];
  storefronts?: PublicSellerStorefront[];
  featuredProducts?: PublicProductView[];
  initialLiveDrop?: PublicDropCatalog | null;
  initialProducts?: PublicProductView[];
  recentDrops?: PublicDropCatalog[];
}
```
- **State Hooks:**
  - `searchQuery` (`useState<string>('')`)
  - `selectedCategory` (`useState<string>('all')`)
  - Memoized filters: `resolvedActiveDrops`, `resolvedStorefronts`, `filteredStorefronts`, `filteredActiveDrops`, `allAvailableProducts`, `displayedProducts`.

### 2.3 Visual & Functional Comparison against Spec (Screen 01)

| Element / Feature | Reference Spec (Screen 01) | Existing Implementation | Gap / Action Needed |
|---|---|---|---|
| **Top Header** | 56px height, crest `✦`, brand serif "LiveDrop", subtitle "INDIAN LUXURY LIVE", search & bag icons with gold count badge | Rendered via `LuxuryTopHeader` (`GlobalBuyerHeader variant="storefront"`) | Aligned. Fully supports search expand and bag badge. |
| **Hero Live Badge** | Red pill `● LIVE NOW` with pulsing dot | Present on `live-drop-hero` | Aligned. |
| **Hero Title & Boutique** | Serif title ("Festive Silk & Handloom Collection") + Boutique name ("Sonali's Boutique") | Serif `h1` with drop title + boutique name | Aligned when drop is active; when no drop, displays "NO LIVE DROP" in large serif. Should feature curated editorial messaging. |
| **Hero Feature Pills** | 3 pill tags: "✦ Live shopping", "✦ Exclusive pieces", "✦ Handpicked" | Not present | **GAP:** Add horizontal feature pills below boutique title. |
| **Hero Pagination / Dots** | Carousel indicators: dots "● ○ ○" and count badge "1/4" | Not present | **GAP:** Add dots indicator and slide count badge. |
| **Category Rail** | **Square gold "All" card** (60×60px, rounded 12px, gold background/border, sparkle/grid icon) + **Circular photo avatars** (52×52px, circular `rounded-full` image preview) for "Sarees", "Kurtis", "Lehengas", "Dupattas", "Jewellery" with text label below | Horizontal scroll of plain pill buttons (`px-3.5 py-1.5 rounded-full`) | **MAJOR GAP:** Replace generic pill buttons with Square gold "All" card followed by circular avatar category items with labels below. |
| **Featured Pieces Header** | "Featured Pieces" + "4 pieces available" + "View All →" | Title + `{displayedProducts.length} pieces available` + `View All →` | Aligned. |
| **Product Card Grid** | 2-column mobile grid, 3:4 portrait aspect ratio cards | `.ld-product-grid` with `ProductCard` (2-col mobile, 3:4 ratio via `.ld-card-media`) | Grid structure aligned. |
| **Product Card Overlays** | Top-left flash code badge (`#A01`) + top-right heart favorite icon (18px) | Top-left `.ld-flash-badge` present; heart outline icon missing | **GAP:** Add top-right favorite heart button to `ProductCard.tsx`. |
| **Product Card Price & Size** | Price in Paisa formatted (₹3,100), Size ("Free Size" / "M"), status dot ("● Available") | Price formatted via `formatPaisaToINR`, size and status text present | Aligned. |
| **Product Card Action Button** | 36×36px gold button (`#D4AF37`) with black shopping bag icon, rounded 8px | `.ld-btn-add-cart-compact` in `globals.css` is styled at 44×44px on mobile | **GAP:** Refine mobile CSS to exact 36×36px, radius 8px, `#D4AF37`. |
| **Bottom Dock** | `MobileBottomDock` with "Home" tab active | Present at bottom with `ld-dock-tab.active` | Aligned. |

---

## 3. Component Survey: Screens 02 & 05 — Shop Directory & Filter Sheet

### 3.1 File Locations & Routes
- **Route:** `buyer-web/src/app/shop/page.tsx` (Server Component)
  - Fetches `getAllVerifiedStorefronts` and `getAllProducts(client, { limit: 80 })`.
- **Client Component:** `buyer-web/src/components/shop/ShopCategoryDirectory.tsx`
- **Filter Sheet Component:** `buyer-web/src/components/shop/FilterSheet.tsx` — **MISSING / NOT YET CREATED**.
- **Related Legacy Component:** `buyer-web/src/components/CatalogToolbar.tsx` (used in `PublicDropView.tsx`).

### 3.2 Props & State Contracts in `ShopCategoryDirectory.tsx`
```typescript
export interface ShopCategoryDirectoryProps {
  storefronts?: PublicSellerStorefront[];
  initialProducts?: PublicProductView[];
}
```
- **State Hooks:**
  - `activeTab`: `'all' | 'sarees' | 'kurtis' | 'lehengas' | 'dupattas' | 'jewellery' | 'accessories'`
  - `searchQuery`: `string`
  - `sortBy`: `'featured' | 'price-asc' | 'price-desc'`

### 3.3 Visual & Functional Comparison against Spec (Screen 02 & Screen 05)

| Element / Feature | Reference Spec (Screen 02 & 05) | Existing Implementation | Gap / Action Needed |
|---|---|---|---|
| **Header & Breadcrumbs** | `LuxuryTopHeader` + "Home > Shop Catalog" | Rendered via `LuxuryTopHeader` + breadcrumb | Aligned. |
| **Title & Subtitle** | Serif "Boutique Collections" + "Discover handcrafted pieces..." | Present in `ShopCategoryDirectory.tsx` | Aligned. |
| **Search Bar** | Full-width search bar with magnifying glass icon and placeholder "Search collection or flash code (e.g. #A01)..." | Search input is inside the control bar flex row | **GAP:** Make search input prominent full-width bar as shown in Screen 02. |
| **Control Bar** | Dedicated control bar with: 1) "Filter" button (with sliders icon) that opens Screen 05 sheet; 2) "Sort: Featured v" luxury dropdown/pill | Contains inline search, piece count, and native HTML `<select id="shop-sort">` | **MAJOR GAP:** Missing "Filter" button to trigger `FilterSheet`. Sort select needs luxury styling. |
| **Category Chips** | Horizontal chips: "All" (gold active), "Sarees", "Kurtis", "Lehengas", "Dupattas", "Jewellery", "Accessories" | `CATEGORY_TABS` mapped to pill buttons | Mostly aligned; ensure active gold pill styling matches spec (`#D4AF37`, text black). |
| **Product Grid** | 2-column mobile grid of 3:4 cards | Renders `ProductCard` in `.ld-product-grid` | Aligned. |
| **Filter Sheet Modal (Screen 05)** | Bottom drawer modal with top handle, "Filters" title, "Clear All" link, 4 sections (Category, Price Range slider ₹0–₹50,000, Availability, Size), and sticky "Show [X] Pieces →" CTA | **DOES NOT EXIST** in codebase | **CRITICAL IMPLEMENTATION TASK (Phase D):** Build `FilterSheet.tsx` matching Screen 05 specification. |

---

## 4. Component Survey: Screen 03 — Live Drop Room

### 4.1 File Locations & Routes
- **Route:** `buyer-web/src/app/drop/[slug]/page.tsx`
  - Fetches `getLiveDropBySlug` and `getPublicProductsForDrop`.
- **Coordinator View:** `buyer-web/src/components/PublicDropView.tsx`
  - Manages view states (`loading`, `live`, `closed`, `not_found`, `error`).
  - Manages `isCinematicMode` state (triggered by `?view=live` or "Watch Live Fullscreen" button).
  - Manages Supabase realtime subscription via `CatalogRealtimeSubscription`.
- **Fullscreen Live Room View:** `buyer-web/src/components/live/CinematicLiveRoomView.tsx`
- **Stream Player Component:** `buyer-web/src/components/live/FacebookLivePlayer.tsx`
- **Product Modal in Room:** `buyer-web/src/components/product/ProductQuickViewDrawer.tsx`

### 4.2 Props & State Contracts
```typescript
export interface CinematicLiveRoomViewProps {
  drop: PublicDropCatalog;
  products: PublicProductView[];
  realtimeStatus?: 'connecting' | 'connected' | 'disconnected' | 'polling';
  onExitToGrid?: () => void;
}
```
- **State Hooks in `CinematicLiveRoomView.tsx`:**
  - `isCatalogExpanded`: `boolean` (controls bottom drawer displaying all products)
  - `selectedProduct`: `PublicProductView | null`
  - `isQuickViewOpen`: `boolean`
  - `likesCount`: `number`
  - `hasLiked`: `boolean`
  - `flyingHearts`: `{ id: number; left: number }[]`
  - `pinnedProductId`: `string | null`
  - Cart access via `useOptionalCart()`

### 4.3 Visual & Functional Comparison against Spec (Screen 03)

| Element / Feature | Reference Spec (Screen 03) | Existing Implementation | Gap / Action Needed |
|---|---|---|---|
| **Top Overlay Bar** | Back button + Boutique avatar + Boutique name ("Sonali's Boutique") + Red `● LIVE` badge + viewer count | Implemented in `CinematicLiveRoomView.tsx` lines 112–172 | Aligned. |
| **Dominant Stream Viewport** | Embedded video stream / broadcast canvas | Rendered via `FacebookLivePlayer.tsx` | Aligned. |
| **Right Floating Actions** | Bag button with count, Like button with hearts counter, Share button | Implemented on right column | Aligned. |
| **Live Chat Overlay** | Semi-transparent chat bubbles on bottom-left | Overlaid chat bubbles (`INITIAL_COMMENTS`) | Aligned visually. |
| **Spotlight Product Card** | Docked card above chat input with 3:4 thumbnail, `#A03`, title, price, size, and gold bag button | Pinned card present above bottom | Aligned with spotlight details. |
| **Bottom Chat Input Bar** | "Say something..." input bar with smiley trigger and gold paper plane button | **NOT IMPLEMENTED** | **GAP:** Add bottom chat input bar matching Screen 03. |
| **Mobile Bottom Dock** | **`MobileBottomDock` rendered with "Live" tab active** | **NOT RENDERED**. In addition, `MobileBottomDock.tsx` lines 66–68 explicitly returns `null` for `/drop/*`! | **MAJOR GAP & CONFLICT:** `MobileBottomDock` must render in the live room with "Live" tab active as illustrated in reference Screen 03. |

---

## 5. Component Survey: Screen 04 — Product Detail Modal / Quick View

### 5.1 File Locations & Competing Implementations
There are currently **two distinct components** providing product detail views:
1. `buyer-web/src/components/ProductDetailModal.tsx`
   - Invoked by `ProductCard.tsx` on storefront (`/` and `/shop`).
   - Uses custom `.ld-product-sheet` CSS classes from `globals.css`.
2. `buyer-web/src/components/product/ProductQuickViewDrawer.tsx`
   - Invoked by `CinematicLiveRoomView.tsx` when a product is clicked inside the live room.
   - Uses Tailwind CSS utility classes.

### 5.2 Visual & Functional Comparison against Spec (Screen 04)

| Element / Feature | Reference Spec (Screen 04) | `ProductDetailModal.tsx` | `ProductQuickViewDrawer.tsx` | Gap / Action Needed |
|---|---|---|---|---|
| **Top Navigation** | Back button + Heart outline + Share icon | Back button, heart toggle, share button | Close "✕" button only | Needs consistent back button + heart + share. |
| **Image Media** | **3:4 portrait image** with **"1/5" counter badge** + 5-thumbnail horizontal strip | `aspect-ratio: 1 / 1` in `globals.css`; has thumbnail strip; **no counter badge** | `aspect-[4/5]`; has thumbnail strip; **no counter badge** | **MAJOR GAP:** Set media frame to strict 3:4 aspect ratio; add "1/5" image counter badge. |
| **Metadata Row** | Flash code badge (`#A03`) on left, `● AVAILABLE` pill on right | Shows code and stock status | Shows code and stock status | Aligned. |
| **Title & Pricing** | Serif title ("Handloom Tussar Silk Saree") + bold INR price (`₹3,100`) + "Free Size" pill | Title, formatted price, size pill | Title, formatted price, size pill | Need explicit Cormorant Garamond serif styling for title. |
| **Craftsmanship Attribute Badges** | **4 badges in a row with icons**: Handloom, Pure Silk, Single Piece, Festive Wear | Has simple tag chips ("Pure Silk", "Zari Weave", "Handpicked") without icons | Has 3 trust cards ("Authentic", "15 Min Hold", "Direct UPI") | **MAJOR GAP:** Implement the 4 craftsmanship attribute badges with icons matching Screen 04. |
| **Expandable Accordions** | **3 collapsible accordions**: Product Details `>`, Atelier Information `>`, Delivery & Returns `>` | Missing accordions; displays plain text description and static boutique box | Missing accordions | **MAJOR GAP:** Implement the 3 collapsible accordions with chevrons. |
| **Sticky Purchase Bar** | **Dual buttons**: "Add to Bag" (dark with gold border) + "Buy Now →" (solid gold) | Dual buttons present ("Add to Bag" + "Buy Now") | Single button ("Add to Bag") | `ProductDetailModal.tsx` has dual buttons; ensure exact styling matches Screen 04 tokens. |

---

## 6. State Management, Hooks & Data Flows Audit

### 6.1 Cart State Store (`buyer-web/src/lib/cart/cart-context.tsx`)
- **Implementation:** Custom React Context powered by `useSyncExternalStore` and synchronized with `localStorage['livedrop_cart_v1']`.
- **Integrity Verification:**
  - `subtotalPaisa` is computed as integer sum of `item.pricePaisa * item.quantity`. Zero floating point operations.
  - Enforces `MAX_CART_ITEMS = 10` per RULE-ORD-04.
  - Multi-drop mixing defense: Adding an item from a different `dropId` produces `{ success: false, reason: 'DIFFERENT_DROP' }`.
  - Single-piece inventory rule: Live drop pieces cannot be duplicated.
- **Hook Export:** `useCart()` and `useOptionalCart()`.
- **Status:** **100% compliant and production-ready.** No changes required to data model.

### 6.2 Realtime Subscription Manager (`buyer-web/src/lib/realtime/catalog-realtime.ts`)
- **Implementation:** `CatalogRealtimeSubscription` class wrapping Supabase client channels.
- **Channel Name:** `drop:${dropId}:products`.
- **Capabilities:**
  - Realtime updates on `INSERT`, `UPDATE`, `DELETE` from table `products`.
  - Monotonic version check: protects against out-of-order WebSocket packet arrival (`localVersions.get(p.id)`).
  - Resilient HTTP polling fallback: if WebSocket drops (`CLOSED`, `TIMED_OUT`, `CHANNEL_ERROR`), engages 3-second HTTP stock-delta polling via `getPublicProductsForDrop`.
- **Status:** **100% compliant with `docs/14-realtime-contract.md`.**

### 6.3 Catalog Data Access (`buyer-web/src/lib/data/buyer-catalog.ts`)
- **Key Functions:**
  - `getAllActiveLiveDrops(client)`: Retrieves live drops joined with seller storefronts; filters test accounts.
  - `getAllVerifiedStorefronts(client)`: Retrieves approved seller profiles.
  - `getFeaturedProducts(client, limit)`: Retrieves active available products.
  - `getAllProducts(client, options)`: Retrieves products for `/shop` catalog with optional category and search filters.
  - `getLiveDropBySlug(client, slug)`: Retrieves drop details by slug.
  - `getPublicProductsForDrop(client, dropId)`: Retrieves catalog for specific drop.
  - RPC transactional functions: `createOrderWithReservation`, `getOrderByToken`, `initiatePaymentAttempt`, `submitBuyerPaymentClaim`.
- **Status:** **100% compliant with PostgreSQL RLS and frozen contracts.**

---

## 7. Design System & CSS Token Audit (`globals.css`)

### 7.1 Existing Color Tokens
Tokens defined in `globals.css` match the reference spec:
- `--ld-bg`: `#08080A` (canvas)
- `--ld-surface`: `#0E0E12` (cards, dock)
- `--ld-surface-elevated`: `#16161C` (inputs, elevated surfaces)
- `--ld-surface-subtle`: `#121217`
- `--ld-border`: `rgba(255, 255, 255, 0.08)`
- `--ld-border-gold`: `rgba(212, 175, 55, 0.25)`
- `--ld-border-gold-strong`: `rgba(212, 175, 55, 0.45)`
- `--ld-text-primary`: `#FBFBFB`
- `--ld-text-secondary`: `rgba(244, 241, 234, 0.72)`
- `--ld-text-muted`: `#AAA49A`
- `--ld-gold`: `#D4AF37`
- `--ld-gold-soft`: `#F5D78E`
- `--ld-gold-deep`: `#C88A24`
- `--ld-live`: `#EF4444`
- `--ld-success`: `#10B981`
- `--ld-warning`: `#F59E0B`
- `--ld-sold`: `#6B7280`

### 7.2 Styling Inconsistencies & Fixes Required
1. **Product Detail Media Frame Aspect Ratio:**
   - In `globals.css` line 2145: `.ld-sheet-media-frame` has `aspect-ratio: 1 / 1`.
   - **Fix:** Update to `aspect-ratio: 3 / 4` to match reference Screen 04.
2. **Product Card Add-to-Bag Button Dimensions on Mobile:**
   - In `globals.css` lines 1949–1950: `@media (max-width: 640px) { .ld-btn-add-cart-compact { width: 44px; height: 44px; border-radius: 10px; } }`.
   - **Fix:** Update to `width: 36px; height: 36px; border-radius: 8px;` per Section 9 of `BUYER-REFERENCE-DESIGN-SPEC.md`.
3. **Bottom Dock Suppression on Drop Route:**
   - In `MobileBottomDock.tsx` lines 66–68: `if (pathname?.startsWith('/drop/')) return null;`.
   - **Fix:** Remove this exclusion so that `MobileBottomDock` renders in Screen 03 with the "Live" tab active.

---

## 8. Unit Test Impact & Migration Analysis

When subsequent phases (Phases B, C, D, E, F) implement the changes identified in this survey, the following test suites will need attention:

1. **`src/test/mobile-bottom-dock.test.tsx`:**
   - Test `strictly hides the dock on fullscreen live drop rooms (/drop/[slug])` (lines 92–97) explicitly asserts that `mobile-bottom-dock` is NOT in the document on `/drop/midnight-silks`.
   - **Migration:** When Screen 03 includes `MobileBottomDock`, update this test to assert that `mobile-bottom-dock` is rendered and that the "Live" tab has the `active` class on `/drop/[slug]`.
2. **`src/test/home-storefront.test.tsx`:**
   - Tests assert presence of `category-chips-rail`, `category-chip-all`, `category-chip-sarees`, etc.
   - **Requirement:** Maintain these `data-testid` attributes (`category-chips-rail`, `category-chip-all`, `category-chip-[category]`) when replacing the pill buttons with the square gold "All" card + circular category avatars to prevent test regression.
3. **`src/test/shop-category-directory.test.tsx`:**
   - Tests assert `shop-search-input`, `shop-pieces-count`, `shop-sort-select`, and `shop-category-[tab]`.
   - **Requirement:** Preserve all existing test IDs while adding the new "Filter" button and `FilterSheet`.

---

## 9. Implementation Roadmap & Priority Sequence for Implementers

Based on this survey, the recommended implementation sequence for Phases C, D, E, and F is:

### Phase C: Home Storefront (Screen 01)
1. In `HomeStorefront.tsx`:
   - Add hero feature pills ("✦ Live shopping", "✦ Exclusive pieces", "✦ Handpicked").
   - Add hero carousel indicators ("● ○ ○ 1/4").
   - Reconstruct category rail to feature square gold "All" card (`#D4AF37`) + circular category photo avatars (Sarees, Kurtis, Lehengas, Dupattas, Jewellery) with labels underneath, preserving `data-testid="category-chip-[id]"`.
2. In `ProductCard.tsx`:
   - Add top-right favorite heart button.
3. In `globals.css`:
   - Adjust mobile `.ld-btn-add-cart-compact` to 36×36px, radius 8px.

### Phase D: Shop Directory & Filter Sheet (Screens 02 & 05)
1. Create `buyer-web/src/components/shop/FilterSheet.tsx`:
   - Modal bottom drawer with drag handle, close button, serif "Filters" title, "Clear All" link.
   - Category chips ("All", "Sarees", "Kurtis", "Lehengas", "Dupattas", "Jewellery", "Accessories").
   - Price range min/max slider (₹0 to ₹50,000).
   - Availability chips ("All", "Available", "Reserved", "Sold").
   - Size chips ("Free Size", "XS", "S", "M", "L", "XL", "XXL").
   - Sticky "Show [X] Pieces →" button.
2. In `ShopCategoryDirectory.tsx`:
   - Add "Filter" button with sliders icon to the control bar.
   - Connect filter state to `FilterSheet`.
   - Refactor search input into full-width bar.

### Phase E: Live Drop Room (Screen 03)
1. In `MobileBottomDock.tsx`:
   - Support rendering on `/drop/[slug]` with "Live" tab active.
2. In `CinematicLiveRoomView.tsx`:
   - Integrate `MobileBottomDock`.
   - Add bottom chat input bar ("Say something..." with smiley trigger and gold send button).
   - Verify layout hierarchy and safe-area padding for 390×844 mobile viewports.

### Phase F: Product Detail (Screen 04)
1. In `ProductDetailModal.tsx`:
   - Update media frame to 3:4 portrait aspect ratio in `globals.css`.
   - Add image counter badge ("1/5").
   - Add 4 craftsmanship attribute badges with icons.
   - Add 3 expandable details accordions (Product Details, Atelier Information, Delivery & Returns).
   - Ensure Cormorant Garamond serif styling for product title.
2. Standardize usage so both `ProductCard` and `CinematicLiveRoomView` leverage the same high-fidelity Screen 04 presentation.
