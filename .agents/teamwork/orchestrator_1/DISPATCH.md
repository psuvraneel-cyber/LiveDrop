## 2026-09-26T19:23:44Z

You are the Project Orchestrator for the LiveDrop project.

Your Identity:
- Archetype: orchestrator
- Working directory: c:\LiveDrop\.agents\teamwork\orchestrator_1
- Parent Sentinel: 006a62e3-d791-4647-9951-117e186089ce

Your authoritative task is recorded in:
- c:\LiveDrop\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\LiveDrop\ORIGINAL_REQUEST.md

Task Summary:
Visual reconstruction of the LiveDrop mobile buyer website to precisely match the 11-screen haute-couture reference image while strictly preserving all existing database schemas, RPCs, inventory reservation, checkout idempotency, direct UPI payment workflows, and token security.

Working directory: c:\LiveDrop

Governing Specifications & Documents:
- Reference Image: media_1790450082820.jpg
- docs/BUYER-REFERENCE-DESIGN-SPEC.md (24-section visual design specification decomposing all 11 screens)
- docs/SOURCE-OF-TRUTH.md
- docs/07-functional-specification.md
- docs/12-database-design.md
- docs/13-api-contract.md
- docs/14-realtime-contract.md
- docs/15-concurrency-and-reservation-spec.md
- docs/16-security-architecture.md
- docs/19-validation-and-business-rules.md
- docs/25-testing-strategy.md
- docs/35-engineering-conventions.md

Requirements:
- R1. Phase A: Authoritative Design Specification Audit (`docs/BUYER-REFERENCE-DESIGN-SPEC.md`) - COMPLETED in Phase A.
- R2. Phase B: Global Shared Visual Primitives & Navigation (`GlobalBuyerHeader`, `MobileBottomDock`, shared CSS tokens, 56px luxury header with sparkle monogram and badge, 5-tab bottom dock with gold active states rendering on matching screens, zero layout shift, smooth touch targets min 44-48px).
- R3. Phase C: Home Screen Visual Alignment (Screen 01) (`HomeStorefront.tsx`, cinematic live hero, category rail with square gold 'All' card & circular avatars, 2-column featured product grid with 3:4 cards and gold bag button).
- R4. Phase D: Shop Screen & Filters Sheet (Screens 02 & 05) (`ShopCategoryDirectory.tsx`, `FilterSheet.tsx`, Boutique Collections header, search/sort, bottom sheet filter modal).
- R5. Phase E: Live Drop Room (Screen 03) (`CinematicLiveRoomView.tsx` / `PublicDropView.tsx`, top bar, video viewport with right floating actions and overlay chat bubbles, pinned spotlight product card, `MobileBottomDock` with 'Live' active).
- R6. Phase F: Product Detail (Screen 04) (`ProductDetailModal.tsx` / `ProductQuickViewDrawer.tsx`, 3:4 portrait image, counter badge, thumbnail strip, product code tag, available status pill, serif title, price and size pill, 4 craftsmanship attribute badges, expandable details accordions, dual sticky bar 'Add to Bag' + 'Buy Now ->').
- R7. Phase G: Cart & Empty Cart (Screens 06 & 07) (`cart/page.tsx`, `CartItemRow.tsx`, `CartEmptyState.tsx`, limited-edition reservation policy banner, 3:4 thumbnail, quantity stepper, trash icon, note field, order summary, gold shopping bags vector illustration).
- R8. Phase H: Checkout & Payment (Screens 08 & 09) (`CheckoutForm.tsx`, `DirectUpiPaymentView.tsx`, 3-step progress indicator, delivery details card with dark elevated inputs, UPI payment view with QR code, UPI ID copy, UTR input, 'Verify Payment ->').
- R9. Phase I: Orders & Order Tracking (Screens 10 & 11) (`order/page.tsx`, `CheckoutSuccessView.tsx`, order cards with thumbnail, code, boutique, amount, status pills, vertical timeline with gold checkmarks, DPDP Act compliant token-gated security).

Acceptance Criteria:
- Automated Gates:
  * npm --prefix buyer-web run typecheck (exit code 0)
  * npm --prefix buyer-web run lint (exit code 0)
  * npm --prefix buyer-web test (all 474+ tests pass with 0 failures)
  * npm --prefix buyer-web run build (successfully compiles all routes)
- Visual & Browser Verification:
  * All 11 screens visually match reference image media_1790450082820.jpg
  * Mobile viewports verified at 390x844, 360x800, 412x915, 430x932
  * No fake or manufactured data; genuine Supabase data model preserved
