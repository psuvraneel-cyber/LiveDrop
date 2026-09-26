# LiveDrop — Architectural & Visual Survey Report: Screens 06–11 and Test Suite Baseline

**Document Version:** 1.0.0  
**Surveyor:** Explorer 3 (Survey: Cart, Checkout, Order Tracking, and Test Suite Baseline)  
**Target Application:** `buyer-web`  
**Governing Documents:**  
- [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)
- [`docs/BUYER-REFERENCE-DESIGN-SPEC.md`](file:///c:/LiveDrop/docs/BUYER-REFERENCE-DESIGN-SPEC.md) (Sections 13–16 & 18–23)
- [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)
- [`docs/13-api-contract.md`](file:///c:/LiveDrop/docs/13-api-contract.md)
- [`docs/15-concurrency-and-reservation-spec.md`](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md)
- [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)
- [`docs/25-testing-strategy.md`](file:///c:/LiveDrop/docs/25-testing-strategy.md)

---

## 1. Executive Summary

This survey provides an exhaustive technical and visual assessment of **Phases G, H, I** and the **Testing Track** for `buyer-web`, encompassing:
1. **Screen 06 & 07:** Cart With Item & Empty Cart (`/cart`, `CartItemRow.tsx`, `CartEmptyState.tsx`, `CartDrawer.tsx`, `StickyCartBar.tsx`).
2. **Screen 08 & 09:** Checkout Form & Direct UPI Payment (`/checkout`, `CheckoutForm.tsx`, `DirectUpiPaymentView.tsx`, `CheckoutReview.tsx`).
3. **Screen 10 & 11:** Order List & Order Timeline Tracking (`/order`, `/order/[id]`, `CheckoutSuccessView.tsx`).
4. **Test Suite Baseline:** Full audit of 31 test files, 474 passing tests, TypeScript verification, ESLint verification, Next.js route builds, and Playwright E2E coverage.
5. **Architectural & Security Guardrails:** Verification of all PostgreSQL RPC contracts (`create_order_with_reservation`, `get_order_by_token`, `initiate_payment_attempt`, `submit_buyer_payment_claim`), integer **Paisa** monetary constraints (ADR-009), single-flight idempotency tokens, and DPDP Act token-gated security.

### Baseline Health Check Matrix

| Automated Quality Gate | Command | Result | Verified Metric |
|---|---|---|---|
| **Unit & Integration Suite** | `npm test` (`vitest run`) | **PASS (Exit 0)** | **31 test files, 474/474 tests passing (0 failures)** |
| **Static Type Checking** | `npm --prefix buyer-web run typecheck` (`tsc --noEmit`) | **PASS (Exit 0)** | 0 TypeScript errors across entire Next.js codebase |
| **Code Style & Linting** | `npm --prefix buyer-web run lint` (`eslint`) | **PASS (Exit 0)** | 0 lint warnings or errors |
| **Production Build** | `npm --prefix buyer-web run build` (`next build`) | **PASS (Exit 0)** | 9 routes compiled cleanly (5 static, 4 dynamic) |

---

## 2. Screen 06 & 07: Cart & Empty Cart (Phase G)

### 2.1 Screen 06: Cart With Item
* **Route & Component Files:**
  - Page: `buyer-web/src/app/cart/page.tsx`
  - Item Row: `buyer-web/src/components/cart/CartItemRow.tsx`
  - Drawer Variant: `buyer-web/src/components/cart/CartDrawer.tsx`
  - Floating Bar: `buyer-web/src/components/cart/StickyCartBar.tsx`
* **Reference Design Spec Alignment (`BUYER-REFERENCE-DESIGN-SPEC.md` Section 18):**
  1. **Header:** 
     - Rendered via `GlobalBuyerHeader` with `variant="minimal"`, back button, title `Your Cart (N)`, and gold link `Clear` button (`data-testid="cart-page-clear-btn"`).
  2. **10-Minute Reservation Policy Warning Banner:**
     - Currently in `cart/page.tsx`:
       ```tsx
       <div className="p-3 rounded-xl bg-[rgba(212,175,55,0.08)] border border-[rgba(212,175,55,0.2)] flex items-start gap-2.5 text-xs text-[#F3E5AB]">
         <span className="text-[#D4AF37] mt-0.5">✦</span>
         <span className="leading-relaxed">
           Items are not reserved until checkout. Live drops are single-piece limited editions.
         </span>
       </div>
       ```
       *Status:* Wording is 100% compliant with reference spec.
  3. **Item Row Geometry:**
     - Current state: `CartItemRow.tsx` uses square thumbnail `w-20 h-20 sm:w-22 sm:h-22 rounded-xl` (`aspect-square`).
     - Required refinement: Update media container to strict **3:4 aspect ratio** (e.g., `w-20 aspect-[3/4]` or `w-[72px] h-[96px]`) to match haute couture reference image.
  4. **Quantity Stepper & Trash Icon:**
     - `CartItemRow.tsx` implements: `[-] 1 [+]` with `+` disabled and hover title `"Single piece edition"`, accompanied by `"Single Piece"` uppercase label.
     - Trash icon: Clean SVG trash icon with `data-testid={`cart-remove-${item.productId}`}` and accessible `aria-label`.
     - *Status:* Compliant.
  5. **Customer Note Field:**
     - Expandable accordion `"Add a note (optional)"` with textarea, 300-char max, `data-testid="cart-page-note-input"`, and `data-testid="cart-page-save-note-btn"`.
     - Refinement needed: Replace system emoji `🎁` in toggle button with a bespoke gold SVG gift icon (`✦` or gift box outline) to uphold the strict "no system emojis" constraint.
  6. **Order Summary Card:**
     - Displays Subtotal (`data-testid="cart-page-subtotal"`), Shipping (`FREE` or calculated fee), and Total (`data-testid="cart-page-total"`).
     - Free shipping threshold logic: `freeThreshold = 200000` (₹2,000.00). If subtotal >= 200000, shipping is `FREE`.
  7. **Sticky Checkout CTA:**
     - `"Proceed to Checkout →"` (`data-testid="cart-page-checkout-btn"`).
     - Disables and indicates unavailable items if any item has been claimed by another buyer during live reconciliation.
  8. **Bottom Dock:**
     - Renders `<MobileBottomDock />` with `"Bag"` tab active.

### 2.2 Screen 07: Empty Cart
* **Route & Component File:** `buyer-web/src/components/cart/CartEmptyState.tsx`
* **Reference Design Spec Alignment (`BUYER-REFERENCE-DESIGN-SPEC.md` Section 19):**
  - Current implementation has line 25:
    ```tsx
    <div className="text-4xl sm:text-5xl select-none" aria-hidden="true">🛍</div>
    ```
    This uses a standard operating system emoji `🛍`.
  - Required refinement:
    - **Eliminate system emoji.**
    - Replace with high-fidelity, handcrafted **Gold Shopping Bags Vector Illustration (`<svg>`)** with obsidian drop shadow and radiant gold sparkle nodes (`#D4AF37`, `#F5D78E`).
    - Heading: `"Your bag is empty"` (Cormorant Garamond serif, 22px).
    - Subtitle: `"Discover unique pieces from independent boutiques."` (Plus Jakarta Sans, `#AAA49A`).
    - Action CTA: `"Explore Shop →"` button (`data-testid="cart-browse-btn"`) with gold gradient background linking to `/shop`.

---

## 3. Screen 08 & 09: Checkout & Direct UPI Payment (Phase H)

### 3.1 Screen 08: Checkout Form
* **Route & Component Files:**
  - Page: `buyer-web/src/app/checkout/page.tsx`
  - Form: `buyer-web/src/components/checkout/CheckoutForm.tsx`
  - Review: `buyer-web/src/components/checkout/CheckoutReview.tsx`
  - Empty: `buyer-web/src/components/checkout/EmptyCheckoutState.tsx`
* **Reference Design Spec Alignment (`BUYER-REFERENCE-DESIGN-SPEC.md` Section 20):**
  1. **3-Step Progress Indicator:**
     - Component: `.ld-checkout-breadcrumbs`
     - Step 1: "1 Details" (active gold `.active` with number pill)
     - Step 2: "2 Payment"
     - Step 3: "3 Confirm" (or Review)
     - Refinement: Update step 3 text from "Review" to "Confirm" to match reference Screen 08 verbatim.
  2. **Delivery Details Form (`CheckoutForm.tsx`):**
     - Fields:
       - Full Name (`data-testid="input-buyer-name"`)
       - Mobile Number (`data-testid="input-buyer-phone"`)
       - Delivery Pincode (`data-testid="input-pincode"`)
       - Full Street Address (`data-testid="input-shipping-address"`)
     - Styling:
       - Background `#16161C` (`var(--ld-surface-elevated)`), hairline borders `1px solid rgba(255, 255, 255, 0.1)`, focused border `rgba(212, 175, 55, 0.6)`.
       - Touch targets >= 48px.
  3. **Order Review & Pre-checkout Breakdown (`CheckoutReview.tsx`):**
     - List of items with code, title, size, and price in integer Paisa.
     - 15-Minute Hold Notice: `"Placing your order reserves a 15-minute hold on your selected pieces. Payment is completed in the next step."` (`data-testid="checkout-hold-notice"`).
     - Primary Action Button: `"Place Order & Hold Items (₹X,XXX)"` (`data-testid="checkout-submit-btn"`).
     - Single-flight lock: Button is disabled while in flight, displaying `"Reserving Items with Database..."`.

### 3.2 Screen 09: Direct UPI Payment
* **Route & Component File:** `buyer-web/src/components/checkout/DirectUpiPaymentView.tsx`
* **Reference Design Spec Alignment (`BUYER-REFERENCE-DESIGN-SPEC.md` Section 21):**
  1. **Amount Display:**
     - Bold large heading: `Pay ₹3,100` (or `Pay ₹X,XXX Advance` / `Pay in Full`).
     - Subtitle: `"Scan this QR using any UPI app"`.
  2. **QR Code Container:**
     - Clean white square box generated with `qrcode` package from `upiUri`.
     - `data-testid="upi-qr-image"`.
  3. **Payee UPI ID & Reference Box:**
     - UPI ID: `activeAttempt.payee_vpa_snapshot` (`data-testid="payee-vpa"`) with `"Copy"` button (`data-testid="copy-vpa-btn"`).
     - Order Reference: `activeAttempt.transaction_reference` (`data-testid="payment-reference"`) with `"Copy"` button (`data-testid="copy-ref-btn"`).
  4. **Deep-Link UPI Intent CTA:**
     - `"Pay ₹X with UPI App"` (`data-testid="pay-with-upi-intent-btn"`) for instant mobile app handover (GPay, PhonePe, Paytm, BHIM).
  5. **Divider:**
     - Visual divider between direct app launch and manual UTR entry.
  6. **12-Digit UTR Input Form:**
     - Label: `"UPI Reference / UTR Number"`.
     - Input: `data-testid="utr-input-field"`, placeholder `"e.g. 428739182734"`, max length 35, alphanumeric sanitizer.
     - Button: `data-testid="submit-payment-claim-btn"`. Label can display `"Verify Payment →"` or `"I've Completed Payment"`.
  7. **Persistent Claims & Verification Lifecycle:**
     - Handled via `submit_buyer_payment_claim` RPC.
     - Transitions state to `awaiting_seller_verification`.
     - Displays `safe-to-close-notice` (`"You can safely close this page. Save this order link..."`).
     - Displays masked UTR (`••••••••2734`).
     - Displays 24-hour verification deadline (`data-testid="verification-deadline"`).
     - Displays `do-not-pay-again-warning` (`"Do not pay again unless the boutique asks you to."`).
     - Bounded adaptive polling fallback (5s to 15s with jitter, 30m cutoff) and Realtime WebSocket listener (`buyer-order-${orderId}`).
  8. **WhatsApp Escalation:**
     - Dedicated button `data-testid="whatsapp-chat-btn"` to chat directly with seller.

---

## 4. Screen 10 & 11: Orders & Order Tracking (Phase I)

### 4.1 Screen 10: Orders Directory
* **Route & Component File:** `buyer-web/src/app/order/page.tsx`
* **Reference Design Spec Alignment (`BUYER-REFERENCE-DESIGN-SPEC.md` Section 22):**
  1. **Header:**
     - Uses `GlobalBuyerHeader` with `title="LiveDrop ORDERS"`.
  2. **Tabs Architecture:**
     - Reference specification dictates two tabs:
       - Tab 1: `"Recent Orders"` (active gold underline).
       - Tab 2: `"Saved (3)"` (inactive muted).
     - *Current implementation:* Renders recent orders on this device as a flat list under "Recent Orders on This Device", followed by a manual lookup form ("Have an order link?").
     - *Refinement for Phase I:* Add visual segmented tab bar ("Recent Orders" / "Saved") to match Screen 10 reference layout.
  3. **Order List Cards:**
     - Reference cards feature:
       - Product thumbnail on left.
       - Order ID in bold (`#LD2FA77E`), Boutique Name, Total amount in Paisa format.
       - Status pills: `"Order Placed"` (gold), `"Payment Verified"` (green), `"In Preparation"` (amber).
     - *Current implementation:* Renders order code, boutique name, amount, and text status.
     - *Refinement for Phase I:*
       - Add optional `thumbnailUrl?: string` to `CachedOrderSummary` in `cart-storage.ts` so when an order is created, the primary garment image is cached for the card thumbnail.
       - Style status badges with rich pill tokens (`ld-badge-paid`, `ld-badge-warning`, `ld-badge-confirmed`).

### 4.2 Screen 11: Order Tracking Timeline & DPDP Act Compliance
* **Route & Component Files:**
  - Route: `buyer-web/src/app/order/[id]/page.tsx`
  - Timeline View: `buyer-web/src/components/checkout/CheckoutSuccessView.tsx`
* **Reference Design Spec Alignment (`BUYER-REFERENCE-DESIGN-SPEC.md` Section 23):**
  1. **Token-Gated Security Architecture (DPDP Act Compliance):**
     - Order receipts require high-entropy UUIDv4 `order_token`.
     - In `order/[id]/page.tsx`:
       - First checks URL `?token=` parameter.
       - If absent, checks local device cache `getCachedOrderToken(orderId)`.
       - If neither exists or if the RPC `get_order_by_token` returns an error, page immediately renders `order-token-error-page` with:
         `"To protect customer privacy under the DPDP Act, orders require a verified access token. Please use the secure order link provided upon reservation."` (`data-testid="order-access-restricted"`).
       - Invalidation defense: If backend rejects token, localStorage token is purged immediately (`clearCachedOrderToken(orderId)`).
  2. **Reserved Item Summary:**
     - Renders thumbnail, product code, title, and purchase price in integer Paisa (`data-testid="success-item-${productId}"`).
  3. **Vertical Timeline Progression:**
     - Reference design features gold checkmarks (`#D4AF37`) for completed milestones and pulsing gold for active states:
       - Step 1: Payment Verified (gold checkmark circle, timestamp).
       - Step 2: In Preparation (active gold pulsing circle, "Being packed by the boutique").
       - Step 3: Shipped (gray circle, tracking number if available).
       - Step 4: Out for Delivery (gray circle).
       - Step 5: Delivered (gray circle).
     - Current implementation has 6 steps (including "Payment Submitted" and "Awaiting Seller Verification").
     - Refinement: Style `.ld-timeline-step.completed` and `.ld-timeline-step.active` with rich champagne gold (`#D4AF37`) circles and checkmarks per the reference design.
  4. **Financial Breakdown:**
     - Authoritative Subtotal (`data-testid="success-subtotal"`).
     - Delivery Fee (`data-testid="success-shipping"`).
     - Total Amount (`data-testid="success-total"`).
  5. **Direct UPI View Integration:**
     - Renders embedded `<DirectUpiPaymentView />` (`data-testid="task-handoff-box"`), enabling the buyer to pay or view verification progress directly from the tracking page.

---

## 5. Test Suite Baseline: Architecture & Coverage Audit

### 5.1 Test Runner & Toolchain Configuration
- **Runner:** Vitest 5.0.0 (`@vitejs/plugin-react` ^6.1.1)
- **Environment:** `jsdom` (with `@testing-library/react` 16.3.3 and `@testing-library/jest-dom` 7.0.1)
- **Database Emulation:** `@electric-sql/pglite` 0.5.8 (in-memory WASM PostgreSQL for running real migration scripts and RPC functions without Docker)
- **Configuration File:** `buyer-web/vitest.config.ts`
  ```ts
  setupFiles: ['./src/test/setup.ts'],
  include: ['src/test/**/*.{test,spec}.{ts,tsx}'],
  exclude: ['e2e/**', 'node_modules/**'],
  hookTimeout: 30000,
  testTimeout: 30000,
  ```
- **Global Setup:** `buyer-web/src/test/setup.ts` initializes `@testing-library/jest-dom/vitest`, mock environment variables (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`), and mocks `next/navigation`.

### 5.2 Test Inventory (31 Test Files, 474 Tests)

The 474 tests in `buyer-web/src/test/` map across 6 functional domains:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        474 PASSING UNIT TESTS                          │
├──────────────────────────┬───────────┬─────────────────────────────────┤
│ Domain                   │ Files     │ Key Covered Files               │
├──────────────────────────┼───────────┼─────────────────────────────────┤
│ 1. Cart & Storage        │ 3 files   │ cart.test.tsx (16)              │
│                          │           │ cart-ui.test.tsx (2)            │
│                          │           │ cart-storage.test.ts (11)       │
├──────────────────────────┼───────────┼─────────────────────────────────┤
│ 2. Checkout & Validation │ 3 files   │ checkout.test.tsx (11)          │
│                          │           │ checkout-validator.test.ts (13) │
│                          │           │ checkout-idempotency.test.ts (5)│
├──────────────────────────┼───────────┼─────────────────────────────────┤
│ 3. UPI Payments & Claims │ 2 files   │ direct-upi-payments.test.ts (35)│
│                          │           │ persistent-payment-claims-ui    │
│                          │           │   .test.tsx (10)                │
├──────────────────────────┼───────────┼─────────────────────────────────┤
│ 4. Order & DPDP Tracking │ 2 files   │ order-lookup.test.tsx (5)       │
│                          │           │ order-route.test.tsx (4)        │
├──────────────────────────┼───────────┼─────────────────────────────────┤
│ 5. Database, RPCs & RLS  │ 4 files   │ rpcs.test.ts (65+)              │
│                          │           │ schema.test.ts (40+)            │
│                          │           │ rls.test.ts (45+)               │
│                          │           │ data-layer.test.ts (22)         │
├──────────────────────────┼───────────┼─────────────────────────────────┤
│ 6. Catalog, Nav & Store  │ 17 files  │ catalog-feed.test.tsx (20)      │
│                          │           │ storefront-route.test.tsx (16)  │
│                          │           │ mobile-bottom-dock.test.tsx (7) │
│                          │           │ cinematic-live-room.test.tsx (5)│
│                          │           │ global-buyer-header.test.tsx    │
│                          │           │ home-storefront.test.tsx        │
│                          │           │ shop-category-directory.test    │
│                          │           │ whatsapp-chat.test.ts (6)       │
│                          │           │ realtime.test.ts (3), etc.      │
└──────────────────────────┴───────────┴─────────────────────────────────┘
```

### 5.3 Automated Verification Commands & Execution Matrix

All four required commands were executed on Windows powershell and passed cleanly:

```powershell
# 1. Typecheck: Passed with 0 errors
npm --prefix buyer-web run typecheck
# Output: > tsc --noEmit (Exit 0)

# 2. Lint: Passed with 0 errors
npm --prefix buyer-web run lint
# Output: > eslint (Exit 0)

# 3. Test: Passed 474/474 tests
npm --prefix buyer-web test
# Output: Test Files 31 passed (31) | Tests 474 passed (474) (Exit 0)

# 4. Production Build: Successfully compiled all 9 routes
npm --prefix buyer-web run build
# Output: Compiled successfully in 10.1s | Finished TypeScript in 2.3s | Exit 0
```

---

## 6. Strict Architectural Guardrails Verification

### 6.1 Database RPC Signatures & Preservation
All RPC calls in the codebase operate with strict typed parameter payloads and must NEVER be modified:

1. **`create_order_with_reservation`:**
   - Signature: `(p_drop_id UUID, p_product_ids UUID[], p_buyer_name TEXT, p_buyer_phone TEXT, p_shipping_address TEXT, p_pincode TEXT, p_confirmation_mode TEXT, p_idempotency_key TEXT)`
   - Caller: `buyer-web/src/lib/data/buyer-catalog.ts` -> `createOrderWithReservation()`
   - Guarantees:
     - Deadlock-free locking (`SELECT ... FOR UPDATE ORDER BY id ASC`).
     - Strict atomicity: single transaction creates order and reserves stock.
     - Subtotal and delivery fee calculated server-side in integer Paisa.
2. **`get_order_by_token`:**
   - Signature: `(p_order_id UUID, p_order_token UUID)`
   - Caller: `buyer-web/src/lib/data/buyer-catalog.ts` -> `getOrderByToken()`
   - Guarantees:
     - Hardened against unauthorized scrapers (zero access without matching token).
     - Minimizes PII (excludes phone and address from receipt payload).
3. **`initiate_payment_attempt`:**
   - Signature: `(p_order_id UUID, p_order_token UUID, p_payment_type TEXT)`
   - Caller: `buyer-web/src/lib/data/buyer-catalog.ts` -> `initiatePaymentAttempt()`
   - Guarantees:
     - Server determines exact expected amount in integer Paisa.
     - Captures immutable snapshot of seller's VPA and display name.
4. **`submit_buyer_payment_claim`:**
   - Signature: `(p_order_id UUID, p_order_token UUID, p_payment_attempt_id UUID, p_utr TEXT)`
   - Caller: `buyer-web/src/lib/data/buyer-catalog.ts` -> `submitBuyerPaymentClaim()`
   - Guarantees:
     - Saves buyer's 12-digit UTR for seller review.
     - Transitions state to `awaiting_seller_verification`.
     - Sets 24-hour verification window without prematurely marking order paid.

### 6.2 Monetary Standard (ADR-009)
- All currency values across database columns, RPC payloads, TypeScript types, and local storage schemas are strictly non-negative integers in **Paisa**:
  - `price_paisa`, `subtotal_paisa`, `shipping_paisa`, `total_paisa`, `advance_required_paisa`, `advance_paid_paisa`, `balance_due_paisa`, `expected_amount_paisa`.
- Conversion to INR string format occurs exclusively at the UI edge via:
  ```ts
  export function formatPaisaToINR(paisa: number): string
  // e.g., 185000 -> "₹1,850"
  ```
- Floating-point arithmetic on currency is strictly forbidden.

### 6.3 Checkout Idempotency (ADR-009)
- Managed in `buyer-web/src/lib/checkout/idempotency.ts`.
- Format: `req_chk_${uuid}`.
- Scoped to `dropId` and sorted product IDs (`${dropId}:${sortedProductIds.join(',')}`).
- Stored in `sessionStorage` under `livedrop_chk_idemp_${dropId}`.
- Successfully prevents duplicate orders from rapid multi-tapping, flaky cellular networks, or browser reloads.

---

## 7. Implementation Roadmap & Gap Analysis for Phases G, H, I

To achieve pixel-perfect visual parity with `media_1790450082820.jpg` while preserving 100% of tests and contracts, the implementing agents should execute the following targeted visual refinements:

### Phase G (Screens 06 & 07: Cart & Empty Cart)
1. **`CartItemRow.tsx`:**
   - Change thumbnail container from `w-20 h-20` (square) to `w-20 aspect-[3/4]` or `w-[72px] h-[96px]` with `object-cover`.
   - Ensure `data-testid={`cart-item-${item.productId}`}` and `data-testid={`cart-remove-${item.productId}`}` are preserved.
2. **`CartEmptyState.tsx`:**
   - Replace system emoji `🛍` with luxury gold shopping bags vector illustration (`<svg>`) with glowing sparkles.
   - Retain `data-testid="cart-empty-state"` and `data-testid="cart-browse-btn"`.
3. **`cart/page.tsx` & `CartDrawer.tsx`:**
   - Replace emoji `🎁` in "Add a note (optional)" toggle with gold SVG sparkle/gift outline.
   - Harmonize informational banner text in both drawer and page to verbatim spec: *"Items are not reserved until checkout. Live drops are single-piece limited editions."*

### Phase H (Screens 08 & 09: Checkout & Direct UPI Payment)
1. **`checkout/page.tsx`:**
   - Update 3-step breadcrumb step 3 label to `"3 Confirm"`.
   - Verify header and mobile container padding align with 56px luxury header.
2. **`CheckoutForm.tsx`:**
   - Apply dark elevated surface styling (`#16161C`, `border: 1px solid rgba(255, 255, 255, 0.1)`, `focus:border-[#D4AF37]`).
   - Retain all `data-testid` attributes (`input-buyer-name`, `input-buyer-phone`, `input-pincode`, `input-shipping-address`).
3. **`DirectUpiPaymentView.tsx`:**
   - Style QR code container with clean white elevated card and fine gold border.
   - Button label: `"Verify Payment →"` on primary CTA (`data-testid="submit-payment-claim-btn"`).
   - Retain all `data-testid` attributes and state transitions.

### Phase I (Screens 10 & 11: Orders & Tracking)
1. **`order/page.tsx`:**
   - Introduce visual segmented tabs: `"Recent Orders"` (active gold underline) and `"Saved (3)"` (inactive).
   - Add product thumbnail on left of order card (supported by caching `thumbnailUrl` in `CachedOrderSummary`).
   - Style status pills with rich status tokens: Gold for "Order Placed", Green for "Payment Verified", Amber for "In Preparation".
2. **`CheckoutSuccessView.tsx` & `order/[id]/page.tsx`:**
   - Update vertical timeline icons: Gold checkmarks (`#D4AF37`) for completed steps, active gold pulsing circle for in-progress step.
   - Retain DPDP Act token gating and privacy notice.

---

## 8. Conclusion

The LiveDrop buyer front-end possesses an exceptionally robust, production-grade architectural and testing foundation. The core database RPCs, transactional locking, Paisa monetary representation, idempotency tokens, and DPDP security gating are fully verified and backed by 474 passing tests. The subsequent visual reconstruction phases (G, H, and I) can proceed with absolute confidence, focusing purely on high-fidelity CSS and vector asset alignment without altering underlying data structures or test contracts.
