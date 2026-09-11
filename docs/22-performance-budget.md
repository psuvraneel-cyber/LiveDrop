# 22 — Performance Budget & Measurement Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  

---

## 1. Performance Engineering Mandate

To ensure adoption among non-technical sellers and low-friction mobile buyers, LiveDrop enforces strict performance budgets.

> [!IMPORTANT]
> All performance metrics documented herein represent **design targets** and **gating criteria**. A metric cannot be marked "achieved" in production reports without documented empirical measurements from the specified test tools.

---

## 2. Comprehensive Performance Budget Matrix

### 2.1 Buyer Webfront (Next.js Edge SSR)

| Metric | Target | Pass/Fail Threshold | Acceptable Tolerance | Measurement Tool | Test Environment & Conditions | Optimization Strategy |
|---|---|---|---|---|---|---|
| **First Contentful Paint (FCP)** | < 1.2s | **< 1.5s** | +150ms | Lighthouse Mobile / WebPageTest | Simulated 4G (10 Mbps / 2 Mbps, 150ms RTT), Moto G4 profile | Edge SSR on Cloudflare Pages / Vercel; zero external fonts; inline critical CSS |
| **Largest Contentful Paint (LCP)** | < 2.0s | **< 2.5s** | +200ms | Chrome DevTools Performance | Simulated 4G, 2-column grid with 30 items | Client-side WebP thumbnails (<40 KB); fetchpriority="high" on top 4 images |
| **Time to Interactive (TTI)** | < 2.5s | **< 3.0s** | +250ms | Lighthouse Mobile | Simulated mid-range mobile CPU (4x slowdown) | Zero heavy UI frameworks; deferred Supabase Realtime client initialization |
| **Total Page Weight (JS Bundle)**| < 200 KB | **< 300 KB (gzipped)** | +25 KB | `@next/bundle-analyzer` | Production production build artifact inspection | System font stack; vanilla React hooks; no moment.js or heavy dependencies |
| **Cumulative Layout Shift (CLS)**| < 0.05 | **< 0.10** | +0.02 | Chrome DevTools Layout Shift | Standard mobile viewport (360×800) | Explicit aspect-ratio containers (`aspect-square`) on all image tiles |
| **Total Blocking Time (TBT)** | < 150ms | **< 250ms** | +50ms | Lighthouse Performance Score | 4x CPU throttling | Lightweight state updates via standard React state |

---

### 2.2 Seller Mobile App (Flutter Native Android)

| Metric | Target | Pass/Fail Threshold | Acceptable Tolerance | Measurement Tool | Test Environment & Conditions | Optimization Strategy |
|---|---|---|---|---|---|---|
| **Full Item Ingestion Cycle** | < 20s | **< 30s per item** | +5s | Stopwatch / Screen Recording | Physical Redmi 9A / Realme C-series Android device | Immediate camera reset; background non-blocking upload queue |
| **Client Image Compression Time**| < 350ms | **< 600ms** | +100ms | Flutter DevTools Timeline | 12MP camera photo to 1:1 square WebP | Native `flutter_image_compress` using C++ libjpeg/libwebp binaries |
| **Compressed Image Size** | < 180 KB | **< 250 KB** | +20 KB | Android File System Stat | 1000×1000 square WebP image at 75% quality | Balanced compression ratio for garment fabric clarity |
| **PDF Label Render Latency** | < 600ms | **< 1000ms** | +150ms | Flutter Stopwatch Stopwatch | Vector 4×6 inch thermal layout with barcode | Pure vector rendering via `pdf` package; no heavy raster operations |
| **Order Realtime Push Latency** | < 1.0s | **< 2.0s** | +500ms | Client-Server Timestamp Delta | Active WebSocket connection over 4G | Supabase Realtime direct PostgreSQL changefeed |
| **App Cold Start Latency** | < 1.5s | **< 2.5s** | +300ms | `adb shell am start -W` | Physical device, cold cache after reboot | Lazy-load PDF and Bluetooth printing modules |

---

### 2.3 Database & Cloud Transaction Performance

| Metric | Target | Pass/Fail Threshold | Acceptable Tolerance | Measurement Tool | Test Environment & Conditions | Optimization Strategy |
|---|---|---|---|---|---|---|
| **`create_order_with_reservation`**| < 250ms | **< 500ms** | +100ms | `pg_stat_statements` / k6 | 50 concurrent checkout transactions | Indexed row locking (`ORDER BY id`); single ACID transaction |
| **`release_expired_holds` Cron** | < 100ms | **< 300ms** | +50ms | PostgreSQL execution plan | Scans 1,000 pending orders | Partial index on `orders(hold_expires_at) WHERE status = 'pending'` |
| **Catalog Feed PostgREST Latency** | < 80ms | **< 150ms** | +30ms | Postman / curl benchmarks | Edge query from Indian region (BOM / HYD) | Composite index on `products(drop_id, status)` |

---

## 3. Analysis of Difficult-to-Guarantee Targets

1. **WhatsApp Launch Latency (< 1.0s):**
   * *Assessment:* **Difficult to Guarantee**.
   * *Reason:* Launching an external native app from an embedded webview (e.g. Facebook In-App Browser) depends entirely on host OS intent-resolution speed, device RAM availability, and whether WhatsApp is already running in background memory.
   * *Mitigation:* LiveDrop guarantees the URL is constructed and fired in `< 50ms`; fallback `/order/[id]` screen ensures buyer never gets stranded.
2. **Bluetooth ESC/POS Print Latency (< 1.0s):**
   * *Assessment:* **Unrealistic Across All Budget Printers**.
   * *Reason:* Budget thermal printers in India communicate over Bluetooth 2.1/4.0 SPP with low baud rates (9600–115200 bps). Sending a rasterized image label can take 2–3 seconds over serial.
   * *Mitigation:* Render using pure ESC/POS vector text and 1D barcode commands rather than bitmap streaming.
