# Phase B Handoff Report: Architecture, Design Tokens, Global Shared Primitives & Layout Navigation

**Author:** Explorer 1 (Survey: Architecture, Design Tokens, Global Shared Primitives & Layout Navigation)  
**Recipient:** orchestrator_1 (conversation ID: `4c705cbc-cf2b-425e-b111-d80dadaa5600`)  
**Date:** 2026-09-27  
**Working Directory:** `c:\LiveDrop\.agents\teamwork\explorer_survey_1`  
**Handoff Type:** Hard (Survey Task Complete)

---

## 1. Observation

1. **Automated Verification Baseline**:
   - `npm --prefix buyer-web run typecheck` exited with code 0.
   - `npm --prefix buyer-web run lint` exited with code 0.
   - `npm --prefix buyer-web test` passed all 31 test files and 474 tests (0 failures).
   - `npm --prefix buyer-web run build` successfully compiled all 9 application routes (`/`, `/[storeSlug]`, `/cart`, `/checkout`, `/drop/[slug]`, `/order`, `/order/[id]`, `/shop`, `/_not-found`).

2. **Tailwind v4 Setup & Font Tokens in `buyer-web/src/app/globals.css`**:
   - Lines 5–23 of `globals.css`:
     ```css
     @import "tailwindcss";

     @theme {
       --color-ld-bg: #08080A;
       --color-ld-surface: #0E0E12;
       --color-ld-surface-elevated: #16161C;
       --color-ld-surface-subtle: #121217;
       --color-ld-border: rgba(255, 255, 255, 0.08);
       --color-ld-border-gold: rgba(212, 175, 55, 0.25);
       --color-ld-text-primary: #FBFBFB;
       --color-ld-text-secondary: rgba(244, 241, 234, 0.72);
       --color-ld-text-muted: #AAA49A;
       --color-ld-gold: #D4AF37;
       --color-ld-gold-soft: #F5D78E;
       --color-ld-gold-deep: #C88A24;
       --color-ld-live: #EF4444;
       --color-ld-success: #10B981;
       --color-ld-warning: #F59E0B;
     }
     ```
   - In `@theme`, no font families (`--font-serif`, `--font-sans`, `--font-display`) are declared.
   - In `:root` (Lines 42, 60, 61, 77), tokens `--ld-border-gold-strong`, `--ld-burgundy`, `--ld-burgundy-accent`, and `--ld-sold` are defined, but omitted from `@theme`.

3. **Font Loading in `buyer-web/src/app/layout.tsx`**:
   - Lines 7–20:
     - `Cormorant_Garamond` sets `variable: "--font-display"`.
     - `Plus_Jakarta_Sans` sets `variable: "--font-sans"`.
   - Line 57: Attached to `<html>` via `className={`${cormorant.variable} ${plusJakarta.variable}`}`.
   - Grep search confirmed `Cinzel` does not exist in the repo; `Playfair` only appeared in Flutter `seller-app`.

4. **`GlobalBuyerHeader` Implementation**:
   - Path: `buyer-web/src/components/navigation/GlobalBuyerHeader.tsx`.
   - Lines 34–50: Implements `variant: 'storefront' | 'boutique' | 'minimal'`.
   - Wrapper: `buyer-web/src/components/navigation/LuxuryTopHeader.tsx` delegates to `GlobalBuyerHeader variant="storefront"`.
   - Line 67 & 204: Monogram sparkle `✦` (`.ld-header-crest-icon`) is styled at `font-size: 16px;` (Line 441 in `globals.css`). Spec Section 7 specifies `18px`.
   - Line 283: Bag badge counter (`.ld-header-bag-badge`) is `min-width: 17px; height: 17px; border-radius: 9px;`. Spec Section 7 specifies an 18px diameter circular badge.
   - Lines 505–506 of `globals.css`: `.ld-header-icon-btn` is `width: 38px; height: 38px;`, below the 44–48px recommended minimum touch target.
   - Sticky behavior: Pure CSS sticky (`position: sticky; top: 0;`). Unit test `global-buyer-header.test.tsx:71` asserts zero scroll listeners.

5. **`MobileBottomDock` Implementation**:
   - Path: `buyer-web/src/components/navigation/MobileBottomDock.tsx`.
   - Lines 84–205: Renders 5 tabs (`Home`, `Live`, `Shop`, `Orders`, `Bag`).
   - Line 756 of `globals.css`: `.ld-bottom-dock-inner` has `height: 56px;`. Spec Section 8 specifies `height: 60px + env(safe-area-inset-bottom)`.
   - Line 770 of `globals.css`: Inactive tab color is `color: rgba(251, 251, 251, 0.45);`. Spec Section 8 specifies `#AAA49A`.
   - Line 795 of `globals.css`: Active indicator `.ld-dock-active-line` is placed at `top: 0;` (overline). Spec specifies rich gold icon/text with gold underline bar or dot.
   - Lines 65–68 of `MobileBottomDock.tsx`:
     ```typescript
     if (pathname?.startsWith('/drop/')) {
       return null;
     }
     ```
     Guarded by unit test `buyer-web/src/test/mobile-bottom-dock.test.tsx:92`:
     ```typescript
     it('strictly hides the dock on fullscreen live drop rooms (/drop/[slug])', () => {
       mockPathname = '/drop/midnight-silks';
       renderWithProviders(<MobileBottomDock />);
       expect(screen.queryByTestId('mobile-bottom-dock')).not.toBeInTheDocument();
     });
     ```
     However, `BUYER-REFERENCE-DESIGN-SPEC.md` Section 8 & Section 15 (Screen 03) requires `MobileBottomDock` to render with "Live" active on live drop rooms.

6. **Layout Hierarchy & Route-Level Integration**:
   - `buyer-web/src/app/layout.tsx` wraps pages in `AppProviders` (`CartProvider`, `ProfileProvider`, `GlobalAppOverlays`). It does NOT render headers or docks.
   - Pages render their own headers and docks directly:
     - `/` (`HomeStorefront.tsx:179, 463`)
     - `/shop` (`ShopCategoryDirectory.tsx:100, 301`)
     - `/[storeSlug]` (`BoutiqueStorefrontView.tsx:105, 377`)
     - `/cart` (`app/cart/page.tsx:104, 310`)
     - `/checkout` (`app/checkout/page.tsx:419`) — no dock
     - `/order` (`app/order/page.tsx:113, 248`)
     - `/order/[id]` (`app/order/[id]/page.tsx:153, 168`)
   - `buyer-web/src/components/layout/BuyerShell.tsx` is defined and tested, but unused in production `app/` routes.
   - Fixed heights (56px) and padding prevent any cumulative layout shift (CLS = 0).

---

## 2. Logic Chain

1. **Font Utility Chain**:
   - *Observation 2 & 3*: `layout.tsx` injects `--font-display` and `--font-sans`, but `@theme` in `globals.css` does not define `--font-serif` or `--font-sans`.
   - *Reasoning*: In Tailwind v4, Tailwind classes `font-serif` and `font-sans` default to standard system fonts unless explicitly declared in `@theme`.
   - *Inference*: Adding `--font-serif: var(--font-display), 'Cormorant Garamond', Georgia, serif;` and `--font-sans: var(--font-sans), 'Plus Jakarta Sans', system-ui, sans-serif;` into `@theme` will ensure all components using `font-serif` render Cormorant Garamond consistently without requiring manual CSS utility classes.

2. **Header Visual Alignment Chain**:
   - *Observation 4*: Spec Section 7 calls for an 18px sparkle icon and 18px circular bag badge. Current CSS sets 16px sparkle and 17px rounded pill badge.
   - *Reasoning*: Adjusting `.ld-header-crest-icon` to 18px and `.ld-header-bag-badge` to 18×18px circular aligns 1:1 with the reference image without affecting DOM structure or test attributes (`data-testid="luxury-bag-badge"`).

3. **Touch Target Ergonomics Chain**:
   - *Observation 4*: `.ld-header-icon-btn` is 38×38px. Spec Section 4 and `35-engineering-conventions.md` require min 44–48px touch targets.
   - *Reasoning*: Expanding the clickable area of `.ld-header-icon-btn` (via minimum bounding box or padding) satisfies accessibility and touch guidelines while maintaining the 38px visual circular outline.

4. **Dock Dimensions and Visual Polish Chain**:
   - *Observation 5*: Current dock inner height is 56px, inactive text is 45% white opacity, and indicator is at top:0. Spec Section 8 specifies 60px height, `#AAA49A` inactive color, and bottom/underline indicator.
   - *Reasoning*: Updating `.ld-bottom-dock-inner` height to 60px, updating `.ld-has-bottom-dock` padding to `calc(60px + env(safe-area-inset-bottom) + 16px)`, changing inactive color to `#AAA49A`, and refining indicator position directly satisfies Spec Section 8.

5. **Live Room Dock Conflict Chain**:
   - *Observation 5*: `MobileBottomDock.tsx:66` hides the dock on `/drop/*`, which is validated by `mobile-bottom-dock.test.tsx:92`. Spec Screen 03 (Phase E) requires the dock to render on the live drop room.
   - *Reasoning*: Changing this in Phase B before Phase E would immediately break `mobile-bottom-dock.test.tsx`.
   - *Inference*: Keep `/drop/*` suppression in Phase B or add an optional override, and perform the live room dock alignment and test update in Phase E (Screen 03).

---

## 3. Caveats

- **No Code Modifications**: As Explorer 1, this task was strictly read-only; no production files or tests were changed.
- **Route-Level Direct Rendering**: Individual pages currently render `<GlobalBuyerHeader>` and `<MobileBottomDock>` rather than wrapping in `<BuyerShell>`. Migrating all pages to `BuyerShell` in Phase B is unnecessary and could risk introducing subtle layout regressions; refining the components in place and in `globals.css` is safer and zero-risk.
- **Phase E Cross-Dependency**: The requirement to show `MobileBottomDock` on Screen 03 (Live Room) must be coordinated with Phase E to ensure the accompanying test `mobile-bottom-dock.test.tsx:92` is updated in tandem.

---

## 4. Conclusion

Phase B frontend architecture is in excellent health. The foundation (Tailwind v4, Next.js 16.3, font loader, 474 passing tests) is completely sound. The required changes for Phase B are precise, localized, and low-risk:
1. **`globals.css`**: Add `--font-serif`, `--font-sans`, and missing colors (`--color-ld-border-gold-strong`, `--color-ld-sold`, etc.) to `@theme`. Refine `.ld-header-crest-icon` to 18px, `.ld-header-bag-badge` to 18×18px circular, `.ld-bottom-dock-inner` to 60px height, `.ld-has-bottom-dock` padding to match 60px, and `.ld-dock-tab` inactive color to `#AAA49A`.
2. **`GlobalBuyerHeader.tsx`**: Ensure 44–48px touch target hit area on icon buttons, while preserving all existing `data-testid` attributes and variant contracts.
3. **`MobileBottomDock.tsx`**: Refine active indicator styling and touch ergonomics. Defer `/drop/` unsuppression to Phase E to protect test suites.
4. **All existing tests** will continue passing with 0 failures.

---

## 5. Verification Method

To independently verify all observations and test baselines:
1. **Run Typecheck**:
   ```bash
   npm --prefix buyer-web run typecheck
   ```
   *Expected*: Exits with code 0.
2. **Run Linter**:
   ```bash
   npm --prefix buyer-web run lint
   ```
   *Expected*: Exits with code 0.
3. **Run Unit & Integration Tests**:
   ```bash
   npm --prefix buyer-web test
   ```
   *Expected*: 31 test files pass, 474 tests pass, 0 failures.
4. **Run Production Build**:
   ```bash
   npm --prefix buyer-web run build
   ```
   *Expected*: Successful compilation of all 9 routes.
5. **Inspect Detailed Survey Report**:
   Review `c:\LiveDrop\.agents\teamwork\explorer_survey_1\survey_report.md`.
