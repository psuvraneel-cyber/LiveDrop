# 18 — Privacy, PII Protection & Data Governance: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Security Architecture:** [`docs/16-security-architecture.md`](file:///c:/LiveDrop/docs/16-security-architecture.md)  

---

## 1. Regulatory Context & Privacy Principles

LiveDrop handles personal customer fulfillment data across India. It complies with the **Digital Personal Data Protection (DPDP) Act of 2023** by adhering to four core privacy principles:
1. **Data Minimization:** Collect only the exact data required to physically package and deliver parcels (Full Name, WhatsApp Phone, Street Address, Pincode). No GPS tracking, no birthdates, no payment card details, and no biometric data.
2. **Purpose Limitation:** Customer contact and delivery information is used strictly for fulfilling orders and communicating parcel tracking. Never sold, shared with third parties, or monetized for advertising.
3. **Storage Limitation & Right to Erasure:** Customers have the right to request purge of their delivery records.
4. **Zero Telemetry Leakage:** Personally Identifiable Information (PII) is strictly prohibited from analytics logs, console statements, error trackers, or unencrypted URLs.

---

## 2. Personal Data Inventory

| Data Field | Category | Collection Purpose | Storage Location | Retention Period | Access Controls |
|---|---|---|---|---|---|
| **Buyer Full Name** | Direct PII | Addressed recipient on parcel shipping label | PostgreSQL `orders.buyer_name`, browser `localStorage` | 180 days post-dispatch (for return/tax audit) | Owning seller via JWT; buyer via `order_token` |
| **WhatsApp Phone** | Sensitive PII | Direct communication, order verification, courier updates | PostgreSQL `orders.buyer_phone`, browser `localStorage` | 180 days post-dispatch | Owning seller via JWT; buyer via `order_token` |
| **Street Address** | Sensitive PII | Physical parcel delivery | PostgreSQL `orders.shipping_address`, browser `localStorage` | 180 days post-dispatch | Owning seller via JWT; buyer via `order_token` |
| **Pincode** | Location PII | Logistics routing & courier dispatch | PostgreSQL `orders.pincode`, browser `localStorage` | 180 days post-dispatch | Owning seller via JWT; buyer via `order_token` |
| **Seller Business Phone** | Business Info | Buyer WhatsApp handoff & return address | PostgreSQL `profiles.phone_number` | Active boutique account lifetime | Publicly visible on catalog & shipping slips |
| **Seller UPI ID (VPA)** | Financial Info | Direct P2P payments | PostgreSQL `profiles.upi_id` | Active boutique account lifetime | Publicly visible on catalog & checkout screen |

---

## 3. Client-Side `localStorage` Governance

### 3.1 UX Convenience vs Shared Device Privacy
To ensure frictionless repeat buying, the buyer webfront automatically stores delivery details in the client's browser:
```json
// Key: 'livedrop_buyer_profile'
{
  "name": "Sangeeta Mukherjee",
  "phone": "9830123456",
  "pincode": "700032",
  "address": "Flat 4B, Greenview Apts, Jadavpur"
}
```

### 3.2 Privacy Safeguards
1. **Clear Saved Details Action:** The cart drawer must prominently display a `[Clear Saved Details]` link whenever pre-filled data is detected. Clicking it immediately executes `localStorage.removeItem('livedrop_buyer_profile')`.
2. **Zero Financial Storage:** Payment information, UPI pins, bank details, and transaction IDs are **never** stored in `localStorage`.
3. **Session Secret Isolation:** Order receipt tokens (`order_token`) are stored in `sessionStorage` (purged when browser tab closes), preventing subsequent users on shared family devices from reopening past receipts.

---

## 4. Exposure Boundaries & URL Governance

* **No PII in Query Parameters:** Customer names, phone numbers, and addresses must **never** appear in GET query parameters of the web application (`https://domain/order/123?name=...` is strictly forbidden).
* **WhatsApp Deep Link Exception:** The WhatsApp deep link (`wa.me`) explicitly encodes recipient details into the pre-filled text parameter (`text=...`). This is secure because:
  * The link is opened directly into the user's native WhatsApp client on the device.
  * WhatsApp applies end-to-end encryption to the chat payload upon sending.
  * The URL is generated ephemerally on the client device and never sent to or logged by the LiveDrop web server.

---

## 5. Logging, Telemetry & Observability Redaction

All application logging frameworks (Next.js server logs, Flutter console logs, Supabase database query logs) must enforce automated PII redaction:

```typescript
// Sanitization utility for structured logging
export function sanitizeLogData(data: Record<string, any>): Record<string, any> {
  const sanitized = { ...data };
  if (sanitized.buyer_phone) {
    sanitized.buyer_phone = sanitized.buyer_phone.slice(0, 2) + 'XXXXXX' + sanitized.buyer_phone.slice(-2);
  }
  if (sanitized.shipping_address) {
    sanitized.shipping_address = '[REDACTED_ADDRESS]';
  }
  if (sanitized.buyer_name) {
    sanitized.buyer_name = sanitized.buyer_name[0] + '***';
  }
  return sanitized;
}
```

* **Rules:**
  * Never output customer phone numbers, street addresses, or names in `console.log` or Sentry crash logs.
  * Database logs (`pg_stat_statements`) must bind customer PII via parameterized query variables (`$1, $2`), preventing PII from appearing in query plan logs.

---

## 6. Test Data & Development Governance

1. **Synthetic Data Mandate:** Under no circumstances may real customer names, genuine home addresses, or actual boutique phone numbers be copied into local test files, seed files (`seed.sql`), or test cases.
2. **Standardized Synthetic Vectors:**
   * Names: "Sangeeta Mukherjee", "Priya Sharma", "Rohan Das"
   * Phones: `9830100001`, `9830100002` (reserved test series)
   * Addresses: "Flat 4B, Greenview Apartments, Near South City, Jadavpur, Kolkata - 700032"
   * UPI IDs: `testboutique@okaxis`, `buyer@okhdfcbank`
3. **Repository Cleanliness:** No production order exports, customer CSVs, or backup dumps may ever be committed to git.
