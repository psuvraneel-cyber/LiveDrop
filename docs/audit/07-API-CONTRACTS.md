# 07 — API/contract inventory

| Interface | Caller | Auth | Purpose / idempotency |
|---|---|---|---|
| `drops`, `public_seller_storefronts`, `public_products_catalog` selects | Buyer `buyer-catalog.ts` | anon/public projection | Discovery/catalog; cache headers on drop routes |
| `create_order_with_reservation` | Buyer | anon or authenticated | Atomic price/inventory order creation; migration 022 adds idempotency conflict handling |
| `get_order_by_token` | Buyer | order UUID + secret token | Receipt/track retrieval |
| `initiate_payment_attempt` | Buyer | token-scoped | Direct UPI payee/attempt creation |
| `submit_buyer_payment_claim` | Buyer | token-scoped | UTR claim; duplicate semantics require runtime test |
| profile/drop/product PostgREST operations | Seller repository | authenticated JWT + RLS | Seller setup/catalog maintenance |
| `verify_manual_upi_payment`, `reject_manual_upi_payment` | Seller repository | authenticated seller ownership | Manual decision on claim |
| `mark_order_ready_to_ship`, `mark_order_shipped`, `close_drop`, `update_product` | Seller repository | authenticated seller ownership | Lifecycle transitions |
| `release_expired_holds` | GitHub cron | service role | maintenance; not safe for client exposure |
| Storage upload | Seller repository | authenticated | product images |
| Realtime postgres changes | Buyer/seller clients | channel subscription | catalog/order/payment updates |

No OpenAPI document, Next API route, Edge Function, or server action was found. Error mappings are client-side `LiveDropError`/PostgREST handling; global server-side rate limiting is not evidenced. Contract drift must be checked against live PostgREST after migrations, not inferred from types alone.
