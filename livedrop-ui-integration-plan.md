# LiveDrop buyer UI v1 integration plan

## Scope and evidence

This is a read-only architecture and integration review. No repository checkout, database, Git history, or uploaded ZIP was modified.

Evidence inspected:

- LiveDrop repository `psuvraneel-cyber/LiveDrop`, fetched into a disposable inspection copy at commit `349dd3f55019e2e4de72ce098a35b6b1c023414f`.
- The attached `livedrop-ui-v1.zip`, extracted into a disposable inspection directory.
- Repository source, SQL migrations, buyer tests, seller code, and the repository's source-of-truth/architecture/payment/security documents.

Labels used below:

- **Verified:** directly observed in source, SQL, tests, or the inspected ZIP.
- **Inference:** a recommended interpretation or implementation consequence.
- **Gap:** not present, contradictory, or requiring confirmation in the deployed environment.

## Executive conclusion

The ZIP should be integrated as a presentation layer and component/design reference, not copied over the buyer application wholesale. The current production buyer web already owns critical behavior that the ZIP does not implement: Supabase catalog reads, anonymous buyer checkout, atomic reservation, server-authoritative Paisa totals, token-gated order lookup, direct UPI payment attempts, buyer payment claims, seller verification, payment-state recovery, Realtime/polling synchronization, and error boundaries.

The safest strategy is to preserve the production routes, domain types, data access, RPC payloads, RLS assumptions, and checkout/payment components while progressively replacing visual composition and interaction primitives. The first implementation milestone should be a read-only catalog slice using live data, followed by cart, then checkout/payment, then order tracking. Do not enable a full-site cutover until the production checkout and payment recovery scenarios pass unchanged.

## 1. Actual architecture

### Seller app

**Verified:** `seller-app` is a Flutter Android application. It authenticates sellers with Supabase email/password sign-in and registration, provisions/updates seller profiles, and exposes seller workflows for drops, product intake, inventory, orders, payment settings, analytics, and shipping labels. `seller_repository.dart` reads and mutates Supabase tables/RPCs; `seller_order_realtime.dart` subscribes to order changes. The intake path includes an offline queue, image upload/storage handling, and client-side PDF shipping-label generation.

Seller authorization is derived from the authenticated Supabase user and ownership joins such as `drops.seller_id = auth.uid()`. The database, not the Flutter client, is the final authorization boundary.

### Buyer website

**Verified:** `buyer-web` is a Next.js App Router application using React, TypeScript, Tailwind, and `@supabase/supabase-js`. Current routes include the homepage, shop, storefront/drop pages, cart, checkout, order lookup, order detail, and drop/live experiences. The current visual system includes global navigation, mobile bottom navigation, product cards, storefront/catalog views, filter sheets, cart drawers, checkout form/review/success views, a direct UPI payment view, error states, and loading/empty states.

The buyer is intentionally anonymous for catalog and purchase initiation. The cart is client-side intent only; it does not reserve inventory. Checkout calls the database reservation RPC, which is the authoritative source for availability, prices, shipping, totals, and order creation.

### Backend and data plane

**Verified:** Supabase provides Auth, PostgreSQL, RLS, Realtime, Storage, and RPC execution. The SQL migrations define profiles, drops, products, orders, order items, payment records/attempts, indexes, RLS policies, public catalog projections, storage buckets, Realtime publication, and business RPCs. Products are single-piece inventory with `available`, `reserved`, and `sold` states.

The repository contains no deployed payment gateway adapter or webhook handler. The implemented payment model is direct peer-to-peer UPI with manual seller verification. Some older documentation discusses gateway integration as future/deferred work; the current migrations and buyer/seller code are the stronger implementation evidence.

## 2. Data and control flows

```text
Seller Flutter app
  │ Supabase Auth: sign up/sign in
  │ seller-owned writes, uploads, order actions, payment verification
  ▼
Supabase Auth + PostgreSQL/RLS/RPCs + Storage + Realtime
  ▲                         │
  │ seller order/catalog    │ public projections, RPCs, Realtime events
  │ events                   ▼
Buyer Next.js web
  │ anonymous catalog reads through public projections
  │ local cart intent + live catalog subscription/poll fallback
  │ checkout RPC with buyer details and product IDs
  │ order_token retained for receipt/payment access
  ▼
Buyer order/payment UI ── direct UPI URI/QR ──► seller's UPI account
  │                                             │
  │ UTR/payment claim                          │ seller checks bank/UPI app
  ▼                                             ▼
submit claim RPC ◄──────── seller manual verification RPC ────────
  │
  └─ payment/order/product state changes → Realtime + authoritative reads
```

### Discovery and listing flow

1. Seller creates/configures a drop and adds products in the seller app.
2. Product images are uploaded to Supabase Storage; product/drop/profile data is stored in PostgreSQL.
3. Buyer loads the public catalog/storefront projection. Buyer code maps database rows into domain objects and does not calculate authoritative price or availability.
4. Realtime product changes provide low-latency updates. The client rejects stale versions and falls back to authoritative polling when the WebSocket is unavailable or capacity is exceeded.

### Cart and reservation flow

1. Buyer adds product IDs to local cart state.
2. Cart changes are reconciled against current catalog snapshots and Realtime events.
3. No database reservation occurs on add-to-cart.
4. Checkout sends the drop, product IDs, buyer name/phone/address/pincode, confirmation mode, and an idempotency key to `create_order_with_reservation`.
5. The RPC locks product rows in deterministic order, validates availability and input, calculates subtotal/shipping/total in integer Paisa, inserts the order and immutable order items, marks products reserved, and returns an authoritative receipt.
6. Conflicts roll back atomically; the UI preserves the remaining cart and explains which item was lost.

### Order lifecycle

```text
checkout RPC
    │
    ▼
pending + products reserved + hold_expires_at
    │
    ├─ hold expires before required payment → expired/cancelled + products available
    │
    ├─ advance payment verified → confirmed + advance_paid + extended hold
    │       └─ balance verified → paid + ready_to_ship
    │
    ├─ full payment verified → paid + ready_to_ship
    │
    └─ seller fulfillment → shipped
```

The exact terminal/transition behavior must be taken from the deployed schema/migration version during implementation. The repository's domain model includes `pending`, `confirmed`, `paid`, `cancelled`, `shipped`, and `expired`; payment status is `unpaid`, `advance_paid`, or `paid`; fulfillment status is `not_ready`, `ready_to_ship`, or `shipped`.

## 3. Payment model and reconciliation

### What is verified

- Payment method is direct UPI; seller configuration includes VPA/UPI ID, display name, QR URL, enablement, and instructions.
- `initiate_payment_attempt` validates the order token, determines `advance`, `balance`, or `full`, snapshots payee/amount/reference data, and returns a UPI URI plus attempt details.
- The buyer opens the UPI app or scans the QR, then submits a UTR/payment reference through `submit_buyer_payment_claim`.
- Payment attempts have states including `created`, `awaiting_payment`, `buyer_claimed`, `awaiting_seller_verification`, `verified`, `rejected`, and `expired`.
- Seller verification is performed in the seller app through protected RPCs/queries. Direct client mutation of payment/order state is blocked by RLS/triggers.
- Payment transitions update the payment ledger and order fields. Advance payment can move an order to `confirmed` with a remaining balance; full payment moves it to `paid`; shipping requires zero balance.
- A late-payment/recovery path and persistent claim window are represented in migrations 014/023. The reaper releases expired holds and handles expiration according to the current state machine.
- Realtime plus bounded polling is used to reflect verification changes to the buyer.

### What is not verified/present

- No Stripe, Razorpay, Cashfree, or other gateway integration was found in the inspected repository.
- No provider webhook endpoint or webhook signature verification handler was found.
- No automatic provider settlement/reconciliation feed was found.
- Reconciliation is therefore operational/manual: seller checks the UPI receipt/bank app against the buyer's claim/reference, then invokes the protected verification transition; the database ledger and order totals become the system record.
- The production scheduler/hosted mechanism that invokes the hold reaper needs confirmation. Repository documentation mentions `pg_cron` or an edge/worker daemon as options; this is an operational gap unless verified in the deployed Supabase project.

### Integration consequence

The new UI must never show a generic “payment succeeded” state after launching a UPI intent. It must show “awaiting verification” until the authoritative payment attempt/order state changes. It must retain the order token and payment-attempt identifiers, support refresh/re-entry, handle rejection/expiry/late payment, and display seller-configured payment instructions without trusting client-calculated amounts.

## 4. ZIP structure and contract assessment

### Verified ZIP contents

The ZIP is a standalone Next.js 16.3.6/React 19.1/Tailwind 4.1 prototype using `motion` and `lucide-react`. It includes local SVG imagery, a design-system document, shared header/footer/bottom-nav/product/boutique/category/trust components, and routes for:

- `/`
- `/shop`
- `/filters`
- `/live`
- `/product/[id]`
- `/cart`
- `/cart/empty`
- `/order`

Its `BuyerProvider` seeds three mock products into a local cart and persists the mock `Product` object shape to localStorage. The data module contains six static products and three static boutiques. The ZIP contains no Supabase client, auth flow, domain adapter, RPC calls, checkout form, direct UPI view, payment-attempt handling, Realtime subscription, order-token handling, or live backend catalog mapping. The `/order` page explicitly describes itself as waiting for a real backend connection.

### High-confidence gaps in the prototype

- No `/checkout` route is present; the cart CTA is presentation-only.
- Product availability, quantity, prices, shipping, and totals are mock/client-derived.
- The cart can contain multiple quantities even though production inventory is single-piece.
- The prototype's `Product`/`CartItem` shape does not match production domain/cart types.
- No production error, loading, stale-data, reservation-conflict, or payment-recovery states are wired.
- Some controls are visual placeholders: newsletter submission, several filter options, wishlist/save, and order tracking.
- Accessibility needs a focused audit before reuse: image alt text, icon-only controls, focus trapping/return for drawers/sheets, keyboard behavior, reduced-motion behavior, form labels, and live announcements for cart/filter/payment state.
- The ZIP includes generated/build and dependency directories; treat them as disposable and do not merge them into the production source tree.

## 5. Integration touchpoints and risks

| Area | Risk | Mitigation / acceptance gate |
|---|---|---|
| Routing | ZIP routes do not match production routes such as `/drop/[slug]`, storefront routes, `/checkout`, and `/order/[id]`. | Preserve production URLs and deep links. Map the new visual components into existing route owners; add redirects only after checking analytics/bookmarks. |
| Data shape | Mock `Product` objects contain display prices and nested cart objects; production uses UUIDs, Paisa integers, drop/storefront metadata, versions, and reservation state. | Add a presentation adapter from production domain types to view props. Keep product IDs/drop IDs and Paisa values authoritative. |
| Cart | Prototype localStorage may persist stale mock objects and supports quantity semantics that do not fit single-piece inventory. | Keep the production cart context/storage, migrate only visual rows/drawer behavior, version/clear incompatible persisted state, and reconcile against the catalog on load. |
| Checkout | Prototype has no checkout implementation. A wholesale replacement could bypass atomic reservation or idempotency. | Retain the production checkout page, validator, idempotency key, RPC call, conflict handling, and authoritative receipt. Replace form/review visuals incrementally. |
| Payments | Prototype has no UPI, UTR, claim, seller verification, or recovery semantics. | Retain `DirectUpiPaymentView` and its RPC/realtime/polling behavior; restyle it only after contract tests pass. |
| Auth/RLS | Anonymous buyer access is deliberate; adding buyer auth or direct table reads can change privacy and RLS behavior. | Do not introduce auth gates or service-role credentials. Preserve order-token headers and public projection queries; run negative RLS tests. |
| Seller integration | Seller app expects the existing order/payment/product states and Realtime payloads. | Do not rename statuses or fields for UI convenience. Validate buyer-to-seller order appearance and seller verification end-to-end. |
| Realtime | New component trees may duplicate subscriptions or miss cleanup, causing stale/incorrect stock. | Keep one catalog subscription owner, preserve version ordering and polling fallback, test tab visibility/reconnect behavior. |
| Accessibility | Luxury visual treatment can obscure focus, status, and error messaging. | Keyboard/mobile screen-reader pass, focus management for sheets/drawers, semantic headings/labels, `aria-live` for cart/payment state, WCAG contrast and reduced-motion checks. |
| Error handling | Prototype has optimistic local behavior but no domain errors. | Preserve typed error mapping for stock conflicts, unauthorized/token failure, expired holds, invalid UTR, payment rejection, and network retry. |
| Rollback | A visual cutover can break deep links or client storage while database state remains valid. | Use a feature flag or route-level canary, keep the current buyer presentation available, and define instant revert plus local-storage migration/versioning. |
| Telemetry | Prototype interactions are not production events. | Add funnel events around catalog view, product open, add-to-cart, checkout start, reservation success/conflict, payment attempt, claim, verification, expiry, and error—without logging PII, tokens, UTRs, or payment secrets. |
| Performance | The ZIP's local assets/build output are large and may not reflect production image delivery. | Use production Storage URLs and image optimization, measure mobile LCP/CLS/INP, lazy-load below-fold imagery, and test low-bandwidth 4G. |
| Documentation drift | README/docs and current migrations are not perfectly aligned; README references older Next versions and older payment wording. | Reconcile against code, deployed schema, tests, and approved ADRs. Record any unresolved deployment discrepancy before implementation. |

## 6. Phased implementation plan

### Phase 1 — Discovery and risk assessment

Deliverables:

1. Freeze the current buyer route/API/RPC contract matrix.
2. Export the deployed Supabase schema/function signatures and compare them with migrations 001–032.
3. Inventory production environment variables, Storage buckets, Realtime publication, scheduler/reaper, domains, and Vercel deployment settings.
4. Capture baseline buyer/seller E2E evidence for catalog, reservation contention, checkout, UPI claim, seller verification, expiry, and order tracking.
5. Produce a component mapping: ZIP component → existing buyer component/route/data owner.
6. Confirm the desired canonical routes for product details, filters, live rooms, storefronts, and order tracking.

Exit gate: no unresolved P0 security, payment, reservation, or deployed-schema discrepancy; all integration assumptions are written down.

### Phase 2 — Integration design

Deliverables:

1. Define the adapter boundary between production domain models and visual components.
2. Define which production state owners remain unchanged: cart context, catalog/realtime layer, checkout orchestration, payment view, order lookup, and error boundaries.
3. Create a route compatibility table and deep-link/redirect policy.
4. Create a design-token migration plan for the existing `globals.css`, including dark/gold tokens, typography, spacing, radii, focus states, and responsive breakpoints.
5. Define localStorage schema/version migration for existing buyers.
6. Define telemetry events and privacy rules.
7. Define feature-flag/canary and rollback mechanics.

Exit gate: design review approves the adapter and ownership boundaries; no new UI API is allowed to call tables directly or calculate authoritative commerce values.

### Phase 3 — Implementation plan

Implement in vertical slices:

1. Shared shell: header, mobile dock, page background, typography, tokens, focus treatment.
2. Read-only home/shop/catalog: live public data, real image URLs, loading/empty/error states, filter/search behavior, Realtime/poll fallback.
3. Product detail/quick view: production product identity, stock state, boutique/drop links, accessible modal/drawer behavior.
4. Cart: retain production cart state and reconciliation; adopt ZIP visual treatment only.
5. Checkout: retain production form validation, idempotency, atomic reservation, receipt/token handling; replace presentation sections.
6. UPI/payment recovery: retain direct UPI RPCs, UTR claim, seller verification state, countdown/expiry, realtime/polling, rejection and late-payment paths.
7. Orders: retain token-gated lookup and order detail/timeline; use ZIP styling only where it does not hide status semantics.
8. Remove mock data and ensure no demo seed cart survives production builds.

Exit gate: production data powers every buyer screen, and all commerce state transitions still originate in existing RPCs/authorized reads.

### Phase 4 — Testing and rollback strategy

Test layers:

- Typecheck/lint/build for the buyer app.
- Existing buyer unit tests and RPC/RLS tests.
- Component tests for keyboard/focus/ARIA/reduced motion and responsive states.
- E2E: anonymous catalog → cart → checkout → reserved order; contention; expiry; direct UPI attempt; claim; seller approval/rejection; balance payment; shipping gate; order lookup with valid/invalid token; refresh/reconnect/offline recovery.
- Cross-device checks for 360–430px mobile widths, desktop widths, iOS/Android in-app browsers, and slow 4G.
- Security checks for public catalog minimization, no PII leakage, no token/UTR telemetry, no service-role exposure, and seller isolation.

Rollback:

1. Keep old and new presentation paths behind a feature flag or route-level switch.
2. Roll back the frontend artifact only; do not roll back database migrations that are already serving live orders.
3. Version client storage and clear/migrate incompatible mock/demo state.
4. Define a support procedure for orders created during a failed visual deployment; backend order/payment state remains authoritative.

Exit gate: all release-blocking tests pass and rollback is rehearsed against a staging deployment.

### Phase 5 — Deployment and monitoring

1. Deploy to staging with production-like Supabase schema/data and safe test UPI accounts.
2. Run a stakeholder pilot using real mobile devices and the seller app.
3. Canary a small buyer traffic slice or explicit feature-flag cohort.
4. Monitor catalog load errors, Realtime disconnect/fallback rate, add-to-cart/reconciliation conflicts, checkout RPC success/conflict rate, payment-attempt/claim/verification/expiry counts, order lookup failures, Web Vitals, JS errors, and support contacts.
5. Keep the previous presentation artifact available for immediate rollback.
6. Expand only after one complete operational cycle—discovery, reservation, payment verification, fulfillment, and order tracking—has been observed.

## 7. Minimal next-48-hours checklist

### Engineering

- [ ] Confirm deployed commit/schema/migration version and export live RPC signatures.
- [ ] Confirm whether the hold reaper is actually scheduled in production.
- [ ] Inventory current buyer routes and create the ZIP-to-production component map.
- [ ] Document production domain/cart/checkout/payment types as the non-negotiable contract.
- [ ] Decide canonical URLs for `/shop`, `/filters`, `/live`, product details, and order tracking.
- [ ] Create a staging-only feature flag and rollback switch; do not begin with a full replacement.
- [ ] Capture baseline E2E results and mobile screenshots for current production behavior.
- [ ] Define telemetry event names and explicitly exclude PII, order tokens, and UTRs.

### Product/design

- [ ] Approve which ZIP visual behaviors are mandatory versus decorative.
- [ ] Confirm the product detail, live-room, filter, checkout, UPI, and order-tracking states that must remain visible.
- [ ] Approve accessibility requirements and reduced-motion behavior.

### Operations/support

- [ ] Confirm the seller verification workflow and who handles unverified/late UPI claims.
- [ ] Confirm rollback owner, incident channel, and customer-support wording for an interrupted checkout.
- [ ] Prepare a small set of safe staging sellers/products and test UPI accounts.

## 8. Stakeholder communication plan

- **Daily engineering checkpoint:** route/contract changes, test status, new risks, and deployment readiness.
- **Product/design review at the end of Phase 2:** approve component mapping, route policy, state visibility, and accessibility.
- **Seller-operations review before Phase 4 exit:** verify payment claims, rejection, expiry, balance, shipping, and order-board behavior.
- **Security/data review before canary:** confirm RLS, token-gated order access, telemetry redaction, and secrets boundaries.
- **Release go/no-go:** engineering, product, seller operations, and support sign off on E2E results and rollback readiness.
- **Post-release review:** report funnel metrics, payment/reconciliation exceptions, buyer support issues, and any deviations from the approved plan.

## Open gaps requiring confirmation

1. The deployed Supabase schema may differ from the repository migrations; local source alone cannot prove production parity.
2. The production scheduler/reaper mechanism is not established by source inspection alone.
3. The intended canonical URL for every ZIP screen is not identical to the current buyer route structure.
4. The repository contains documentation from multiple implementation stages, including older payment-gateway language; current SQL/client code indicates direct UPI/manual verification, but product/operations should confirm that this is the intended live model.
5. No production analytics/telemetry connector was identified in the inspected buyer source; the monitoring implementation and ownership need confirmation.

## Recommended decision

Approve the ZIP as the visual target and begin with a production-backed catalog slice. Do not merge the ZIP as a standalone app or replace checkout/payment/order code until the adapter, route compatibility, RLS/token, and payment-state gates above are satisfied.
