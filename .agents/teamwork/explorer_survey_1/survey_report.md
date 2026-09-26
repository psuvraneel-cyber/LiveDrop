# LiveDrop Phase B Architecture & Navigation Survey Report

**Surveyor:** Explorer 1 (Survey: Architecture, Design Tokens, Global Shared Primitives & Layout Navigation)  
**Date:** 2026-09-27  
**Status:** Complete & Verified Read-Only Survey  
**Scope:** Phase B — Global Shared Visual Primitives, Design Tokens, `GlobalBuyerHeader`, `MobileBottomDock`, and Layout Navigation  
**Authoritative Documents:**
- `docs/BUYER-REFERENCE-DESIGN-SPEC.md` (Sections 1–6, 7, 8, 17–24)
- `docs/SOURCE-OF-TRUTH.md`
- `docs/35-engineering-conventions.md`
- `AGENTS.md`
- `.agents/teamwork/ORIGINAL_REQUEST.md`

---

## 1. Executive Summary & Verification Baseline

Before beginning code and token analysis, all automated test gates and build pipelines were executed to establish a strictly verified baseline:

| Gate | Command | Result | Details |
|---|---|---|---|
| **TypeScript** | `npm --prefix buyer-web run typecheck` | **PASS (Code 0)** | 0 type errors across Next.js 16.3.4 & React 19.2.8 |
| **ESLint** | `npm --prefix buyer-web run lint` | **PASS (Code 0)** | 0 lint warnings or errors |
| **Unit & Integration** | `npm --prefix buyer-web test` | **PASS (Code 0)** | **31 test files passed, 474 tests passed, 0 failures** |
| **Production Build** | `npm --prefix buyer-web run build` | **PASS (Code 0)** | All 9 routes compiled cleanly via Turbopack |

All Phase B modifications must preserve this 474/474 test pass rate and clean build status.

---

## 2. CSS Architecture, Tailwind v4 Setup & Design Tokens

### 2.1 Tailwind CSS v4 Architecture
The project runs **Tailwind CSS v4.3.3** with `@tailwindcss/postcss`.
- **Configuration Split**:
  - `buyer-web/tailwind.config.ts`: Contains minimal content glob patterns and default color extends (`background`, `foreground`).
  - `buyer-web/src/app/globals.css`: Contains `@import "tailwindcss";` followed by `@theme { ... }` and `:root { ... }`.
- **How Tailwind v4 Resolves Variables**:
  In Tailwind v4, `@theme { --color-*: ...; }` registers utilities for `bg-*`, `text-*`, `border-*`, etc.
  However, `:root { ... }` defines CSS custom properties for standard vanilla CSS, which are accessible via `var(--...)`.

### 2.2 Token Registry & Mapping Matrix
Comparing `docs/BUYER-REFERENCE-DESIGN-SPEC.md` Section 2 with `buyer-web/src/app/globals.css`:

| Token Name | Spec Value | `globals.css` `:root` (Line) | `globals.css` `@theme` (Line) | Status / Utility Availability |
|---|---|---|---|---|
| `--ld-bg` | `#08080A` | `#08080A` (Line 32) | `--color-ld-bg: #08080A` (Line 8) | ✅ Available as `bg-ld-bg`, `text-ld-bg` |
| `--ld-surface` | `#0E0E12` | `#0E0E12` (Line 33) | `--color-ld-surface: #0E0E12` (Line 9) | ✅ Available as `bg-ld-surface` |
| `--ld-surface-elevated` | `#16161C` | `#16161C` (Line 34) | `--color-ld-surface-elevated: #16161C` (Line 10) | ✅ Available as `bg-ld-surface-elevated` |
| `--ld-surface-subtle` | `#121217` | `#121217` (Line 35) | `--color-ld-surface-subtle: #121217` (Line 11) | ✅ Available as `bg-ld-surface-subtle` |
| `--ld-border` | `rgba(255, 255, 255, 0.08)` | `rgba(255, 255, 255, 0.08)` (Line 39) | `--color-ld-border: rgba(255, 255, 255, 0.08)` (Line 12) | ✅ Available as `border-ld-border` |
| `--ld-border-gold` | `rgba(212, 175, 55, 0.25)` | `rgba(212, 175, 55, 0.25)` (Line 41) | `--color-ld-border-gold: rgba(212, 175, 55, 0.25)` (Line 13) | ✅ Available as `border-ld-border-gold` |
| `--ld-border-gold-strong` | `rgba(212, 175, 55, 0.45)` | `rgba(212, 175, 55, 0.45)` (Line 42) | **MISSING** | ⚠️ In `:root` only; cannot use `border-ld-border-gold-strong` in Tailwind |
| `--ld-text-primary` | `#FBFBFB` | `#FBFBFB` (Line 45) | `--color-ld-text-primary: #FBFBFB` (Line 14) | ✅ Available as `text-ld-text-primary` |
| `--ld-text-secondary` | `rgba(244, 241, 234, 0.72)` | `rgba(244, 241, 234, 0.72)` (Line 46) | `--color-ld-text-secondary: ...` (Line 15) | ✅ Available |
| `--ld-text-muted` | `#AAA49A` | `#AAA49A` (Line 47) | `--color-ld-text-muted: #AAA49A` (Line 16) | ✅ Available as `text-ld-text-muted` |
| `--ld-gold` | `#D4AF37` | `#D4AF37` (Line 52) | `--color-ld-gold: #D4AF37` (Line 17) | ✅ Available as `bg-ld-gold`, `text-ld-gold`, `border-ld-gold` |
| `--ld-gold-soft` | `#F5D78E` | `#F5D78E` (Line 53) | `--color-ld-gold-soft: #F5D78E` (Line 18) | ✅ Available |
| `--ld-gold-deep` | `#C88A24` | `#C88A24` (Line 54) | `--color-ld-gold-deep: #C88A24` (Line 19) | ✅ Available |
| `--ld-gold-muted` | `rgba(212, 175, 55, 0.15)` | `rgba(212, 175, 55, 0.15)` (Line 55) | **MISSING** | ⚠️ In `:root` only |
| `--ld-gold-gradient` | `linear-gradient(...)` | Defined (Line 56) | N/A (CSS property) | ✅ Used in `.ld-gold-pill-btn` |
| `--ld-burgundy` | `#1A0D11` | `#1A0D11` (Line 60) | **MISSING** | ⚠️ In `:root` only |
| `--ld-burgundy-accent` | `#2D141C` | `#2D141C` (Line 61) | **MISSING** | ⚠️ In `:root` only |
| `--ld-live` | `#EF4444` | `#EF4444` (Line 65) | `--color-ld-live: #EF4444` (Line 20) | ✅ Available |
| `--ld-success` | `#10B981` | `#10B981` (Line 69) | `--color-ld-success: #10B981` (Line 21) | ✅ Available |
| `--ld-warning` | `#F59E0B` | `#F59E0B` (Line 73) | `--color-ld-warning: #F59E0B` (Line 22) | ✅ Available |
| `--ld-sold` | `#6B7280` | `#6B7280` (Line 77) | **MISSING** | ⚠️ In `:root` only; components resort to hardcoded `text-white/50` or `#6B7280` |

### 2.3 Typography Configuration & Font Resolution
- **Fonts Injected**:
  In `buyer-web/src/app/layout.tsx` (Lines 7–20):
  - `Cormorant_Garamond` is loaded with weights 400, 500, 600, 700 into CSS variable `--font-display`.
  - `Plus_Jakarta_Sans` is loaded with weights 400, 500, 600, 700 into CSS variable `--font-sans`.
  - Both are attached to `html` via `className={`${cormorant.variable} ${plusJakarta.variable}`}`.
- **Font Font-Stack Rules**:
  - `globals.css` (Line 211) locks `html, body, button, input, textarea, select` to `var(--font-sans), 'Plus Jakarta Sans', system-ui, sans-serif`.
  - Display utilities `.ld-text-display`, `.ld-text-heading`, `.ld-text-section` set `font-family: var(--font-display), 'Cormorant Garamond', Georgia, serif;`.
- **Investigation into Playfair / Cinzel / Inter**:
  - The query noted: "fonts (Playfair Display / Cinzel serif, Inter / Plus Jakarta Sans)".
  - Codebase grep confirmed:
    - Neither `Cinzel` nor `Inter` is imported or configured in `buyer-web/`.
    - `Playfair` was historically referenced in Flutter seller-app (`seller_pending_approval_screen.dart:73`).
    - The frozen authoritative specification `docs/BUYER-REFERENCE-DESIGN-SPEC.md` Section 3 explicitly standardizes on:
      - **Display Serif**: `Cormorant Garamond` (`var(--font-display)`)
      - **Body & Functional Sans**: `Plus Jakarta Sans` (`var(--font-sans)`)
- **CRITICAL GAP in Tailwind `@theme`**:
  `@theme` in `globals.css` does NOT map `--font-serif` or `--font-sans`. Therefore, when developers write `className="font-serif"` in Tailwind, it falls back to Tailwind default serif (Times New Roman / Georgia) instead of Cormorant Garamond!
  **Remedy for Phase B**: Add to `@theme` in `globals.css`:
  ```css
  --font-serif: var(--font-display), 'Cormorant Garamond', Georgia, serif;
  --font-display: var(--font-display), 'Cormorant Garamond', Georgia, serif;
  --font-sans: var(--font-sans), 'Plus Jakarta Sans', system-ui, sans-serif;
  ```

---

## 3. `GlobalBuyerHeader` Component Deep Dive

### 3.1 Architecture & Locations
- Primary Component: `buyer-web/src/components/navigation/GlobalBuyerHeader.tsx` (312 lines)
- Backward-Compatible Wrapper: `buyer-web/src/components/navigation/LuxuryTopHeader.tsx` (15 lines, delegates to `GlobalBuyerHeader variant="storefront"`)
- Test Coverage: `buyer-web/src/test/global-buyer-header.test.tsx` (6 unit tests, verifies variants and flicker immunity)

### 3.2 Props Interface Contract
```typescript
export type BuyerHeaderVariant = 'storefront' | 'boutique' | 'minimal';

export interface GlobalBuyerHeaderProps {
  variant?: BuyerHeaderVariant;
  // Storefront variant props
  searchQuery?: string;
  onSearchChange?: (query: string) => void;
  showSearch?: boolean;
  // Boutique variant props
  storeName?: string;
  storeSlug?: string;
  onShare?: () => void;
  isCopied?: boolean;
  hasLiveDrop?: boolean;
  // Minimal / Checkout / Order variant props
  title?: string;
  subtitle?: string;
  backHref?: string;
  onBack?: () => void;
  backLabel?: string;
  backTestId?: string;
  rightAction?: React.ReactNode;
}
```

### 3.3 Visual & Functional Analysis of Header Variants

#### Variant 1: `storefront` (Screens 01 & 02)
- **Geometry**: Height 56px (`height: 56px` on mobile, `height: 60px` at `md: 768px+`).
- **Sticky / Scrolling Behavior**:
  - `position: sticky; top: 0; z-index: 40;`
  - `background: rgba(8, 8, 10, 0.94); backdrop-filter: blur(16px); border-bottom: 1px solid var(--ld-border);`
  - Immune to scroll-jitter: Zero `window.addEventListener('scroll')` calls (tested in `global-buyer-header.test.tsx:71`).
- **Left Monogram Brand Emblem**:
  - Four-pointed sparkle: `<span className="ld-header-crest-icon">✦</span>`. Font size is 16px (Spec Section 7 calls for 18px). Color is `var(--champagne-gold)` (`#D4AF37`).
  - Title: `<span className="ld-header-title">LiveDrop</span>` in `var(--font-display)` (Cormorant Garamond, 21px).
  - Subtitle: `<span className="ld-header-subtitle">INDIAN LUXURY LIVE</span>` in `var(--font-sans)` (8px, uppercase, letter-spacing 0.18em).
- **Center Navigation**:
  - Desktop nav links (`Shop`, `Live Drops`, `Collections`, `Boutiques`) hidden on mobile (`display: none` below 860px).
- **Right Action Bar**:
  - Search trigger icon (`.ld-header-search-trigger`): 38×38px button that toggles inline expansion of `.ld-header-search-field`.
  - Bag button (`.ld-header-bag-btn`): 38×38px button triggering `openDrawer` from `useOptionalCart()`, or linking to `/cart`.
  - Badge counter (`.ld-header-bag-badge`): Min-width 17px, height 17px, rounded-full, background `#D4AF37`, color `#08080A`, bold text.
- **Touch Target Audit**:
  - Buttons (`.ld-header-icon-btn`) are currently styled at `width: 38px; height: 38px;`.
  - *Discrepancy*: Fails strict 44–48px touch target requirements unless padded or given `::after` touch expansion.

#### Variant 2: `boutique` (`/[storeSlug]`)
- Renders `✦ LiveDrop BOUTIQUE` on left, store name badge in center (`.ld-storefront-nav-name`), and share + cart buttons on right.

#### Variant 3: `minimal` (`/cart`, `/checkout`, `/order`, `/order/[id]`)
- Renders back button on left, centered title in Cormorant Garamond serif (`.ld-header-minimal-title`), and `rightAction` or spacer on right.
- *Discrepancies*:
  - `/cart`: Title is `"Your Cart (N)"`, back button goes to `/`. Spec Screen 06 calls for title in Cormorant Garamond and "Clear" button in gold text on right.
  - `/checkout`: Currently renders `title="LiveDrop"` instead of `"Checkout"` (Spec Screen 08).
  - `/order`: Currently renders `title="LiveDrop ORDERS"` instead of `"LiveDrop"` with subtitle `"ORDERS"` (Spec Screen 10).
  - `/order/[id]`: Currently renders `title="LiveDrop"` instead of `"Track Your Order"` with order subtitle (Spec Screen 11).

---

## 4. `MobileBottomDock` Component Deep Dive

### 4.1 Architecture & Implementation
- Component File: `buyer-web/src/components/navigation/MobileBottomDock.tsx` (209 lines)
- Test Coverage: `buyer-web/src/test/mobile-bottom-dock.test.tsx` (7 unit tests)
- Rendered In: Fixed viewport bottom across routes.

### 4.2 The 5 Navigation Tabs
| Tab Index | ID | Icon | Label | Target Route / Action | Active Condition |
|---|---|---|---|---|---|
| **1** | `dock-home-tab` | Home (20×20) | `Home` | `/` | `pathname === '/' && !hash && !drawerOpen` |
| **2** | `dock-live-tab` | Broadcast waves + red pulsing dot (20×20) | `Live` | `/#live-drops` | `pathname === '/' && hash === '#live-drops'` (or `/drop/*`) |
| **3** | `dock-shop-tab` | Storefront Bag (20×20) | `Shop` | `/shop` | `pathname === '/shop'` |
| **4** | `dock-orders-tab` | Receipt / Invoice (20×20) | `Orders` | `/order` | `pathname.startsWith('/order')` |
| **5** | `dock-bag-tab` | Shopping Bag + Gold count badge (20×20) | `Bag` | `/cart` or `openDrawer()` | `pathname === '/cart' \|\| pathname === '/checkout' \|\| isDrawerOpen` |

### 4.3 Geometry, Styling & Safe Area Padding
- **Geometry**:
  - Container (`.ld-bottom-dock`): `position: fixed; bottom: 0; left: 0; right: 0; z-index: 45;`.
  - Inner row (`.ld-bottom-dock-inner`): `height: 56px; max-width: 480px; margin: 0 auto; display: flex; align-items: center;`.
  - Spec Section 8 specifies: `height: 60px + env(safe-area-inset-bottom)`.
  - Background: `rgba(10, 10, 14, 0.96); backdrop-filter: blur(20px); border-top: 1px solid var(--ld-border);`.
  - Desktop extension (`min-width: 768px`): Centers dock at `bottom: 16px; width: 100%; max-width: 440px; border-radius: 9999px; box-shadow: var(--shadow-elevated)`.
- **Safe Area Insets**:
  - Container padding: `padding-bottom: env(safe-area-inset-bottom, 0px)`.
  - Page buffer padding: `.ld-has-bottom-dock` applies `padding-bottom: calc(56px + env(safe-area-inset-bottom, 0px) + 16px) !important;`.
- **Touch Target Assessment**:
  - Each tab is `flex: 1; height: 100%;` inside a 480px max-width container.
  - Effective touch area is `~72px to 96px width × 56px height`, comfortably satisfying the 44–48px mobile touch target rule.
- **Active State Indicators**:
  - Text and Icon: `color: var(--champagne-gold)` (`#D4AF37`).
  - Active Indicator: Current `.ld-dock-active-line` is placed at `top: 0; left: 50%; transform: translateX(-50%); width: 16px; height: 2px; background: var(--champagne-gold);`.
  - Inactive State Color: Currently `rgba(251, 251, 251, 0.45)` (45% opacity). Spec Section 8 specifies `#AAA49A` (`var(--ld-text-muted)`).

### 4.4 CRITICAL ARCHITECTURAL CONFLICT: `/drop/[slug]` Suppression
In `MobileBottomDock.tsx` lines 65–68:
```typescript
  // Don't render on live drop fullscreen room if it conflicts with real-time controls
  if (pathname?.startsWith('/drop/')) {
    return null;
  }
```
And in `mobile-bottom-dock.test.tsx` lines 92–97:
```typescript
  it('strictly hides the dock on fullscreen live drop rooms (/drop/[slug])', () => {
    mockPathname = '/drop/midnight-silks';
    renderWithProviders(<MobileBottomDock />);

    expect(screen.queryByTestId('mobile-bottom-dock')).not.toBeInTheDocument();
  });
```
**Conflict Analysis**:
- `docs/BUYER-REFERENCE-DESIGN-SPEC.md` Section 8 explicitly states:
  > **Rule:** The dock renders on Home, Shop, Orders, Cart, and Live Drop Room (matching reference Screen 03).
- And Section 15 (Screen 03):
  > 7. `MobileBottomDock`: Live active
- And `.agents/teamwork/ORIGINAL_REQUEST.md` R5:
  > - Render `MobileBottomDock` with "Live" active
- **Safety Resolution for Phase B**:
  - The suppression was introduced in Phase 1 to satisfy `TASK-2.1/2.2` test requirements.
  - In Phase B, changing this unconditionally would break `mobile-bottom-dock.test.tsx:92`!
  - **Recommended Phase B Strategy**: Add a prop `forceShow?: boolean` or environment/route flag, or defer the `/drop/` unsuppression and test update to **Phase E** (which specifically implements Screen 03 and aligns `CinematicLiveRoomView.tsx`), ensuring zero test failures in Phase B.

---

## 5. Layout Hierarchy & Route Rendering Analysis

### 5.1 Root Layout & Providers
- `buyer-web/src/app/layout.tsx`:
  ```tsx
  export default function RootLayout({ children }: { children: ReactNode }) {
    return (
      <html lang="en" className={`${cormorant.variable} ${plusJakarta.variable}`}>
        <body className="ld-body-root">
          <AppProviders>{children}</AppProviders>
        </body>
      </html>
    );
  }
  ```
- `AppProviders.tsx`:
  - Encloses children in `CartProvider` and `ProfileProvider`.
  - Mounts `<GlobalAppOverlays />` which contains `<CartDrawer />` and `<BuyerProfileDrawer />`.
  - Does NOT mount navigation headers or docks globally.

### 5.2 Per-Route Navigation Matrix
| Route | Page File | Header Rendered | Dock Rendered | Bottom Padding Class |
|---|---|---|---|---|
| `/` | `app/page.tsx` -> `HomeStorefront.tsx` | `LuxuryTopHeader` (`variant="storefront"`) | `MobileBottomDock` | `ld-has-bottom-dock` / `ld-home-storefront` |
| `/shop` | `app/shop/page.tsx` -> `ShopCategoryDirectory.tsx` | `LuxuryTopHeader` (`variant="storefront"`) | `MobileBottomDock` | `ld-has-bottom-dock` |
| `/[storeSlug]` | `app/[storeSlug]/page.tsx` -> `BoutiqueStorefrontView.tsx` | `GlobalBuyerHeader` (`variant="boutique"`) | `MobileBottomDock` | `ld-has-bottom-dock` |
| `/cart` | `app/cart/page.tsx` | `GlobalBuyerHeader` (`variant="minimal"`) | `MobileBottomDock` | `ld-has-bottom-dock` |
| `/checkout` | `app/checkout/page.tsx` | `GlobalBuyerHeader` (`variant="minimal"`) | **None** (Full-bleed checkout) | Standard padding |
| `/order` | `app/order/page.tsx` | `GlobalBuyerHeader` (`variant="minimal"`) | `MobileBottomDock` | `ld-has-bottom-dock` |
| `/order/[id]` | `app/order/[id]/page.tsx` | `GlobalBuyerHeader` (`variant="minimal"`) | `MobileBottomDock` | `ld-has-bottom-dock` |
| `/drop/[slug]` | `app/drop/[slug]/page.tsx` -> `PublicDropView.tsx` | `DropHeader` or `CinematicLiveRoomView` top bar | Suppressed | `pb-20` / custom |

### 5.3 `BuyerShell.tsx` Component Status
- `buyer-web/src/components/layout/BuyerShell.tsx`:
  - Contains a standard wrapper with `showHeader`, `showBottomDock`, and `headerProps`.
  - Currently **only referenced in `src/test/global-buyer-header.test.tsx`** (Lines 89–119).
  - No production routes in `app/` currently use `BuyerShell`.
  - Each page directly renders its header and dock to maintain full control over page-specific search handlers and sticky banners.

### 5.4 Cumulative Layout Shift (CLS) Assessment
- Both `GlobalBuyerHeader` and `LuxuryTopHeader` render with a static CSS height of 56px (`height: 56px; position: sticky; top: 0;`).
- `MobileBottomDock` renders with a static CSS height of 56px fixed to the bottom (`position: fixed; bottom: 0;`).
- All pages that host `MobileBottomDock` reserve bottom margin via `.ld-has-bottom-dock` (`padding-bottom: calc(56px + env(safe-area-inset-bottom, 0px) + 16px) !important;`).
- Result: **Zero layout shift (CLS = 0)** during route transitions or page hydration.

---

## 6. Discrepancy Matrix vs `docs/BUYER-REFERENCE-DESIGN-SPEC.md`

| Area | Feature / Element | Reference Design Spec | Current Implementation | Severity | Phase B Action |
|---|---|---|---|---|---|
| **Tokens** | Tailwind `@theme` font-serif | Should resolve `font-serif` to Cormorant Garamond (`var(--font-display)`) | `@theme` has NO font definitions; `font-serif` resolves to system serif | **Medium** | Add `--font-serif: var(--font-display), 'Cormorant Garamond', Georgia, serif;` to `@theme` |
| **Tokens** | Tailwind `@theme` font-sans | Should resolve `font-sans` to Plus Jakarta Sans (`var(--font-sans)`) | `@theme` has NO font definitions | **Medium** | Add `--font-sans: var(--font-sans), 'Plus Jakarta Sans', system-ui, sans-serif;` to `@theme` |
| **Tokens** | Missing `@theme` colors | `--color-ld-border-gold-strong`, `--color-ld-sold`, `--color-ld-gold-muted` | Present in `:root`, absent in `@theme` | **Low** | Add missing color tokens to `@theme` |
| **Header** | Crest Sparkle Icon Size | 18px four-pointed sparkle (`✦`) | 16px in `.ld-header-crest-icon` | **Low** | Update `.ld-header-crest-icon` font size to 18px |
| **Header** | Bag Badge Geometry | Circular gold badge (`#D4AF37`, 18px diameter, bold black number) | Min-width 17px, height 17px, border-radius 9px | **Low** | Adjust `.ld-header-bag-badge` to 18×18px circular |
| **Header** | Icon Button Touch Target | Min 44–48px accessible touch target | `.ld-header-icon-btn` is 38×38px without touch expansion | **Medium** | Add accessible touch hit area (`min-w-[44px] min-h-[44px]` or pseudo-element) |
| **Header** | Backdrop Background Alpha | `rgba(8, 8, 10, 0.92)` with `backdrop-filter: blur(16px)` | `rgba(8, 8, 10, 0.94)` | **Trivial** | Align to 0.92 for airy glassmorphism |
| **Dock** | Dock Height | Height 60px + `env(safe-area-inset-bottom)` | Height 56px (`.ld-bottom-dock-inner`) | **Medium** | Increase height to 60px in `.ld-bottom-dock-inner` and adjust `.ld-has-bottom-dock` padding |
| **Dock** | Inactive Tab Color | `#AAA49A` (`var(--ld-text-muted)`) | `rgba(251, 251, 251, 0.45)` | **Low** | Update inactive `.ld-dock-tab` color to `#AAA49A` |
| **Dock** | Active Indicator Line | Rich gold icon/text with gold underline bar or dot | Gold line at `top: 0` (overline) | **Low** | Position active line below icon or at tab bottom to match "underline bar" |
| **Dock** | Presence on Live Room (`/drop/*`) | Render on Live Room with "Live" active (Screen 03) | Suppressed on `/drop/*` in `MobileBottomDock.tsx:66` | **High** | Plan unsuppression for Phase E with test update |

---

## 7. Phase B Implementation Plan & File Touch Checklist

### 7.1 Files to Touch in Phase B

1. **`buyer-web/src/app/globals.css`**:
   - Update `@theme` block:
     - Add `--font-serif: var(--font-display), 'Cormorant Garamond', Georgia, serif;`
     - Add `--font-display: var(--font-display), 'Cormorant Garamond', Georgia, serif;`
     - Add `--font-sans: var(--font-sans), 'Plus Jakarta Sans', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;`
     - Add `--color-ld-border-gold-strong: rgba(212, 175, 55, 0.45);`
     - Add `--color-ld-sold: #6B7280;`
     - Add `--color-ld-gold-muted: rgba(212, 175, 55, 0.15);`
     - Add `--color-ld-burgundy: #1A0D11;`
     - Add `--color-ld-burgundy-accent: #2D141C;`
   - Update Header CSS:
     - `.ld-header-crest-icon`: `font-size: 18px;`
     - `.ld-header-bag-badge`: `width: 18px; height: 18px; min-width: 18px; border-radius: 50%;`
     - `.ld-header-icon-btn`: Ensure effective touch target is min 44×44px (e.g., `min-width: 44px; min-height: 44px;` or touch area expansion).
   - Update Bottom Dock CSS:
     - `.ld-bottom-dock-inner`: update height from `56px` to `60px`.
     - `.ld-dock-tab`: update inactive color to `#AAA49A`.
     - `.ld-has-bottom-dock`, `.ld-home-storefront`: update safe padding to `calc(60px + env(safe-area-inset-bottom, 0px) + 16px)`.

2. **`buyer-web/src/components/navigation/GlobalBuyerHeader.tsx`**:
   - Refine touch targets on search and bag icon buttons.
   - Refine badge rendering to ensure strictly 18px circular badge.
   - Ensure minimal variant supports custom titles and subtitles cleanly for Screens 06, 08, 09, 10, 11 without breaking existing test assertions in `global-buyer-header.test.tsx`.

3. **`buyer-web/src/components/navigation/MobileBottomDock.tsx`**:
   - Ensure active tab indicator matches spec (rich gold icon & text, gold underline bar or dot).
   - Retain backward-compatible props and route detection.
   - Ensure touch target sizes remain >= 44×44px.

4. **`buyer-web/src/test/global-buyer-header.test.tsx` & `mobile-bottom-dock.test.tsx`**:
   - Verify all existing tests pass with zero regressions.
   - Add test assertions for 60px height token / 18px sparkle / 18px bag badge.

### 7.2 Safety Invariants & Guardrails
- **DO NOT** modify any database migration, SQL function, or RPC.
- **DO NOT** modify any checkout idempotency, price calculation, or stock reservation logic.
- **DO NOT** alter the interface contracts of `GlobalBuyerHeaderProps` or `MobileBottomDockProps` in ways that break existing test suites.
- Guarantee that all 474 existing tests continue to pass after Phase B completion.
