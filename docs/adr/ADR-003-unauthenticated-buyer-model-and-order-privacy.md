# ADR-003: Unauthenticated Buyer Model & Token-Scoped Order Privacy

## Status
**Accepted**

## Context
Requiring buyers to create an account, verify an email, or enter an OTP before purchasing causes massive drop-off (40-60%) in impulse live-stream shopping. A core value proposition of LiveDrop is **zero-friction checkout**: a buyer enters name, phone, and delivery address directly in the checkout bottom sheet and places their order in under 30 seconds.

However, an unauthenticated buyer model presents a severe privacy and data security vulnerability:
* If the `orders` table allows public read access (`SELECT` to `anon`), any malicious actor can scrape names, phone numbers, and home addresses across all sellers.
* If the `orders` table forbids public read access, the legitimate buyer cannot view their confirmation screen (`/order/[id]`) or refresh their browser.

## Decision
Implement **Cryptographic Token-Scoped Row-Level Security (RLS)**:
1. **Unauthenticated Checkout**: Buyers do not log in. During order placement via the `create_order_with_reservation` RPC, the database generates a cryptographically secure 128-bit entropy token: `order_token UUID DEFAULT gen_random_uuid()`.
2. **Token Handshake**: The RPC returns `{ order_id, order_token, status, ... }` exclusively to the initiating client session.
3. **Restricted RLS Policy**: The `orders` table enables RLS with strict read policies:
   * **Sellers**: Authenticated sellers can read orders where `auth.uid() = seller_id`.
   * **Buyers**: Anonymous users (`anon`) can read order records **ONLY** when supplying the valid `order_token` via a custom RPC (`get_order_by_token`) or matching session header.
   ```sql
   CREATE POLICY "Buyers can view order with valid token"
   ON public.orders
   FOR SELECT
   TO anon
   USING (
     order_token IS NOT NULL AND
     order_token::text = (current_setting('request.headers', true)::jsonb ->> 'x-order-token')
   );
   ```
4. **Client Navigation**: The confirmation URL is formatted as `/order/[id]?token=[order_token]`. If the buyer refreshes the tab, the token in the URL restores read access.

## Alternatives Considered
* **Phone Number OTP Login**: Eliminates impulse purchases; incurs SMS gateway costs (₹0.15 - ₹0.25 per SMS in India), destroying the ₹0 cost model. Rejected.
* **Open Public Order Access with UUIDs**: UUIDs are difficult to guess, but anyone who obtains a shared link can view complete customer PII. Rejected as unacceptable under India DPDP Act 2023.

## Consequences
* **Positive**: Maintains zero-friction impulse checkout; 100% compliant with privacy regulations; eliminates automated scraping attacks.
* **Negative**: If a buyer loses their confirmation URL and clears browser history, they cannot look up past orders on the webfront without contacting the seller directly via WhatsApp.

## Security Implications
* Rate limit checkout and token lookups at Cloudflare edge to prevent token brute-forcing.
* Never log `order_token` in access logs or client analytics.
