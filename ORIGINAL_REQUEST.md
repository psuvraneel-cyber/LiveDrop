# Original User Request

## 2026-09-21T16:24:18Z

Comprehensive UI/UX elevation, animated splash, micro-interactions, and design system overhaul for the LiveDrop Flutter Seller App, establishing a distinguished Luxury Boutique Noir aesthetic while strictly preserving all core business logic, database RPC interfaces, and architectural stability.

Working directory: c:/LiveDrop/seller-app
Integrity mode: demo

## Context & Architecture Baseline
- Governing Specifications: docs/SOURCE-OF-TRUTH.md, docs/03-ui-ux-specification.md, docs/KIMI-K3-COMPLETE-ARCHITECTURE-AUDIT.md.
- Target Stack: Flutter 3.41.6 / Dart 3.11.4, Material 3, flutter_animate: ^4.5.2, supabase_flutter: ^2.8.0.
- Strict Non-Negotiables: No weakening of security/auth, no alteration of SellerRepository method signatures or models, no floating-point currency (integer Paisa only), 100% test passage on existing test suites (23/23 tests green).

## Requirements

### R1. Luxury Boutique Noir Design System & Theme Engine
Establish a cohesive, distinguished visual identity designed specifically for Indian boutique and thrift merchants:
- Background: Deep obsidian/charcoal base (`#0F0F12`), satin surface cards (`#18181E`), elevated panels (`#22222A`), hairline borders (`#272730`).
- Accents: Metallic gold/amber primary (`#F59E0B` / `#D97706`), emerald verification badge (`#10B981`), crimson error state (`#EF4444`).
- Typography: Strict geometric hierarchy with tabular numbers for currency and flash codes.
- Global Theme: Centralized AppTheme / design tokens referenced across the entire application shell and all screens.

### R2. Hardware-Accelerated Animated Splash Screen & Parallel Auth Entrance
- Implement a bespoke AnimatedSplashScreen featuring a code-drawn geometric monogram brand mark (LiveDrop) using Flutter CustomPainter.
- Choreographed entrance animation: Monogram draw/scale, ambient golden light bloom, and title typography reveal (minimum 1.5s brand presence to prevent jarring flickering).
- Background validation: Supabase auth session check (SupabaseService.instance.isAuthenticated) runs in parallel during the splash sequence.
- Fluid hero cross-fade: When auth resolves and minimum duration elapses, execute a shared-axis/scale fade directly into SellerHomeScreen (if authenticated) or SellerLoginScreen (if unauthenticated).

### R3. Declarative Micro-Motion & Tactile Component Physics
- Integrate flutter_animate: ^4.5.2 into pubspec.yaml for declarative, 60fps micro-interactions without heavy external asset bundles.
- Tactile Buttons: Custom AppButton / BounceableButton widget providing spring-scale feedback (scale(0.97) on press with spring recovery) and embedded progress rings for async actions.
- Animated Navigation Shell: Modern bottom navigation bar with active glowing pill indicator, icon scale/bounce transitions, and smooth page switching.
- Status Indicators: Pulsing emerald glow dot on active "LIVE" drops, animated countdown timer pills on pending Kanban order cards, and animated golden clipboard feedback when copying buyer UTRs.

### R4. Shimmer Skeleton Loading & Empty States
- Replace all raw CircularProgressIndicator screens with custom shimmering skeleton loaders matching the exact card geometries of:
  - Drops List (DropsListSkeleton)
  - Kanban Orders Pipeline (KanbanSkeleton)
  - Pending Verifications Queue (VerificationsSkeleton)
- Styled empty states with custom geometric vector icons and actionable boutique guidance copy when lists are empty.

### R5. Operational Screen Refinement
Elevate the existing operational screens to match the Luxury Boutique Noir standard:
- SellerLoginScreen: Elegant card framing, subtle ambient glow, polished text fields with floating labels.
- DropsListScreen & CreateDropScreen: Elevated drop cards, live status badges, tactile action buttons.
- KanbanBoardScreen & OrderCard: Polished 3-tab pipeline, crisp address layouts, WhatsApp quick-action button with subtle green accent.
- PendingVerificationsScreen: Distinct UTR highlight card, quick copy animation, tactile Verify/Reject buttons.
- PaymentSettingsScreen: Grouped setting cards, clear input formatting, and responsive save feedback.

## Acceptance Criteria

### Visual Polish & Motion Standards
- [ ] Cold launch opens with the hardware-accelerated animated splash screen with zero black screens or jank.
- [ ] Splash screen smoothly cross-fades into either Login or Home without visual flashes.
- [ ] Tab switches in the bottom navigation bar animate fluidly with active indicator movement.
- [ ] All primary buttons display tactile spring-press animation on tap.
- [ ] Shimmer skeleton loaders render during initial data fetching across Drops, Kanban, and Verifications.
- [ ] Live drop badges feature an active pulsing green indicator.

### Architectural Invariants & Code Quality
- [ ] flutter analyze passes with zero errors.
- [ ] flutter test passes 100% of all existing 23 tests with zero regressions.
- [ ] New widget tests authored covering the animated splash screen, theme tokens, and button micro-interactions.
- [ ] Zero changes to Supabase RPC schemas, database migrations, or SellerRepository core domain logic.

## Verification Resources
- Test suite: seller-app/test/ (flutter test)
- Analysis: seller-app/ (flutter analyze)

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
