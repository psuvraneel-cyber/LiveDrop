# ADR-004: WhatsApp Deep-Link Handshake & Direct Peer-to-Peer UPI Model

## Status
**Accepted**

## Context
Small Indian boutique owners selling via Facebook and Instagram Live operate on thin margins (10-15%). Standard payment gateways (Razorpay, Cashfree, Stripe) impose significant friction:
1. They require business registration (GST / MSME certificates), which informal sellers do not possess.
2. They deduct a 2% transaction fee on every sale.
3. They enforce a T+2 or T+3 bank settlement delay, starving sellers of immediate working capital.

Conversely, **Unified Payments Interface (UPI)** is universal in India, free (0% fee), and provides instant bank-to-bank settlement. Indian live sellers routinely receive payment screenshots directly from buyers on WhatsApp.

## Decision
Adopt a **WhatsApp Deep-Link Handshake & Direct UPI Payment Workflow**:
1. **Automated Order Message Assembly**: Upon successful checkout, the webfront generates a structured text message containing the order ID, items purchased, total amount, delivery address, and payment instructions.
2. **Sanitized Deep Link**: The message is strictly URL-encoded (`encodeURIComponent`) and formatted into an authoritative WhatsApp deep link:
   ```
   https://wa.me/{seller_phone}?text={encoded_order_message}
   ```
3. **Direct UPI Details & Dynamic QR Code**: The order confirmation screen renders:
   * The seller's verified UPI ID (e.g., `priya@okhdfcbank`).
   * A dynamic UPI QR code encoded with:
     ```
     upi://pay?pa={seller_upi_id}&pn={seller_name}&am={total_in_rupees}&cu=INR&tn=Order_{order_id}
     ```
   * A 1-click button to launch installed UPI apps (Google Pay, PhonePe, Paytm).
4. **WebView Fallback Protection**: If the buyer is browsing inside an Instagram/Facebook in-app browser where `wa.me` deep links are sandboxed or blocked, the UI automatically detects the environment and provides:
   * A 1-click "Copy Order Details" clipboard button.
   * An on-screen UPI QR code.
   * A "Open in System Browser" prompt.

```
Buyer Completes Checkout
         │
         ▼
Database Creates Order (Status: Pending)
         │
         ├──> Webfront Shows UPI QR Code & Seller UPI ID
         │
         ▼
Buyer Clicks "Send Order on WhatsApp"
         │
         ├──> Opens WhatsApp Chat with Seller
         │    (Pre-filled message: Order #1042, Items, Total)
         │
         ▼
Buyer Sends Payment Screenshot on WhatsApp
         │
         ▼
Seller Verifies Bank SMS ──> Clicks "Mark Paid" in Flutter App
```

## Alternatives Considered
* **Integrated Payment Gateway (Razorpay/Cashfree)**: Rejected for MVP due to 2% gateway fees, KYC friction, and setup barriers for micro-boutiques. Reserved for post-MVP.
* **Cash on Delivery (COD)**: High Return to Origin (RTO) rate (> 35% in Indian fashion e-commerce). Rejected.

## Consequences
* **Positive**: Zero processing fees (₹0 cost forever); immediate liquidity for sellers; aligns 100% with existing informal buyer habits.
* **Negative**: Requires manual human verification by the seller (comparing bank notification with WhatsApp screenshot) before marking order as "Paid".

## Security Implications
* Phone numbers must be normalized to E.164 standard (`+91` prefix).
* All user input embedded in `wa.me` links must be strictly sanitized to prevent URI injection attacks.
