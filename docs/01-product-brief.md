# 01 — Canonical Product Brief: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  

---

## 1. Executive Summary

**LiveDrop** is a specialized, zero-overhead live-commerce and fulfillment operating system purpose-built for independent home boutique sellers operating via Facebook Live and WhatsApp. By pairing a high-speed, native **Seller Operations Mobile App (Flutter)** with an ultra-lightweight, zero-download **Buyer Web Catalog (Next.js)**, LiveDrop eliminates the operational chaos of comment-based selling, inventory misallocation, manual payment tracking, and handwritten shipping slips.

Built with modern full-stack technologies and architected to run within cloud free tiers (₹0 operating overhead), LiveDrop bridges the critical gap between chaotic informal social selling and cumbersome enterprise e-commerce platforms.

---

## 2. Vision & Core Value Proposition

* **Vision:** Empower independent social boutique entrepreneurs to professionalize and scale their live-stream sales without altering how their buyers love to shop.
* **Core Value Proposition:**
  * **For Sellers:** Cuts post-broadcast administrative drag by 80%—from hours spent deciphering screenshots and handwriting courier slips down to minutes of one-tap order verification and automated 4×6 inch label generation.
  * **For Buyers:** Zero friction. No app downloads, no account registrations, and no passwords. Buyers browse clear flash codes on a mobile web link, bundle multiple garments into a single cart across a 90-minute livestream, and complete checkout directly via their familiar WhatsApp chat.

---

## 3. Market Context & Target Personas

### 3.1 The Market Reality
Across India and Southeast Asia, thousands of micro-entrepreneurs generate substantial livelihoods through Facebook Live garment selling. Communities like *FASHION SWAP*, *Debikar Sajghor*, and countless regional boutique circles host daily streams where sellers showcase unique, limited-quantity garments (handloom sarees, kurtis, western dresses, jewelry). 

Despite moving millions of rupees in merchandise monthly, these sellers operate on an entirely manual pipeline:
1. Streamers display garments on Facebook Live.
2. Viewers type "booked" in comments or capture blurry screenshots.
3. Viewers reach out to sellers on WhatsApp with vague descriptions (*"the pink saree shown around minute 24"*).
4. Sellers manually verify whether the piece is still available, calculate bundle totals, collect UPI payments, and handwrite shipping labels on paper parcels.

### 3.2 Primary Persona: The Home Boutique Seller
* **Profile:** Independent entrepreneur running a home-based garment boutique; broadcasts 2–5 times weekly on Facebook Live; manages inventory, customer relations, and courier dispatches solo or with family assistance.
* **Key Characteristics:**
  * Highly proficient in WhatsApp, Facebook, and UPI applications, but resistant to complex enterprise software (Shopify, WooCommerce, ERPs).
  * Manages high inventory turnover with unique, single-piece stock (SKU count = 1 per design/color).
  * Fast-paced broadcast style: presents 30–60 unique items in a 90-minute livestream.
* **Core Pain Points:**
  * Post-live WhatsApp avalanche: 50+ simultaneous chats asking for the same item.
  * Cross-talk and disputes over who claimed a single-piece dress first.
  * Time-consuming address collection and illegible handwritten courier slips.
  * Unmatched payments: difficulty tracking which UPI screenshot belongs to which parcel.

### 3.3 Secondary Persona: The Social Shopper / Live Viewer
* **Profile:** Mobile-first consumer watching live streams on Facebook; impulse-driven buyer who values personal connection with the boutique host.
* **Key Characteristics:**
  * Browses exclusively on smartphones, often on variable mobile networks (4G/5G).
  * High sensitivity to purchase friction: will immediately abandon a purchase if forced to download an app from Google Play or fill out a multi-step registration form.
  * Prefers interacting directly over WhatsApp for reassurance, custom sizing questions, and payment proof.
* **Core Pain Points:**
  * Inability to describe which exact garment was seen on stream.
  * Missing out on garments because someone else messaged first on WhatsApp while they were still watching the live.
  * Difficulty bundling multiple items across an hour-long stream into a single shipment.

---

## 4. Problem Statement & Root Cause Analysis

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      THE CURRENT MANUAL BOTTLENECK                          │
├───────────────────┬───────────────────────────┬─────────────────────────────┤
│ 1. Stream Chaos   │ 2. Communication Drag     │ 3. Dispatch Nightmare       │
│ • "Comment BOOKED"│ • Unclear screenshots     │ • Manually tallying items   │
│ • Single-piece    │ • 5 buyers want same item │ • Manual address typing     │
│   collisions      │ • Fragmented chats        │ • Handwritten parcel labels │
│ • Missed orders   │ • Manual UPI checking     │ • Courier dispatch delays   │
└───────────────────┴───────────────────────────┴─────────────────────────────┘
```

1. **Item Identification Breakdown:** Garments displayed quickly under studio or ring lights look slightly different in screenshots. Buyers frequently send cropped or blurry frames, leading to wrong items being packaged and shipped.
2. **Single-Piece Concurrency Collisions:** Boutiques rarely carry bulk stock; most sarees or boutique dresses are single pieces. When multiple viewers attempt to claim the same piece, sellers suffer reputational damage when informing buyers that their item was already promised to someone else.
3. **Cart Bundling Friction:** A buyer often wants dress `#04` shown at 8:15 PM and dress `#29` shown at 9:00 PM. In the current workflow, this requires multiple disconnected WhatsApp messages, leading to missed items and split shipments.
4. **Fulfillment & Logistics Inefficiency:** After broadcasting, sellers spend 3 to 5 hours transcribing buyer names, phone numbers, and addresses onto parcel paper, increasing dispatch errors with logistics partners (India Post, DTDC, Delhivery).

---

## 5. Solution Architecture: The Two-Tier Paradigm

LiveDrop decouples the system into two specialized surfaces connected by a unified real-time database:

```
                          ┌───────────────────────────┐
                          │   Supabase Cloud (Postgres│
                          │   Auth, Realtime, Storage)│
                          └─────────────┬─────────────┘
                                        │
                ┌───────────────────────┴───────────────────────┐
                ▼                                               ▼
┌───────────────────────────────┐               ┌───────────────────────────────┐
│     SELLER OPERATIONS APP     │               │      BUYER WEB CATALOG        │
│   (Flutter Native Mobile APK) │               │   (Next.js PWA / Edge Web)    │
├───────────────────────────────┤               ├───────────────────────────────┤
│ • 30-sec photo + code upload  │               │ • Zero-download web link      │
│ • Real-time stock status sync │               │ • Bold flash-code thumbnails  │
│ • Kanban order pipeline       │               │ • Sticky multi-item cart      │
│ • 1-tap 4x6 courier slip PDF  │               │ • Direct WhatsApp deep-link   │
└───────────────────────────────┘               └───────────────────────────────┘
```

### Surface A: The Seller Mobile App (Flutter)
* **Target Environment:** Android smartphone (direct APK install, eliminating Play Store fees).
* **Role:** High-speed inventory intake, real-time broadcast monitoring, payment verification, and dispatch management.
* **Why Native Flutter:** Provides instant hardware camera access, offline-first image caching, native file system integration for generating PDF shipping labels, and real-time push/WebSocket updates.

### Surface B: The Buyer Web Catalog (Next.js / Edge)
* **Target Environment:** Mobile web browser (optimized for Facebook In-App Browser, WhatsApp Webview, Chrome, and Safari).
* **Role:** Product discovery, rapid code search, cart bundling, and structured WhatsApp checkout.
* **Why Edge Web:** Requires zero installation. When the seller drops the link in the pinned Facebook comment, it renders server-side in under 1.5 seconds on mobile data.

---

## 6. Product Lifecycle & Operational Workflow

```
[Pre-Live Ingestion] ──► [Live Broadcast] ──► [Instant Web Cart] ──► [WhatsApp DM] ──► [1-Tap Fulfillment]
  • Snap garment photo     • Pin catalog link   • Buyer picks codes    • Pre-filled text  • Verify UPI
  • Assign code (#A01)     • Display flash code • Enter address        • Send UPI proof   • Print 4x6 label
  • Set price & stock      • Host live drop     • 15-min stock lock    • Direct handshake • Dispatch parcel
```

1. **Pre-Live Ingestion:** 1 hour before the broadcast, seller opens Flutter app, taps "Create New Drop", takes rapid square photos, assigns 2-to-3 character Flash Codes (`#A01`, `#A02`), sets prices, and publishes a drop link: `drop.store/mothers-boutique`.
2. **Live Broadcast & Flash-Code Booking:** Seller pins the link in Facebook Live comments and shows physical flash cards next to each dress. Viewers tap the link directly inside Facebook without installing anything.
3. **Cart Bundling & Stock Hold:** Buyer selects items across the stream, opens the sticky bottom cart bar, enters delivery details (Name, Phone, Pincode, Address), and taps checkout. The backend executes an atomic reservation holding the items for 15 minutes.
4. **WhatsApp Handshake & UPI Payment:** Browser launches WhatsApp with a pre-formatted message listing order reference, items, subtotal, shipping, and delivery address. Buyer attaches UPI payment screenshot directly in WhatsApp.
5. **One-Tap Billing & Dispatch:** Seller verifies payment against bank app, taps "Mark as Paid" on the Kanban board (marking items permanently Sold Out), taps "Generate Shipping Slip" to render a standard 4×6 inch thermal PDF label, prints via Bluetooth thermal printer, and enters tracking number on dispatch.

---

## 7. Success Metrics & KPIs

| Metric Category | Key Performance Indicator | MVP Target | Measurement Tool |
|---|---|---|---|
| **Buyer Friction** | Time from link tap to WhatsApp launch | < 45 seconds | Client analytics timer |
| **Ingestion Velocity**| Time to photograph, code, price & upload item | < 30 seconds per garment | Stopwatch test on device |
| **Inventory Integrity**| Double-sold single-piece collision rate | **0.00%** | Database conflict logs |
| **Fulfillment Time**| Post-live packaging & labeling time for 30 orders | < 20 minutes (vs 3+ hours) | Time-motion study |
| **Operating Cost** | Infrastructure & SaaS cost at MVP scale | **₹0.00** | Monthly billing audit |
