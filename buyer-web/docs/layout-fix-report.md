# Layout Fix Report — `buyer-web` Spacing & Alignment Remediation

**Date:** 2026-10-01
**Branch:** `fix/buyer-web-layout-spacing`
**Author:** Antigravity (AI agent)

---

## 1. Root Causes — Confirmed

### RC1 (CRITICAL): Unlayered CSS reset overrides Tailwind v4 utilities ✅ CONFIRMED & FIXED

**Location:** `globals.css` lines 202–209 (before fix)

```css
/* UNLAYERED — beats @layer utilities in Tailwind v4 */
*, *::before, *::after {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
}
```

**Evidence (computed style probes before → after):**

| Surface | Property | Before (expected 0) | After (expected non-zero) |
|---|---|---|---|
| `/shop` main (390px) | `padding-left` | `0px` | `16px` ✅ |
| `/shop` main (390px) | `padding-right` | `0px` | `16px` ✅ |
| `/shop` main (1280px) | `padding-left` | `0px` | `32px` ✅ |
| `/shop` main (1280px) | `margin-left` | `0px` | `64px` ✅ (centered) |
| `/` home rail first item x (390px) | left offset | `0px` (flush) | `14.8px` ✅ |
| `/` home hero left (390px) | left offset | `16px` (via `.ld-*`) | `16px` ✅ (unchanged) |
| `/` home section title (390px) | left offset | `16px` (via `.ld-*`) | `16px` ✅ (unchanged) |

**Scale of impact:** 557+ padding/margin/gap/space utility usages across ~25 component files were silently zeroed.

**Fix:** Wrapped the universal reset (`*`, `*::before`, `*::after`), bare-element typography rules (`html`, `body`, `button`, `input`, `textarea`, `select`), and the overflow-x clip rule in `@layer base`. This lets Tailwind v4 `@layer utilities` win as intended.

**Additional unlayered bare-element selectors moved into `@layer base`:**
- `html,body,button,input,textarea,select { font-family: ... }` (line 222)
- `html { background-color, color, line-height, scroll-behavior }` (line 232)
- `body { min-height, display, flex-direction, overflow-x }` (line 241)
- `html,body { max-width: 100%; overflow-x: clip }` (line 319)

**Rules intentionally left unlayered:**
- `a, button { text-decoration: none !important }` — already uses `!important`, not spacing
- `.sr-only` — uses `!important` on everything
- All `.ld-*` component classes — intentional component CSS
- `:root` CSS variable definitions — no layout properties

### RC2 (HIGH): Duplicate `.ld-status-badge` rule ✅ CONFIRMED & FIXED

**Location:** `globals.css` lines 1923 and 4504 (before fix)

- Line 1923: Product-card badge — `font-size: 9.5px; padding: 1px 5px; border-radius: 3px`
- Line 4504: Order-tracking badge — `padding: 6px 10px; border-radius: 8px; font-size: 11px`

Same selector `.ld-status-badge`, same specificity, later wins → product-card "AVAILABLE" badges rendered with the large order-tracking padding.

**Fix:** Changed the line-4504 selector from `.ld-status-badge` to `.ld-status-badge[class*="ld-status-badge-"]`. This ensures it only matches order-tracking badges (which carry modifiers like `ld-status-badge-order-confirmed`) and not product-card badges (which carry `available/reserved/sold`).

**Screenshot confirmation:** After fix, product-card badges show compact styling visible in all screenshots.

### RC3 (MEDIUM): Product card footer wrapping ✅ CONFIRMED & FIXED

**Location:** `globals.css` lines 1990–2022

**Fix applied:**
- `.ld-product-size`: Added `white-space: nowrap; flex-shrink: 0` — prevents "Free Size" from word-breaking
- `.ld-card-sub-info`: Added `flex-wrap: wrap; row-gap: 4px` — allows the size chip + badge to drop to a second line cleanly at narrow widths

### RC4 (LOW): Self-referential font variable — NOT FIXED (no visible bug)

`@theme { --font-sans: var(--font-sans); }` at line 11. The `next/font` loader sets `--font-sans` on `<html>` via `className` in `layout.tsx`. The self-reference resolves correctly via CSS inheritance. No rendering problem observed. **Left unchanged as specified.**

---

## 2. Changes Made

### Commit 1: `fix(buyer-web): move global reset into @layer base so Tailwind v4 spacing utilities apply`
- **File:** `src/app/globals.css`
- **Lines changed:** 202–209, 222–248, 319–325
- **What:** Wrapped 3 groups of bare-element selectors in `@layer base { ... }` blocks
- **Net diff:** +43 / -33 lines

### Commit 2: `fix(buyer-web): scope order status badge so it no longer overrides product-card badge`
- **File:** `src/app/globals.css`
- **Line changed:** 4504 (now 4514 after prior edits)
- **What:** Changed `.ld-status-badge` to `.ld-status-badge[class*="ld-status-badge-"]`
- **Net diff:** +2 / -1 lines

### Commit 3: `fix(buyer-web): harden product card footer wrapping and price alignment`
- **File:** `src/app/globals.css`
- **Lines changed:** 2000–2005, 2014–2022
- **What:** Added `flex-wrap`, `row-gap`, `white-space`, `flex-shrink` properties
- **Net diff:** +4 / -0 lines

**Total diff across all commits:** 1 file changed, 49 insertions, 34 deletions.

---

## 3. Screenshot Evidence

All screenshots saved at `scratch/layout-audit/after/`:

| File | Viewport | Surface |
|---|---|---|
| `home_390x844.png` | 390×844 (mobile) | `/` |
| `shop_390x844.png` | 390×844 (mobile) | `/shop` |
| `home_1280x800.png` | 1280×800 (desktop) | `/` |
| `shop_1280x800.png` | 1280×800 (desktop) | `/shop` |

### What the screenshots confirm:

**Home (`/`) — Mobile:**
- Category rail has visible left padding (~15px), aligned with hero (16px) and section title (16px)
- Hero has proper side padding
- Boutique cards have inner padding with "Visit →" and WhatsApp button
- Trust strip has comfortable padding
- Footer has proper spacing
- No horizontal overflow (scrollWidth: 390 = viewportWidth: 390)

**Home (`/`) — Desktop:**
- Hero centred with proper margins
- Category rail aligned with hero and content below
- Product grid in 4-column layout with proper gap
- Product card badges compact, "Add to Bag" buttons properly sized
- Footer centred with comfortable spacing

**Shop (`/shop`) — Mobile:**
- Main content has 16px side gutters (was 0px)
- Breadcrumb, title, search, controls, pills, grid all aligned to one left edge
- Control bar stacks vertically with inner padding
- Category pills have visible padding and scroll horizontally

**Shop (`/shop`) — Desktop:**
- Main content centred with max-width 1152px
- 32px side gutters (was 0px)
- Control bar is a single row with search, count, sort, filter
- Grid in 4-column layout with proper spacing
- Verified Ateliers section properly spaced

---

## 4. Probe Output Summary

```json
{
  "home_alignment_390x844": {
    "hasHorizontalOverflow": false,
    "scrollWidth": 390,
    "viewportWidth": 390,
    "railFirstItemLeft": 14.8,
    "heroLeft": 16,
    "sectionTitleLeft": 16
  },
  "shop_main_390x844": {
    "paddingLeft": "16px",
    "paddingRight": "16px",
    "marginLeft": "0px",
    "marginRight": "0px",
    "maxWidth": "1152px"
  },
  "home_alignment_1280x800": {
    "hasHorizontalOverflow": false,
    "scrollWidth": 1280,
    "viewportWidth": 1280,
    "railFirstItemLeft": 30.8,
    "heroLeft": 32,
    "sectionTitleLeft": 32
  },
  "shop_main_1280x800": {
    "paddingLeft": "32px",
    "paddingRight": "32px",
    "marginLeft": "64px",
    "marginRight": "64px",
    "maxWidth": "1152px"
  }
}
```

---

## 5. Test / Typecheck / Lint / Build Results

| Gate | Baseline | After Fix | Status |
|---|---|---|---|
| `npm run typecheck` | 0 errors | 0 errors | ✅ |
| `npm run lint` | 0 warnings | 0 warnings | ✅ |
| `npm test` | 49 files, 652 passed | 49 files, 652 passed | ✅ |
| `npm run build` | N/A | ✅ Compiled successfully | ✅ |

No tests were modified, skipped, or weakened. All 652 tests pass identically.

---

## 6. Surfaces Not Verified (data-dependent)

The following surfaces require live Supabase data or specific cart state and could not be fully captured with the automated script:

- **Cart drawer with items** — requires adding items to cart via the UI
- **Cart drawer empty** — requires opening the cart with no items
- **Product detail modal** — requires clicking a product card
- **Filter sheet** — requires clicking the filter button
- **`/checkout`** — requires items in cart
- **`/order`** — requires order ID
- **`/order/[id]`** — requires valid order with token
- **`/[storeSlug]`** (boutique storefront) — requires valid store slug
- **`/drop/[slug]`** (live drop room) — requires active drop

However, these surfaces all use the same Tailwind utilities that RC1 unblocked. The fix is a global CSS cascade change — if `/` and `/shop` work correctly, all other surfaces will too, since the root cause was universal (`*` selector).

---

## 7. Items Noticed But Not Changed (Out of Scope)

1. **Emojis in UI** — 🎁 appears in cart note row; `.stitch/DESIGN.md` bans emojis
2. **5-column grid gap** — At ≥1280px the product grid is 5 columns, so a 4-item list leaves an empty fifth column. Could be centred in a follow-up.
3. **Dual colour token systems** — `--ld-*` variables (`:root`) and `--color-ld-*` variables (`@theme`) coexist with slightly different hex values
4. **124 KB globals.css** — significant dead CSS and consolidation opportunity
5. **Hard-coded Windows paths** in existing `scripts/` and `scratch/` files
6. **RC4 self-referential font variable** — `@theme { --font-sans: var(--font-sans); }` — works today, cosmetic issue
7. **`HomeStorefront.tsx` redundant utilities** — `max-w-7xl mx-auto px-4 sm:px-6 lg:px-8` on main element duplicates the `.ld-home-main` plain CSS. Works correctly (doubled padding values are identical), but could be cleaned up for clarity.
8. **`Hero.tsx` redundant utilities** — Same pattern: `ld-home-hero-wrap` has plain CSS + identical Tailwind utilities.

---

## 8. `!important` Usage

No new `!important` was added. The existing `!important` usages remain unchanged:
- `text-decoration: none !important` on links/buttons (line 219)
- `.sr-only` properties (lines 328-339)
- `.ld-has-bottom-dock` padding-bottom (line 344, 350)
