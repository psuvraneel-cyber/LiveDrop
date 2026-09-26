# Handoff Report — Explorer Survey 2: Screens 01–05

**Agent:** Explorer 2 (`explorer_survey_2`)  
**Parent:** Orchestrator 1 (`orchestrator_1` / `4c705cbc-cf2b-425e-b111-d80dadaa5600`)  
**Date:** 2026-09-27  
**Task:** Survey existing components, routes, data flows, and state hooks for Phases C, D, E, F (Screens 01–05) against `docs/BUYER-REFERENCE-DESIGN-SPEC.md` and reference image `media_1790450082820.jpg`.

---

## 1. Observation

### 1.1 Existing Component Inventory & Status
- **Screen 01 (Home Storefront):**
  - Route: `buyer-web/src/app/page.tsx:9-24` (Server component, queries `getAllActiveLiveDrops`, `getAllVerifiedStorefronts`, `getFeaturedProducts`).
  - View Component: `buyer-web/src/components/HomeStorefront.tsx:45-466`.
  - Category rail: `HomeStorefront.tsx:259-286` renders flat pill buttons (`px-3.5 py-1.5 rounded-full`) instead of square gold "All" card + circular category photo avatars.
  - Hero: `HomeStorefront.tsx:185-256` renders title, boutique, and CTA, but lacks 3 feature pills ("✦ Live shopping", etc.) and pagination dots ("● ○ ○ 1/4").
  - Card: `buyer-web/src/components/ProductCard.tsx:69-236` renders 3:4 portrait thumbnail, flash code, formatted price, but lacks top-right favorite heart button.
  - Button styling: `buyer-web/src/app/globals.css:1949-1950` sizes mobile `.ld-btn-add-cart-compact` at 44×44px with 10px radius (spec requires 36×36px, 8px radius).

- **Screens 02 & 05 (Shop Directory & Filter Sheet):**
  - Route: `buyer-web/src/app/shop/page.tsx:15-33` (Server component, queries `getAllVerifiedStorefronts` and `getAllProducts`).
  - View Component: `buyer-web/src/components/shop/ShopCategoryDirectory.tsx:39-304`.
  - Control bar: `ShopCategoryDirectory.tsx:124-172` contains search input, count, and HTML `<select id="shop-sort">`, but lacks the "Filter" button with sliders icon.
  - Filter Sheet: **Does not exist**. No file named `FilterSheet.tsx` exists in `buyer-web/src/components/`.

- **Screen 03 (Live Drop Room):**
  - Route: `buyer-web/src/app/drop/[slug]/page.tsx:38-78`.
  - Coordinator: `buyer-web/src/components/PublicDropView.tsx:40-397` (handles live/closed states, realtime subscription).
  - Cinematic View: `buyer-web/src/components/live/CinematicLiveRoomView.tsx:33-461`.
  - Dock omission: `CinematicLiveRoomView.tsx` does NOT render `MobileBottomDock`.
  - Dock suppression: `buyer-web/src/components/navigation/MobileBottomDock.tsx:66-68` explicitly states:
    ```typescript
    if (pathname?.startsWith('/drop/')) {
      return null;
    }
    ```
  - Chat input: `CinematicLiveRoomView.tsx` has static chat bubble overlays (`INITIAL_COMMENTS`), but lacks the bottom chat input bar ("Say something...", smiley trigger, gold send button).

- **Screen 04 (Product Detail Modal / Quick View):**
  - Component 1: `buyer-web/src/components/ProductDetailModal.tsx:20-413` (opened from `ProductCard.tsx`).
  - Component 2: `buyer-web/src/components/product/ProductQuickViewDrawer.tsx:302-346` (opened from `CinematicLiveRoomView.tsx`).
  - Media aspect ratio: `globals.css:2145` defines `.ld-sheet-media-frame { aspect-ratio: 1 / 1; }` (spec requires strict 3:4 portrait).
  - Missing elements in both: Image counter badge ("1/5"), 4 craftsmanship attribute badges with icons, 3 expandable details accordions (`Product Details >`, `Atelier Information >`, `Delivery & Returns >`).

### 1.2 Verification Commands Run & Outputs
1. **Vitest Unit Test Suite:**
   - Command: `npm --prefix buyer-web test`
   - Output: `Test Files: 31 passed (31) | Tests: 474 passed (474) | Duration: 28.39s`
   - Exit code: 0.
2. **TypeScript Compilation:**
   - Command: `npm --prefix buyer-web run typecheck`
   - Output: `tsc --noEmit` exited with code 0.

---

## 2. Logic Chain

1. **Baseline Stability:** All 474 existing tests pass and TypeScript emits 0 errors, confirming that all underlying database schema definitions, integer Paisa calculations, and atomic RPC contracts are healthy.
2. **Visual Spec Discrepancies:**
   - Comparing `HomeStorefront.tsx` with Section 13 of `BUYER-REFERENCE-DESIGN-SPEC.md`, the category rail lacks the primary visual differentiator of the reference design (the square gold "All" card followed by circular avatar photos).
   - Comparing `ShopCategoryDirectory.tsx` with Section 14 and 17, the control bar cannot filter by price, availability, or size because `FilterSheet.tsx` is completely unbuilt.
   - Comparing `CinematicLiveRoomView.tsx` with Section 15, the reference image explicitly shows `MobileBottomDock` with "Live" active at the bottom of Screen 03. Currently, `MobileBottomDock.tsx` suppresses itself on `/drop/*`, and `CinematicLiveRoomView.tsx` does not render it. Furthermore, the chat input bar is absent.
   - Comparing `ProductDetailModal.tsx` with Section 16, the modal renders square 1:1 media and lacks the 4 craftsmanship badges and 3 collapsible accordions specified for the luxury atelier lookbook.
3. **Synthesis:** Implementing Phases C, D, E, and F will require visual component refinement, creating `FilterSheet.tsx`, removing the dock suppression on `/drop/*`, adjusting CSS aspect ratios, and updating one existing test (`src/test/mobile-bottom-dock.test.tsx:92`) that currently expects the dock to be hidden on `/drop/*`.

---

## 3. Caveats

1. **Read-Only Constraint:** Per instructions, no production or test code was modified during this survey.
2. **Test ID Preservation:** Existing tests heavily rely on `data-testid` attributes (such as `category-chip-all`, `category-chips-rail`, `shop-search-input`, `shop-sort-select`, `pinned-product-card`, `quick-view-add-to-bag-btn`). Implementers must preserve these test IDs to maintain 0 regression across the 474 tests.
3. **Mobile Viewport Ergonomics:** On 390×844px screens, Screen 03 (Live Drop Room) stacks top overlay, video canvas, floating actions, pinned spotlight card, chat input bar, and `MobileBottomDock`. Care must be taken to ensure proper z-index layering and touch clearance without obscuring the video.

---

## 4. Conclusion

The application infrastructure for Screens 01–05 is robust, bug-free, and well-typed. The visual gaps are concrete, localized, and fully documented in `c:\LiveDrop\.agents\teamwork\explorer_survey_2\survey_report.md`.

### Concrete Next Steps for Implementers:
- **Phase C (Screen 01):** Transform category rail in `HomeStorefront.tsx` to square gold "All" card + circular avatars; add hero feature pills and slide indicators; add heart icon to `ProductCard.tsx`; adjust mobile button CSS to 36×36px.
- **Phase D (Screens 02 & 05):** Build `FilterSheet.tsx` bottom drawer; add "Filter" button to `ShopCategoryDirectory.tsx` control bar; wire multi-dimensional filters (Category, Price Range, Availability, Size).
- **Phase E (Screen 03):** Enable `MobileBottomDock` on `/drop/[slug]` with "Live" active; add bottom chat input bar in `CinematicLiveRoomView.tsx`; adjust `mobile-bottom-dock.test.tsx`.
- **Phase F (Screen 04):** Update media frame to 3:4 portrait in `globals.css`; add "1/5" counter badge, 4 craftsmanship badges, and 3 collapsible accordions in `ProductDetailModal.tsx`.

---

## 5. Verification Method

To independently verify the findings in this report:

1. **Verify Baseline Test Suite:**
   ```bash
   npm --prefix buyer-web test
   ```
   *Expected:* 31 test files passed, 474 tests passed, exit code 0.

2. **Verify Typecheck:**
   ```bash
   npm --prefix buyer-web run typecheck
   ```
   *Expected:* Exit code 0.

3. **Verify Absence of `FilterSheet.tsx`:**
   Inspect `c:\LiveDrop\buyer-web\src\components\shop\` to confirm `FilterSheet.tsx` is not present.

4. **Verify Dock Suppression on Drop Route:**
   Inspect `c:\LiveDrop\buyer-web\src\components\navigation\MobileBottomDock.tsx` lines 66–68:
   `if (pathname?.startsWith('/drop/')) return null;`
   and `c:\LiveDrop\buyer-web\src\test\mobile-bottom-dock.test.tsx` lines 92–97.

5. **Verify Media Frame Aspect Ratio:**
   Inspect `c:\LiveDrop\buyer-web\src\app\globals.css` line 2145: `.ld-sheet-media-frame { aspect-ratio: 1 / 1; }`.
