# 24 — Observability, Logging & Telemetry Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Observability Architecture & Standards

LiveDrop implements a zero-overhead observability model designed to operate within cloud free tiers while providing complete visibility into business transactions, concurrency collisions, and error spikes.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         OBSERVABILITY ARCHITECTURE                          │
├───────────────────────┬─────────────────────────────┬───────────────────────┤
│ Surface 1: Buyer Web  │ Surface 2: Supabase Backend │ Surface 3: Seller APK │
├───────────────────────┼─────────────────────────────┼───────────────────────┤
│ • Structured Console  │ • PostgreSQL Query Logs     │ • Flutter Local Logs  │
│ • Client Performance  │ • Auth & Storage Audit Logs │ • Crash Handler       │
│ • Sentry Crash Tracker│ • Supabase Dashboard Metrics│ • Sync Queue Logger   │
└───────────────────────┴─────────────────────────────┴───────────────────────┘
```

---

## 2. Structured Event Schema

All log entries across web and mobile surfaces follow a standard JSON schema:

```json
{
  "timestamp": "2026-09-11T14:32:00.124Z",
  "level": "INFO | WARN | ERROR",
  "surface": "BUYER_WEB | SELLER_APP | SUPABASE_RPC",
  "event_type": "CHECKOUT_INITIATED | COLLISION_DETECTED | ORDER_RESERVED | PAYMENT_CONFIRMED",
  "drop_id": "c1f76d42-4f36-4d2b-9801-b5e1cf3e6801",
  "order_code": "LD-8F42",
  "latency_ms": 245,
  "payload_metadata": {
    "item_count": 2,
    "subtotal": 2600.00
  },
  "error_details": null
}
```

---

## 3. Privacy-Safe Logging & PII Sanitization

> [!CRITICAL]
> **Strict Zero-PII Log Standard:** No customer name, WhatsApp phone number, street address, or full UPI ID may ever appear in log streams, console messages, or external crash telemetry.

### Sanitization Implementation
```typescript
export function sanitizeLogMetadata(data: Record<string, any>): Record<string, any> {
  const safe = { ...data };
  // Redact customer phone numbers
  if (safe.buyer_phone) {
    safe.buyer_phone = safe.buyer_phone.slice(0, 2) + 'XXXXXX' + safe.buyer_phone.slice(-2);
  }
  // Strip physical home addresses
  if (safe.shipping_address) {
    safe.shipping_address = '[REDACTED_ADDRESS]';
  }
  // Mask customer names
  if (safe.buyer_name) {
    safe.buyer_name = safe.buyer_name[0] + '***';
  }
  return safe;
}
```

---

## 4. Key Operational Metrics & Alerting Thresholds

| Metric | Source | Warning Threshold | Critical Incident Threshold | Recommended Remediation |
|---|---|---|---|---|
| **Checkout Stock Collision Rate** | RPC Logs | > 15% of checkout requests | > 35% of checkout requests | High stream concurrency. Normal for single-piece inventory; verify UI properly renders red contested modal. |
| **RPC Execution Latency** | `pg_stat_statements` | P95 > 500ms | P95 > 1,500ms | Inspect database locks, query plan degradation, or unindexed foreign keys. |
| **Realtime Connection Count** | Supabase Dashboard | > 150 concurrent conns | > 190 concurrent conns (near 200 free tier limit) | Trigger automated tab-sleep throttling; prepare for tier upgrade if audience grows. |
| **Storage Egress Bandwidth** | Cloudflare / Supabase | > 1.5 GB monthly (75%) | > 1.9 GB monthly (95%) | Verify CDN cache hit ratio; adjust Cache-Control max-age to 1 year immutable. |
| **Database Disk Storage** | Supabase Dashboard | > 350 MB (70%) | > 450 MB (90% of 500 MB) | Execute archiving routine on closed drops older than 6 months. |
| **Seller Ingestion Queue Errors** | Flutter Local Log | > 3 failed uploads | > 10 failed uploads | Check cellular network or Supabase Storage bucket write permissions. |

---

## 5. Health Monitoring & Keepalive Architecture

To counteract the Supabase Free Tier policy that automatically pauses projects after 7 days of inactivity:
* **Automated Keepalive Probe:** A lightweight GitHub Actions cron workflow or free external service (e.g., cron-job.org) issues an anonymous `GET /rest/v1/profiles?select=id&limit=1` request every **24 hours**.
* **Health Check Endpoint:** Verifies database responsiveness, returning `200 OK` and active timestamp.
