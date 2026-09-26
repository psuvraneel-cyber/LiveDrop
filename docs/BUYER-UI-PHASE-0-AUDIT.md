# BUYER UI/UX PHASE 0 ARCHITECTURAL & VISUAL AUDIT

**Document Identifier:** `BUYER-UI-PHASE-0-AUDIT`  
**Date:** 2026-09-26  
**Project:** LiveDrop Haute Couture (`buyer-web`)  
**Scope:** Presentation-Layer Audit under Absolute Functional Freeze  
**Status:** COMPLETE — Phase 0 Gate  
**Reference Visual Standard:** Approved LiveDrop Haute Couture Luxury Reference  

---

## Executive Summary

LiveDrop is executing a presentation-layer visual redesign to elevate the buyer website into an **ultra-luxury Indian fashion commerce + live shopping** experience. The underlying commerce architecture (Supabase client, database migrations, RPCs, RLS, direct UPI payment state machine, atomic reservation logic, anonymous buyer model, and Realtime synchronization) is frozen and strictly protected.

This Phase 0 Audit examines the current UI architecture across `buyer-web/src/app/**`, `buyer-web/src/components/**`, `buyer-web/src/app/globals.css`, and dependencies to diagnose root-cause defects, identify duplicate CSS and legacy systems, analyze the header scroll flicker, and map the phased implementation plan before any code is modified.

---

## 1. Protected Architecture & Functional Freeze Boundaries

The following core modules are strictly protected under the mandatory architectural freeze. Presentation layers may bind to their exported hooks and contracts, but their internal logic, state machines, and RPC contracts must remain untouched:

| Layer / Directory | Primary Role | Invariants & Protection |
|---|---|---|
| `buyer-web/src/lib/data/**` | Data fetching, RPC invocations, Supabase queries | Price authority in integer Paisa (ADR-009); `create_order_with_reservation`; `initiate_payment_attempt`; `submit_buyer_payment_claim`; `getOrderByToken`. |
| `buyer-web/src/lib/cart/**` | Client cart intent and localStorage persistence | Schema versioning (`livedrop_buyer_cart_v1`); zero client reservation authority; stock reconciliation hooks. |
| `buyer-web/src/lib/realtime/**` | Supabase Postgres Changes and broadcast sync | Channel lifecycle management; fallback polling triggers. |
| `buyer-web/src/lib/checkout/**` | Idempotency key generation & DPDP PII validation | Single-flight checkout lock; 10-digit Indian phone normalization; 6-digit postal pincode validation. |
| `buyer-web/src/lib/supabase/**` | Supabase client singleton & env validation | Anonymous buyer client isolation; public anon key only; zero service-role leakage. |
| `buyer-web/src/types/**` | TypeScript domain contracts | Non-negative integer Paisa currency; order lifecycle states; payment claim states. |

---

## 2. Current Structure & Route Map

The buyer web application utilizes Next.js 16.3.4 (App Router) with React 19.2.8 and Tailwind CSS 4.3.3.

```
buyer-web/src/
├── app/
│   ├── layout.tsx             # Root layout: Cormorant Garamond & Plus Jakarta Sans font variables, AppProviders
│   ├── globals.css            # Unified global stylesheet (4,966 lines, 98.4 KB, 532 selectors)
│   ├── page.tsx               # Homepage route (delegates to HomeStorefront)
│   ├── shop/page.tsx          # Catalog directory route (delegates to ShopCategoryDirectory)
│   ├── cart/page.tsx          # Dedicated mobile cart page
│   ├── checkout/page.tsx      # Atomic reservation and checkout route
│   ├── order/page.tsx         # Order lookup and local order history
│   ├── order/[id]/page.tsx    # Token-gated order tracking and receipt route
│   ├── [storeSlug]/page.tsx   # Boutique storefront route (delegates to BoutiqueStorefrontView)
│   ├── drop/[slug]/page.tsx   # Live drop catalog / streaming room (delegates to PublicDropView)
│   ├── error.tsx              # Error boundary
│   ├── global-error.tsx       # Root error boundary
│   └── not-found.tsx          # 404 page
├── components/
│   ├── navigation/
│   │   ├── LuxuryTopHeader.tsx  # Sticky header with brand emblem, search, desktop links, bag button
│   │   └── MobileBottomDock.tsx # 5-tab floating/fixed bottom navigation dock
│   ├── product/
│   │   └── ProductQuickViewDrawer.tsx # Live room quick view sheet
│   ├── cart/
│   │   ├── CartDrawer.tsx       # Slide-over cart sheet with availability reconciliation
│   │   ├── CartItemRow.tsx      # Individual cart item presentation
│   │   ├── CartEmptyState.tsx   # Empty cart graphic and CTA
│   │   └── StickyCartBar.tsx    # Bottom sticky summary bar for mobile drop browsing
│   ├── checkout/
│   │   ├── CheckoutForm.tsx     # Delivery details input (Name, Phone, Address, Pincode)
│   │   ├── CheckoutReview.tsx   # Order item review & pricing breakdown
│   │   ├── CheckoutSuccessView.tsx # Order code, hold countdown, tracking timeline
│   │   ├── DirectUpiPaymentView.tsx # QR code, UPI intent link, UTR submission, verification polling
│   │   ├── EmptyCheckoutState.tsx # Direct access fallback when cart is empty
│   │   └── HoldCountdown.tsx    # 15-minute countdown timer with expired state handling
│   ├── live/
│   │   ├── CinematicLiveRoomView.tsx # Fullscreen live room with embedded stream and chat simulation
│   │   └── FacebookLivePlayer.tsx   # Responsive Facebook live embed player
│   ├── profile/
│   │   ├── BuyerProfileDrawer.tsx # Guest identity drawer with saved phone and notifications toggle
│   │   └── EditProfileModal.tsx   # Name and phone edit modal
│   ├── providers/
│   │   ├── AppProviders.tsx     # Context wrapper (CartProvider, ProfileProvider, GlobalAppOverlays)
│   │   └── GlobalAppOverlays.tsx # Mounts global CartDrawer and BuyerProfileDrawer
│   ├── shop/
│   │   └── ShopCategoryDirectory.tsx # Product catalog feed with category filter tabs and sort dropdown
│   ├── states/
│   │   ├── CatalogEmptyState.tsx
│   │   ├── CatalogErrorState.tsx
│   │   ├── CatalogLoadingSkeleton.tsx
│   │   ├── CatalogSearchEmptyState.tsx
│   │   ├── DropNotFoundState.tsx
│   │   └── DropUnavailableState.tsx
│   ├── BoutiqueStorefrontView.tsx # Multi-seller boutique profile, active drop link, past showcases
│   ├── CatalogToolbar.tsx         # Search bar and status filter pills for PublicDropView
│   ├── DropHeader.tsx             # Drop-specific header with realtime status badge and store branding
│   ├── HomeStorefront.tsx         # Commerce-first homepage with hero, category rail, featured grid
│   ├── InAppBrowserBanner.tsx     # Instagram / Facebook in-app browser breakout notice
│   ├── ProductCard.tsx            # Grid card with flash badge, image carousel, price, and cart button
│   ├── ProductDetailModal.tsx     # Mobile bottom sheet / desktop dialog for product inspection
│   └── PublicDropView.tsx         # Realtime live drop browsing container with fallback polling
```

---

## 3. Reusable vs. Legacy Components Inventory

### Reusable Core Components (Keep & Standardize)
- **`ProductCard.tsx`**: High-performance image-first card with flash code badge, multi-angle carousel, status pill, and "+ Add to Bag" / "In Cart" state.
- **`ProductDetailModal.tsx`**: Rich bottom sheet / modal with full image angles, craftsmanship tags, boutique seller card, and direct "Add to Bag" / "Buy Now" actions.
- **`CartDrawer.tsx`**: Slide-over cart overlay mounted globally in `GlobalAppOverlays.tsx` with dynamic availability reconciliation, gift note support, and subtotal calculation.
- **`CartItemRow.tsx`**: Clean row layout displaying square thumbnail, title, price, size, flash code, and removal action.
- **`DirectUpiPaymentView.tsx`**: Direct UPI payment view containing dynamic QR code generation, UPI URI intent links, masked UTR submission, safe-to-close notice, and adaptive polling fallback.
- **`HoldCountdown.tsx`**: Resilient 15-minute countdown timer with expiration triggers.
- **`CheckoutForm.tsx` & `CheckoutReview.tsx`**: Minimalist PII capture and authoritative server pricing breakdown.
- **`MobileBottomDock.tsx`**: 5-tab navigation dock (`Home`, `Live`, `Shop`, `Orders`, `Bag`).

### Divergent & Fragmented Components (Require Consolidation)
1. **Header Proliferation (7 different headers across routes):**
   - `HomeStorefront.tsx` & `ShopCategoryDirectory.tsx` use `LuxuryTopHeader.tsx`.
   - `PublicDropView.tsx` uses `DropHeader.tsx`.
   - `BoutiqueStorefrontView.tsx` renders an inline `<header className="ld-navbar">`.
   - `app/order/page.tsx` renders an inline `<header className="ld-navbar">` with "ORDERS" text.
   - `app/order/[id]/page.tsx` renders an inline `<header className="ld-checkout-header">`.
   - `app/checkout/page.tsx` renders an inline `<header className="ld-checkout-header">`.
   - `app/cart/page.tsx` renders an inline `<header className="px-4 py-4 ...">`.
   *Remedy:* Unify under a single, responsive `LuxuryTopHeader` component supporting back-navigation, contextual titles, search, and bag triggers.

2. **Mobile Bottom Dock Layout Inconsistency:**
   - On desktop viewports (`≥ 768px`), `MobileBottomDock` floats as a 420px pill in the middle-bottom of the viewport (`left: 50%; transform: translateX(-50%)`), physically obstructing product cards and catalog items.
   *Remedy:* Dock must be strictly mobile-only (`block md:hidden`), while desktop relies on the top navigation bar.

3. **In-App Browser & Notification Banners:**
   - Ad-hoc banners scattered across views without unified design system styling.

---

## 4. CSS Systems & Legacy Stylesheet Analysis

The stylesheet `buyer-web/src/app/globals.css` spans **4,966 lines** and **98,463 bytes**. It exhibits significant technical debt from successive redesign iterations:

### 1. Competing Color Token Systems in `:root`
Four competing naming conventions coexist in `:root`:
- **Current Unified Palette:** `--ld-bg`, `--ld-surface`, `--ld-surface-2`, `--ld-gold`, `--ld-gold-soft`, `--ld-live`, `--ld-success`, `--ld-warning`, `--ld-border`.
- **Haute Couture / Stitch Tokens:** `--noir-black`, `--noir-card`, `--noir-elevated`, `--burgundy-deep`, `--burgundy-accent`, `--champagne-gold`, `--ivory-text`.
- **Obsidian Baseline:** `--obsidian`, `--obsidian-surface`, `--obsidian-elevated`, `--card-border`, `--card-border-gold`.
- **Legacy Spec:** `--gold-primary`, `--gold-secondary`, `--gold-light`, `--gold-gradient`, `--primary-emerald`.

### 2. Arbitrary Spacing & Dimensions
Arbitrary hardcoded pixel values are scattered across CSS rules:
- Heights: `38px`, `40px`, `42px`, `50px`, `54px`, `56px`, `70px`, `85px`.
- Border radiuses: `3px`, `4px`, `6px`, `8px`, `12px`, `14px`, `18px`, `20px`, `24px`, `28px`, `9999px`.
- Shadows: Competing box-shadow definitions (`0 2px 6px ...`, `0 4px 18px ...`, `0 12px 32px ...`, `-10px 0 30px ...`).

### 3. Font Misapplication (Serif Leaking into Functional UI)
- Global style rules or container font inheritance cause **Cormorant Garamond (Serif)** to leak into:
  - Form inputs and placeholder text (`CheckoutForm`, `OrderLookupPage`).
  - Button text and CTAs (`EXPLORE SHOP`, `EXPLORE COLLECTIONS →`, `Find Order →`).
  - Category tabs and filter chips.
  - Product descriptions.
  *Design Rule:* Serif is reserved strictly for **editorial headlines and brand display**. Modern sans-serif (`Plus Jakarta Sans`) must be enforced for all functional UI, buttons, inputs, pills, metadata, and body copy.

---

## 5. Root Cause Investigation: Header Flicker While Scrolling

### Symptoms
When scrolling down or up on `/` or `/shop`, the header vibrates, flashes, disappears and reappears rapidly, or stutters during deceleration and momentum scroll.

### Diagnostic Matrix

| Suspected Cause | Investigation Finding | Verdict |
|---|---|---|
| **Scroll Listener & Unthrottled State Updates** | In `LuxuryTopHeader.tsx` (lines 30–52), `window.addEventListener('scroll', handleScroll)` runs on every scroll frame (60–120Hz). `setIsScrolled` and `setIsVisible` are called repeatedly during scroll gestures without `requestAnimationFrame` scheduling or throttling. | **PRIMARY CAUSE** |
| **8px Delta Threshold Ping-Pong Oscillation** | The condition `if (currentScrollY > lastScrollY && currentScrollY - lastScrollY > 8)` triggers `setIsVisible(false)`. During momentum scrolling, deceleration, or finger lift, touch micro-rebound (-9px) immediately trips `lastScrollY - currentScrollY > 8`, triggering `setIsVisible(true)`. This causes a high-frequency toggle loop: `visible -> hidden -> visible -> hidden` within milliseconds. | **PRIMARY CAUSE** |
| **CSS Transition Interruption & Compositing Thrashing** | `.ld-luxury-header` has `transition: transform 0.3s cubic-bezier(0.16, 1, 0.3, 1)` and `backdrop-filter: blur(16px)`. Rapidly toggling `.hidden` (`transform: translateY(-100%)`) cancels animations mid-flight, forcing the GPU to repeatedly recomposite heavy blur layers. | **PRIMARY CAUSE** |
| **Sticky Positioning & Boundary Recalculation** | Header uses `position: sticky; top: 0;`. When translated out of view while sticky inside normal document flow, it does not cause reflow, but combined with background opacity shifts, it creates visual flickering against dark hero images. | **CONTRIBUTING FACTOR** |
| **Hydration Mismatch** | Header renders with `isVisible = true` on both server and client. Hydration is clean and does not trigger scroll-time re-renders. | **RULED OUT** |
| **Resize Events / Viewport Recalculation** | No resize listeners are active during scroll. | **RULED OUT** |
| **Duplicated Header Rendering** | `LuxuryTopHeader` is rendered once per page; there is no duplicate component instance in DOM. | **RULED OUT** |

### Definitive Root-Cause Summary
The scroll flicker is caused by an **unthrottled scroll event listener coupled with an aggressive 8px delta threshold that triggers a React state update ping-pong loop, which repeatedly cancels and restarts CSS transform transitions on a GPU-heavy `backdrop-filter` sticky container**.

### Architectural Solution
1. **Persistent Sticky Elegance (Recommended):** Modern luxury commerce experiences (Net-A-Porter, Sabyasachi, Farfetch) keep a compact, fixed sticky header (48px) rather than collapsing on scroll. Eliminating the collapse mechanism completely removes all transform animations, eliminates GPU thrashing, and ensures the brand logo and shopping bag are 100% accessible at all scroll depths.
2. **Smooth Hysteresis (If Collapsible):** If auto-hide is retained, it must use a debounced/`requestAnimationFrame` loop with a wide hysteresis window (e.g. 50px delta) and zero micro-toggling.

---

## 6. Mobile Layout & Responsive Issues

Based on local browser audit across 390px (Mobile) and 1280px (Desktop):

1. **Desktop Dock Obstruction:**
   `MobileBottomDock` renders on desktop viewports as an awkward floating pill blocking product cards at the bottom center.
2. **Category Rail Crowding on Mobile `/shop`:**
   On `/shop`, the "Sort by" dropdown is stacked inline with horizontal category filter pills without adequate vertical rhythm, leading to visual collision.
3. **Empty State Void:**
   `/cart` and `/checkout` empty states render a tiny icon and button with >500px of bare black empty space below.
4. **All-Caps Harsh Buttons:**
   Cart and drawer continue to render all-caps CTAs (`EXPLORE SHOP`, `EXPLORE COLLECTIONS →`) in Cormorant Garamond serif, violating luxury styling guidelines.
5. **Product Detail Typography Clutter:**
   Product description, feature tags, and store review text inherit serif font styles, reducing legibility.

---

## 7. Recommended Phased Implementation Sequence

To adhere to the phased visual refactor protocol and maintain test coverage:

```
[Phase 0: Audit & Architecture Verification]  <-- COMPLETED
        ↓
[Phase 1: Design Tokens & Visual Foundation]
        • Single coherent buyer palette in globals.css
        • Typography hierarchy (Cormorant Garamond = Editorial headlines only; Plus Jakarta Sans = UI)
        • Standardized spacing (4, 8, 12, 16, 20, 24, 32, 40, 48, 64px)
        • Radius scale (sm: 6px, md: 10px, lg: 16px, pill: 9999px)
        • Elevation & shadow scale (zero aggressive glows)
        • Test suite validation (460/460 passing)
        ↓
[Phase 2: Core Navigation & Header Unification]
        • Header scroll flicker fix (persistent smooth sticky header)
        • Unified LuxuryTopHeader across all routes
        • MobileBottomDock strictly mobile-only (hidden on md/lg)
        ↓
[Phase 3: Catalog & Product Card Presentation]
        • ProductCard visual elevation (hairline champagne borders, refined badges, typography)
        • ProductDetailModal luxury styling (sans-serif body copy, refined buttons)
        • Category chips rail styling
        ↓
[Phase 4: Cart, Checkout & Direct UPI Payment Experience]
        • CartDrawer & CartItemRow luxury elevation
        • CheckoutForm & CheckoutReview visual refinement
        • DirectUpiPaymentView luxury card, QR presentation, status timeline
        • Empty cart and empty checkout states
        ↓
[Phase 5: Final Cross-Device Visual QA & Polish]
        • Multi-viewport browser validation (360px, 390px, 768px, 1280px, 1440px)
        • Complete E2E regression verification
```

---

## 8. Verification & Gate Signoff

- **Baseline Test Suite:** All 30 test files and 460 vitest unit/integration tests pass with exit code 0.
- **Typecheck:** `tsc --noEmit` passes with 0 errors.
- **Lint:** ESLint passes with 0 errors.
- **Next.js Production Build:** Completed successfully with Turbopack in 8.1s.
- **Application Code Status:** 100% frozen in Phase 0. No application code has been modified.

---
*End of Phase 0 Audit Document.*
