# LiveDrop — E2E Test Infrastructure Specification (Tiers 1–4)

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-27  
**Test Framework:** Vitest 5.0.0 + `@testing-library/react` 16.3.3 + `jsdom` 30.0.1  
**Target Application:** `buyer-web` (Mobile Haute-Couture Live Commerce)  
**Governing Documents:**
- [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)
- [`PROJECT.md`](file:///c:/LiveDrop/PROJECT.md)
- [`docs/BUYER-REFERENCE-DESIGN-SPEC.md`](file:///c:/LiveDrop/docs/BUYER-REFERENCE-DESIGN-SPEC.md) (Screens 01–11)
- [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)
- [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md)
- [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md)
- [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)
- [`docs/25-testing-strategy.md`](file:///c:/LiveDrop/docs/25-testing-strategy.md)

---

## 1. Test Philosophy: Opaque-Box & Requirement-Driven

The LiveDrop buyer front-end E2E testing framework operates strictly on **opaque-box principles**:
1. **Behavioral Black-Box Verification:** Tests interact with the system solely through public DOM accessibility affordances (ARIA roles, accessible names, text content, user click/change events, and URL routing parameters). Tests never inspect or couple to internal component state, private variables, or transient CSS class names.
2. **Authoritative Specification Derivation:** Every expected outcome, label, error message, and layout state is derived directly from authoritative design and functional specifications:
   - Visual and functional layout: `docs/BUYER-REFERENCE-DESIGN-SPEC.md` (Sections 1–24).
   - Business requirements: `docs/07-functional-specification.md` and `PROJECT.md`.
   - Security and data contracts: `docs/13-api-contract.md`, `docs/15-concurrency-and-reservation-spec.md`, and `docs/16-security-architecture.md`.
3. **No Requirement Invention or Facade Testing:** Tests never construct arbitrary success criteria or write dummy assertions that pass vacuously. Every test exercises real component lifecycles, real React state transitions, real storage mutations, and real RPC mock contracts.
4. **Architectural & Financial Invariants:**
   - **Monetary Representation (ADR-009):** Every financial value (`price_paisa`, `subtotal_paisa`, `shipping_paisa`, `total_paisa`, `advance_amount_paisa`, `expected_amount_paisa`) is strictly represented as an integer in **Paisa** (`150000` = ₹1,500.00). Floating-point currency math is prohibited.
   - **Checkout Idempotency (ADR-009 & ADR-014):** Single-flight locks and unique `req_chk_${uuid}` tokens are enforced per checkout submission.
   - **Atomic Database RPC Contracts:** Exact typed payloads are enforced for `create_order_with_reservation`, `get_order_by_token`, `initiate_payment_attempt`, and `submit_buyer_payment_claim`.
   - **DPDP Act Customer Privacy (ADR-011):** Token-gated order lookup; zero public PII scraping; immediate token invalidation on unauthorized access.

---

## 2. Test Architecture & Runner Setup

### 2.1 Framework & Environment
- **Runner:** Vitest 5.0.0 (`@vitejs/plugin-react` 6.1.1)
- **DOM Simulator:** `jsdom` 30.0.1
- **Component Testing Utilities:** `@testing-library/react` 16.3.3 and `@testing-library/jest-dom/vitest` 7.0.1
- **Database / RPC Layer Mocking:** Strict typesafe Vitest spies and contract-conforming mock responses simulating Supabase PostgREST and PostgreSQL RPC transactions.

### 2.2 Test Isolation & State Reset
To guarantee complete test independence, the test harness enforces the following setup protocol before every test execution (`beforeEach`):
```typescript
window.localStorage.clear();
window.sessionStorage.clear();
resetCartStore();
vi.clearAllMocks();
```
All route parameters (`useParams`, `useSearchParams`, `useRouter`, `usePathname`) are freshly initialized per test suite.

### 2.3 Canvas & Browser API Protection
In headless `jsdom` environments, HTML5 `<canvas>` (used for festive gold confetti particles) and `navigator.clipboard` are gracefully mocked or safeguarded to prevent unhandled rejections during test execution.

---

## 3. Multi-Tiered Verification Structure (Tiers 1–4)

```
buyer-web/src/test/e2e/
├── fixtures/
│   ├── mock-catalog-data.ts           # Typesafe domain mock entities (drops, products, boutiques)
│   └── test-providers.tsx             # Canonical provider wrapper (CartProvider, ProfileProvider)
├── tier-1-screens/
│   ├── screen-01-home.test.tsx        # Screen 01: Home Storefront (>=5 tests)
│   ├── screen-02-shop.test.tsx        # Screen 02: Shop Catalog Directory (>=5 tests)
│   ├── screen-03-live-drop.test.tsx   # Screen 03: Live Drop Room (>=5 tests)
│   ├── screen-04-product-detail.test.tsx # Screen 04: Product Detail Modal (>=5 tests)
│   ├── screen-05-filter-sheet.test.tsx   # Screen 05: Multi-Dimensional Filter Sheet (>=5 tests)
│   ├── screen-06-cart.test.tsx        # Screen 06: Cart With Items (>=5 tests)
│   ├── screen-07-empty-cart.test.tsx  # Screen 07: Empty Cart State (>=5 tests)
│   ├── screen-08-checkout.test.tsx    # Screen 08: Checkout & Delivery Details (>=5 tests)
│   ├── screen-09-direct-upi.test.tsx  # Screen 09: Direct UPI & UTR Verification (>=5 tests)
│   ├── screen-10-orders.test.tsx      # Screen 10: Orders Directory & Lookup (>=5 tests)
│   └── screen-11-order-timeline.test.tsx # Screen 11: Order Tracking Timeline & DPDP (>=5 tests)
├── tier-2-boundary-corner-cases.test.tsx # Tier 2: Boundary, Extreme Limits & Corner Cases
├── tier-3-cross-feature-combinations.test.tsx # Tier 3: Pairwise & Multi-Screen Cross-Feature Workflows
└── tier-4-real-world-scenarios.test.tsx  # Tier 4: End-to-End Luxury Buyer Scenarios
```

### 3.1 Tier 1: Feature Coverage (Screens 01–11)
Requires >=5 dedicated tests per screen/feature:
- **Screen 01 (Home Storefront):**
  - Cinematic live hero rendering with LIVE NOW badge, collection title, and boutique name.
  - Category discovery rail with square "All" card and circular boutique avatars.
  - 2-column featured product grid with 3:4 portrait cards.
  - Compact 36×36px gold bag button adding item to bag.
  - No-live fallback state rendering "NO LIVE DROP" with boutique discovery.
- **Screen 02 (Shop Catalog Directory):**
  - Boutique collections header with breadcrumb navigation and catalog subtitle.
  - Dedicated search input filtering products by title or flash code.
  - Sort control bar with featured, price low-to-high, and price high-to-low ordering.
  - Horizontal category chips rail filtering products (Sarees, Kurtis, Lehengas, etc.).
  - High-density 2-column product grid with empty search fallback.
- **Screen 03 (Live Drop Room):**
  - Top bar with boutique avatar, name, and pulsing red LIVE badge.
  - Video stream viewport with embedded player container.
  - Floating right interactions (heart likes counter, flying heart particles).
  - Pinned spotlight product card above chat with title, price, and quick-add CTA.
  - Live chat overlay and bottom chat input bar.
- **Screen 04 (Product Detail Modal):**
  - Large 3:4 portrait media frame with image angle navigation and thumbnail strip.
  - Product code badge (`#A03`), stock badge (AVAILABLE / RESERVED / SOLD), and formatted price.
  - Size indicator pill, editorial description, and craftsmanship attribute badges.
  - Sticky dual purchase bar with "Add to Bag" and "Buy Now →" actions.
  - Wishlist toggle and link share clipboard handler.
- **Screen 05 (Filter Sheet):**
  - Bottom drawer presentation with drag handle and close button.
  - Category selector chips with active gold highlight.
  - Integer Paisa price range slider (min/max range, INR labels).
  - Availability status filter (All, Available, Reserved, Sold).
  - Size options ("Free Size", "XS", "S", "M", "L", "XL", "XXL").
  - "Clear All" reset button restoring defaults and "Show [X] Pieces →" submit trigger.
- **Screen 06 (Cart With Items):**
  - Global header with back button, item count badge, and "Clear" cart link.
  - 10-minute reservation policy warning banner.
  - Item row with 3:4 portrait thumbnail, flash code, title, and formatted price.
  - Quantity stepper enforcing single-piece edition limit.
  - Customer gift note expandable accordion with 300-char limit.
  - Order summary showing subtotal, free shipping calculation, and total.
  - "Proceed to Checkout →" CTA enabling progression.
- **Screen 07 (Empty Cart):**
  - Handcrafted gold shopping bags vector illustration (`<svg>`) with sparkles (zero emoji).
  - Display serif heading: "Your bag is empty".
  - Editorial subtitle: "Discover unique pieces from independent boutiques."
  - Primary gold CTA: "Explore Shop →" linking directly to `/shop`.
- **Screen 08 (Checkout Form):**
  - 3-step progress indicator ("1 Details", "2 Payment", "3 Confirm").
  - Delivery details form with elevated inputs (Full Name, Phone Number, PIN Code, Address).
  - Phone number validation (Indian 10-digit mobile) and PIN code validation (6-digit).
  - Order review breakdown with 15-minute hold reservation notice.
  - Primary CTA "Place Order & Hold Items" with single-flight idempotency lock.
- **Screen 09 (Direct UPI Payment):**
  - Dynamic payment heading ("Pay ₹X,XXX") with UPI QR code container.
  - Payee VPA display with one-click copy button.
  - Transaction reference box with one-click copy button.
  - Direct UPI Intent deep-link button for mobile payment apps.
  - 12-digit UTR input field with validation and "Verify Payment →" primary action.
  - Verification deadline (24 hours) and "Do not pay again" warning notice.
- **Screen 10 (Orders Directory & Lookup):**
  - Header with "LiveDrop ORDERS" branding.
  - Segmented filter tabs ("Recent Orders" and "Saved").
  - Order summary cards displaying order code, boutique, and formatted Paisa amount.
  - Status badges ("Order Placed", "Payment Verified", "In Preparation").
  - Order lookup input with validation for order numbers or tracking links.
- **Screen 11 (Order Tracking Timeline & DPDP):**
  - DPDP Act token gating: restricts access and renders privacy notice if token is missing or invalid.
  - Order header with order code and active 10-minute hold countdown timer.
  - Reserved item summary with product thumbnail, title, and purchase price.
  - Vertical milestone tracking timeline with gold checkmarks and active status descriptions.
  - Embedded Direct UPI payment container for pending or unverified orders.

### 3.2 Tier 2: Boundary & Corner Cases
- Free shipping threshold boundary: Order subtotal of ₹1,999.00 (`199900` Paisa) incurs delivery fee; ₹2,000.00 (`200000` Paisa) qualifies for `FREE` shipping.
- Quantity boundary: Stepper attempts to increase quantity beyond 1 trigger disabled state with "Single Piece" limited edition constraint.
- Note boundary: 300-character gift note boundary enforcement with truncation and count limits.
- Phone & PIN boundary: Non-10-digit phone numbers and non-6-digit PIN codes rejected with inline validation alerts.
- UTR validation boundary: UTR inputs shorter than 12 characters or containing invalid punctuation rejected.
- Missing / invalid token boundary: Navigating to `/order/[id]` without a token immediately renders DPDP privacy error and purges corrupted local cache.

### 3.3 Tier 3: Cross-Feature Combinations
- **Pairwise Flow 1:** Home storefront product card -> Open Product Detail Modal -> Add to Bag -> Open Cart -> Proceed to Checkout -> Reserve with Database -> View Direct UPI QR & submit UTR claim.
- **Pairwise Flow 2:** Live Drop room spotlight product -> Quick add to Bag -> Open Cart Drawer -> Proceed to Checkout -> Verify 15-minute hold timer & order receipt.
- **Pairwise Flow 3:** Shop catalog category filtering -> Search query refinement -> Open Filter Sheet -> Apply price/size filter -> Add filtered product to Bag.
- **Pairwise Flow 4:** Empty bag state -> Click "Explore Shop" -> Browse catalog -> Add item -> Return to cart -> Clear cart back to empty state.
- **Pairwise Flow 5:** Place order with advance payment mode -> Navigate to Orders Directory -> Lookup recent order -> View Order Tracking Timeline in advance_paid / awaiting verification state.

### 3.4 Tier 4: Real-World Scenarios
- **Scenario 1:** Complete luxury live shopping journey: buyer enters live drop room, browses spotlight silk saree, adds to bag, completes checkout reservation, copies boutique UPI ID, submits UTR, and monitors vertical tracking timeline.
- **Scenario 2:** High-value multi-piece boutique haul: buyer adds multiple garments exceeding free shipping threshold, verifies zero shipping fee, places order, and receives itemized receipt.
- **Scenario 3:** Concurrency & stock reconciliation: buyer has item in cart when boutique marks product as reserved or sold; checkout button disables gracefully with unavailable items banner.
- **Scenario 4:** Multi-device return visit: buyer returns to `/order`, restores order via cached device token, views vertical delivery milestones, and initiates WhatsApp boutique concierge.

---

## 4. Execution Commands & Quality Gates

### Running All Tests
```bash
# Run all unit, integration, and E2E tests across all 11 screens:
npm --prefix buyer-web test
```

### Running E2E Test Suite Only
```bash
# Run E2E test files specifically:
npx --prefix buyer-web vitest run src/test/e2e/
```

### Automated Gate Verification Matrix
| Quality Gate | Command | Passing Threshold |
|---|---|---|
| **Full Test Suite** | `npm --prefix buyer-web test` | 100% passing (0 failures across all 474+ existing + all new E2E tests) |
| **Type Integrity** | `npm --prefix buyer-web run typecheck` | 0 TypeScript errors (`tsc --noEmit`) |
| **Lint & Style** | `npm --prefix buyer-web run lint` | 0 ESLint warnings or errors |
| **Next.js Compilation** | `npm --prefix buyer-web run build` | 9/9 routes compiled cleanly with 0 route errors |

---

## 5. Directory Layout & File Manifest

```
buyer-web/src/test/e2e/
├── fixtures/
│   ├── mock-catalog-data.ts
│   └── test-providers.tsx
├── screen-01-home.test.tsx
├── screen-02-shop.test.tsx
├── screen-03-live-drop.test.tsx
├── screen-04-product-detail.test.tsx
├── screen-05-filter-sheet.test.tsx
├── screen-06-cart.test.tsx
├── screen-07-empty-cart.test.tsx
├── screen-08-checkout.test.tsx
├── screen-09-direct-upi.test.tsx
├── screen-10-orders.test.tsx
├── screen-11-order-timeline.test.tsx
├── tier-2-boundary-corner-cases.test.tsx
├── tier-3-cross-feature-combinations.test.tsx
└── tier-4-real-world-scenarios.test.tsx
```
