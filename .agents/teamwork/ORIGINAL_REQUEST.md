# Original User Request

## 2026-09-26T19:22:25Z

Visual reconstruction of the LiveDrop mobile buyer website to precisely match the 11-screen haute-couture reference image while strictly preserving all existing database schemas, RPCs, inventory reservation, checkout idempotency, direct UPI payment workflows, and token security.

Working directory: c:\LiveDrop

## Requirements

### R1. Phase A: Authoritative Design Specification Audit
Complete a comprehensive, 24-section visual design specification (`docs/BUYER-REFERENCE-DESIGN-SPEC.md`) decomposing all 11 screens from the reference image (`media_1790450082820.jpg`) without touching application code. (COMPLETED in Phase A).

### R2. Phase B: Global Shared Visual Primitives & Navigation
Align `GlobalBuyerHeader`, `MobileBottomDock`, and shared CSS tokens with the reference image:
- 56px luxury header with sparkle monogram and badge
- 5-tab bottom dock with gold active states (Home, Live, Shop, Orders, Bag) rendering on all matching screens
- Zero layout shift, smooth mobile touch targets (min 44-48px)

### R3. Phase C: Home Screen Visual Alignment (Screen 01)
Refine `HomeStorefront.tsx`:
- Cinematic live hero with live badge, collection title, boutique name, tags, and gold CTA
- Category rail with square gold "All" card and circular boutique avatars
- 2-column featured product grid with 3:4 cards and gold bag button

### R4. Phase D: Shop Screen & Filters Sheet (Screens 02 & 05)
Refine `ShopCategoryDirectory.tsx` and implement `FilterSheet.tsx`:
- Boutique Collections header with breadcrumb and search
- Dedicated control bar for filter and sort
- Dedicated bottom sheet filter modal matching Screen 05 (Category, Price Range, Availability, Size)

### R5. Phase E: Live Drop Room (Screen 03)
Refine `CinematicLiveRoomView.tsx` / `PublicDropView.tsx`:
- Top bar with boutique avatar, name, and live indicator
- Video viewport with right floating actions and overlay chat bubbles
- Pinned spotlight product card above chat input
- Render `MobileBottomDock` with "Live" active

### R6. Phase F: Product Detail (Screen 04)
Refine `ProductDetailModal.tsx` / `ProductQuickViewDrawer.tsx`:
- Large 3:4 portrait image with counter badge and thumbnail strip
- Product code tag, available status pill, serif title, price and size pill
- 4 craftsmanship attribute badges and expandable details accordions
- Dual sticky purchase bar: "Add to Bag" + "Buy Now →"

### R7. Phase G: Cart & Empty Cart (Screens 06 & 07)
Refine `cart/page.tsx`, `CartItemRow.tsx`, and `CartEmptyState.tsx`:
- Limited-edition reservation policy banner
- Item row with 3:4 thumbnail, quantity stepper, trash icon, note field
- Order summary with Free shipping and total
- Empty state with gold shopping bags vector illustration (no emoji)

### R8. Phase H: Checkout & Payment (Screens 08 & 09)
Refine `CheckoutForm.tsx` and `DirectUpiPaymentView.tsx`:
- 3-step progress indicator ("1 Details", "2 Payment", "3 Confirm")
- Delivery details card with dark elevated inputs
- UPI payment view with QR code, UPI ID copy, UTR input, and "Verify Payment →"

### R9. Phase I: Orders & Order Tracking (Screens 10 & 11)
Refine `order/page.tsx` and `CheckoutSuccessView.tsx`:
- Order cards with thumbnail, code, boutique, amount, and status pills
- Vertical timeline with gold checkmarks and active status descriptions
- DPDP Act compliant token-gated security

## Acceptance Criteria

### Automated Gates
- [ ] `npm --prefix buyer-web run typecheck` exits with 0
- [ ] `npm --prefix buyer-web run lint` exits with 0
- [ ] `npm --prefix buyer-web test` passes all 474+ tests with 0 failures
- [ ] `npm --prefix buyer-web run build` successfully compiles all routes

### Visual & Browser Verification
- [ ] All 11 screens visually match reference image `media_1790450082820.jpg`
- [ ] Mobile viewports verified at 390×844, 360×800, 412×915, 430×932
- [ ] No fake or manufactured data; genuine Supabase data model preserved
