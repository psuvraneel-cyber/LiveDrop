# 20 — Error Taxonomy & Failure Recovery Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Error Handling Philosophy

1. **Graceful Degradation:** A failure in non-critical components (e.g. WebSocket realtime, Bluetooth printing) must never halt primary commerce flows (catalog browsing, checkout, order intake).
2. **Defensive Messaging:** User-facing errors must be transparent, actionable, and non-technical. Avoid raw database or HTTP codes in UI dialogs.
3. **Automated Recovery:** Cellular networks fluctuate. Applications must implement exponential backoff, background queue retries, and state reconciliation automatically without requiring manual page reloads.

---

## 2. Comprehensive Failure Mode Taxonomy

| # | Failure Mode | Technical Behavior | User-Facing Behavior | Recovery Mechanism | Retry Policy | Telemetry & Logging |
|---|---|---|---|---|---|---|
| **01** | **No Network (Offline)** | Network request throws connection error (DNS / TCP timeout). | Offline banner: *"No internet connection. Waiting for network..."* | Client detects `navigator.onLine` / connectivity events; resumes automatically when online. | Exponential backoff: 1s, 2s, 4s, 8s up to 30s. | Local error event logged. |
| **02** | **Slow Network (High Jitter 4G)** | HTTP request takes > 5 seconds; image download throttled. | Skeleton placeholders persist; button shows progress spinner: *"Securing pieces..."*. | Image CDN serves progressive WebP; client caches thumbs in service worker. | Timeout set to 15s before aborting. | Network duration logged to performance metrics. |
| **03** | **Supabase Outage (503 Service Unavailable)** | REST and RPC calls return HTTP 500/503. | High-priority banner: *"Service is experiencing high traffic. Please wait a moment."* | Fallback to cached catalog if available; retry checkout after delay. | 3 retries with jittered backoff. | Logged to external error tracker. |
| **04** | **Checkout RPC Timeout** | Database transaction exceeds 10-second statement timeout. | Modal: *"Server took too long to respond. Checking order status..."* | Client executes idempotent status check via `order_token` before re-attempting. | 1 retry after 3-second delay. | Transaction duration logged to PostgreSQL slow query log. |
| **05** | **Checkout Partial Collision** | RPC detects 1 of 3 items locked by another viewer; returns `STOCK_UNAVAILABLE`. | Modal: *"Item #A01 was just reserved by another buyer."* Contested item outlined in red with `[Remove]` button. | Buyer removes contested item; remaining 2 items and entered address remain intact. | Manual re-submission by user. | Conflict metric incremented. |
| **06** | **Realtime Disconnect** | WebSocket drops heartbeat (ping/pong failure). | Subtle indicator changes from `● Connected` to `○ Reconnecting...`. | Client attempts automatic reconnect; executes full catalog REST snapshot upon re-establishment. | Exponential backoff: 1s, 2s, 5s, 10s. | Reconnection attempt logged to client console. |
| **07** | **WhatsApp Redirect Blocked (In-App Browser)** | Facebook or Chrome webview suppresses automatic `window.location = wa.me`. | Navigates to `/order/[id]` receipt screen with explicit `[ Open WhatsApp Now ]` CTA button. | Buyer clicks button manually to launch WhatsApp. | User-driven tap. | Redirect block event recorded in client telemetry. |
| **08** | **Buyer Closes WhatsApp Without Sending** | Order already persisted in Supabase with `pending` status. | None (buyer abandoned WhatsApp). | Seller sees order on Kanban board with buyer phone; can initiate chat directly or wait for 15m hold to expire. | None. Hold auto-expires at 15m. | Order created event preserved. |
| **09** | **Seller Phone Dies / Closes App** | Flutter app process killed by Android OS. | None. In-flight background uploads cached in local SQLite/Hive database. | On next app launch, background worker inspects queue and resumes pending uploads. | Automatic on app startup. | Crash/kill logged locally. |
| **10** | **Hold Expires While Seller Reviews Payment** | Cron marks order `cancelled` and products `available`. | Seller taps "Mark as Paid"; RPC checks for contested reclaim. | If contested: rejects with `PRODUCT_ALREADY_RECLAIMED`. If uncontested: re-locks and marks `paid`. | Seller reviews chat; refunds or delivers. | Conflict event logged in audit table. |
| **11** | **Invalid Product ID in Request** | Malformed UUID passed in `p_product_ids`. | Toast error: *"Invalid garment selected. Please refresh your cart."* | Client purges invalid item from cart. | No retry. | Warning logged. |
| **12** | **Stale Product Display** | Buyer carts item displayed as available on stale tab, but locked minutes ago. | RPC rejects checkout with `STOCK_UNAVAILABLE`. | Contested item marked reserved; catalog reconciles. | User removes item. | Normal conflict metric. |
| **13** | **Image Upload Failure (Seller App)** | Image upload to Supabase Storage fails due to cellular dip. | Ingestion screen shows badge: *"1 upload queued offline"*; camera resets smoothly. | Background upload worker retries upload when cellular signal strengthens. | Auto-retry every 15s in background. | Upload failure logged. |
| **14** | **Image Compression Crash** | Corrupt bitmap or out-of-memory during WebP compression. | Toast: *"Failed to process photo. Please retake."* | Viewfinder re-opens camera for immediate retake. | Immediate user retake. | Fatal image error logged. |
| **15** | **Duplicate Rapid Button Taps** | Buyer taps "Confirm" 5 times in 1 second. | Button disabled on first tap; shows spinner. | Frontend disables pointer events. Backend RPC utilizes transaction locks. | Discard duplicate taps. | Ignored. |
| **16** | **PDF Generation Crash** | Out of memory or font missing during 4×6 label rendering. | Dialog: *"Could not render PDF label. Retrying..."* | Falls back to simplified plain-text label layout. | 1 retry with simplified vector. | PDF exception logged with stack trace. |
| **17** | **Bluetooth Thermal Printer Disconnect** | Printer runs out of paper, battery dies, or Bluetooth drops. | Alert dialog: *"Bluetooth printer disconnected. Reconnect or share PDF."* | Provides instant `[ Share PDF to WhatsApp ]` fallback. | User re-pairs or prints via system spooler. | Bluetooth socket error logged. |
| **18** | **No Printer Available** | Boutique does not own a Bluetooth thermal printer. | Screen offers `[ Print via System ]` or `[ Share to WhatsApp ]`. | Native Android Print Spooler or share PDF to laptop/shop printer. | N/A (Feature Fallback). | None. |
| **19** | **Corrupted Local Upload Queue** | Local Hive/SQLite database file corrupted by abrupt power loss. | App alerts: *"Local queue error. Checking cloud inventory."* | App wipes corrupted queue table and pulls ground truth from Supabase. | Automatic on error catch. | Critical database recovery event logged. |
| **20** | **Malformed Seller Phone Number** | Seller entered phone with spaces, symbols, or invalid digits. | Profile edit screen highlights phone in red; blocks drop publishing. | Seller corrects phone number in profile settings. | Block until valid E.164. | Validation error logged. |
| **21** | **Invalid Seller UPI ID** | Malformed VPA (e.g. missing `@` domain). | Profile edit screen blocks saving: *"Invalid UPI ID format."* | Seller enters valid VPA (e.g., `store@okaxis`). | Block until valid. | Validation error logged. |
| **22** | **App Crash During State Transition** | Phone shuts down while seller marks order "Paid". | When phone turns back on, app re-syncs state from Supabase. | Database transaction is atomic: either committed or rolled back. | Re-reads state from cloud. | App lifecycle log recorded. |
| **23** | **Malicious Script Injection in Address** | Buyer pastes `<script>alert(1)</script>` or SQL injection. | Sanitized cleanly by server; stored as raw escaped text. | Displayed as plain text on label and Kanban card. | N/A. | Security warning logged. |
| **24** | **Drop Closed During Active Live Stream** | Seller accidentally taps "Close Drop" while viewers are browsing. | Confirmation dialog requires explicit double-tap: *"Are you sure you want to end this live drop?"*. | If confirmed, viewers see "Broadcast ended". Existing reservations finish normally. | Seller must create a new drop if closed. | Drop lifecycle logged. |
