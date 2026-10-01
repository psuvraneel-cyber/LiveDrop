# 06 — Seller ↔ buyer integration

**Confidence: PARTIALLY VERIFIED.** The shared transport is Supabase PostgREST/RPC/Realtime, not a separate backend API.

| Flow | Source → transport → data | Authorization / state | Failure/retry confidence |
|---|---|---|---|
| Create/edit product | seller repository → `products` / `update_product` → public catalog view | seller owns drop; authoritative editing RPC exists | runtime unverified |
| Create/publish drop | seller repository → `drops` / `close_drop` | RLS ownership, unique live constraint, approval trigger | runtime unverified |
| Buyer discovery | buyer catalog → `drops`, `public_seller_storefronts`, `public_products_catalog` | anon projection/grants | static only |
| Reserve/checkout | buyer catalog → `create_order_with_reservation` → orders/items/products | public RPC; DB should lock/calculate | concurrency unverified |
| Claim/verify | buyer then seller → attempt/claim/verify/reject RPCs | order token then drop ownership | payment authenticity manual |
| Fulfil/shipping | seller → ready/shipped RPCs → token receipt/Realtime | paid + seller ownership gate | notification/runtime sync unverified |

No cache other than browser/Next caching headers and client state was found. The buyer catalog has a polling fallback; the payment view subscribes to Realtime, but a payment-specific fallback was not established by this audit. Seller-created data propagation and buyer consistency are structurally connected through the same database views, but no safe deployed runtime test was available.
