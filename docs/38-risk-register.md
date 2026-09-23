# LiveDrop — Comprehensive Risk Register

## 1. Risk Classification Matrix
Risks are evaluated on Likelihood (Low, Medium, High) and Impact (Low, Medium, High), resulting in an overall Severity rating (**CRITICAL**, **HIGH**, **MEDIUM**, **LOW**).

```
IMPACT      LOW      MEDIUM    HIGH
LIKELIHOOD
HIGH        Medium   High      CRITICAL
MEDIUM      Low      Medium    HIGH
LOW         Low      Low       Medium
```

---

## 2. Risk Log

| Risk ID | Category | Risk Description | Likelihood | Impact | Severity | Trigger / Indicator | Mitigation Strategy | Owner | Contingency Plan |
|---|---|---|---|---|---|---|---|---|---|
| **RSK-CONC-01** | Data Integrity | **Deadlock during concurrent multi-item reservations** | High | High | **CRITICAL** | PostgreSQL `40P01` deadlock detected errors under load | Sort all product IDs in ascending UUID order before acquiring `FOR UPDATE` row locks in checkout RPC. | Database Architect | Retry with exponential backoff on client side. |
| **RSK-DATA-02** | Data Integrity | **Client-Side Price Manipulation** | Medium | High | **CRITICAL** | Order subtotal does not match sum of DB product prices | Order subtotal and shipping are computed strictly inside PostgreSQL RPC from stored row prices; client price inputs are discarded. | Backend Engineer | Reject transaction if client payload attempts to inject total. |
| **RSK-SEC-03** | Security | **Public Order Scraping / Buyer PII Exposure** | High | High | **CRITICAL** | Sequential ID scanning or unauthorized order query | Replace public order access with high-entropy UUIDv4 `order_token`. RLS requires matching token to read order details. | Security Engineer | Revoke token and alert admin if brute-force attempts detected. |
| **RSK-EXT-04** | External Dep | **WhatsApp Deep-Link (`wa.me`) In-App Browser Block** | High | Medium | **HIGH** | Buyer taps "Send Order via WhatsApp" inside Instagram/FB browser and link fails to trigger app | Detect in-app webview; provide copyable text box, UPI QR code modal, and native intent fallback buttons on the webfront. | Frontend Lead | Fallback to manual UPI payment screen with seller WhatsApp number displayed. |
| **RSK-OPS-05** | Operational | **Contested Payment on Expired Hold** | Medium | High | **HIGH** | Seller clicks "Mark Paid" on order that expired 10 minutes ago | `mark_order_paid` RPC validates whether product was reclaimed by another buyer before updating status. | Lead Architect | Seller contacted via UI alert to issue refund or offer alternative SKU. |
| **RSK-COST-06** | Cost / Limits | **Supabase Egress Bandwidth Exhaustion (2 GB Cap)** | Medium | High | **HIGH** | High-volume drop with 500+ attendees downloading raw 2MB photos | Client-side image compression in Flutter to WebP/JPEG (< 200 KB) + Cloudflare CDN proxy with aggressive 1-year cache headers. | DevOps Engineer | Temporarily upgrade to Supabase Pro ($25/mo) if drop exceeds quota. |
| **RSK-PERF-07** | Performance | **Slow Realtime Updates during Flash Spike** | Medium | Medium | **MEDIUM** | Realtime socket drops or latency > 3 seconds | Periodic fallback HTTP polling (every 10s) on buyer webfront when socket drops or reconnects. | Frontend Lead | Buyer web relies on checkout RPC as ultimate source of truth. |
| **RSK-MOB-08** | UX / Mobile | **Camera Lag & Crash during Rapid 50-Item Ingestion** | Medium | Medium | **MEDIUM** | Flutter memory spike or OOM crash during batch photography | Isolate image compression in background Flutter Isolate (`compute()`); do not keep high-res uncompressed bitstreams in RAM. | Mobile Engineer | Restart app; SQLite queue preserves already photographed items. |
| **RSK-PRIV-09** | Privacy | **Customer PII Retained Indefinitely on Disk** | High | Medium | **HIGH** | Regulatory audit under India DPDP Act 2023 | 180-day automated purge policy for completed order PII; explicit privacy disclosure on checkout bottom-sheet. | Compliance Lead | Manual purge function executable by seller from profile settings. |
| **RSK-HW-10** | Hardware | **Thermal Bluetooth Printer Connection Incompatibility** | High | Medium | **HIGH** | Seller's printer rejects raw ESC/POS commands | Generate standard vector PDF 4×6 inch and route through Android Print Framework or PDF share. | Mobile Lead | Seller prints from laptop/desktop via shared PDF. |
| **RSK-SEC-11** | Security | **Unapproved Seller Self-Service Drop Publication & Fraud** | High | High | **CRITICAL** | Fraudulent actor registers and publishes drop before KYC | `profiles.is_approved` column defaulted to `FALSE`; `trg_enforce_drops_seller_approval` trigger blocks drop publication until `admin_approve_seller` RPC executed via service role. | Security Lead | Unapproved sellers routed to holding screen with admin WhatsApp hotline. |
| **RSK-BUY-12** | Data Access | **Anonymous Buyer Catalog Access Blocked (PostgREST 42501)** | High | High | **CRITICAL** | Anonymous buyer cannot view drop catalog due to raw `profiles` join | `buyer-catalog.ts` rewired to query `public_seller_storefronts` view; raw `profiles` access eliminated for unauthenticated callers. | Frontend Lead | Read-only projection view masks PII while returning branding. |
| **RSK-ORD-13** | Concurrency | **Checkout Retry Cart Collision / Desynchronization** | Medium | High | **HIGH** | Browser reload / network retry causes duplicate orders or false `STOCK_UNAVAILABLE` | SHA-256 payload fingerprinting + `sessionStorage` key persistence; `create_order_with_reservation` returns existing order for identical payload or rejects conflict. | Backend Engineer | Client recovers original order token and receipt seamlessly. |
| **RSK-SYNC-14** | Reliability | **Anonymous Buyer Misses Realtime Payment Verification CDC** | High | Medium | **HIGH** | WebSocket CDC drops events due to absent `x-order-token` in WAL replication | Dual-mode synchronization: Realtime CDC push + 3-second adaptive bounded polling fallback on visibility/focus resume. | Frontend Lead | Terminal state check terminates polling once order is paid/rejected. |
| **RSK-PAY-15** | Financial | **Late UPI Transfer After Reservation Window Expiry** | Medium | High | **HIGH** | Buyer launches payment before 15m expires, submits UTR after hold released | `023_late_upi_recovery.sql` creates `unmatched_payment_claims` audit log; auto-extends hold if inventory free, or creates dispute ticket for seller resolution. | Payments Lead | Seller manual verification/refund workflow without money stranding. |
| **RSK-DROP-16** | Operational | **Active Reservations Stranded on Abrupt Drop Closure** | Medium | High | **HIGH** | Seller closes drop while orders are awaiting UTR verification | `close_drop` RPC preserves confirmed holds and pending verification orders; releases only available stock. | Database Architect | Reaper processes unverified holds past deadline. |
| **RSK-INT-17** | Data Loss | **Seller Photography Lost on Cellular Disconnect** | High | High | **HIGH** | Mobile app process death or network loss during batch camera intake | Disk-first persistence in `offline_intake_queue.dart`: raw bytes written to flash storage before upload, exponential backoff background sync. | Mobile Lead | Unsynced queue UI with manual retry and background worker. |
| **RSK-INV-18** | Data Integrity | **Seller Altering Price/Details on Reserved or Sold Garment** | Medium | High | **CRITICAL** | Seller modifies product price after buyer has reserved or paid | `025_product_editing.sql` trigger `enforce_products_inventory_immutability` blocks title/price/size mutations on `reserved` or `sold` items; `update_product` RPC allows edits only on `available` stock. | Database Architect | Rejects mutation with SQLSTATE `42501`. |
| **RSK-FUL-19** | Logistics | **Order Shipped Without Packing or Settlement Verification** | Medium | High | **HIGH** | Seller attempts premature dispatch of unpaid or unpacked order | `mark_order_ready_to_ship` RPC enforces `payment_status = 'paid'` and sets `packed_at`; `mark_order_shipped` enforces `fulfilment_status = 'ready_to_ship'`. | Backend Engineer | Order Kanban board enforces strict state progression. |

---

## 3. Risk Monitoring & Escalation Protocol
1. **Trigger Review**: Any trigger event logged in production or staging automatically halts release until resolved.
2. **Weekly Risk Audit**: Lead Architect reviews error logs, Supabase bandwidth metrics, and customer drop feedback.
