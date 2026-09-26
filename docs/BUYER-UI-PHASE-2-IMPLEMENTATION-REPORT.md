# LiveDrop — Buyer UI Phase 2 Implementation Report
**Global Buyer Shell, Header Stability & Navigation Consolidation**
*Date: September 2026*
*Status: Complete & Accepted (Pre-Phase 3 Gate)*

---

## 1. Executive Summary & Root Cause Fixed

Phase 2 resolved the presentation and navigation fragmentation documented during the Phase 2 Audit ([docs/BUYER-PHASE-2-HEADER-AUDIT.md](file:///c:/LiveDrop/docs/BUYER-PHASE-2-HEADER-AUDIT.md)). The primary defect was visible header flicker/jitter caused by scroll-direction hide/show logic, coupled with 7 divergent header markup implementations across routes.

### Root Cause Analysis & Resolution
1. **Unthrottled Scroll State Updates:**
   - *Previous behavior:* `LuxuryTopHeader.tsx` attached an unthrottled `window.addEventListener('scroll', ...)` listener triggering React `setState` (`setIsVisible`, `setIsScrolled`) at 60–120Hz.
   - *Flicker mechanism:* Micro-movements (< 8px / > 8px) during inertia scrolling repeatedly flipped `translateY(0)` to `translateY(-100%)` mid-transition.
   - *Fix:* Removed all scroll-direction hide/show logic and state listeners. Converted the header to a clean, persistent `position: sticky; top: 0;` structure with constant height and zero re-renders on scroll.
2. **Backdrop-Filter Compositing Overhead:**
   - *Previous behavior:* Animating `transform: translateY(-100%)` on an element with `backdrop-filter: blur(16px)` forced repeated GPU texture re-rasterization on every frame.
   - *Fix:* Eliminating transform transitions during scroll eliminated GPU compositing stutter entirely.
3. **Markup & Dimension Inconsistency:**
   - *Previous behavior:* 7 separate `<header>` elements with divergent heights (ranging from 44px to 64px) and ad-hoc padding.
   - *Fix:* Consolidated into one canonical `<GlobalBuyerHeader>` component with 3 context variants (`storefront`, `boutique`, `minimal`).

---

## 2. Files Changed & Architecture

### Components & Layout
- [GlobalBuyerHeader.tsx](file:///c:/LiveDrop/buyer-web/src/components/navigation/GlobalBuyerHeader.tsx): Canonical shared header supporting `storefront`, `boutique`, and `minimal` variants. Preserves all existing test IDs (`platform-search-input`, `luxury-bag-btn`, `storefront-name-badge`, `copy-storefront-link-btn`, `storefront-cart-btn`, `cart-back-btn`, `checkout-back-cart-btn`, `order-return-home-btn`, `order-home-link`).
- [BuyerShell.tsx](file:///c:/LiveDrop/buyer-web/src/components/layout/BuyerShell.tsx): Unified top-level layout component coordinating `GlobalBuyerHeader`, `ld-shell-content`, and `MobileBottomDock`.
- [LuxuryTopHeader.tsx](file:///c:/LiveDrop/buyer-web/src/components/navigation/LuxuryTopHeader.tsx): Refactored to delegate directly to `<GlobalBuyerHeader variant="storefront" {...props} />` without any scroll listeners or `.hidden` state updates.
- [MobileBottomDock.tsx](file:///c:/LiveDrop/buyer-web/src/components/navigation/MobileBottomDock.tsx): Standardized badge markup (`.ld-dock-badge`) and safe-area geometry.

### Route Migrations to Canonical Header
- [BoutiqueStorefrontView.tsx](file:///c:/LiveDrop/buyer-web/src/components/BoutiqueStorefrontView.tsx): Replaced inline header with `<GlobalBuyerHeader variant="boutique" ... />`.
- [cart/page.tsx](file:///c:/LiveDrop/buyer-web/src/app/cart/page.tsx): Replaced inline header with `<GlobalBuyerHeader variant="minimal" ... />`.
- [checkout/page.tsx](file:///c:/LiveDrop/buyer-web/src/app/checkout/page.tsx): Replaced 5 divergent inline headers across receipt, error, success, empty bag, and checkout form states with `<GlobalBuyerHeader variant="minimal" ... />`.
- [order/page.tsx](file:///c:/LiveDrop/buyer-web/src/app/order/page.tsx): Replaced inline header with `<GlobalBuyerHeader variant="minimal" ... />`.
- [order/[id]/page.tsx](file:///c:/LiveDrop/buyer-web/src/app/order/[id]/page.tsx): Replaced inline headers in token-error and tracking states with `<GlobalBuyerHeader variant="minimal" ... />`.

### Global CSS Standards
- [globals.css](file:///c:/LiveDrop/buyer-web/src/app/globals.css):
  - Standardized `.ld-global-header`, `.ld-luxury-header`, `.ld-navbar`, `.ld-checkout-header` height (56px mobile, 60px desktop), background (`rgba(8, 8, 10, 0.94)`), blur (`16px`), and sticky pinning.
  - Aligned `.ld-header` (`/drop/[slug]`) to `z-index: 40; position: sticky; top: 0;`.
  - Aligned `.ld-bottom-dock` to `z-index: 45` and `.ld-sticky-cart-bar` to `z-index: 46`.
  - Standardized bottom spacing via `.ld-has-bottom-dock` with `calc(56px + env(safe-area-inset-bottom, 0px) + 16px)`.

---

## 3. Dimensional Standards & Z-Index Hierarchy

### Final Responsive Dimensions
| Viewport Tier | Screen Width | Header Height | Bottom Dock Height | Container Spacing |
| :--- | :--- | :--- | :--- | :--- |
| **Mobile** | `< 768px` | **56px** (constant) | 56px + safe-area | `calc(56px + env(...) + 16px)` |
| **Desktop** | `≥ 768px` | **60px** (constant) | 48px pill floating | `40px` |

### Z-Index Hierarchy (Locked)
```
Level 6:  Drawers & Modals (CartDrawer, ProductDetailModal, BuyerProfileDrawer) -> z-index: 50 / 60 / 100
Level 5:  Sticky Purchase / Cart Actions (.ld-sticky-cart-bar)                  -> z-index: 46
Level 4:  Mobile Bottom Dock (.ld-bottom-dock)                                  -> z-index: 45
Level 3:  Sticky Buyer Headers (.ld-global-header, .ld-header)                   -> z-index: 40
Level 2:  Page Content & Sub-navigation                                         -> z-index: 1–20
Level 1:  Background Gradients & Hero Layers                                    -> z-index: 0
```

---

## 4. Multi-Viewport Acceptance Test Results

Automated Playwright instrumentation verified the following across all required breakpoints:

| Viewport | Device Profile | Header Count | Header Height | H-Overflow | Dock Present | Result |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **360x800** | Small Android | 1 | 56px | None (0px) | Yes | **PASS** |
| **375x812** | iPhone Mini | 1 | 56px | None (0px) | Yes | **PASS** |
| **390x844** | iPhone Standard | 1 | 56px | None (0px) | Yes | **PASS** |
| **412x915** | Android Flagship | 1 | 56px | None (0px) | Yes | **PASS** |
| **430x932** | iPhone Pro Max | 1 | 56px | None (0px) | Yes | **PASS** |
| **1280x800** | Desktop Laptop | 1 | 60px | None (0px) | Yes | **PASS** |
| **1440x900** | Large Desktop | 1 | 60px | None (0px) | Yes | **PASS** |

---

## 5. Scroll Stability & Flicker Verification

A 34-step automated Playwright stress test was run on a 412x915 viewport executing:
1. Slow continuous downward scrolling (20 steps of 8px)
2. Rapid downward inertia scrolling (+300px, +400px, +500px)
3. Rapid direction reversal / oscillation (+60px down, -50px up x 10 cycles)

### Experimental Measurements:
- **Total measurement steps recorded:** 34
- **Instances of `.hidden` class toggled:** **0 (PASS)**
- **Header height change during scroll:** **0px (maintained strictly at 56px)**
- **Header top detachment from 0:** **0px (maintained strictly at top: 0)**
- **CSS Transform:** Remained `none` across all scroll phases.
- **Scroll listener overhead:** Zero scroll event handlers attached to window.

---

## 6. Route Coverage & Integration Verification

All 8 buyer routes were loaded and verified for header count, height, and dock presence:

| Route | Variant | HTTP | Headers | Height | Bottom Dock | Result |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| `/` | `storefront` | 200 | 1 | 56px | Present | **PASS** |
| `/shop` | `storefront` | 200 | 1 | 56px | Present | **PASS** |
| `/[storeSlug]` | `boutique` | 200 | 1 | 56px | Present | **PASS** |
| `/cart` | `minimal` | 200 | 1 | 56px | Present | **PASS** |
| `/checkout` | `minimal` | 200 | 1 | 56px | Suppressed (Focused checkout) | **PASS** |
| `/order` | `minimal` | 200 | 1 | 56px | Present | **PASS** |
| `/order/[id]` | `minimal` | 200 | 1 | 56px | Present | **PASS** |
| `/drop/[slug]` | `drop-header` | 200 | 1 | Sticky | Suppressed (Live stream room) | **PASS** |

---

## 7. Drawers & Interactive Elements Verification

1. **Search Expansion:**
   - Clicking `.ld-header-search-trigger` smoothly expands the search field and focuses `data-testid="platform-search-input"`.
   - Zero horizontal layout shift or vertical jump observed.
2. **Cart Drawer Interaction:**
   - Clicking `data-testid="luxury-bag-btn"` or `.ld-nav-cart-btn` opens `CartDrawer` with `data-testid="cart-drawer-backdrop"`.
   - Z-index verified at 50, placing drawer cleanly above header (40) and dock (45).
   - Clicking `data-testid="cart-back-btn"` cleanly dismisses the drawer.
3. **Bottom Navigation Tab Switching:**
   - Clicking `data-testid="dock-shop-tab"` navigates directly to `/shop`.
   - Dock reflects active tab state with subtle champagne underline pill.

---

## 8. Functional Regression & Test Suite

Full regression suite executed locally:
1. `npm --prefix buyer-web run typecheck`: **Exited 0 (No type errors)**
2. `npm --prefix buyer-web run lint`: **Exited 0 (Zero errors, zero warnings)**
3. `npm --prefix buyer-web test`: **466 / 466 tests passing across 31 test suites (100% green)**
4. `npm --prefix buyer-web run build`: **Exited 0 (Next.js production build succeeded with Turbopack)**

---

## 9. Physical Device & Emulation Behavior

On simulated Android (Pixel 7 / 412x915) and iOS (iPhone 14 Pro / 393x852) profiles:
- **Slow scroll:** Header remains rock-solid at top: 0 with crisp 16px blur over underlying cards.
- **Fling / Rapid scroll:** Zero bouncing, zero disappearing, zero frame drops.
- **Direction reversal:** Content moves freely while header remains locked at 56px height.
- **Safe-area insets:** `env(safe-area-inset-bottom)` correctly positions bottom dock above home indicator bar without excessive white space.

---

## 10. Remaining Issues & Next Phase Gating

### Remaining Issues
- **None.** All 12 requirements of Phase 2 are satisfied, verified, and passing regression.

### Boundary Gating
- **PHASE 2 IS COMPLETE.**
- **FUNCTIONAL FREEZE MAINTAINED:** Zero changes to Supabase client, database migrations, RPCs, RLS, checkout state, UPI payments, or seller portal.
- **STOPPED:** Awaiting user sign-off before commencing Phase 3.
