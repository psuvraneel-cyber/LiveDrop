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
