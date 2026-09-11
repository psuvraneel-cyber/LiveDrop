9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

# **Building an App for Facebook Live Sellers** 

https://gemini.google.com/app/c248dc596c1aecf0 

_User prompt: Hey, so you know that I am a BCA honors student, and I am in my 4th year of college. My mother is a businesswoman, and she has been in the garment-selling business for almost 8-9 years. During the pandemic, my mother started selling clothes using Facebook Live. There is a whole community of groups that are essentially made for small-time sellers who do not have their own shops or run their business from their homes. You should check out some of the groups like_ 🛍🛒 _FASHION SWAP_ 🛒⬆ _, Debikar Sajghor, etc. So these groups host sellers who sell garments and other cloth-related or boutique items on Facebook. The sellers post their contact info, and buyers contact them via WhatsApp, and the sale continues from there. Now, I recently realized while observing my mother that when doing this kind of business, keeping track of your customers and who ordered which dress can be a massive headache, especially customers who buy a bunch of products at once. Most of them don't even send photos or screenshots of which dress they want. So, as you know, I am something of a budding developer, and I wanted to help my mother. I thought about it a lot, and I had an idea. What if I build an app where a seller can post their collection of garments with their price, size, and other details? Also, there should be a billing system in the app to handle all the purchases. Now, I don't want to turn this app into an online shopping store. There wouldn't be any real transaction. For example, a person selects three dresses from the app from my mother's collection and then clicks on buy. This sends the seller with the buyer's relevant details, like their exact address for delivery, their contact info, and exactly which dress they want to buy. This is just in the brainstorming session of the idea. Tell me if you think this idea is viable and if I am missing any features or ideas that I should add or anything else in general that you think I should know. According to my mother, there are approximately thousands of online garment sellers on Facebook. This could be a massive opportunity, or it could be a dumb idea. Tell me which it is. Is there any scope for this app?_ 

Response: This is a genuinely viable problem to solve, not a dumb idea at all, but its success hinges entirely on one crucial architectural choice: 

#### **buyers will almost certainly refuse to download an app just to place an order.** 

Home boutique sellers rely on spontaneous, low-friction buying. If a customer watching a Facebook Live has to leave Facebook, go to the Play Store, install an app, create an account, and find the item, drop-off will be massive. 

#### The high-potential version of your idea is a **Seller-side Mobile App + Buyer-facing Web Catalog (PWA/Link)** . 

#### **The Core Pivot: How It Should Flow** 

- **For the Seller:** A dedicated app where your mother can quickly photograph inventory, set prices/sizes/quantities, track orders, and generate bills. 

- **For the Buyer:** A lightweight web link (e.g., `[motherstore.com/live-collection](https://motherstore.com/live-collection)` or a temporary live drop link) that opens directly inside Facebook's browser or WhatsApp. No download, no registration—just select items, enter phone/address, and confirm. 

**The Checkout Action:** When the buyer hits "Submit Order", it formats a clean, pre-filled WhatsApp message sent straight to the seller's chat with the order summary, exact product thumbnails, and delivery address. 

#### **Key Features to Solve Real Live-Selling Headaches** 

**Item Codes / SKU Flash Tags:** During a Live, sellers usually say, _"Look at code 12, take a screenshot!"_ If your app lets sellers tag items with simple 2-digit numbers or quick codes, buyers can find and cart them on the link in seconds. 

- **Single-Piece "Hold" or Stock Lock:** Boutique sellers often have only one piece of a specific saree or dress. You need an automated temporary stock reservation (e.g., "Reserved for 15 minutes while payment is verified") to prevent multiple buyers fighting over the same dress. 

- **One-Click Courier Slip & Invoice Generator:** Once your mother confirms payment over UPI, the app should instantly generate a printable or shareable shipping label (Buyer Name, Phone, Address, Weight/Items) formatted for standard local couriers like DTDC, Delhivery, or India Post. 

- **Integrated UPI QR on Confirmation:** Even without an expensive payment gateway (like Razorpay), your web checkout page can display your mother’s static UPI QR code with the total cart amount pre-calculated, prompting the buyer: _"Scan, pay, and attach screenshot on WhatsApp."_ 

#### **Market Scope & Competition** 

Platforms like Dukaan, Bikayi, and TakeApp attempted generic "WhatsApp store" builders, but most pivoted to standard e-commerce SaaS or died down because they didn't cater to the specific chaos of **Live stream selling** . 

The scope in India is massive—tier-2/3 cities and regional Facebook communities move crores worth of garments weekly via informal DMs. If you tailor the workflow specifically around how Facebook Live sessions operate (fast drops, code booking, bundle shipping, single-piece stock), there is a distinct, uncrowded niche. 

How does your mother currently handle the post-Live scramble—does she review comments during the video, or does she spend hours sorting through WhatsApp chats afterward? Knowing this will pinpoint the exact bottleneck to tackle first in your MVP. 

_User prompt: How should I go about this? Will it be like an app for the selller and a website for the buyers?_ 

Response: Yes, exactly. A **mobile app for the seller** paired with a **lightweight, mobile-first web catalog for buyers** is the standard architecture for this model. 

Buyers will not install an app from a live stream, but your mother needs a native phone app for rapid camera access, push notifications, and quick billing on the move. 

#### **The Architecture Split** 

#### **Seller App (Android / iOS):** 

**Role:** Inventory management, live catalog toggles, order tracking, and invoice creation. 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

1/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

**Why native app:** Your mother needs to quickly take photos of dresses before a Live, receive instant notifications when an order lands, and generate PDF shipping slips with one tap. 

#### **Buyer Catalog (Mobile Web / PWA):** 

**Role:** Browsing inventory, cart selection, and checkout form. 

- **Why web link:** It opens instantly inside Facebook’s in-app browser or WhatsApp without leaving the app or requiring account creation. 

#### **Backend & Database:** 

Handles real-time inventory counts (to prevent overselling), order records, and image hosting. 

#### **The 5-Step Operational Flow** 

1. **Catalog Setup:** The seller snaps photos of 20 dresses, assigns a quick code (e.g., `#A12` , `#B04` ), sets the price and stock (often `stock = 1` ), and hits publish. 

2. **The Drop Link:** The seller pins a single short link in the Facebook Live comments (e.g., `[appname.com/store/mothers-boutique] (https://appname.com/store/mothers-boutique)` ). 

3. **Cart & Hold:** A buyer taps the link, picks `#A12` and `#B04` , enters their name, phone, and delivery address, and taps "Place Order". 

4. **WhatsApp Handshake:** The web checkout triggers a direct WhatsApp deep link ( `[https://wa.me/91XXXXXXXXXX?text=] (https://wa.me/91XXXXXXXXXX?text=)...` ) to your mother’s number with a pre-filled message: 

_"Hi! I'd like to order: \n- #A12 Red Saree (₹1,200)\n- #B04 Kurti (₹850)\nTotal: ₹2,050\nDeliver to: Priya Sharma, Salt Lake, Kolkata, 700064"_ 

5. **Billing & Confirmation:** The order registers as "Pending Payment" in the seller app. Once your mother verifies the UPI payment screenshot on WhatsApp, she marks it "Paid", which auto-generates a clean PDF invoice and courier shipping label. 

#### **Recommended Tech Stack for Fast Execution** 

**Seller App: Flutter** (single codebase for Android/iOS, fast camera integration, smooth UI) or **React Native** . 

**Buyer Webfront: Next.js** or **React** hosted on Vercel. Keep bundle sizes minimal so it loads in under 2 seconds on mobile data. 

- **Backend & Database: Supabase** (PostgreSQL + built-in Auth, real-time subscriptions, and fast S3-compatible image storage) or **Firebase** . This saves you from writing repetitive CRUD boilerplate so you can focus on the UI. 

#### **How to Build It: The 3-Stage Roadmap** 

- **Week 1 (Validate with "User Zero"):** Build just the buyer web catalog first. Hardcode your mother's current collection with photos, codes, and the WhatsApp direct-message checkout button. Have her pin it during her very next Facebook Live to see if her buyers actually use it. 

- **Week 2 (Build the Seller Admin):** Once you prove buyers will click the link, build the seller dashboard to let your mother add products, upload photos from her phone, and change stock statuses without your manual intervention. 

- **Week 3 (Automate Dispatch):** Add the courier label generator and PDF bill creator so she can pack orders in minutes instead of manually writing addresses on paper packages. 

_User prompt: One thing I want to mention is to make sure that the app and website look impressive, but they must be simple enough for people to instantly understand what is what and how to go about it. Another thing is that I want to keep the cost to a minimum as low as you can make it. Make it free if you can. Also which tech stack is the better choice according to you? Compare them with advantages and disadvantages._ 

Response: You can build and deploy this entire system for **₹0** using modern cloud free tiers. The key to keeping it free while delivering an impressive, high-speed experience is selecting tools that don’t charge for server uptime or database reads at low-to-medium scale. 

### **The $0 Cost Architecture Blueprint** 

Every component runs indefinitely on standard developer free tiers: 

|**Layer**|**Recommended Tool**|**Free Tier Limits**|**Cost**|
|---|---|---|---|
|**Buyer Web**<br>**Catalog**|**Cloudflare Pages**or**Vercel**|Unlimited static requests, 100 GB<br>bandwidth/month|**₹0**|
|**Database & API**|**Supabase**(PostgreSQL)|500 MB database, 50,000 monthly active<br>users, instant REST/Realtime APIs|**₹0**|
|**Image Storage**|**Cloudinary**or**Supabase Storage**|Cloudinary: 25 GB monthly credits with auto-<br>compression & WebP conversion|**₹0**|
|**Seller App**<br>**Distribution**|**Direct Android APK**or**PWA**|Install directly onto your mother's phone via<br>APK or "Add to Home Screen"|**₹0**(bypasses the $25<br>Google Play fee)|
|**Domain**|Subdomain (`boutique.pages.dev`or<br>`boutique.vercel.app`)|Included with hosting (custom`.in`domain<br>optional later for ~₹400/yr)|**₹0**|



https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

2/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

### **Tech Stack Comparison** 

The core architectural decision is whether to maintain two separate codebases or run a unified web-first system. 

|**Criteria**|Option 1: Flutter (App) +<br>Next.js (Web)|Option 2: Full-Stack Next.js PWA (All<br>Web)|Option 3: React Native /<br>Expo + React|
|---|---|---|---|
|**Core Idea**|Native mobile app for seller;<br>Next.js for buyer link|One responsive Next.js web app serving both<br>seller dashboard and buyer store|Expo mobile app for seller;<br>React web for buyer|
|**Codebases**|2 (Dart + TypeScript/JavaScript)|1 (TypeScript/JavaScript across the board)|2 (Shared React ecosystem)|
|**Camera &**<br>**Hardware**|High native performance, instant<br>camera trigger|Good on mobile browsers, but feels slightly less<br>native|High native performance via<br>Expo camera plugins|
|**Development**<br>**Speed**|Moderate (need to build UI twice)|Fastest (build once, use responsive layouts)|Moderate|
|**Zero-Cost**<br>**Feasibility**|Easy (Build direct`.apk`locally)|Easiest (Single deployment on Vercel/Cloudflare)|Easy (Export APK via EAS<br>local build)|



#### **The Verdict: Option 1 (Flutter + Next.js + Supabase)** 

- **Why Flutter for the Seller App:** Home boutique sellers need rapid camera snaps, instant image cropping, and local file sharing (generating a shipping label PDF and sending it straight to WhatsApp/printer). Flutter excels at native hardware access and snappy UI animations. You can build the `.apk` release locally in VS Code and install it directly on your mother's phone with zero Google Play Store fees. 

- **Why Next.js for the Buyer Catalog:** It generates server-rendered, lightweight HTML. When a buyer clicks the Facebook link, the page loads in under 1.5 seconds even on 3G/4G networks, with proper OpenGraph preview cards (showing your mother's store logo and banner directly inside Facebook). 

- **Why Supabase as the Glue:** You get a full relational PostgreSQL database, authentication, file storage, and real-time websockets out of the box. When a buyer submits an order on the website, Supabase pushes the event instantly to the Flutter app without you needing to build or host a custom WebSocket server. 

### **UX Blueprint: High Impact with Zero Learning Curve** 

To make the platform intuitive for non-tech-savvy users while looking modern: 

#### **For the Buyer (Frictionless Web Catalog)** 

- **Big Product Tiles with Clear Item Codes:** Prominently display a bold code tag (e.g., `#A1` , `#A2` ) over each photo so buyers immediately recognize the item they just saw on Facebook Live. 

- **No Account Creation / No Passwords:** Never ask buyers to register. A checkout form needs only four fields: Full Name, WhatsApp Number, Pincode, and Delivery Address. 

- **Floating Cart Bar:** Borrow UI conventions from apps like Swiggy or Zomato—a sticky bottom bar showing `"2 Items Selected • ₹2,100 — Review Order"` with a prominent green action button. 

**Direct WhatsApp Checkout:** The final button launches WhatsApp with a pre-formatted message listing item codes, total price, and address so your mother receives clean, verifiable text. 

#### **For the Seller (Streamlined Mobile App)** 

- **30-Second Item Upload:** A dedicated "Add Item" screen: tap camera, snap dress photo, type a 2-character code ( `#01` ), enter price, and tap "Live". No mandatory descriptions or complex category dropdowns. 

**Visual Kanban Order Board:** Three simple columns: _Pending Payment_ , _Paid (Ready to Pack)_ , and _Dispatched_ . 

- **One-Tap Packing Slip:** A button on each paid order that formats the customer's name, phone, and address into a clean printable 4×6 inch slip or shareable image to stick onto courier parcels. 

_User prompt: Now before we go any further, I need to tell you that I want to make both the app and the website in the Antigravity IDE using Gemini 3.8 Flash(High) with occasional use of Claude Opus 4.6 for reviewing the code. Is this viable?_ 

Response: This setup is an exceptionally practical and cost-effective agentic development workflow. Pairing a high-speed, low-cost "workhorse" agent with a frontier reasoning model for auditing is the industry-standard design pattern for solo developers building multi-platform apps. 

### **Why This Division of Labor Works** 

#### **Gemini 3.8 Flash (High) as the Builder:** 

- **Native IDE Integration:** In Antigravity IDE, 3.8 Flash operates directly inside the agent loop—it reads workspace context, executes terminal commands ( `flutter run` , `npm run dev` ), analyzes compiler errors, and performs multi-file edits autonomously. 

- **Speed and Cost:** The "High" reasoning setting gives you deep software-engineering problem-solving (scoring ~74% on DeepSWE) without the latency drag or steep pricing of frontier models, preserving your development momentum. 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

3/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

**Full-Stack Competency:** It handles both Dart/Flutter and TypeScript/Next.js seamlessly, along with writing PostgreSQL SQL migrations for Supabase. 

#### **Claude Opus 4.6 as the Architect & Auditor:** 

**Catching Blind Spots:** Fast models occasionally create subtle logic leaks—such as unhandled edge cases in inventory reservation, loose Supabase Row-Level Security (RLS) policies, or unescaped URL strings in WhatsApp deep links. 

**System Review:** Opus 4.6 excels at deep static analysis, spotting concurrency race conditions (e.g., two buyers claiming the last saree simultaneously), and simplifying messy component trees. 

### **Recommended Project Structure in Antigravity IDE** 

Configure Antigravity to manage both codebases under a single root project so the agent understands the shared data contracts: 

#### `boutique-platform/` 

```
├── .antigravity/            # Agent planning docs (task.md, implementation_plan.md)
├── supabase/                # Migrations, seed data, and RLS policies
```

```
│   └── migrations/
```

```
├── buyer-web/               # Next.js / Cloudflare Pages project
```

- `│   ├── src/app/` 

```
│   └── package.json
└── seller-app/              # Flutter mobile application
   ├── lib/
   └── pubspec.yaml
```

### **Best Practices to Maximize This Setup** 

- **Leverage Antigravity's Task Planning:** Before writing code, prompt Gemini 3.8 Flash to generate an `implementation_plan.md` and `task.md` inside the `.antigravity/` workspace. Force it to work feature-by-feature (e.g., "Implement Supabase schema first," then "Build Next.js cart bar") rather than generating everything in one shot. 

**Run Autonomous Terminal Verification:** Grant Antigravity permission to execute `flutter analyze` and `npm run build` . When builds fail, 3.8 Flash can read the terminal output directly and patch syntax or dependency errors without your manual intervention. 

- **How to Prompt Claude Opus 4.6 for Reviews:** Don't feed Opus generic "review my code" prompts. Export specific critical files and give it targeted constraints: 

_"Review this Supabase schema and Next.js checkout route. Audit specifically for: (1) Race conditions during single-item stock reservation, (2) RLS bypass vulnerabilities, and (3) Mobile browser URL encoding failures in the WhatsApp deep link."_ 

#### **Sources** 

1. Gemini 3.8 Flash Review: Accuracy, Price & Is It Worth It? (2026) 

2. Introducing Claude Opus 4.6 - Anthropic 

3. Getting Started with Antigravity 2.0 - Medium 

_User prompt: Firstly, generate a detailed product brief explaining the product and it's uses._ 

## **Response: Product Brief: LiveDrop (Live-Commerce & Order Dispatch System)** 

LiveDrop is a lightweight, zero-overhead commerce platform designed specifically for home-based garment sellers operating via Facebook Live and WhatsApp. It bridges the gap between chaotic comment-based sales and complex e-commerce stores by combining a **native mobile app for sellers** with an **instant, zero-download web catalog for buyers** . 

### **Problem Statement** 

Home boutique sellers on Facebook Live face systemic operational bottlenecks: 

- **Identification Chaos:** Buyers comment "booked" or send WhatsApp messages with vague descriptions like _"the red saree you showed after the blue one,"_ leading to cross-talk, miscommunication, and lost sales. 

- **Single-Piece Stock Collisions:** Boutiques often stock only one or two pieces per design. Without real-time reservations, multiple buyers attempt to purchase the same garment. 

- **Buyer Drop-Off:** Traditional e-commerce setups fail because impulse buyers watching a livestream will abandon the purchase if forced to download an app or register an account. 

**Manual Fulfillment Drag:** Sellers spend hours after every broadcast manually matching UPI payments to screenshot DMs, transcribing customer addresses by hand onto paper, and handwriting courier parcel slips. 

### **Target Personas** 

|**Persona**|**Environment**|**Primary Needs**|
|---|---|---|
|**The Boutique Seller**(e.g.,<br>Home Business Owner)|Android Smartphone|Rapid pre-live product uploads, instant stock toggles, clear order status<br>tracking, and one-tap shipping slip generation.|



https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

4/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

|**Persona**|**Environment**|**Primary Needs**|
|---|---|---|
|**The Social Buyer**(e.g.,|Mobile Browser (via|Instant catalog access without login, clear item identification codes,|
|Facebook Live Viewer)|Facebook/WhatsApp)|seamless multi-item bundling, and familiar WhatsApp checkout.|



### **Product Architecture & Core Touchpoints** 

```
[Seller: Flutter Mobile App] ──> [Supabase Backend / DB] <── [Buyer: Next.js Webfront]
             │                                                        │
             ▼                                                        ▼
     Kanban Order Board &                                   Select Items & Checkout
   One-Tap Courier Label PDF                                via WhatsApp Deep-Link
```

#### **1. Buyer Web Catalog (Next.js / Cloudflare Pages)** 

- **Zero-Friction Access:** Runs directly inside the Facebook in-app browser or via a shared WhatsApp link. No account creation, passwords, or app installation required. 

- **Flash-Code Identification:** Every garment is prominently tagged with a bold, two-to-three character identifier (e.g., `#A12` , `#B04` ) matching what the seller displays on camera. 

- **Sticky Bundle Cart:** A mobile-optimized floating cart bar allowing buyers to bundle multiple dresses from a single live session into one shipment. 

**WhatsApp Deep-Link Checkout:** Submitting the cart captures the buyer’s delivery details (Name, Phone, Delivery Address, Pincode) and routes them directly to the seller's WhatsApp with a clean, pre-formatted order summary. 

#### **2. Seller Operations App (Flutter Android APK)** 

**Rapid Catalog Ingestion:** A streamlined camera workflow to photograph a garment, assign a flash code, input price/size/stock, and publish in under 30 seconds. 

- **Real-Time Stock Lock:** Automatically marks single-piece inventory as "Reserved" once a buyer initiates checkout, preventing doublebooking. 

**Visual Kanban Board:** Tracks orders through three simple states: 

1. _Pending Payment_ (Awaiting UPI verification). 

2. _Paid / To Pack_ (Verified, ready for parceling). 

3. _Dispatched_ (Courier tracking added, archived). 

**Automated Dispatch Engine:** Generates standardized, printable 4×6 inch thermal or paper shipping labels (including recipient address, seller return info, item breakdown, and contact details) with a single tap. 

### **Primary Uses & Operational Lifecycle** 

#### **Phase 1: Pre-Live Ingestion (1-2 Hours Before Broadcast)** 

1. The seller opens the Flutter app and taps **New Drop** . 

2. She photographs 25 unique dresses directly from the camera interface. 

3. For each item, she enters an item code (e.g., `#01` to `#25` ), sets price (e.g., `₹1,250` ), size (e.g., `Free Size` ), and sets inventory count (typically `1` ). 

4. She taps **Go Live Mode** , which generates a short catalog URL (e.g., `drop.store/mother-boutique` ). 

#### **Phase 2: During the Live Broadcast** 

1. The seller pins the catalog link in the pinned comment of the Facebook Live stream. 

2. While showing a dress on camera, she displays a small physical card with `#08` and states: _"This is code #08, tap the link in the comments to grab it."_ 

3. A viewer taps the link, opens the web catalog, sees dress `#08` at the top of the feed, taps **Add to Bag** , selects an additional scarf `#14` , and proceeds to checkout. 

4. The buyer inputs her shipping details and taps **Confirm on WhatsApp** . The web client reserves codes `#08` and `#14` for 15 minutes. 

#### **Phase 3: Post-Live Verification & Fulfillment** 

1. The seller receives a pre-formatted WhatsApp DM from the buyer: 

```
*NEW ORDER - LIVE DROP*
```

```
Items:
```

```
- #08 Handloom Silk Saree (₹1,800)
- #14 Cotton Dupatta (₹450)
Total: ₹2,250
```

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

5/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

```
Delivery Details:
Name: Sangeeta Das
Phone: 98300XXXXX
```

```
Address: 42/B, Lake Gardens, Ground Floor, Kolkata - 700045
```

2. The buyer sends their UPI payment screenshot in the same WhatsApp thread. 

3. The seller opens the Flutter app, locates Sangeeta Das under **Pending** , and taps **Mark as Paid** . 

4. The app changes the order state to **Ready to Pack** and instantly generates a standardized courier packing slip PDF, ready to be printed or attached to the package. 

### **Technical & Cost Feasibility Profile** 

|**Attribute**|**Specification**|**Cost Implication**|
|---|---|---|
|**Hosting (Webfront)**|Cloudflare Pages / Vercel (Edge-rendered Next.js)|**₹0**(Zero cost under free tier bandwidth limits)|
|**Backend & Realtime**|Supabase (PostgreSQL, Auth, Realtime WebSockets)|**₹0**(Free tier covers 500 MB DB & 50k MAUs)|
|**Asset Storage**|Cloudinary / Supabase Storage|**₹0**(Generous free tier with automated image compression)|
|**App Distribution**|Standalone Android APK (Direct USB / Drive install)|**₹0**(Bypasses Google Play Console $25 registration fee)|
|**Payment Layer**|Direct UPI Deep-Link / Static QR Display|**₹0**(Zero payment gateway integration or transaction fees)|



_User prompt: Firstly, generate a detailed product brief.md document file explaining the product and it's uses._ 

Response: ┌─────────────────────────────────────────────────────────────────────────────┐ │ THE CURRENT MANUAL BOTTLENECK │ 

├───────────────────┬───────────────────────────┬─────────────────────────────┤ │ 1. Stream Chaos │ 2. Communication Drag │ 3. Dispatch Nightmare │ │ • "Comment BOOKED"│ • Unclear screenshots │ • Manually tallying items │ │ • Single-piece │ • 5 buyers want same item │ • Manual address typing │ │ collisions │ • Fragmented chats │ • Handwritten parcel labels │ │ • Missed orders │ • Manual UPI checking │ • Courier dispatch delays │ └───────────────────┴───────────────────────────┴─────────────────────────────┘ 

```
1. **Item Identification Breakdown:** Garments displayed quickly under studio or ring lights look slightly different
```

```
2. **Single-Piece Concurrency Collisions:** Boutiques rarely carry bulk stock; most sarees or boutique dresses are s
```

`3. **Cart Bundling Friction:** A buyer often wants dress #04 shown at 8:15 PM and dress #29 shown at 9:00 PM. In the 4. **Fulfillment & Logistics Inefficiency:** After broadcasting, sellers spend 3 to 5 hours transcribing buyer names` 

```
---
```

```
### 4. Solution Architecture: The Two-Tier Paradigm
```

```
LiveDrop decouples the system into two specialized surfaces connected by a unified real-time database:
```

```
                     ┌───────────────────────────┐
                     │   Supabase Cloud (Postgres│
                     │   Auth, Realtime, Storage)│
                     └─────────────┬─────────────┘
                                   │
           ┌───────────────────────┴───────────────────────┐
```

```
           ▼                                               ▼
```

┌───────────────────────────────┐ ┌───────────────────────────────┐ │ SELLER OPERATIONS APP │ │ BUYER WEB CATALOG │ │ (Flutter Native Mobile APK) │ │ (Next.js PWA / Edge Web) │ ├───────────────────────────────┤ ├───────────────────────────────┤ │ • 30-sec photo + code upload │ │ • Zero-download web link │ │ • Real-time stock status sync │ │ • Bold flash-code thumbnails │ │ • Kanban order pipeline │ │ • Sticky multi-item cart │ │ • 1-tap 4x6 courier slip PDF │ │ • Direct WhatsApp deep-link │ └───────────────────────────────┘ └───────────────────────────────┘ 

```
#### Surface A: The Seller Mobile App (Flutter)
```

```
* **Target Environment:** Android smartphone (direct APK install, eliminating Play Store fees).
```

```
* **Role:** High-speed inventory intake, real-time broadcast monitoring, payment verification, and dispatch manageme
* **Why Native Flutter:** Provides instant hardware camera access, offline-first image caching, native file system i
```

```
#### Surface B: The Buyer Web Catalog (Next.js / Cloudflare Pages)
```

```
* **Target Environment:** Mobile web browser (optimized for Facebook In-App Browser, WhatsApp Webview, Chrome, and S
```

```
* **Role:** Product discovery, rapid code search, cart bundling, and structured WhatsApp checkout.
```

```
* **Why Edge Web:** Requires zero installation. When the seller drops the link in the pinned Facebook comment, it re
```

```
---
```

```
### 5. Step-by-Step Product Lifecycle & Operational Workflow
```

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

6/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

[Pre-Live Ingestion] ──> [Live Broadcast] ──> [Instant Web Cart] ──> [WhatsApp DM] ──> [1-Tap Fulfillment] • Snap garment photo • Pin catalog link • Buyer picks codes • Pre-filled text • Verify UPI • Assign code (#A01) • Display flash code • Enter address • Send UPI proof • Print 4x6 label • Set price & stock • Host live drop • 15-min stock lock • Direct handshake • Dispatch parcel 

```
#### Step 1: Pre-Live Ingestion (1 Hour Before Broadcast)
```

`1. The seller opens the LiveDrop app on her phone and taps **"Create New Drop"** (e.g., *"Friday Silk Special"*).` 

`2. The app opens an optimized rapid-camera shutter.` 

`3. For each garment:` 

```
  * Seller snaps a photo.
```

```
  * Assigns a 2-to-3 character Flash Code (e.g., `#A01`, `#A02`, or `#12`).
```

```
  * Inputs Price (e.g., `₹1,450`), Size/Fabric (`Free Size / Tussar Silk`), and Quantity (`1`).
```

`4. Seller taps **"Publish Drop"**. The app generates a clean short link: `livedrop.store/mothers-boutique`.` 

```
#### Step 2: Live Broadcast & Flash-Code Booking
```

`1. The seller begins her Facebook Live stream and pins the catalog link in the comment section:` 

```
  > *"Welcome to today's handloom drop! Browse and lock your pieces here: livedrop.store/mothers-boutique"*
```

`2. The seller displays physical flash cards next to each garment on camera (e.g., holding up a placard with `#A07`).` 

`3. Viewers tap the link directly inside Facebook. The catalog opens instantly without leaving the Facebook app.` 

`4. Each garment displays its bold Flash Code badge, high-resolution thumbnail, price, and real-time stock indicator` 

```
#### Step 3: Cart Bundling & Stock Hold
```

`1. The buyer taps **"Add to Bag"** on `#A07` (Saree) and continues watching.` 

`2. Twenty minutes later, the seller presents a kurti marked `#B02`. The buyer adds `#B02` to the same bag.` 

`3. When ready, the buyer opens the floating bottom cart bar.` 

```
4. The buyer enters four essential fields:
  * **Full Name**
  * **WhatsApp Mobile Number**
  * **Delivery Pincode**
  * **Complete Delivery Address (House No, Street, Landmark, City)**
```

`5. Tapping **"Submit Order via WhatsApp"** triggers an optimistic 15-minute stock hold on Supabase to prevent double` 

```
#### Step 4: The WhatsApp Handshake & UPI Payment
```

`1. The browser automatically redirects to WhatsApp with a pre-filled message addressed to the seller's business numb ```text` 

- 🌟 `NEW ORDER - MOTHER'S BOUTIQUE` 🌟 

```
  ---------------------------------
  Order ID: #LD-8942
  Items:
```

`1. #A07 Handloom Tussar Saree - ₹1,850` 

`2. #B02 Chanderi Cotton Kurti - ₹750` 

```
  ---------------------------------
  Subtotal: ₹2,600
  Shipping: ₹80 (Kolkata Local)
  TOTAL PAYABLE: ₹2,680
```

📦 `Delivery Address: Sangeeta Mukherjee Flat 4B, Greenview Apartments, Near South City Jadavpur, Kolkata - 700032 Phone: 98301XXXXX --------------------------------Please share UPI QR code to complete payment!` 

2. The order simultaneously registers on the seller's Flutter app under **"Pending Verification"** . 

3. The seller confirms the total and replies with her static UPI QR / VPA, or the buyer scans the static QR displayed on the order confirmation webpage and uploads the transaction screenshot directly into the WhatsApp chat. 

#### **Step 5: One-Tap Billing & Dispatch Management** 

1. Once the seller checks her bank app and sees the incoming UPI transfer, she opens the LiveDrop mobile app. 

2. She taps the order for Sangeeta Mukherjee and selects **"Mark as Paid"** . 

3. The system permanently marks items `#A07` and `#B02` as `Sold Out` . 

#### 4. The seller taps **"Generate Shipping Slip"** : 

The app generates a formatted 4×6 inch PDF shipping label complete with recipient address, sender return address, parcel contents summary, and tracking barcode placeholder. 

The label can be printed directly via a Bluetooth thermal printer or shared to WhatsApp/printer. 

5. Once handed over to the courier (DTDC, India Post, etc.), the seller taps **"Dispatched"** and inputs the tracking number, archiving the order. 

### **6. Comprehensive Feature Specifications** 

#### **6.1 Seller Mobile App (Flutter)** 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

7/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

|**Feature Module**|**Description & Functional Logic**|
|---|---|
|**Rapid Ingestion**<br>**Camera**|Custom camera view with automatic square cropping, WebP compression, auto-incrementing flash codes (`#01`,`#02`...),<br>and single-field price entry for sub-30-second uploads.|
|**Live Drop**<br>**Controller**|Toggle catalog visibility:`Draft`,`Active Live Drop`, or`Archived`. Ability to mark items active or hidden on the fly<br>during a broadcast.|
||Intuitive order board divided into three actionable stages:|
|**Visual Kanban**<br>**Pipeline**|•**Pending:**Awaiting buyer payment screenshot.<br>•**Paid / Ready to Pack:**Payment confirmed; shipping label ready.|
||•**Dispatched:**Package handed to courier; tracking recorded.|
|**One-Tap Packing**<br>**Slip**|Generates standardized 4×6 inch PDF labels containing buyer address, item codes, seller contact info, and packaging<br>date.|
|**Realtime Push**<br>**Alerts**|Instant device notifications whenever a buyer submits an order via the web front.|
|**Customer Order**<br>**History**|Instant search by customer phone number to view past purchase history, preferred delivery addresses, and lifetime<br>value.|



#### **6.2 Buyer Webfront (Next.js / Cloudflare Pages)** 

|**Feature Module**|**Description & Functional Logic**|
|---|---|
|**Edge SSR Catalog**|Pre-rendered, ultra-fast mobile feed. High-contrast flash-code badges on every product tile for immediate<br>visual matching with the livestream.|
|**Zero-Friction Checkout**|No accounts, passwords, or emails. Minimal delivery form: Name, Phone, Address, Pincode.|
|**Floating Cart Bar**|Sticky bottom sheet showing selected garment count, total price, and instantaneous access to review.|
|**Inventory State Badging**|Dynamic product status updates in real-time (`In Stock`,`Reserved`,`Sold Out`) powered by Supabase<br>Realtime subscriptions.|
|**Deep-Link WhatsApp**<br>**Dispatcher**|Encodes cart contents and shipping details into standard URL parameters for direct handoff to the WhatsApp<br>mobile app.|
|**Static UPI Display**|Displays seller's static UPI QR code and UPI ID on the checkout success screen with an instant "Copy UPI<br>ID" button.|



### **7. Technical Architecture & Zero-Cost Cloud Strategy** 

LiveDrop is engineered to eliminate recurring SaaS fees, cloud infrastructure charges, and payment gateway cuts. 

|`┌────────────────────────────────────────────────────────────────────────────┐`<br>`│                    ZERO-COST INFRASTRUCTURE STACK                          │`<br>`├──────────────────────────────────────────────────────────────────────────┤`|
|---|
|`┬┬`<br>`│ Layer              │ Service / Tool              │ Free Tier Specification │`<br>`├────────────────────┼─────────────────────────────┼─────────────────────────┤`|
|`│ Frontend Hosting   │ Cloudflare Pages / Vercel   │ Unlimited static edge   │`<br>`│                    │                             │ requests, 100 GB bandw. │`<br>|
|`│ Backend & Database │ Supabase (PostgreSQL)       │ 500 MB DB storage,      │`<br>`│                    │                             │ 50,000 MAUs, Realtime   │`<br>|
|`│ Media & Images     │ Cloudinary / Supabase Store │ Auto-WebP compression,  │`<br>`│                    │                             │ 25 GB monthly bandwidth │`<br>|
|`│ Mobile App Distro  │ Direct Android APK (USB/DL) │ Bypasses $25 Google Play│`<br>`│                    │                             │ developer license fee   │`<br>|
|`│ Payment Processing │ Direct UPI (P2P / VPA)      │ 0% transaction fees     │`<br>`│ Domain             │ Cloudflare / Pages.dev URL  │ ₹0 custom subdomain    │`<br>`└────────────────────┴─────────────────────────────┴─────────────────────────┘`|



#### **7.1 Database Schema (High-Level Entities)** 

**`sellers`** : Profile, store name, phone number, UPI ID, default return address. 

**`drops`** : Live session event (title, start timestamp, status: `draft` , `live` , `closed` ). 

**`products`** : Item code ( `#A12` ), drop_id, image_url, price, size, status ( `available` , `reserved` , `sold` ), hold_timestamp. 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

8/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

**`orders`** : Buyer name, phone, shipping address, pincode, total amount, status ( `pending` , `paid` , `shipped` ), courier tracking code. 

**`order_items`** : Junction table linking orders to specific product items. 

#### **7.2 Concurrency & Single-Piece Stock Protection** 

To solve the critical single-piece collision problem without a heavy queue server: 

1. When a buyer initiates checkout on the web, a Postgres function executes an optimistic reservation: 

```
UPDATE products
SET status = 'reserved', reserved_at = NOW()
WHERE id = $product_id AND status = 'available';
```

2. If the update affects 0 rows, the client immediately informs the buyer that the item was just claimed by another viewer. 

3. A lightweight Supabase Edge Function or cron job releases any `reserved` items whose checkout was not completed within 15 minutes. 

### **8. Engineering Execution Plan: Antigravity IDE Agentic Workflow** 

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

- **Gemini 3.8 Flash (High):** Primary implementation workhorse. Handles rapid workspace generation, iterative terminal compilation ( `flutter run` , `npm run dev` ), state management wiring, and UI layout creation. 

**Claude Opus 4.6:** Strategic auditor. Periodically reviews database migration scripts, Row-Level Security (RLS) policies, inventory locking functions, and deep-link encoding logic to ensure bulletproof reliability. 

### **9. Success Metrics & Phased Roadmap** 

#### **Phase 1: MVP Validation ("User Zero" Drop) — Weeks 1–2** 

Build lightweight Next.js web catalog linked to Supabase. 

Manually ingest 25 garments for the seller's next Facebook Live broadcast. 

Track buyer checkout completion and measure seller feedback. 

**Target Metric:** 100% elimination of ambiguous garment screenshots from buyers who use the link. 

#### **Phase 2: Native Seller Operations App — Weeks 3–4** 

Implement Flutter APK with rapid camera intake and item code generator. 

Build the Visual Kanban pipeline (Pending -> Paid -> Dispatched). 

Integrate 4×6 inch PDF courier packing slip generation. 

**Target Metric:** Reduce post-live packing and addressing time from 3 hours to under 30 minutes. 

#### **Phase 3: Multi-Boutique Expansion — Month 2+** 

Support multiple boutique accounts with independent subdomains. 

Introduce automated buyer SMS/WhatsApp notifications with courier tracking links. 

Provide analytics dashboard (best-selling price brackets, top repeat buyers, drop revenue). 

### **10. Conclusion** 

LiveDrop transforms informal, chaotic social selling into a streamlined, high-speed retail operation. By respecting the natural habits of both boutique owners (speed, camera-first, WhatsApp-centric) and livestream shoppers (zero-friction, instant mobile browsing), LiveDrop delivers an enterprise-grade experience at absolute zero infrastructure cost. """ 

file_path = "product_brief.md" with open(file_path, "w", encoding="utf-8") as f: f.write(content) 

print(f"File created successfully at {file_path}") 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

9/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

```
```text?code_stdout&code_event_index=1
```

```
File created successfully at product_brief.md
```

Your Markdown (MD) file is ready 

[file-tag: code-generated-file-b789eaca-5816-4640-89fe-0d95fe3d4fa7] 

I have generated the complete **`product_brief.md`** file. Below is an overview of the core sections documented in the brief, designed to serve as your foundation inside the Antigravity IDE workspace: 

### **Key Highlights from the Product Brief** 

#### 1. **Executive Summary & Vision:** 

Clarifies **LiveDrop** as a live-commerce and fulfillment management platform bridging informal Facebook Live selling and structured order management. 

Explains the core philosophy: zero friction for buyers (no app downloads or accounts) and operational automation for sellers (camera-first inventory and automated courier labels). 

#### 2. **Persona Analysis & Real-World Bottlenecks:** 

Documents the exact live-stream flow in communities like _FASHION SWAP_ and _Debikar Sajghor_ . 

Identifies the core failure modes: blurry screenshots, single-piece stock collisions (race conditions), manual ledger transcription, and handwritten courier slips. 

#### 3. **Two-Tier System Architecture:** 

- **Seller Native Mobile App (Flutter APK):** Sub-30-second camera intake, auto-incrementing flash codes ( `#A01` , `#A02` ), real-time stock toggles, and a 3-column Visual Kanban order board ( _Pending Payment_ → _Ready to Pack_ → _Dispatched_ ). 

**Buyer Webfront (Next.js / Cloudflare Pages):** Zero-install, high-contrast mobile catalog with real-time stock indicators, sticky multiitem cart, and WhatsApp deep-link checkout. 

**Data & Realtime Layer (Supabase PostgreSQL):** Optimistic row-level locking for single-piece inventory and instant WebSocket updates. 

#### 4. **Step-by-Step Lifecycle:** 

Details the 5 operational phases: Pre-Live Ingestion, Live Stream Code Matching, Instant Web Cart Bundling, WhatsApp Handshake & UPI Verification, and One-Tap 4×6 inch Courier Packing Slip generation (compatible with DTDC, India Post, and Delhivery). 

#### 5. **₹0 Cloud Cost Strategy:** 

Complete architectural mapping using Cloudflare Pages / Vercel, Supabase Free Tier, Cloudinary/Supabase Storage, and local APK generation to ensure 100% free hosting and zero payment gateway transaction cuts. 

#### 6. **Agentic Development Workflow:** 

Concrete guidelines for driving development in Antigravity IDE using **Gemini 3.8 Flash (High)** as the implementation engine and **Claude Opus 4.6** as the architectural reviewer. 

_User prompt: Next, generate a detailed prd.md document file explaining exactly what the app and the website should do._ 

Response: ┌─────────────────────────────────────────────────────────────────────────────┐ │ TWO-TIER WORKSPACE │ 

├──────────────────────────────────────┬──────────────────────────────────────┤ │ 1. Buyer Webfront (Next.js) │ 2. Seller Operations App (Flutter) │ 

├──────────────────────────────────────┼──────────────────────────────────────┤ │ • Zero app download (runs in browser)│ • Native Android APK (No Play Store) │ │ • No authentication or passwords │ • Supabase Email/Password Auth │ │ • Large flash-code product cards │ • Rapid camera ingestion (<30s) │ │ • Real-time stock availability badge │ • Real-time Kanban order pipeline │ │ • Sticky bundle cart & WhatsApp link │ • 1-tap 4x6 courier slip PDF engine │ 

└──────────────────────────────────────┴──────────────────────────────────────┘ 

```
---
```

```
## 3. Buyer Webfront Specifications (Next.js)
```

```
### 3.1 Target Platform & Constraints
```

```
* **Platform:** Responsive Mobile Web (Edge SSR on Cloudflare Pages or Vercel).
```

- `**Browsers:** Facebook In-App Browser, WhatsApp In-App Webview, Chrome Mobile, Safari iOS.` 

- `**Zero-Download Rule:** No native app prompts, no PWA install force-dialogs, no mandatory account sign-ups.` 

```
### 3.2 Feature Matrix & Functional Requirements
```

```
#### FR-B1: Drop Catalog Feed
```

```
* **Feed Display:** Clean, high-density two-column or single-column feed showing all items attached to the active li
* **Product Card Elements:**
```

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

10/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

```
 * Bold Flash Code badge (e.g., `#A01`, `#B12`) overlaid on the top-left of the image.
```

- `Square thumbnail with Cloudinary/Supabase auto-WebP compression. * Title/Fabric name (optional, short text). * Price in INR (`₹1,250`).` 

- `Real-time Status Badge: `Available` (Green), `Reserved` (Amber - with remaining hold timer), `Sold Out` (Muted G` 

- `* **Sticky Filter Bar:** Filter by status (`All`, `Available`) and quick-search input by Flash Code (`Search code #.` 

```
#### FR-B2: Multi-Item Sticky Cart
```

- `**Floating Bottom Sheet:** Sticky bar fixed to the bottom displaying: * Count badge: `"X items selected"`. * Running Subtotal: `"₹X,XXX"`. * `"Review & Book"` primary CTA button.` 

- `**Bundle Drawer:** Tapping expands an interactive modal showing selected items, individual prices, thumbnail previ` 

```
#### FR-B3: Zero-Friction Checkout & Delivery Form
```

- `**Input Fields (Strictly Minimal):**` 

`1. `Full Name` (Text, required, min 3 chars).` 

`2. `WhatsApp Number` (Numeric, 10 digits, validated against Indian mobile prefixes 6-9).` 

`3. `Delivery Pincode` (Numeric, 6 digits, auto-resolves City/State if possible).` 

`4. `Detailed Address` (Textarea, required: Flat/House No, Street, Landmark).` 

`* **Local Persistence:** Form fields must be saved to browser `localStorage` so repeat buyers never re-type their ad` 

```
#### FR-B4: Atomic Stock Reservation & WhatsApp Deep-Link
```

- `**Atomic Hold Trigger:** Clicking `"Place Order on WhatsApp"` calls the Supabase RPC function `reserve_order_items * If successful: Items enter `reserved` state for a 15-minute expiration window. * If conflict: Alerts the user: *"Item #A07 was just reserved by another buyer. Please remove it to proceed."*` 

- `**WhatsApp Deep Link Constructor:** Generates a formatted standard `https://wa.me/{seller_phone}?text={encoded_mes` 

- `**Confirmation & UPI Screen:** If the buyer does not automatically get redirected, displays: * Order Summary & Reference ID (`#LD-XXXX`).` 

- `Direct "Open in WhatsApp" fallback button. * Seller's static UPI QR code and UPI ID (`example@okaxis`) with a 1-tap "Copy UPI ID" action. * Direct instructions: *"Please send your payment screenshot directly in the WhatsApp chat."*` 

```
---
```

```
## 4. Seller Mobile App Specifications (Flutter Android)
```

```
### 4.1 Target Platform & Constraints
```

```
* **Platform:** Flutter 3.x for Android (Built as a release APK; direct sideload).
```

- `**Target Device:** Android 11.0+, optimized for handheld single-hand operations.` 

```
* **Authentication:** Supabase Auth (Email/Password or Magic Link) for the seller only.
```

```
### 4.2 Feature Matrix & Functional Requirements
```

```
#### FR-S1: Rapid Camera Ingestion Engine
```

- `**Camera Integration:** Direct integration with `camera` or `image_picker` package.` 

- `**Sub-30-Second Flow:**` 

`1. Shutter tap takes photo.` 

`2. Image auto-cropped to 1:1 square ratio and compressed client-side to < 250 KB (WebP).` 

`3. Auto-incrementing Flash Code suggested (e.g., if last was `#14`, auto-fills `#15`).` 

`4. Single price keypad input (`₹`).` 

`5. Tap `"Add Next"` immediately loops back to camera view without closing.` 

`* **Bulk Drop Publishing:** Group uploaded items into a named "Drop" (e.g., *"Friday Silk Special"*) and toggle Drop` 

- `#### FR-S2: Real-Time Live Session Monitor * **Inventory Overview:** Live-updating grid showing real-time states of all items during the broadcast. * **Quick Manual Actions:** * Long-press an item to mark `Sold Offline` or `Toggle Hold`. * Live counter: Total Items, Reserved Items, Confirmed Sold, Total Revenue.` 

```
#### FR-S3: Visual Kanban Order Management
```

```
Orders flow through three strict stages:
```

`1. **Pending Verification (`pending`):**` 

- `Triggered when buyer places order on web. * Displays buyer name, phone, item codes, total amount, and time remaining on 15-min hold. * Action buttons: `Confirm Payment (Mark as Paid)` or `Cancel / Release Hold`.` 

`2. **Ready to Pack (`paid`):**` 

- `Displays confirmed orders ready for packaging. * Action button: `Print / Share Courier Label` (Opens PDF preview). * Transition action: `Mark as Dispatched`.` 

`3. **Dispatched (`shipped`):** * Archive column displaying courier tracking number, dispatch date, and full order breakdown.` 

`#### FR-S4: Automated 4×6 Courier Packing Slip Engine * **Engine:** Built using `pdf` and `printing` packages in Flutter. * **Format:** Standard 4×6 inch (100×150 mm) thermal shipping label layout. * **Slip Elements:** * **Recipient Section:** Full Name, Large Bold Phone Number, Formatted Multiline Address, Bold 6-digit Pincode. * **Sender / Return Section:** Boutique Store Name, Contact Number, Return Address.` 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

11/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

```
 * **Package Breakdown:** Item Flash Codes, Short Descriptions, Total Declared Value.
```

```
 * **System Reference:** Barcode/QR Code containing the internal Order ID (`#LD-XXXX`).
```

```
* **Output Targets:** Direct print via Bluetooth thermal printer (ESC/POS) or share as PDF to WhatsApp/Files.
```

```
---
```

```
## 5. Database Schema & Architecture (Supabase PostgreSQL)
```sql
-- 1. PROFILES / SELLERS
CREATE TABLE profiles (
   id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
   store_name TEXT NOT NULL,
   phone_number TEXT NOT NULL,
   upi_id TEXT NOT NULL,
   return_address TEXT NOT NULL,
   created_at TIMESTAMPTZ DEFAULT NOW()
);
-- 2. DROPS (LIVE SESSIONS)
CREATE TABLE drops (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   seller_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
   title TEXT NOT NULL,
   slug TEXT UNIQUE NOT NULL,
   status TEXT CHECK (status IN ('draft', 'live', 'closed')) DEFAULT 'draft',
   created_at TIMESTAMPTZ DEFAULT NOW()
);
-- 3. PRODUCTS
CREATE TABLE products (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   drop_id UUID REFERENCES drops(id) ON DELETE CASCADE,
   code TEXT NOT NULL, -- e.g., '#A01'
   title TEXT,
   price NUMERIC(10, 2) NOT NULL,
   size TEXT,
   image_url TEXT NOT NULL,
   status TEXT CHECK (status IN ('available', 'reserved', 'sold')) DEFAULT 'available',
   reserved_at TIMESTAMPTZ,
   reserved_by_session TEXT,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   UNIQUE(drop_id, code)
);
-- 4. ORDERS
CREATE TABLE orders (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   drop_id UUID REFERENCES drops(id) ON DELETE RESTRICT,
   order_code TEXT UNIQUE NOT NULL, -- e.g., 'LD-1024'
   buyer_name TEXT NOT NULL,
   buyer_phone TEXT NOT NULL,
   shipping_address TEXT NOT NULL,
   pincode TEXT NOT NULL,
   total_amount NUMERIC(10, 2) NOT NULL,
   status TEXT CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')) DEFAULT 'pending',
   tracking_number TEXT,
   courier_partner TEXT,
   created_at TIMESTAMPTZ DEFAULT NOW()
);
-- 5. ORDER ITEMS (JUNCTION)
CREATE TABLE order_items (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
   product_id UUID REFERENCES products(id) ON DELETE RESTRICT,
   price_at_purchase NUMERIC(10, 2) NOT NULL
);
```

### **5.1 Concurrency & Atomic Hold RPC** 

```
CREATE OR REPLACE FUNCTION reserve_order_items(
   p_product_ids UUID[],
   p_session_id TEXT
) RETURNS BOOLEAN AS $$ DECLARE     v_available_count INT; BEGIN     -- Check if all requested items are currently a
```

## **6. Security, RLS & Edge Cases** 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

12/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

### **6.1 Row Level Security (RLS) Policies** 

**`profiles`** : Public read-only for store info (store name, UPI ID); write allowed only for matching `auth.uid()` . 

**`drops`** : Public read for `live` drops; write only for owning `seller_id` . 

**`products`** : Public read for products under active drops; updates restricted to RPC functions (for reservation) or owning seller. 

**`orders`** : Public insert allowed (unauthenticated buyers creating orders); update/delete restricted exclusively to owning seller. 

### **6.2 Critical Edge Cases & Recovery** 

|**Edge Case Scenario**|**System Behavior & Mitigation**|
|---|---|
|**Abandoned Cart after**<br>**Reservation**|A Supabase cron job or Edge Function checks every 60 seconds:`UPDATE products SET status =`<br>`'available' WHERE status = 'reserved' AND reserved_at < NOW() - INTERVAL '15 minutes'`.|
|**Buyer Closes WhatsApp**<br>**Immediately**|Order is already saved in Supabase as`pending`. Seller sees order on Kanban board with buyer phone; can<br>initiate chat directly.|
|**Simultaneous Checkout**<br>**Collision**|The atomic RPC guarantees that only one transaction succeeds. The losing buyer receives an instant inline UI<br>prompt to deselect the unavailable item.|
|**Poor Mobile Data**<br>**Connectivity**|Webfront images are served via Cloudinary/Supabase Storage with aggressive caching, responsive`srcset`,<br>and WebP compression (< 40 KB per thumbnail).|



## **7. Implementation Milestones (Antigravity IDE Agentic Plan)** 

#### **Sprint 1: Core Database & Buyer Webfront (Gemini 3.8 Flash)** 

Deploy Supabase schema, RLS policies, and `reserve_order_items` RPC. 

Build Next.js catalog view with sticky cart bar and WhatsApp link constructor. 

Audit with Claude Opus 4.6 for injection vulnerabilities and race conditions. 

#### **Sprint 2: Seller Mobile Intake & Kanban (Gemini 3.8 Flash)** 

Build Flutter rapid camera intake module with automatic code assignment. 

Implement real-time Kanban board syncing order status updates via Supabase WebSockets. 

#### **Sprint 3: Dispatch Engine & End-to-End Validation (Gemini 3.8 Flash + Opus 4.6)** 

Build 4×6 inch thermal PDF packing slip generator in Flutter. 

Conduct simulated Facebook Live dry-run with 30 items to verify stock locking under concurrent loads. """ 

file_path = "prd.md" with open(file_path, "w", encoding="utf-8") as f: f.write(prd_content) 

print(f"File created successfully at {file_path}") 

```
```text?code_stdout&code_event_index=1
File created successfully at prd.md
```

The **`prd.md`** file has been generated and added to your workspace. It defines the precise functional requirements, technical specifications, database schema, and operational edge cases for both the **Next.js Buyer Webfront** and the **Flutter Seller App** . 

### **Key Specifications Defined in** **`prd.md`** 

#### **1. Buyer Webfront (Next.js / Cloudflare Pages)** 

- **Catalog Browsing:** Displays high-contrast Flash Code badges (e.g., `#A01` , `#B12` ) overlaid on product thumbnails, with real-time stock indicators ( `Available` , `Reserved` , `Sold Out` ). 

- **Sticky Bundle Cart:** A mobile bottom drawer allowing viewers to bundle multiple dresses from across a live stream into a single order without refreshing or losing items. 

- **Frictionless Delivery Form:** Captures only essential fields (Name, 10-digit WhatsApp number, Pincode, Address) with local browser persistence for repeat buyers. 

**Atomic Hold & WhatsApp Deep Link:** Calls a PostgreSQL function to lock single-piece stock for 15 minutes before launching WhatsApp with a clean, pre-filled order string addressed to the seller. 

**Payment Fallback Screen:** Displays order reference `#LD-XXXX` , the seller's static UPI QR code, and a one-tap "Copy UPI ID" action. 

#### **2. Seller Operations App (Flutter Android APK)** 

**Sub-30-Second Ingestion:** Rapid camera view with auto-square cropping, client-side WebP compression, auto-incrementing flash codes, and single-field price inputs for swift uploads before a stream. 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

13/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

**Live Session Monitor:** Real-time stock overview with manual long-press overrides to mark items sold offline or release reservations. 

- **3-Stage Visual Kanban:** Moves incoming orders through `Pending Verification` , `Ready to Pack` , and `Dispatched` with real-time Supabase WebSocket sync. 

**Automated 4×6 Courier Slip Engine:** One-tap PDF generation formatted for standard 4×6 inch (100×150 mm) thermal labels (compatible with India Post, DTDC, and Delhivery) containing recipient address, sender details, flash codes, and an internal barcode. 

#### **3. Database & System Architecture (Supabase PostgreSQL)** 

Full SQL migration schema included: `profiles` , `drops` , `products` , `orders` , and `order_items` tables. 

Row-Level Security (RLS) policies defining public read-only access for active drops and authenticated write access for the seller. 

PL/pgSQL atomic reservation function ( `reserve_order_items` ) that prevents single-piece double-booking during concurrent checkouts. 

Automated 15-minute expiration logic to return abandoned cart reservations back to `available` status. 

#### **4. Development & Agentic Execution Plan** 

Clear task boundaries allocating rapid full-stack scaffolding and UI implementation to **Gemini 3.8 Flash (High)** , and database RLS auditing, edge-case analysis, and concurrency reviews to **Claude Opus 4.6** . 

#### _User prompt: Give me the prd in downloadable format._ 

Response: The full **`prd.md`** specification is provided below in a self-contained export block. You can copy its contents directly into a new `prd.md` file at the root of your project directory in Antigravity IDE to guide implementation. 

```
# Product Requirements Document (PRD): LiveDrop[cite: 2]
**Document Version:** 1.0.0[cite: 2]
```

```
**Target Release:** MVP Phase 1[cite: 2]
```

```
**Tech Stack:** Next.js (Buyer Webfront), Flutter (Seller Android APK), Supabase (PostgreSQL, Realtime, Storage)[cit
**Hosting Overhead:** ₹0 (Cloudflare Pages / Vercel + Supabase Free Tier)[cite: 2]
```

#### `---` 

```
## 1. Executive Summary & Goals[cite: 2]
```

```
### 1.1 Product Objective[cite: 2]
LiveDrop is a specialized two-tier live-commerce operating system designed for independent home boutique sellers on
```

```
### 1.2 Target Success Metrics (KPIs)[cite: 2]
```

```
* **Checkout Velocity:** A buyer completes selection, enters shipping details, and routes to WhatsApp in under 45 se
```

```
* **Ingestion Speed:** A seller can photograph, tag with a flash code, price, and publish an inventory item in under
* **Zero Inventory Collisions:** 100% elimination of double-sold single-piece inventory through atomic reservation l
* **Dispatch Time Reduction:** Post-live parcel labeling time reduced from 3+ hours to under 20 minutes via automate
* **Zero Operating Cost:** Base platform operates entirely within free cloud tier allowances (₹0 compute, storage, a
```

#### `---` 

```
## 2. User Personas & System Workspaces[cite: 2]
```

┌─────────────────────────────────────────────────────────────────────────────┐ │ TWO-TIER 

WORKSPACE │ ├──────────────────────────────────────┬──────────────────────────────────────┤ │ 1. Buyer Webfront (Next.js) │ 2. Seller Operations App (Flutter) │ 

├──────────────────────────────────────┼──────────────────────────────────────┤ │ • Zero app download (runs in browser)│ • Native Android APK (No Play Store) │ │ • No authentication or passwords │ • Supabase Email/Password Auth │ │ • Large flash-code product cards │ • Rapid camera ingestion (<30s) │ │ • Real-time stock availability badge │ • Real-time Kanban order pipeline │ │ • Sticky bundle cart & WhatsApp link │ • 1-tap 4x6 courier slip PDF engine │ └──────────────────────────────────────┴──────────────────────────────────────┘ 

```
---
```

```
## 3. Buyer Webfront Specifications (Next.js)[cite: 2]
```

```
### 3.1 Target Platform & Constraints[cite: 2]
```

```
* **Platform:** Responsive Mobile Web (Edge SSR on Cloudflare Pages or Vercel)[cite: 2].
```

```
* **Browsers:** Facebook In-App Browser, WhatsApp In-App Webview, Chrome Mobile, Safari iOS[cite: 2].
```

```
* **Zero-Download Rule:** No native app prompts, no PWA install force-dialogs, no mandatory account sign-ups[cite: 2
```

```
### 3.2 Feature Matrix & Functional Requirements[cite: 2]
```

```
#### FR-B1: Drop Catalog Feed[cite: 2]
```

```
* **Feed Display:** Clean, high-density two-column or single-column feed showing all items attached to the active li
* **Product Card Elements:**[cite: 2]
```

```
 * Bold Flash Code badge (e.g., `#A01`, `#B12`) overlaid on the top-left of the image[cite: 2].
 * Square thumbnail with Cloudinary/Supabase auto-WebP compression[cite: 2].
 * Title/Fabric name (optional, short text)[cite: 2].
```

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

14/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

```
 * Price in INR (`₹1,250`)[cite: 2].
 * Real-time Status Badge: `Available` (Green), `Reserved` (Amber - with remaining hold timer), `Sold Out` (Muted G
* **Sticky Filter Bar:** Filter by status (`All`, `Available`) and quick-search input by Flash Code (`Search code #.
```

```
#### FR-B2: Multi-Item Sticky Cart[cite: 2]
* **Floating Bottom Sheet:** Sticky bar fixed to the bottom displaying:[cite: 2]
 * Count badge: `"X items selected"`[cite: 2].
 * Running Subtotal: `"₹X,XXX"`[cite: 2].
 * `"Review & Book"` primary CTA button[cite: 2].
* **Bundle Drawer:** Tapping expands an interactive modal showing selected items, individual prices, thumbnail previ
```

- `#### FR-B3: Zero-Friction Checkout & Delivery Form[cite: 2] * **Input Fields (Strictly Minimal):**[cite: 2]` 

`1. `Full Name` (Text, required, min 3 chars)[cite: 2].` 

`2. `WhatsApp Number` (Numeric, 10 digits, validated against Indian mobile prefixes 6-9)[cite: 2].` 

`3. `Delivery Pincode` (Numeric, 6 digits, auto-resolves City/State if possible)[cite: 2].` 

`4. `Detailed Address` (Textarea, required: Flat/House No, Street, Landmark)[cite: 2].` 

`* **Local Persistence:** Form fields must be saved to browser `localStorage` so repeat buyers never re-type their ad` 

```
#### FR-B4: Atomic Stock Reservation & WhatsApp Deep-Link[cite: 2]
* **Atomic Hold Trigger:** Clicking `"Place Order on WhatsApp"` calls the Supabase RPC function `reserve_order_items
 * If successful: Items enter `reserved` state for a 15-minute expiration window[cite: 2].
 * If conflict: Alerts the user: *"Item #A07 was just reserved by another buyer. Please remove it to proceed."*[cit
* **WhatsApp Deep Link Constructor:** Generates a formatted standard `https://wa.me/{seller_phone}?text={encoded_mes
* **Confirmation & UPI Screen:** If the buyer does not automatically get redirected, displays:[cite: 2]
 * Order Summary & Reference ID (`#LD-XXXX`)[cite: 2].
 * Direct "Open in WhatsApp" fallback button[cite: 2].
 * Seller's static UPI QR code and UPI ID (`example@okaxis`) with a 1-tap "Copy UPI ID" action[cite: 2].
 * Direct instructions: *"Please send your payment screenshot directly in the WhatsApp chat."*[cite: 2]
```

```
---
```

```
## 4. Seller Mobile App Specifications (Flutter Android)[cite: 2]
```

```
### 4.1 Target Platform & Constraints[cite: 2]
* **Platform:** Flutter 3.x for Android (Built as a release APK; direct sideload)[cite: 2].
```

```
* **Target Device:** Android 11.0+, optimized for handheld single-hand operations[cite: 2].
* **Authentication:** Supabase Auth (Email/Password or Magic Link) for the seller only[cite: 2].
```

```
### 4.2 Feature Matrix & Functional Requirements[cite: 2]
```

```
#### FR-S1: Rapid Camera Ingestion Engine[cite: 2]
```

- `**Camera Integration:** Direct integration with `camera` or `image_picker` package[cite: 2].` 

- `**Sub-30-Second Flow:**[cite: 2]` 

`1. Shutter tap takes photo[cite: 2].` 

`2. Image auto-cropped to 1:1 square ratio and compressed client-side to < 250 KB (WebP)[cite: 2].` 

`3. Auto-incrementing Flash Code suggested (e.g., if last was `#14`, auto-fills `#15`)[cite: 2].` 

`4. Single price keypad input (`₹`)[cite: 2].` 

`5. Tap `"Add Next"` immediately loops back to camera view without closing[cite: 2].` 

- `**Bulk Drop Publishing:** Group uploaded items into a named "Drop" (e.g., *"Friday Silk Special"*) and toggle Drop` 

```
#### FR-S2: Real-Time Live Session Monitor[cite: 2]
```

- `**Inventory Overview:** Live-updating grid showing real-time states of all items during the broadcast[cite: 2]. * **Quick Manual Actions:**[cite: 2]` 

- `Long-press an item to mark `Sold Offline` or `Toggle Hold`[cite: 2].` 

- `Live counter: Total Items, Reserved Items, Confirmed Sold, Total Revenue[cite: 2].` 

```
#### FR-S3: Visual Kanban Order Management[cite: 2]
Orders flow through three strict stages:[cite: 2]
```

`1. **Pending Verification (`pending`):**[cite: 2]` 

- `Triggered when buyer places order on web[cite: 2].` 

- `Displays buyer name, phone, item codes, total amount, and time remaining on 15-min hold[cite: 2]. * Action buttons: `Confirm Payment (Mark as Paid)` or `Cancel / Release Hold`[cite: 2].` 

`2. **Ready to Pack (`paid`):**[cite: 2]` 

- `Displays confirmed orders ready for packaging[cite: 2].` 

- `Action button: `Print / Share Courier Label` (Opens PDF preview)[cite: 2].` 

- `Transition action: `Mark as Dispatched`[cite: 2].` 

`3. **Dispatched (`shipped`):**[cite: 2]` 

- `Archive column displaying courier tracking number, dispatch date, and full order breakdown[cite: 2].` 

```
#### FR-S4: Automated 4×6 Courier Packing Slip Engine[cite: 2]
```

- `**Engine:** Built using `pdf` and `printing` packages in Flutter[cite: 2].` 

- `**Format:** Standard 4×6 inch (100×150 mm) thermal shipping label layout[cite: 2]. * **Slip Elements:**[cite: 2]` 

- `**Recipient Section:** Full Name, Large Bold Phone Number, Formatted Multiline Address, Bold 6-digit Pincode[cit * **Sender / Return Section:** Boutique Store Name, Contact Number, Return Address[cite: 2]. * **Package Breakdown:** Item Flash Codes, Short Descriptions, Total Declared Value[cite: 2]. * **System Reference:** Barcode/QR Code containing the internal Order ID (`#LD-XXXX`)[cite: 2].` 

- `**Output Targets:** Direct print via Bluetooth thermal printer (ESC/POS) or share as PDF to WhatsApp/Files[cite: 2` 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

15/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

```
---
```

```
## 5. Database Schema & Architecture (Supabase PostgreSQL)[cite: 2]
```sql
-- 1. PROFILES / SELLERS
CREATE TABLE profiles (
   id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
   store_name TEXT NOT NULL,
   phone_number TEXT NOT NULL,
   upi_id TEXT NOT NULL,
   return_address TEXT NOT NULL,
   created_at TIMESTAMPTZ DEFAULT NOW()
);
-- 2. DROPS (LIVE SESSIONS)
CREATE TABLE drops (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   seller_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
   title TEXT NOT NULL,
   slug TEXT UNIQUE NOT NULL,
   status TEXT CHECK (status IN ('draft', 'live', 'closed')) DEFAULT 'draft',
   created_at TIMESTAMPTZ DEFAULT NOW()
);
-- 3. PRODUCTS
CREATE TABLE products (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   drop_id UUID REFERENCES drops(id) ON DELETE CASCADE,
   code TEXT NOT NULL, -- e.g., '#A01'
   title TEXT,
   price NUMERIC(10, 2) NOT NULL,
   size TEXT,
   image_url TEXT NOT NULL,
   status TEXT CHECK (status IN ('available', 'reserved', 'sold')) DEFAULT 'available',
   reserved_at TIMESTAMPTZ,
   reserved_by_session TEXT,
   created_at TIMESTAMPTZ DEFAULT NOW(),
   UNIQUE(drop_id, code)
);
-- 4. ORDERS
CREATE TABLE orders (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   drop_id UUID REFERENCES drops(id) ON DELETE RESTRICT,
   order_code TEXT UNIQUE NOT NULL, -- e.g., 'LD-1024'
   buyer_name TEXT NOT NULL,
   buyer_phone TEXT NOT NULL,
   shipping_address TEXT NOT NULL,
   pincode TEXT NOT NULL,
   total_amount NUMERIC(10, 2) NOT NULL,
   status TEXT CHECK (status IN ('pending', 'paid', 'shipped', 'cancelled')) DEFAULT 'pending',
   tracking_number TEXT,
   courier_partner TEXT,
   created_at TIMESTAMPTZ DEFAULT NOW()
);
-- 5. ORDER ITEMS (JUNCTION)
CREATE TABLE order_items (
   id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
   order_id UUID REFERENCES orders(id) ON DELETE CASCADE,
   product_id UUID REFERENCES products(id) ON DELETE RESTRICT,
   price_at_purchase NUMERIC(10, 2) NOT NULL
);
```[cite: 2]
### 5.1 Concurrency & Atomic Hold RPC[cite: 2]
```sql
CREATE OR REPLACE FUNCTION reserve_order_items(
   p_product_ids UUID[],
   p_session_id TEXT
) RETURNS BOOLEAN AS $$ DECLARE     v_available_count INT; BEGIN     -- Check if all requested items are currently a
```[cite: 2]
---
```

```
## 6. Security, RLS & Edge Cases[cite: 2]
```

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

16/17 

9/11/26, 2:24 AM 

Building an App for Facebook Live Sellers 

- `### 6.1 Row Level Security (RLS) Policies[cite: 2]` 

- `**`profiles`**: Public read-only for store info (store name, UPI ID); write allowed only for matching `auth.uid()`` 

- `**`drops`**: Public read for `live` drops; write only for owning `seller_id`[cite: 2].` 

- `**`products`**: Public read for products under active drops; updates restricted to RPC functions (for reservation)` 

- `**`orders`**: Public insert allowed (unauthenticated buyers creating orders); update/delete restricted exclusively` 

- `### 6.2 Critical Edge Cases & Recovery[cite: 2]` 

- `| Edge Case Scenario | System Behavior & Mitigation[cite: 2] |` 

```
|---|---|
```

```
| **Abandoned Cart after Reservation** | A Supabase cron job or Edge Function checks every 60 seconds: `UPDATE produ
```

```
| **Buyer Closes WhatsApp Immediately** | Order is already saved in Supabase as `pending`. Seller sees order on Kanb
| **Simultaneous Checkout Collision** | The atomic RPC guarantees that only one transaction succeeds. The losing buy
| **Poor Mobile Data Connectivity** | Webfront images are served via Cloudinary/Supabase Storage with aggressive cac
```

```
---
```

- `## 7. Implementation Milestones (Antigravity IDE Agentic Plan)[cite: 2]` 

- `**Sprint 1: Core Database & Buyer Webfront (Gemini 3.8 Flash)**[cite: 2]` 

- `Deploy Supabase schema, RLS policies, and `reserve_order_items` RPC[cite: 2].` 

- `Build Next.js catalog view with sticky cart bar and WhatsApp link constructor[cite: 2].` 

- `Audit with Claude Opus 4.6 for injection vulnerabilities and race conditions[cite: 2].` 

- `**Sprint 2: Seller Mobile Intake & Kanban (Gemini 3.8 Flash)**[cite: 2]` 

- `Build Flutter rapid camera intake module with automatic code assignment[cite: 2].` 

- `Implement real-time Kanban board syncing order status updates via Supabase WebSockets[cite: 2].` 

- `**Sprint 3: Dispatch Engine & End-to-End Validation (Gemini 3.8 Flash + Opus 4.6)**[cite: 2]` 

- `Build 4×6 inch thermal PDF packing slip generator in Flutter[cite: 2].` 

- `Conduct simulated Facebook Live dry-run with 30 items to verify stock locking under concurrent loads[cite: 2].` 

To save this directly in Antigravity IDE, create a file named `prd.md` in your workspace root and paste the block above. Gemini 3.8 Flash can then reference it during your agentic build loops. 

https://gemini.google.com/app/c248dc596c1aecf0?hl=en-IN 

17/17 

