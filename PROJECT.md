# Project: LiveDrop Haute-Couture Mobile Buyer Web

## Architecture
LiveDrop is a real-time luxury live commerce platform designed for mobile-first buyer experiences. The buyer frontend is built with Next.js 15 (App Router), React 19, Tailwind CSS v4, Lucide React, and Supabase client bindings.

### Core Architecture Principles
1. **Opaque-Box Mobile Haute-Couture Visual Fidelity**: Complete fidelity to the 11-screen haute-couture design specification (`docs/BUYER-REFERENCE-DESIGN-SPEC.md`) and reference image `media_1790450082820.jpg`.
2. **Immutable Business & Security Invariants**: Strict preservation of all Supabase schemas, atomic database RPCs (`create_order_with_reservation`, `get_order_by_token`, `initiate_payment_attempt`, `submit_buyer_payment_claim`, `verify_manual_upi_payment`), integer Paisa currency calculations, idempotency keys, single-flight locks, and DPDP Act compliant token-gated order lookup security.
3. **Zero Layout Shift & Predictable Viewport Ergonomics**: Fixed-height headers (56px) and docks (60px), reserved aspect ratios (3:4 portrait cards and media), and touch targets meeting or exceeding 44-48px across 360px-430px viewports.
4. **Dual Track Orchestration**: Independent parallel development of implementation milestones alongside requirement-driven opaque-box E2E test suite creation.

---

## Feature Inventory
Every feature identified during Phase 0 Survey mapped directly to an assigned milestone.

| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Luxury Typography & Color Tokens | Tailwind v4 `@theme` mappings for `--font-serif` (Cormorant Garamond), `--font-sans` (Plus Jakarta Sans), `--color-ld-border-gold-strong`, `--color-ld-sold`, `--color-ld-gold-muted` | M1 | Survey (Explorer 1) |
| 2 | Luxury Global Header (56px) | Sticky top header with sparkle monogram, rounded circular 18×18px bag badge, and touch targets min 44-48px | M1 | Survey (Explorer 1) |
| 3 | Mobile Bottom Dock (60px) | 5-tab floating bottom navigation (Home, Live, Shop, Orders, Bag) with gold active states, 60px height, and `#AAA49A` inactive styling | M1 | Survey (Explorer 1) |
| 4 | Home Cinematic Live Hero | Live badge with pulse, collection title, boutique name, 3 feature tags ("✦ Live shopping", etc.), and pagination dots | M2 | Survey (Explorer 2) |
| 5 | Category Rail Visual Transformation | Square gold "All" card followed by circular avatar photos with labels | M2 | Survey (Explorer 2) |
| 6 | Featured Product Grid & Card Alignment | 2-column 3:4 portrait product cards, top-right favorite heart button, 36×36px compact gold bag button | M2 | Survey (Explorer 2) |
| 7 | Boutique Collections Shop Directory | Boutique collections header with breadcrumbs, search input, and dedicated control bar with filter button | M2 | Survey (Explorer 2) |
| 8 | Multi-Dimensional Filter Sheet (Screen 05) | Dedicated bottom sheet filter modal with Category, Price Range slider/pills, Availability, and Size selectors | M2 | Survey (Explorer 2) |
| 9 | Live Drop Room Dock Integration | Enable `MobileBottomDock` on `/drop/[slug]` with "Live" tab active | M3 | Survey (Explorer 2) |
| 10 | Live Drop Room Chat Input Bar | Bottom chat input ("Say something...", emoji/smiley trigger, gold send button) overlaid on video canvas | M3 | Survey (Explorer 2) |
| 11 | Product Detail 3:4 Portrait Media Frame | Update `.ld-sheet-media-frame` aspect ratio to 3:4 portrait with "1/5" counter badge and thumbnail strip | M3 | Survey (Explorer 2) |
| 12 | Craftsmanship Badges & Accordions | 4 craftsmanship attribute badges with icons and 3 expandable accordions (`Product Details >`, `Atelier Information >`, `Delivery & Returns >`) | M3 | Survey (Explorer 2) |
| 13 | Dual Sticky Purchase Bar | Sticky bottom purchase bar with dual CTAs: "Add to Bag" + "Buy Now →" | M3 | Survey (Explorer 2) |
| 14 | Cart 10-Minute Reservation Policy Banner | Limited-edition reservation policy warning banner with gold clock icon and countdown timer | M4 | Survey (Explorer 3) |
| 15 | Cart Item Row 3:4 Thumbnail & Stepper | 3:4 portrait thumbnail, quantity stepper, trash button, and customer gift note input | M4 | Survey (Explorer 3) |
| 16 | Empty Cart Vector Illustration (Screen 07) | Replace emoji with handcrafted gold shopping bags vector illustration (`<svg>`) with sparkles | M4 | Survey (Explorer 3) |
| 17 | Checkout 3-Step Progress Indicator | Stepper indicator ("1 Details", "2 Payment", "3 Confirm") | M4 | Survey (Explorer 3) |
| 18 | Checkout Delivery Details Elevated Inputs | Delivery form card with dark elevated inputs (`#16161C`) and gold focus rings | M4 | Survey (Explorer 3) |
| 19 | Direct UPI Payment View (Screen 09) | High-contrast QR code, UPI ID with copy button, 12-digit UTR input, and "Verify Payment →" primary CTA | M4 | Survey (Explorer 3) |
| 20 | Orders List Segmented Tabs (Screen 10) | Segmented filter tabs ("Recent Orders" / "Saved") and order cards with product thumbnails, codes, and status pills | M5 | Survey (Explorer 3) |
| 21 | Order Detail Vertical Gold Timeline (Screen 11) | Vertical order milestone tracking timeline with gold checkmarks (`#D4AF37`) and active step descriptions | M5 | Survey (Explorer 3) |
| 22 | DPDP Act Token Security Invariant | Token-gated order lookup security, URL token stripping, and fallback state preservation | M5 | Survey (Explorer 3) |
| 23 | E2E Opaque-Box Test Suite (Tiers 1-4) | Comprehensive opaque-box test suite covering all 11 screens, boundaries, pairwise combinations, and real-world buyer flows | M6 / E2E Track | Survey (Explorer 3) |
| 24 | Adversarial Hardening & Viewport Audits (Tier 5) | Mobile viewport audits (390×844, 360×800, 412×915, 430×932) and adversarial stress tests | M6 / E2E Track | Survey (Explorer 3) |

---

## Milestones

| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Global Shared Primitives & Tokens (Phase B) | `globals.css` (@theme tokens, fonts, colors), `GlobalBuyerHeader.tsx` (sparkle icon, bag badge, touch targets), `MobileBottomDock.tsx` (60px height, inactive styling) | None | IN_PROGRESS |
| M2 | Storefront & Browsing Experience (Phases C & D) | `HomeStorefront.tsx` (hero, category rail with square gold 'All' card & circular avatars), `ProductCard.tsx` (heart, compact cart button), `ShopCategoryDirectory.tsx`, `FilterSheet.tsx` (new modal) | M1 | PLANNED |
| M3 | Live Drop Room & Product Atelier (Phases E & F) | `CinematicLiveRoomView.tsx` (chat input bar, bottom dock integration), `ProductDetailModal.tsx` & `ProductQuickViewDrawer.tsx` (3:4 portrait aspect, counter, craftsmanship badges, accordions, sticky dual CTAs) | M1 | PLANNED |
| M4 | Cart & Checkout Experience (Phases G & H) | `CartItemRow.tsx` (3:4 thumbnail), `CartEmptyState.tsx` (gold vector illustration), `CheckoutForm.tsx` (3-step progress, dark elevated inputs), `DirectUpiPaymentView.tsx` ("Verify Payment →", QR presentation) | M1 | PLANNED |
| M5 | Orders & Order Tracking (Phase I) | `buyer-web/src/app/order/page.tsx` (tabs, order cards with thumbnail), `CheckoutSuccessView.tsx` / `order/[id]/page.tsx` (vertical timeline with gold checkmarks, DPDP token security) | M4 | PLANNED |
| M6 | Final Verification & Adversarial Hardening | Pass 100% E2E test suite (Tiers 1-4), Tier 5 adversarial tests, mobile viewport audits (390×844, 360×800, 412×915, 430×932), full automated gates (`typecheck`, `lint`, `test`, `build`) | M1-M5, TEST_READY.md | PLANNED |
| E2E | E2E Testing Track (Parallel) | Test runner infra, Tiers 1-4 test suite across all 11 screens, publication of `TEST_READY.md` | None | IN_PROGRESS |

---

## Interface Contracts

### M1 ↔ M2/M3/M4/M5 (Global Primitives & Design Tokens)
- **CSS Utility Classes**: `font-serif` must map to `Cormorant Garamond`, `font-sans` to `Plus Jakarta Sans`.
- **CSS Color Tokens**: `var(--color-ld-gold)` (`#D4AF37`), `var(--color-ld-gold-strong)` (`#E5C158`), `var(--color-ld-border-gold)` (`rgba(212, 175, 55, 0.2)`), `var(--color-ld-surface-elevated)` (`#16161C`).
- **Aspect Ratios**: `.ld-card-media-frame`, `.ld-sheet-media-frame`, `.ld-cart-thumb-frame` must strictly enforce `aspect-ratio: 3 / 4`.
- **Dock Height**: Outer height including safe area bottom with min 60px visible bar. Pages must reserve `pb-24` or `.ld-has-bottom-dock` padding.
- **Dock Props & Route Visibility**:
  ```typescript
  interface MobileBottomDockProps {
    cartItemCount?: number;
    activeTabOverride?: 'home' | 'live' | 'shop' | 'orders' | 'bag';
  }
  ```

### M2: ShopCategoryDirectory ↔ FilterSheet
```typescript
export interface FilterState {
  category: string | null;
  priceRange: [number, number]; // in Paisa
  availability: 'all' | 'in_stock' | 'reserved';
  sizes: string[];
}

export interface FilterSheetProps {
  isOpen: boolean;
  onClose: () => void;
  filters: FilterState;
  onApplyFilters: (filters: FilterState) => void;
  availableCategories: string[];
  availableSizes: string[];
  maxPricePaisa: number;
}
```

### M3: Live Drop Room ↔ MobileBottomDock
- `CinematicLiveRoomView` must mount `MobileBottomDock` with `activeTabOverride="live"`.
- `MobileBottomDock.tsx` route check `/drop/` condition updated to allow rendering when configured.

### M4: Cart & Checkout ↔ Supabase Database Contracts (Immutable)
- Currency: All prices and amounts MUST be integers in Paisa (`amountPaisa: number`).
- RPC calls: `create_order_with_reservation`, `initiate_payment_attempt`, `submit_buyer_payment_claim` MUST preserve exact payload signatures.
- Idempotency key: UUID generated per checkout attempt and sent in `x-idempotency-key` header.

### M5: Order Tracking ↔ Token Validation Contract (Immutable)
- Order Lookup: `get_order_by_token` RPC requires valid secure token.
- DPDP compliance: Order URLs must strip raw tokens from browser history while maintaining session verification.

---

## Code Layout

```
buyer-web/
├── src/
│   ├── app/
│   │   ├── layout.tsx                     # Root luxury shell & font injections
│   │   ├── page.tsx                       # Screen 01: Home Storefront
│   │   ├── globals.css                    # Tailwind v4 @theme, tokens, aspect ratios
│   │   ├── shop/
│   │   │   └── page.tsx                   # Screen 02: Shop Directory
│   │   ├── drop/[slug]/
│   │   │   └── page.tsx                   # Screen 03: Live Drop Room
│   │   ├── cart/
│   │   │   └── page.tsx                   # Screens 06 & 07: Cart & Empty State
│   │   ├── checkout/
│   │   │   └── page.tsx                   # Screens 08 & 09: Checkout & Direct UPI
│   │   └── order/
│   │       ├── page.tsx                   # Screen 10: Orders list
│   │       └── [id]/page.tsx              # Screen 11: Order tracking timeline
│   ├── components/
│   │   ├── navigation/
│   │   │   ├── GlobalBuyerHeader.tsx      # 56px sticky header
│   │   │   └── MobileBottomDock.tsx       # 60px 5-tab dock
│   │   ├── HomeStorefront.tsx             # Hero & category rail
│   │   ├── ProductCard.tsx                # 3:4 product card with gold bag button
│   │   ├── ProductDetailModal.tsx         # Screen 04: Product detail modal
│   │   ├── shop/
│   │   │   ├── ShopCategoryDirectory.tsx  # Screen 02 directory view
│   │   │   └── FilterSheet.tsx            # Screen 05 bottom filter sheet (NEW)
│   │   ├── live/
│   │   │   └── CinematicLiveRoomView.tsx  # Screen 03 live room view
│   │   ├── cart/
│   │   │   ├── CartItemRow.tsx            # Cart item row (3:4 thumb)
│   │   │   └── CartEmptyState.tsx         # Screen 07 gold vector illustration
│   │   ├── checkout/
│   │   │   ├── CheckoutForm.tsx           # Screen 08 checkout form
│   │   │   └── DirectUpiPaymentView.tsx   # Screen 09 UPI payment view
│   │   └── order/
│   │       └── CheckoutSuccessView.tsx    # Screen 11 order success & timeline
│   └── test/
│       ├── e2e/                           # Requirement-driven E2E tests (E2E Track)
│       └── ...                            # 31 existing unit test suites
```
