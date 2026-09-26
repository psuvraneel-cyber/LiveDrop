# LiveDrop — Buyer UI Phase 4 Product Card & Shop Audit
**Comprehensive Component & Consumer Audit Prior to Visual Refactoring**

**Date:** September 2026  
**Scope:** `ProductCard.tsx`, `/shop` Catalog Experience, and All Consumers  
**Functional Freeze Status:** STRICT — No business, cart, inventory, or Supabase logic alterations.

---

## 1. ProductCard Component Anatomy

**Source File:** [`buyer-web/src/components/ProductCard.tsx`](file:///c:/LiveDrop/buyer-web/src/components/ProductCard.tsx)

### 1.1 Props Interface
```typescript
export interface ProductCardProps {
  product: PublicProductView;
  dropId?: string;
  storeName?: string;
  onAddToCart?: (product: PublicProductView) => void;
}
```

### 1.2 Callbacks & Handlers
1. **`onAddToCart?: (product: PublicProductView) => void`**:
   - Optional external override handler.
   - Default behavior if omitted:
     ```typescript
     if (cart && isAvailable) {
       const targetDropId = dropId || (product as unknown as { drop_id?: string }).drop_id || cart.dropId || '';
       cart.addItem(product, targetDropId);
     }
     ```
   - Invocation: Triggered by clicking the compact cart button (`data-testid="cart-btn-${product.id}"`).
   - Event propagation is stopped via `e.stopPropagation()` so that clicking "Add to Bag" does **not** inadvertently trigger product navigation or open the detail modal.
2. **Card Click (Product Navigation / Detail Quick View)**:
   - Attached to the root `<article>` element.
   - Handler: `onClick={() => setIsDetailOpen(true)}` opens [`ProductDetailModal`](file:///c:/LiveDrop/buyer-web/src/components/ProductDetailModal.tsx).
3. **Carousel Image Navigation**:
   - `handlePrevImage(e: React.MouseEvent)`: `e.stopPropagation()`; moves to previous angle index.
   - `handleNextImage(e: React.MouseEvent)`: `e.stopPropagation()`; moves to next angle index.
   - `dotIndicatorClick(idx, e)`: `e.stopPropagation()`; switches active angle index.

---

## 2. ProductCard Internal & External States

| State Dimension | Possible Values | Visual / DOM Manifestation | Test Contract / TestID |
|---|---|---|---|
| **Inventory Status** | `available` | Full opacity, active hover scale, green status pill | `status-badge-${product.id}`: text `AVAILABLE`, class `.available` |
| | `reserved` | Dimmed opacity, grayscale filter, amber status pill | `status-badge-${product.id}`: text `RESERVED`, class `.reserved`, card has `.unavailable` |
| | `sold` | Dimmed opacity, grayscale filter, neutral status pill | `status-badge-${product.id}`: text `SOLD OUT`, class `.sold`, card has `.unavailable` |
| **Cart State** | Available, Not in Cart | Gold gradient button with bag icon + "Add to Bag" text (desktop) / 32px icon button (mobile) | `cart-btn-${product.id}` with text `Add to Bag` |
| | In Cart | Emerald tinted button with checkmark icon + "In Cart" text (desktop) / 32px icon (mobile) | `cart-btn-${product.id}` with text `In Cart` |
| | Unavailable (Sold/Reserved) | Neutral disabled button with "Sold Out" or "Reserved" text | `cart-btn-${product.id}` is `:disabled`, text `Sold Out` / `Reserved` |
| **Media Display** | Single Image | 1:1 square media thumbnail, cover cropped, zoom on hover | `img.ld-product-image` |
| | Multi-Angle Images | Left/right chevron navigation arrows (`‹`, `›`) and bottom dot indicators | `carousel-prev-${product.id}`, `carousel-next-${product.id}`, `carousel-dots-${product.id}` |
| | Image Error / Fallback | Dark radial gradient container with `✦ LiveDrop` crest monogram and flash code text | `fallback-image-${product.id}` containing `.ld-image-fallback-text` with `{product.code}` |
| **Quick Detail Modal** | `isDetailOpen === true` | Mounts `ProductDetailModal` with full gallery, description, specs, and secondary bag action | Rendered conditionally |

---

## 3. Comprehensive Test Contracts & Assertions

Existing automated test suites depend on exact test IDs, class names, and text contracts:

1. **`flash-badge-${product.id}`**:
   - Must contain exact flash code (e.g. `#A01`).
   - High-contrast monospace badge.
2. **`product-card-${product.id}`**:
   - Root element `<article>`.
   - Must NOT have `.unavailable` when available.
   - Must have `.unavailable` when reserved or sold.
3. **`status-badge-${product.id}`**:
   - Must have exact class `.available` and text `AVAILABLE`.
   - Must have exact class `.reserved` and text `RESERVED`.
   - Must have exact class `.sold` and text `SOLD OUT`.
4. **`fallback-image-${product.id}`**:
   - Must be displayed upon `fireEvent.error(img)`.
   - Must contain an element with class `.ld-image-fallback-text` displaying the product code.
5. **`carousel-prev-${product.id}` & `carousel-next-${product.id}` & `carousel-dots-${product.id}`**:
   - Renders when `image_urls` has multiple photos.
   - Clicking changes image `src`.
6. **`cart-btn-${product.id}`**:
   - Text is `Add to Bag` when available and not in cart.
   - Text becomes `In Cart` on click.
   - When product is sold, button is `disabled` and text is `Sold Out`.

---

## 4. All Consumers & Reusable Touchpoints

`ProductCard` is reused across 4 primary buyer surfaces:

1. **Homepage (`/`) via [`HomeStorefront.tsx`](file:///c:/LiveDrop/buyer-web/src/components/HomeStorefront.tsx)**:
   - Primary commerce grid ("Featured Pieces").
   - 2 columns on mobile, 5 columns on desktop.
2. **Shop Catalog (`/shop`) via [`ShopCategoryDirectory.tsx`](file:///c:/LiveDrop/buyer-web/src/components/shop/ShopCategoryDirectory.tsx)**:
   - Main catalog grid with category chips and price sorting.
   - 2 columns on mobile, 4-5 columns on desktop.
3. **Live Drop Room & Showcase via [`ProductGrid.tsx`](file:///c:/LiveDrop/buyer-web/src/components/ProductGrid.tsx)**:
   - Embedded inside live rooms, catalog tabs, and past collection showcases.
4. **Boutique Storefront (`/[storeSlug]`) via [`BoutiqueStorefrontView.tsx`](file:///c:/LiveDrop/buyer-web/src/components/BoutiqueStorefrontView.tsx)**:
   - Dedicated atelier catalog and live product grids.

---

## 5. Shop Page (`/shop`) Baseline Audit

**Source File:** [`buyer-web/src/components/shop/ShopCategoryDirectory.tsx`](file:///c:/LiveDrop/buyer-web/src/components/shop/ShopCategoryDirectory.tsx)

### Current Architecture:
1. **Header:** Uses shared `LuxuryTopHeader`.
2. **Breadcrumb:** `Home / Shop Catalog`.
3. **Page Title:** `Boutique Collections` with subtitle `{count} pieces available from verified ateliers`.
4. **Sort Control:** HTML `<select>` with options:
   - `featured`: Featured / Latest
   - `price-asc`: Price: Low to High
   - `price-desc`: Price: High to Low
5. **Category Rail:** Horizontal chips:
   - `All`, `Sarees`, `Kurtis`, `Lehengas`, `Dupattas`, `Jewelry` (needs alignment with `Jewellery` or both), `Accessories`.
   - Normal flow, non-sticky.
6. **Product Grid:** `.ld-product-grid` rendering `ProductCard`.
7. **Empty State:** `No pieces found` with reset button.
8. **Boutique Directory Rail:** Secondary section at bottom ("Verified Ateliers") displaying atelier cards with monogram avatar and `Visit →` link.
9. **Dock:** Canonical `MobileBottomDock`.

### Areas for Enhancement in Phase 4:
1. **ProductCard Visual Polish:**
   - Dominant photograph with consistent 1:1 or 4:5 fashion aspect ratio (controlled, no distortion or shift).
   - Clear visual hierarchy: Photograph -> Code (`#A03`) -> Title (up to 2 lines, legible Cormorant Garamond or Plus Jakarta Sans) -> Price in INR -> Size / key metadata -> Availability -> Compact Bag Action.
   - Compact add-to-bag action (minimum 44-48px touch target with clean bag icon and smooth state transitions).
   - Subordinate, restrained status indicators (no neon, no loud badges).
2. **Shop Page Visual Restructure:**
   - Clean, modern filter and sort bar matching luxury e-commerce aesthetics.
   - Seamless category chip rail aligned with Phase 3 chips.
   - Responsive density: 2-column mobile, 4-5 column desktop.
   - Secondary boutique directory visual hierarchy refinement (subordinate to product catalog).
   - Safe-area bottom dock spacing to guarantee zero collision with products or footer.
