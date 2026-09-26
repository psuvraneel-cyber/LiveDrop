# LiveDrop — Buyer Homepage Hero Image Composition Fix Report

**Document Date:** September 27, 2026  
**Component:** `buyer-web/src/components/HomeStorefront.tsx`  
**Primary Design Reference:** Screen 01 in `media_1790453678472.jpg`  
**Hero Asset:** `media_1790453667585.jpg` (`buyer-web/public/hero-live-drop.jpg`)  
**Status:** COMPLETE & VERIFIED (Passes `typecheck`, `lint`, 544/544 tests, `build`, and responsive visual QA)

---

## 1. Executive Summary & Objective

The user identified an issue in the homepage hero where the full tall 9:16 portrait asset was displayed uncropped inside the hero section, giving a boxed, portrait-poster aesthetic rather than the intended cinematic mobile luxury-fashion hero.

### The Objective:
Transform the homepage hero from:
```
FULL PORTRAIT IMAGE
  ↓
Entire body / saree pleats / full length visible
  ↓
Ordinary image card block
```
into:
```
CINEMATIC HAUTE-COUTURE HERO
  ↓
Image fills the hero container with aggressive horizontal & vertical cropping
  ↓
Only the woman's head, face profile, hair bun with white flowers, gold earring, hand, and upper blouse visible
  ↓
Zero waist, zero hips, zero lower saree skirt visible
  ↓
Layered luxury dark gradients on the left and bottom
  ↓
Seamlessly dissolved into #08080A
  ↓
Title, live badge, tags, gold CTA button, and dots counter clearly readable with high contrast
```

---

## 2. Geometry & Crop Coordinates

### 2.1 Hero Container Dimensions
- **Mobile (360px – 390px):** `h-[300px]` (compact haute-couture hero leaving category rail and featured pieces visible above the fold on 844px viewports).
- **Small Tablet / Large Mobile (412px – 430px):** `sm:h-[320px]`.
- **Tablet (768px):** `md:h-[350px]`.
- **Desktop (1024px – 1440px+):** `lg:h-[360px]`.

### 2.2 Image Scaling & Positioning
- **Source Aspect Ratio:** 9:16 vertical portrait (1080 × 1920 px).
- **Mobile Focal Point:** `object-cover object-[78%_26%] scale-[1.22] origin-[78%_26%]`.
  - **Horizontal Offset (78%):** Places the subject's face profile and earring gracefully on the right half of the hero card, while leaving the entire left 50% clear for dark obsidian text backing.
  - **Vertical Offset (26%):** Centers the crown of golden bokeh foliage at the top, her jasmine-adorned hair bun, face, earrings, and embroidered blouse neck, while clipping off everything below mid-back (~55% to 100% of the original photo).
  - **Scale Factor (1.22 on mobile):** Discards extraneous tree foliage on the far left of the raw source photo, positioning the woman's silhouette in the right third of the mobile screen.
- **Desktop Focal Point:** `sm:object-[75%_32%] sm:scale-100 origin-[75%_32%]`.
  - Across wide 1440px displays, scales proportionally with natural landscape crop, preserving the warm golden light flare and profile on the right with dark vignette on the left.

---

## 3. Multi-Layer Dark Gradient Overlay Architecture

To ensure WCAG AAA contrast for typography while maintaining the warm golden sunset aesthetic:

1. **Directional Left-to-Right Read Gradient:**
   - Class: `absolute inset-0 bg-gradient-to-r from-[#08080A] via-[#08080A]/85 via-48% to-transparent`
   - Purpose: Dense obsidian backing on the left 0%–48% ensuring 100% legibility of the white serif headline, red live badge, and gold CTA, smoothly fading out before the woman's sunlit profile.
2. **Vertical Bottom-to-Top Dissolve Gradient:**
   - Class: `absolute inset-0 bg-gradient-to-t from-[#08080A] via-[#08080A]/60 via-30% to-transparent`
   - Purpose: Softly dissolves the lower fabric edge into `#08080A` so the card floor blends with the storefront surface without harsh rectangular borders.
3. **Top Ambient Vignette:**
   - Class: `absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-transparent`
   - Purpose: Subtle framing vignette over the upper canopy and status bar area.

---

## 4. Typography & CTA Spacing

- **Live Now Badge:** `px-2.5 py-0.5 rounded-full bg-[#EF4444] text-white font-mono font-bold text-[10px] tracking-wider uppercase` with pulsing white dot.
- **Headline:** `font-serif text-xl sm:text-2xl md:text-3xl max-w-[220px] sm:max-w-md text-[#FBFBFB] leading-tight drop-shadow-md` (gracefully wraps to 2 compact lines matching Screen 01).
- **Boutique Attribution:** `text-xs sm:text-sm text-[#F4F1EA]/80 font-sans max-w-xs leading-snug drop-shadow`.
- **Feature Chips:** `px-2 py-0.5 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-[9px] sm:text-[10px] text-white/90` with gold sparkles `✦`.
- **Primary Action CTA:** `px-4 sm:px-5 py-2 sm:py-2.5 rounded-full bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] text-xs sm:text-sm font-bold tracking-wide transition-all shadow-lg active:scale-[0.98]` (`rounded-full` pill button).
- **Pagination Counter:** `px-2.5 py-1 rounded-full bg-black/50 backdrop-blur-sm border border-white/10 text-[10px] text-white/70` with gold active dot `●` and inactive dots `○ ○` followed by `1/4`.
- **Content Padding:** `p-4 sm:p-6 pb-5 sm:pb-6` providing a clean 16-20px bottom margin above the card border.

---

## 5. Automated Quality Gate Results

| Quality Gate | Command | Result |
|---|---|---|
| **TypeScript Typecheck** | `npm --prefix buyer-web run typecheck` | **PASS (Exit 0)** — 0 errors |
| **ESLint Validation** | `npm --prefix buyer-web run lint` | **PASS (Exit 0)** — 0 warnings, 0 errors |
| **Vitest Unit & E2E Suite** | `npm --prefix buyer-web test` | **PASS (Exit 0)** — 544/544 tests passing across 42 test files |
| **Next.js Production Build** | `npm --prefix buyer-web run build` | **PASS (Exit 0)** — Compiled in 1309ms with Turbopack |

---

## 6. Visual Verification Artifacts

Screenshots captured across viewports using Playwright:
- **Mobile 390×844 Hero:** `verify_hero_mobile_390x844.png`
- **Mobile 390×844 Full Fold:** `verify_fold_mobile_390x844.png`
- **Mobile 412×915 Hero:** `verify_hero_mobile_412x915.png`
- **Mobile 430×932 Hero:** `verify_hero_mobile_430x932.png`
- **Desktop 1440×900 Hero:** `verify_hero_desktop_1440x900.png`

---

## 7. Strict Functional Freeze Affirmation

- **No RPC or Supabase Modifications:** Zero changes to Supabase queries, RPC signatures, or database schemas.
- **No State or Cart Modifications:** Cart store, checkout flow, reservation locks, and URL routing are 100% untouched.
- **Test ID Preservation:** `live-drop-hero`, `spotlight-hero`, `shop-live-hero-btn`, and `explore-live-shows-btn` remain in place.
