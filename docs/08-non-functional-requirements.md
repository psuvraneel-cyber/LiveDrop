# 08 — Non-Functional Requirements (NFR): LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  

---

## 1. Performance & Latency Budgets

### 1.1 Buyer Webfront (Next.js Edge)
Tested under simulated 4G mobile networks (10 Mbps down / 2 Mbps up, 150ms round-trip latency):

| Metric | Target Limit | Pass/Fail Threshold | Measurement Tool | Optimization Strategy |
|---|---|---|---|---|
| **First Contentful Paint (FCP)** | < 1.2s | **< 1.5s** | Lighthouse Mobile / WebPageTest | Edge SSR on Cloudflare/Vercel; zero client bundle blocking |
| **Largest Contentful Paint (LCP)** | < 2.0s | **< 2.5s** | Lighthouse Mobile | Auto-WebP thumbnails (<40 KB); 1:1 skeleton placeholders |
| **Cumulative Layout Shift (CLS)** | < 0.05 | **< 0.10** | Chrome DevTools Performance | Explicit aspect-ratio containers on all product tiles |
| **Total Blocking Time (TBT)** | < 150ms | **< 250ms** | Lighthouse Mobile | Zero heavy UI libraries; native Web APIs; vanilla/Tailwind CSS |
| **Initial Bundle Size (JS)** | < 180 KB | **< 300 KB (gzipped)** | Next.js Build Analyzer | Code-splitting; deferred Realtime client initialization |
| **Atomic Checkout RPC Latency** | < 400ms | **< 800ms** | PostgreSQL `pg_stat_statements` | Indexed row-level locking; single database round-trip |

### 1.2 Seller Mobile App (Flutter Native)
Tested on budget Android hardware (e.g., Redmi 9A / Realme C-series, 3GB RAM):

| Operational Workflow | Target Budget | Hard Upper Bound | Measurement Method | Optimization Mechanism |
|---|---|---|---|---|
| **Shutter-to-Viewfinder Reset** | < 0.8s | **< 1.2s** | Flutter DevTools Timeline | Non-blocking background upload queue |
| **Client-Side Image Compression** | < 400ms | **< 600ms** | Stopwatch Benchmark | Native C++ libjpeg-turbo / WebP compressor |
| **PDF Shipping Label Render** | < 600ms | **< 1000ms** | Flutter Frame Profiler | Pre-compiled vector layout in `pdf` package |
| **Realtime Order Notification** | < 1.0s | **< 2.0s** | WebSocket E2E Latency | Persistent Supabase Realtime channel |
| **App Cold Start Time** | < 1.5s | **< 2.5s** | `adb shell am start -W` | Deferred library initialization |

---

## 2. Concurrency & Throughput Limits

* **Simultaneous Broadcast Viewers:** System supports up to **500 concurrent buyers** viewing a live drop feed simultaneously.
* **Peak Checkout Collisions:** Handles up to **20 simultaneous checkout requests per second** on a single contested product without deadlock or data corruption.
* **Database Row Locking:** All atomic checkout operations lock products via `ORDER BY id` to guarantee mathematical deadlock prevention under concurrent contention.
* **Realtime Broadcast Saturation:** Designed to operate smoothly within Supabase free-tier limits of **200 concurrent Realtime connections** per project, using polling fallbacks if WebSocket connection limits are reached.

---

## 3. Availability, Durability & Recovery

* **System Availability SLA:** **99.9% availability** during scheduled boutique broadcast windows (typically 2-hour evening slots, 2–5 times weekly).
* **Data Loss Tolerance (RPO):** **0 seconds (Zero Data Loss)** for confirmed orders, payments, and product reservations. PostgreSQL WAL replication guarantees ACID persistence.
* **Recovery Time Objective (RTO):** `< 5 minutes` to restore service from cloud backup in disaster recovery scenarios.
* **Inactivity Resilience:** Automated daily keepalive pings prevent Supabase free tier from pausing projects after 7 days of seller inactivity.

---

## 4. Security & Compliance Standards

* **Data Isolation:** Complete multi-tenant isolation between boutiques via PostgreSQL Row-Level Security (RLS). No seller may view or manipulate another boutique's drops, products, or customer orders.
* **Public Buyer Privilege Boundary:** Unauthenticated public buyers can only view active (`status = 'live'`) drops and products. Order records are readable only by presenting the cryptographically random `order_token` issued at creation.
* **Privilege Hardening:** All PostgreSQL `SECURITY DEFINER` functions explicitly enforce `SET search_path = public, pg_temp;` to prevent search-path injection.
* **URL Injection Defense:** All buyer inputs injected into WhatsApp deep links (`wa.me`) are strictly sanitized and encoded via `encodeURIComponent` with `%0A` newline normalization.
* **Data Protection Compliance:** System complies with India's Digital Personal Data Protection (DPDP) Act by storing only strictly necessary fulfillment PII (Name, Phone, Pincode, Address) with explicit buyer clearance options.

---

## 5. Compatibility & Environmental Constraints

### 5.1 Buyer Webfront Environment
* **Primary Mobile Webviews:**
  * Facebook In-App Browser (Android & iOS).
  * WhatsApp In-App Webview (Android & iOS).
  * Chrome Mobile 90+.
  * Safari iOS 14+.
* **Screen Resolutions:** Fully responsive across mobile viewports from 320px (iPhone SE 1st gen) to 430px (iPhone Pro Max) and standard Android viewports (360×800).
* **Network Tolerance:** Fully functional on fluctuating 3G/4G connections; all static assets aggressively cached with fallback retry logic.

### 5.2 Seller Mobile App Environment
* **Platform:** Android 11.0+ (API Level 30+).
* **Hardware Requirements:** Working rear camera (min 5MP), Bluetooth 4.0+ (for optional thermal printing), 2GB RAM minimum.
* **Network Requirements:** Intermittent connectivity tolerance; background upload queue caches images in local storage (Hive/SQLite) if cellular signal drops during live stream.
