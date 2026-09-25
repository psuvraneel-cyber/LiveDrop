# BUYER UI/UX CLEANUP & VISUAL RESET AUDIT

**Document Version:** 1.0.0  
**Date:** 2026-09-25  
**Scope:** LiveDrop Buyer Website (`buyer-web`)  
**Reference Evidence:** Android mobile screenshots (`livedrop-in.vercel.app`), codebase review, and user requirements.

---

## Executive Summary

The LiveDrop buyer web application has accumulated multiple layers of editorial, luxury-poster styling from iterative redesigns. While individual components are visually intricate, the aggregate user experience on mobile suffers from severe **design accumulation**, push of core commerce below the fold, fake hardcoded drops/viewer counts, giant category poster blocks with zero direct products on `/shop`, overlapping fixed navigation, and a 4,924-line global CSS stylesheet containing 532 distinct class selectors with competing token palettes.

This audit provides the definitive technical inventory required to execute a root-cause visual and architectural reset to return LiveDrop to a **clean, fast, responsive, trustworthy, commerce-first** platform.

---

## 1. Current Visual Systems

The codebase currently runs multiple conflicting visual philosophies in parallel:
1. **Editorial Luxury Fashion Poster:**
   - 4-line Cormorant Garamond serif headlines (`India's / Finest / Styles, / Live.`) occupying >520px vertical space.
   - Cinematic full-bleed bridal portraits with 4 layers of atmospheric gradient overlays and gold glow effects.
2. **Circular Story Reels:**
   - 5 large circular story rings (72px–84px diameter) with multi-stop gold conic gradients and hardcoded Unsplash stock images.
3. **Simulated TV Broadcast / Event Schedule:**
   - "UP NEXT • SEP 28, 7:00 PM" event banners with interactive "Notify Me" notifications and bookmark icons.
4. **Stacked Full-Page Posters on `/shop`:**
   - 5 full-screen image cards (`Sarees`, `Lehengas`, `Jewelry`, `Men's Couture`, `Accessories`) each consuming 260px–320px vertical height with buttons that merely link back to `/#boutiques`.
5. **Dense Multi-Tier Account System:**
   - Profile drawer configured like an enterprise patron portal ("Verified Guest Patron", "App v2.0", "Payment Methods UPI Direct", "Be the First to Know" notification banners).

---

## 2. Duplicate & Legacy UI Systems in `globals.css`

`buyer-web/src/app/globals.css` spans **4,924 lines** and **97.7 KB** with **532 distinct custom class selectors**.

### Competing Design Token Sets
Inside `:root`, at least 3 distinct era token systems compete with identical or near-identical color definitions:
- **Noir / Haute Couture Era:**
  `--noir-black: #08080A; --noir-card: #0E0E12; --noir-elevated: #15151B; --burgundy-deep: #2A0811; --champagne-gold: #D4AF37;`
- **Obsidian / Universal Invariant Era:**
  `--obsidian: #08080A; --obsidian-surface: #0E0E12; --obsidian-elevated: #15151B; --card-border-gold: rgba(212, 175, 55, 0.25);`
- **Specification Baseline Era (from `docs/03-ui-ux-specification.md`):**
  `--bg-page: #08080A; --surface-card: #0E0E12; --surface-elevated: #15151B; --text-primary: #FBFBFB; --gold-primary: #D4AF37; --gold-secondary: #C88A24;`

### Dead & Redundant CSS Chunks
- Section 2 (`.ld-luxury-header`, `.ld-luxury-header-brand`, `.ld-header-search-wrap`, `.ld-header-search-field`): 320+ lines.
- Section 3 (`.ld-hero-*`, `.ld-hero-timer-*`, `.ld-hero-stats-*`): 250+ lines of unused aside cards and countdowns.
- Section 4 (`.ld-value-strip`, `.ld-perks-*`): 60+ lines.
- Section 5 (`.ld-category-carousel`): 50+ lines.
- Section 19 (`.ld-confetti-canvas`): 20+ lines.
- Inconsistent naming: `.ld-products-grid` in CSS vs. `.ld-product-grid` in `ProductGrid.tsx`.

---

## 3. Current Homepage Structure

Current rendering in `buyer-web/src/components/HomeStorefront.tsx`:
```
Header (LuxuryTopHeader)
  ↓
Hero Section (520px+ min-height, multiline serif, Unsplash background)
  ↓
Category Story Circles (5 oversized circular image rings)
  ↓
Live Commerce Section (State 1: Active Live Drop OR State 2: Fake "UP NEXT • SEP 28, 7:00 PM • Anaya Atelier")
  ↓
Verified Designers Directory (Vertical card stack of 3 storefronts with WhatsApp links)
  ↓
Bottom Dock (MobileBottomDock)
```

**Critical Flaw:** The homepage contains **zero product cards**. A buyer visiting the homepage cannot see a single purchasable product without navigating elsewhere.

---

## 4. Current Shop Structure

Current rendering in `buyer-web/src/components/shop/ShopCategoryDirectory.tsx`:
```
Header (LuxuryTopHeader)
  ↓
Title ("✦ CURATED COLLECTIONS ✦ Couture by Category")
  ↓
Filter Tabs ([All], [Sarees], [Lehengas], [Jewelry], [Men's Couture], [Accessories])
  ↓
5 Stacked Full-Screen Category Poster Cards (Sarees, Lehengas, Jewelry, Men's, Accessories)
  ↓
Verified Ateliers Directory (Grid of boutique links)
  ↓
Bottom Dock (MobileBottomDock)
```

**Critical Flaw:** The `/shop` route contains **zero product cards**. Clicking "Explore Sarees" routes back to `/#boutiques` rather than displaying garments. The page acts as a redundant category billboard.

---

## 5. Current Navigation Structure

### Desktop Header
- Links: `Boutiques`, `Live Drops`, `Categories`.
- Search field with expandable trigger.
- Shopping bag icon with live badge counter.

### Mobile Navigation
- Top Header: Logo (`✦ LiveDrop INDIAN LUXURY LIVE`) + Search Icon + Shopping Bag Icon.
- Fixed Bottom Dock (5 tabs):
  1. `Home` (`/`)
  2. `Live` (`/#live-drops`)
  3. `Shop` (`/shop`)
  4. `Designers` (`/#boutiques`)
  5. `Profile` (triggers `BuyerProfileDrawer`)

**Problems:**
- `Designers` and `Profile` dominate the bottom dock, whereas LiveDrop is an anonymous, low-friction live commerce funnel.
- Bottom dock lacks proper clearance calculations, resulting in fixed navigation overlapping cards, buttons, and footers on mobile.
- Search input placeholder states `"Search boutiques, drops..."` instead of commerce-focused `"Search sarees, kurtis, dupattas..."`.

---

## 6. Mobile Layout & Overflow Problems

Inspected at mobile viewports (`360×800` through `430×932`):
1. **Vertical Space Monopoly:** The hero occupies >520px (`min-h-[520px]`), consuming 70–80% of the mobile viewport. Buyers must scroll through >1200px of editorial cards before finding actionable content.
2. **Text Clipping & Edge Crowding:** Headings and buttons sit with tight or inconsistent margins against viewport edges.
3. **Overuse of `select-none`:** Applied globally to container wrappers (`ld-home-storefront`, `shop-category-directory`, `cart-page`, `buyer-profile-drawer`), frustrating buyers attempting to copy product codes, boutique names, or addresses.
4. **Over-reliance on `overflow-x: hidden`:** Used as a blanket band-aid on top-level tags rather than ensuring responsive intrinsic dimensions.

---

## 7. Fixed-Position & Z-Index Conflicts

1. **Bottom Dock Overlap:**
   - `.ld-bottom-dock` uses fixed bottom positioning with `z-index: 50`.
   - Content containers use arbitrary `pb-36 sm:pb-24` or `pb-24`, which does not dynamically account for `env(safe-area-inset-bottom)` plus the dock height across varying mobile devices, causing cut-offs.
2. **Profile Drawer Isolation:**
   - Operates at `z-[100]`.
   - Populated with placeholder settings ("App v2.0", "Payment Methods UPI Direct", Unsplash promotion banner) that create an oversized, mostly empty black sheet.

---

## 8. Hardcoded & Fake UI Content Inventory

The following synthetic elements are hardcoded in the codebase and must be removed or replaced with real database data:

| Location | Hardcoded Content | Problem | Action |
|---|---|---|---|
| `HomeStorefront.tsx:34-65` | `STORY_CIRCLES` Unsplash array | Fake category photo rings | Replace with compact category chip rail |
| `HomeStorefront.tsx:293` | `👁 2.4K` viewer count badge | Fabricated social proof | Remove; show real viewer telemetry only if connected |
| `HomeStorefront.tsx:325` | `Anaya Sharma` fallback designer | Fabricated designer name | Fallback strictly to actual store name |
| `HomeStorefront.tsx:354-385` | `UP NEXT • SEP 28, 7:00 PM`<br>`Saree Stories & Handloom Weaves`<br>`Anaya Atelier` | Complete fake scheduled drop session | Remove entire fake block; render clean No-Live state or real upcoming drop |
| `ShopCategoryDirectory.tsx:33-74` | `EDITORIAL_CATEGORIES` (5 huge posters) | Hardcoded Unsplash posters blocking product catalog | Replace with real product grid filtered by category |
| `BuyerProfileDrawer.tsx:250-262` | `Payment Methods: UPI Direct` | Non-functional account menu item | Remove |
| `BuyerProfileDrawer.tsx:284-297` | `Settings: App v2.0` | Non-functional fake version label | Remove |
| `BuyerProfileDrawer.tsx:300-328` | `Be the First to Know` banner + Unsplash bride | Decorative stock filler | Remove |

---

## 9. Component Action Matrix

### Components to Keep (Core Business & Transactional Logic)
- `buyer-web/src/components/cart/CartDrawer.tsx`
- `buyer-web/src/components/cart/CartItemRow.tsx`
- `buyer-web/src/components/cart/CartEmptyState.tsx`
- `buyer-web/src/components/cart/StickyCartBar.tsx`
- `buyer-web/src/components/checkout/CheckoutForm.tsx`
- `buyer-web/src/components/checkout/CheckoutReview.tsx`
- `buyer-web/src/components/checkout/CheckoutSuccessView.tsx`
- `buyer-web/src/components/checkout/DirectUpiPaymentView.tsx`
- `buyer-web/src/components/checkout/EmptyCheckoutState.tsx`
- `buyer-web/src/components/checkout/HoldCountdown.tsx`
- `buyer-web/src/components/PublicDropView.tsx`
- `buyer-web/src/components/BoutiqueStorefrontView.tsx`
- `buyer-web/src/components/live/CinematicLiveRoomView.tsx`
- `buyer-web/src/components/live/FacebookLivePlayer.tsx`
- `buyer-web/src/components/ProductDetailModal.tsx`
- `buyer-web/src/components/CatalogToolbar.tsx`
- All error boundaries, skeletons, and loading states (`src/components/states/*`).

### Components to Refactor
- `buyer-web/src/app/globals.css`: Drastically consolidate from ~5000 lines into a single clean token architecture.
- `buyer-web/src/components/HomeStorefront.tsx`: Restructure to commerce-first layout (Compact Hero + Category Rail + Featured Products Grid + Live Boutiques Rail + Trust Footer).
- `buyer-web/src/components/ProductCard.tsx`: Standardize into the single canonical product card with clean, quiet styling (12–16px radii, no gold glow).
- `buyer-web/src/components/navigation/LuxuryTopHeader.tsx`: Clean, compact 64–72px header with product-focused search placeholder (`Search sarees, kurtis, dupattas...`).
- `buyer-web/src/components/navigation/MobileBottomDock.tsx`: 5 commerce-first tabs: `Home`, `Live`, `Shop`, `Orders`, `Bag`. Proper safe clearance.
- `buyer-web/src/components/profile/BuyerProfileDrawer.tsx`: Streamline to genuine utility drawer (Orders, Saved Shows, Wishlist, Addresses, Support).
- `buyer-web/src/components/shop/ShopCategoryDirectory.tsx` & `buyer-web/src/app/shop/page.tsx`: Product-first shopping experience with category filter chips and 2-column product grid.
- `buyer-web/src/lib/data/buyer-catalog.ts`: Add `getFeaturedProducts` and `getAllProducts` helpers to query `public_products_catalog`.

### Components / Code to Remove
- `STORY_CIRCLES` and circular reels markup.
- Hardcoded upcoming drop card ("UP NEXT • SEP 28").
- Full-screen editorial category posters on `/shop`.
- Fake statistics (`2.4K viewers`) and fake profile metadata.
- Hundreds of redundant, dead CSS rules in `globals.css`.
- Global `select-none` restrictions.

---

## 10. Proposed Final Buyer Information Architecture

```
HOMEPAGE (/)
├── 1. Compact Header (Logo + Bag, or desktop nav with Search)
├── 2. Live Drop Spotlight Hero (~360–450px mobile, 45–60% vh, real drop or clean No-Live state)
├── 3. Category Filter Rail (Compact horizontal scroll: All, Sarees, Kurtis, Lehengas, Jewelry, Accessories)
├── 4. Featured Products Section (2-col mobile, 4-col desktop, real items from public_products_catalog)
├── 5. Live & Verified Boutiques Rail (Horizontal compact boutique cards)
├── 6. Trust Strip & Restrained Footer
└── 7. Mobile Bottom Dock (Home | Live | Shop | Orders | Bag)

SHOP PAGE (/shop)
├── 1. Compact Header
├── 2. Search & Category Filter Chips
├── 3. Product Catalog Grid (2-col mobile, 4-col desktop, instant filtering)
├── 4. Secondary Boutique Directory Rail
└── 5. Mobile Bottom Dock
```
