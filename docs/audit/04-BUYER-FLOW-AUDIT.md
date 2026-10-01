# 04 — Buyer flow audit

**Confidence: PARTIALLY VERIFIED.** Buyer routes support shop/storefront/drop browsing, cart, checkout, direct UPI claim, and tokenized order lookup. Browser cart persistence is implemented in `src/lib/cart/cart-storage.ts`; checkout idempotency support is documented in the client and migration 022. Catalog synchronization uses Realtime with a polling fallback implementation (`src/lib/realtime/catalog-realtime.ts`).

Static journey: public views → product selection/cart → `create_order_with_reservation` → `initiate_payment_attempt` → UPI intent/claim → `submit_buyer_payment_claim` → token receipt. `DirectUpiPaymentView.tsx` subscribes to order/payment changes. Buyer controls do not calculate authoritative price or reserve inventory directly.

The following are **UNVERIFIED / BLOCKED**: anonymous browsing against a deployed RLS policy; cart reload/restart behavior in a real browser; sold/reserved reconciliation; duplicate checkout; malformed/expired token handling; payment refresh/network loss; Realtime failure/fallback timing; and cross-device behavior. Unit tests exist but the full Vitest suite did not complete locally (see audit/TEST-RESULTS.json).
