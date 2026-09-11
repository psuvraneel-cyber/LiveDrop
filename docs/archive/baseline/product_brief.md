# Product Brief: LiveDrop
## Next-Generation Live-Commerce & Order Dispatch System for Social Boutique Sellers

---

### Executive Summary

**LiveDrop** is a specialized, zero-overhead live-commerce and fulfillment management platform purpose-built for independent home boutique sellers operating via Facebook Live and WhatsApp. By pairing a high-speed, native **Seller Operations Mobile App** with an ultra-lightweight, zero-download **Buyer Web Catalog**, LiveDrop eliminates the operational chaos of comment-based selling, inventory misallocation, manual payment tracking, and handwritten shipping slips.

Built with modern full-stack technologies (Flutter, Next.js, Supabase) and architected to run permanently within cloud free tiers (₹0 operating overhead), LiveDrop bridges the critical gap between chaotic informal social selling and cumbersome enterprise e-commerce platforms.

---

### 1. Vision & Core Value Proposition

* **Vision:** Empower independent social boutique entrepreneurs to professionalize and scale their live-stream sales without changing how their buyers love to shop.
* **Core Value Proposition:**
  * **For Sellers:** Cuts post-broadcast administrative drag by 80%—from hours spent deciphering screenshots and handwriting courier slips down to minutes of one-tap order verification and automated label generation.
  * **For Buyers:** Zero friction. No app downloads, no account registrations, and no passwords. Buyers browse clear flash codes on a mobile web link, bundle multiple garments into a single cart, and complete checkout directly via their familiar WhatsApp chat.

---

### 2. Market Context & Target Personas

#### 2.1 The Market Reality
Across India and Southeast Asia, thousands of micro-entrepreneurs generate substantial livelihoods through Facebook Live garment selling. Groups like *FASHION SWAP*, *Debikar Sajghor*, and countless regional boutique circles host daily streams where sellers showcase unique, limited-quantity garments (handloom sarees, kurtis, western dresses, jewelry). 

Despite moving millions of rupees in merchandise monthly, these sellers operate on an entirely manual pipeline:
1. Streamers display garments on Facebook Live.
2. Viewers type "booked" in comments or take low-quality screen captures.
3. Viewers reach out to sellers on WhatsApp with vague descriptions (*"the pink saree shown around minute 24"*).
4. Sellers manually verify whether the piece is still available, manually calculate bundle totals, collect UPI payments, and handwrite shipping labels on paper parcels.

#### 2.2 Primary Persona: The Home Boutique Seller
* **Profile:** Independent entrepreneur running a home-based garment boutique; broadcasts 2–5 times weekly on Facebook Live; manages inventory, customer relations, and courier dispatches solo or with family assistance.
* **Key Characteristics:**
  * Highly proficient in WhatsApp, Facebook, and UPI applications, but resistant to complex enterprise software (e.g., Shopify, WooCommerce, ERPs).
  * Manages high inventory turnover with unique, single-piece stock (SKU count = 1 per design/color).
  * Fast-paced broadcast style: presents 30–60 unique items in a 90-minute livestream.
* **Core Pain Points:**
  * Post-live WhatsApp avalanche: 50+ simultaneous chats asking for the same item.
  * Cross-talk and disputes over who claimed a single-piece dress first.
  * Time-consuming address collection and illegible handwritten courier slips.
  * Unmatched payments: difficulty tracking which UPI screenshot belongs to which parcel.

#### 2.3 Secondary Persona: The Social Shopper / Live Viewer
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

### 3. Problem Statement & Root Cause Analysis

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
3. **Cart Bundling Friction:** A buyer often wants dress #04 shown at 8:15 PM and dress #29 shown at 9:00 PM. In the current workflow, this requires multiple disconnected WhatsApp messages, leading to missed items and split shipments.
4. **Fulfillment & Logistics Inefficiency:** After broadcasting, sellers spend 3 to 5 hours transcribing buyer names, phone numbers, and addresses onto parcel paper, increasing dispatch errors with logistics partners (India Post, DTDC, Delhivery).

---

### 4. Solution Architecture: The Two-Tier Paradigm

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

#### Surface A: The Seller Mobile App (Flutter)
* **Target Environment:** Android smartphone (direct APK install, eliminating Play Store fees).
* **Role:** High-speed inventory intake, real-time broadcast monitoring, payment verification, and dispatch management.
* **Why Native Flutter:** Provides instant hardware camera access, offline-first image caching, native file system integration for generating PDF shipping labels, and real-time push/WebSocket updates.

#### Surface B: The Buyer Web Catalog (Next.js / Cloudflare Pages)
* **Target Environment:** Mobile web browser (optimized for Facebook In-App Browser, WhatsApp Webview, Chrome, and Safari).
* **Role:** Product discovery, rapid code search, cart bundling, and structured WhatsApp checkout.
* **Why Edge Web:** Requires zero installation. When the seller drops the link in the pinned Facebook comment, it renders server-side in under 1.5 seconds on mobile data.

---

### 5. Step-by-Step Product Lifecycle & Operational Workflow

```
[Pre-Live Ingestion] ──> [Live Broadcast] ──> [Instant Web Cart] ──> [WhatsApp DM] ──> [1-Tap Fulfillment]
  • Snap garment photo     • Pin catalog link   • Buyer picks codes    • Pre-filled text  • Verify UPI
  • Assign code (#A01)     • Display flash code • Enter address        • Send UPI proof   • Print 4x6 label
  • Set price & stock      • Host live drop     • 15-min stock lock    • Direct handshake • Dispatch parcel
```

#### Step 1: Pre-Live Ingestion (1 Hour Before Broadcast)
1. The seller opens the LiveDrop app on her phone and taps **"Create New Drop"** (e.g., *"Friday Silk Special"*).
2. The app opens an optimized rapid-camera shutter.
3. For each garment:
   * Seller snaps a photo.
   * Assigns a 2-to-3 character Flash Code (e.g., `#A01`, `#A02`, or `#12`).
   * Inputs Price (e.g., `₹1,450`), Size/Fabric (`Free Size / Tussar Silk`), and Quantity (`1`).
4. Seller taps **"Publish Drop"**. The app generates a clean short link: `livedrop.store/mothers-boutique`.

#### Step 2: Live Broadcast & Flash-Code Booking
1. The seller begins her Facebook Live stream and pins the catalog link in the comment section:
   > *"Welcome to today's handloom drop! Browse and lock your pieces here: livedrop.store/mothers-boutique"*
2. The seller displays physical flash cards next to each garment on camera (e.g., holding up a placard with `#A07`).
3. Viewers tap the link directly inside Facebook. The catalog opens instantly without leaving the Facebook app.
4. Each garment displays its bold Flash Code badge, high-resolution thumbnail, price, and real-time stock indicator (`Available` or `Reserved`).

#### Step 3: Cart Bundling & Stock Hold
1. The buyer taps **"Add to Bag"** on `#A07` (Saree) and continues watching.
2. Twenty minutes later, the seller presents a kurti marked `#B02`. The buyer adds `#B02` to the same bag.
3. When ready, the buyer opens the floating bottom cart bar.
4. The buyer enters four essential fields:
   * **Full Name**
   * **WhatsApp Mobile Number**
   * **Delivery Pincode**
   * **Complete Delivery Address (House No, Street, Landmark, City)**
5. Tapping **"Submit Order via WhatsApp"** triggers an optimistic 15-minute stock hold on Supabase to prevent double-booking.

#### Step 4: The WhatsApp Handshake & UPI Payment
1. The browser automatically redirects to WhatsApp with a pre-filled message addressed to the seller's business number:
   ```text
   🌟 NEW ORDER - MOTHER'S BOUTIQUE 🌟
   ---------------------------------
   Order ID: #LD-8942
   Items:
   1. #A07 Handloom Tussar Saree - ₹1,850
   2. #B02 Chanderi Cotton Kurti - ₹750
   ---------------------------------
   Subtotal: ₹2,600
   Shipping: ₹80 (Kolkata Local)
   TOTAL PAYABLE: ₹2,680
   
   📦 Delivery Address:
   Sangeeta Mukherjee
   Flat 4B, Greenview Apartments, Near South City
   Jadavpur, Kolkata - 700032
   Phone: 98301XXXXX
   ---------------------------------
   Please share UPI QR code to complete payment!
   ```
2. The order simultaneously registers on the seller's Flutter app under **"Pending Verification"**.
3. The seller confirms the total and replies with her static UPI QR / VPA, or the buyer scans the static QR displayed on the order confirmation webpage and uploads the transaction screenshot directly into the WhatsApp chat.

#### Step 5: One-Tap Billing & Dispatch Management
1. Once the seller checks her bank app and sees the incoming UPI transfer, she opens the LiveDrop mobile app.
2. She taps the order for Sangeeta Mukherjee and selects **"Mark as Paid"**.
3. The system permanently marks items `#A07` and `#B02` as `Sold Out`.
4. The seller taps **"Generate Shipping Slip"**:
   * The app generates a formatted 4×6 inch PDF shipping label complete with recipient address, sender return address, parcel contents summary, and tracking barcode placeholder.
   * The label can be printed directly via a Bluetooth thermal printer or shared to WhatsApp/printer.
5. Once handed over to the courier (DTDC, India Post, etc.), the seller taps **"Dispatched"** and inputs the tracking number, archiving the order.

---

### 6. Comprehensive Feature Specifications

#### 6.1 Seller Mobile App (Flutter)

| Feature Module | Description & Functional Logic |
|---|---|
| **Rapid Ingestion Camera** | Custom camera view with automatic square cropping, WebP compression, auto-incrementing flash codes (`#01`, `#02`...), and single-field price entry for sub-30-second uploads. |
| **Live Drop Controller** | Toggle catalog visibility: `Draft`, `Active Live Drop`, or `Archived`. Ability to mark items active or hidden on the fly during a broadcast. |
| **Visual Kanban Pipeline** | Intuitive order board divided into three actionable stages:<br>• **Pending:** Awaiting buyer payment screenshot.<br>• **Paid / Ready to Pack:** Payment confirmed; shipping label ready.<br>• **Dispatched:** Package handed to courier; tracking recorded. |
| **One-Tap Packing Slip** | Generates standardized 4×6 inch PDF labels containing buyer address, item codes, seller contact info, and packaging date. |
| **Realtime Push Alerts** | Instant device notifications whenever a buyer submits an order via the web front. |
| **Customer Order History** | Instant search by customer phone number to view past purchase history, preferred delivery addresses, and lifetime value. |

#### 6.2 Buyer Webfront (Next.js / Cloudflare Pages)

| Feature Module | Description & Functional Logic |
|---|---|
| **Edge SSR Catalog** | Pre-rendered, ultra-fast mobile feed. High-contrast flash-code badges on every product tile for immediate visual matching with the livestream. |
| **Zero-Friction Checkout** | No accounts, passwords, or emails. Minimal delivery form: Name, Phone, Address, Pincode. |
| **Floating Cart Bar** | Sticky bottom sheet showing selected garment count, total price, and instantaneous access to review. |
| **Inventory State Badging** | Dynamic product status updates in real-time (`In Stock`, `Reserved`, `Sold Out`) powered by Supabase Realtime subscriptions. |
| **Deep-Link WhatsApp Dispatcher**| Encodes cart contents and shipping details into standard URL parameters for direct handoff to the WhatsApp mobile app. |
| **Static UPI Display** | Displays seller's static UPI QR code and UPI ID on the checkout success screen with an instant "Copy UPI ID" button. |

---

### 7. Technical Architecture & Zero-Cost Cloud Strategy

LiveDrop is engineered to eliminate recurring SaaS fees, cloud infrastructure charges, and payment gateway cuts.

```
┌────────────────────────────────────────────────────────────────────────────┐
│                    ZERO-COST INFRASTRUCTURE STACK                          │
├────────────────────┬─────────────────────────────┬─────────────────────────┤
│ Layer              │ Service / Tool              │ Free Tier Specification │
├────────────────────┼─────────────────────────────┼─────────────────────────┤
│ Frontend Hosting   │ Cloudflare Pages / Vercel   │ Unlimited static edge   │
│                    │                             │ requests, 100 GB bandw. │
│ Backend & Database │ Supabase (PostgreSQL)       │ 500 MB DB storage,      │
│                    │                             │ 50,000 MAUs, Realtime   │
│ Media & Images     │ Cloudinary / Supabase Store │ Auto-WebP compression,  │
│                    │                             │ 25 GB monthly bandwidth │
│ Mobile App Distro  │ Direct Android APK (USB/DL) │ Bypasses $25 Google Play│
│                    │                             │ developer license fee   │
│ Payment Processing │ Direct UPI (P2P / VPA)      │ 0% transaction fees     │
│ Domain             │ Cloudflare / Pages.dev URL  │ ₹0 custom subdomain    │
└────────────────────┴─────────────────────────────┴─────────────────────────┘
```

#### 7.1 Database Schema (High-Level Entities)
* **`sellers`**: Profile, store name, phone number, UPI ID, default return address.
* **`drops`**: Live session event (title, start timestamp, status: `draft`, `live`, `closed`).
* **`products`**: Item code (`#A12`), drop_id, image_url, price, size, status (`available`, `reserved`, `sold`), hold_timestamp.
* **`orders`**: Buyer name, phone, shipping address, pincode, total amount, status (`pending`, `paid`, `shipped`), courier tracking code.
* **`order_items`**: Junction table linking orders to specific product items.

#### 7.2 Concurrency & Single-Piece Stock Protection
To solve the critical single-piece collision problem without a heavy queue server:
1. When a buyer initiates checkout on the web, a Postgres function executes an optimistic reservation:
   ```sql
   UPDATE products 
   SET status = 'reserved', reserved_at = NOW() 
   WHERE id = $product_id AND status = 'available';
   ```
2. If the update affects 0 rows, the client immediately informs the buyer that the item was just claimed by another viewer.
3. A lightweight Supabase Edge Function or cron job releases any `reserved` items whose checkout was not completed within 15 minutes.

---

### 8. Engineering Execution Plan: Antigravity IDE Agentic Workflow

The application will be developed inside the **Antigravity IDE** utilizing a dual-model agentic development framework:

```
┌───────────────────────────────────────────────────────────────────────────┐
│                      AGENTIC COLLABORATION MODEL                          │
│                                                                           │
│   ┌────────────────────────────────┐    ┌─────────────────────────────┐   │
│   │   Gemini 3.8 Flash (High)      │    │    Claude Opus 4.6          │   │
│   │   "The Lead Builder"           │    │    "The Chief Architect"    │   │
│   ├────────────────────────────────┤    ├─────────────────────────────┤   │
│   │ • Full-stack code generation   │    │ • Schema & security audits  │   │
│   │ • Flutter UI & Next.js routes  │───>│ • Concurrency validation    │   │
│   │ • Terminal execution & builds  │    │ • RLS & edge-case review    │   │
│   │ • Rapid bug fixing & iteration │    │ • Architecture sanity checks│   │
│   └────────────────────────────────┘    └─────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────────────┘
```

* **Gemini 3.8 Flash (High):** Primary implementation workhorse. Handles rapid workspace generation, iterative terminal compilation (`flutter run`, `npm run dev`), state management wiring, and UI layout creation.
* **Claude Opus 4.6:** Strategic auditor. Periodically reviews database migration scripts, Row-Level Security (RLS) policies, inventory locking functions, and deep-link encoding logic to ensure bulletproof reliability.

---

### 9. Success Metrics & Phased Roadmap

#### Phase 1: MVP Validation ("User Zero" Drop) — Weeks 1–2
* Build lightweight Next.js web catalog linked to Supabase.
* Manually ingest 25 garments for the seller's next Facebook Live broadcast.
* Track buyer checkout completion and measure seller feedback.
* **Target Metric:** 100% elimination of ambiguous garment screenshots from buyers who use the link.

#### Phase 2: Native Seller Operations App — Weeks 3–4
* Implement Flutter APK with rapid camera intake and item code generator.
* Build the Visual Kanban pipeline (Pending -> Paid -> Dispatched).
* Integrate 4×6 inch PDF courier packing slip generation.
* **Target Metric:** Reduce post-live packing and addressing time from 3 hours to under 30 minutes.

#### Phase 3: Multi-Boutique Expansion — Month 2+
* Support multiple boutique accounts with independent subdomains.
* Introduce automated buyer SMS/WhatsApp notifications with courier tracking links.
* Provide analytics dashboard (best-selling price brackets, top repeat buyers, drop revenue).

---

### 10. Conclusion

LiveDrop transforms informal, chaotic social selling into a streamlined, high-speed retail operation. By respecting the natural habits of both boutique owners (speed, camera-first, WhatsApp-centric) and livestream shoppers (zero-friction, instant mobile browsing), LiveDrop delivers an enterprise-grade experience at absolute zero infrastructure cost.
