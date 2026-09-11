# 17 — Threat Model & Attack Surface Analysis (STRIDE): LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Security Architecture:** [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)  

---

## 1. Threat Modeling Methodology

This threat model uses the **STRIDE** methodology (Spoofing, Tampering, Repudiation, Information Disclosure, Denial of Service, Elevation of Privilege) to systematically identify, categorize, and mitigate attack vectors targeting the LiveDrop ecosystem.

```
                    ┌───────────────────────────────┐
                    │      Attacker Profiles        │
                    ├───────────────────────────────┤
                    │ • Malicious Viewer / Buyer    │
                    │ • Competitor Scraper / Bot    │
                    │ • Network Attacker (Man-in-M) │
                    │ • Disgruntled Seller / Insider│
                    └───────────────┬───────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          LIVEDROP ATTACK SURFACES                           │
├───────────────────────┬─────────────────────────────┬───────────────────────┤
│ Surface 1: Buyer Web  │ Surface 2: Supabase APIs    │ Surface 3: Seller APK │
│ • Catalog URL         │ • PostgREST Endpoints       │ • Sideloaded binary   │
│ • Floating cart form  │ • Database RPC Functions    │ • Local storage cache │
│ • WhatsApp redirect   │ • Realtime WebSockets       │ • Camera & Print link │
└───────────────────────┴─────────────────────────────┴───────────────────────┘
```

---

## 2. STRIDE Threat Analysis Matrix

### 2.1 Spoofing (Identity Deception)

| Threat ID | Threat Vector & Description | Target Asset | Severity | Mitigation & Defense Mechanism |
|---|---|---|---|---|
| **THR-SPOOF-01** | Attacker spoofs another buyer's browser session to claim or hijack their active reservation. | `products.reserved_by_order_id` | **HIGH** | Reservations are owned strictly by database `orders.id` coupled with a cryptographic `order_token` (UUIDv4), not by client-controlled session cookies. |
| **THR-SPOOF-02** | Attacker impersonates the seller to mark unpaid orders as "Paid". | `orders.status` | **CRITICAL** | `mark_order_paid` RPC verifies `auth.uid() = drops.seller_id`. Public anonymous users cannot execute this function. |
| **THR-SPOOF-03** | Attacker submits fake phone numbers to lock catalog items. | `orders.buyer_phone` | **MEDIUM** | Strict regex validation (`^[6-9]\d{9}$`). 15-minute automatic expiration frees held inventory quickly if payment is not initiated. |

---

### 2.2 Tampering (Data Modification)

| Threat ID | Threat Vector & Description | Target Asset | Severity | Mitigation & Defense Mechanism |
|---|---|---|---|---|
| **THR-TAMP-01** | Malicious buyer modifies order `total_amount` in client memory to pay ₹1 for a ₹2,000 saree. | `orders.total_amount` | **CRITICAL** | Subtotal is computed exclusively on the server: `SELECT SUM(price) FROM products WHERE id = ANY(p_product_ids)`. Client-supplied totals are completely discarded. |
| **THR-TAMP-02** | Buyer modifies shipping fee in web client. | `orders.shipping_amount` | **HIGH** | Shipping is computed authoritatively from the seller's `profiles` shipping policy within the database transaction. |
| **THR-TAMP-03** | Attacker injects malicious scripts or HTML into the delivery address field (Stored XSS). | Seller Kanban & Courier Slip | **HIGH** | Inputs sanitized; React/Next.js automatically escapes text nodes; Flutter PDF generator treats strings as raw text without HTML evaluation. |
| **THR-TAMP-04** | Attacker injects malicious parameters into WhatsApp `wa.me` deep link. | Buyer WhatsApp Client | **MEDIUM** | Strict `encodeURIComponent()` encoding and `%0A` newline normalization. Length capped at 2,000 characters. |

---

### 2.3 Repudiation (Denial of Action)

| Threat ID | Threat Vector & Description | Target Asset | Severity | Mitigation & Defense Mechanism |
|---|---|---|---|---|
| **THR-REP-01** | Buyer claims they never placed an order or disputes the address on the courier label. | Order Record & WhatsApp DM | **MEDIUM** | Order record permanently captures `buyer_phone`, `shipping_address`, and `created_at`. The pre-filled WhatsApp chat provides an immutable bilateral communication audit log. |
| **THR-REP-02** | Seller claims customer paid less than required. | Order & Payment Receipt | **LOW** | 4×6 shipping label and WhatsApp message display exact line-item breakdown, subtotal, and shipping fee. |

---

### 2.4 Information Disclosure (Privacy Leaks)

| Threat ID | Threat Vector & Description | Target Asset | Severity | Mitigation & Defense Mechanism |
|---|---|---|---|---|
| **THR-INFO-01** | Competitor or scraper enumerates `/rest/v1/orders` to steal customer names, phone numbers, and home addresses. | Customer PII | **CRITICAL** | RLS policy strictly denies unauthenticated `SELECT` on `orders` without a matching secret `order_token`. Enumeration returns `404 / 403`. |
| **THR-INFO-02** | Attacker guesses sequential order codes (`LD-1001`, `LD-1002`) to harvest buyer details. | Order Verification | **HIGH** | Order codes use randomized 4-character uppercase alphanumeric suffixes (`LD-7K92`). Search space ($36^4 \approx 1.68 \times 10^6$) prevents brute-force enumeration. |
| **THR-INFO-03** | Public Realtime channel broadcasts identity of customer reserving items. | Realtime Payload | **HIGH** | Product Realtime publication broadcasts only `{ id, code, price, status, reserved_at }`. Columns `reserved_by_order_id` are excluded from the public publication. |

---

### 2.5 Denial of Service (Availability Disruption)

| Threat ID | Threat Vector & Description | Target Asset | Severity | Mitigation & Defense Mechanism |
|---|---|---|---|---|
| **THR-DOS-01** | Competitor runs an automated script to place orders for all 40 products in a live drop, locking the entire collection for 15 minutes. | Catalog Availability | **HIGH** | IP-based rate limiting on checkout RPC (max 5 orders per 15 mins per IP). 15-minute reaper quickly releases unconfirmed orders. Seller can force-release holds via long-press in app. |
| **THR-DOS-02** | Attacker spams unauthenticated WebSocket connections to exhaust Supabase free tier connection limit (200 conns). | Realtime Service | **HIGH** | Idle client tabs disconnect WebSockets after 60 seconds of background visibility. Catalog falls back to REST polling if WebSocket capacity is exceeded. |
| **THR-DOS-03** | Attacker downloads high-res images in an infinite loop to exhaust 2 GB storage bandwidth quota. | Image Storage Egress | **HIGH** | Images served via Cloudflare CDN caching layer with `Cache-Control: public, max-age=31536000, immutable`. CDN absorbs repeat hits at zero cost. |

---

### 2.6 Elevation of Privilege

| Threat ID | Threat Vector & Description | Target Asset | Severity | Mitigation & Defense Mechanism |
|---|---|---|---|---|
| **THR-ELEV-01** | Attacker exploits missing `search_path` on `SECURITY DEFINER` functions to execute commands as database superuser. | PostgreSQL Database | **CRITICAL** | All `SECURITY DEFINER` functions explicitly set `SET search_path = public, pg_temp;`. |
| **THR-ELEV-02** | Unauthenticated user calls seller management functions directly. | Seller Management RPCs | **CRITICAL** | Management RPCs execute `REVOKE EXECUTE FROM PUBLIC, anon;` and verify `auth.uid() = drop.seller_id`. |
| **THR-ELEV-03** | Reverse engineer extracts service role key from Flutter APK binary or Next.js JS bundle. | Supabase Admin API | **CRITICAL** | `SERVICE_ROLE_KEY` is strictly prohibited from client repositories and build pipelines. Only public `anon` key is distributed. |
