# 33 — MVP Scope, MoSCoW Prioritization & Roadmap: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent PRD:** [`docs/02-prd.md`](file:///c:/LiveDrop/docs/02-prd.md)  

---

## 1. Scope Management Philosophy

The primary objective of LiveDrop MVP is **operational validation with a single real-world home boutique ("User Zero")**. To ensure fast execution at ₹0 cost, features are strictly categorized using the **MoSCoW** (Must, Should, Could, Won't) framework.

> [!CRITICAL]
> **Anti-Scope-Creep Invariant:** Multi-boutique SaaS billing, payment gateway integrations, consumer account creation, and automated courier API pickups are **strictly deferred** from MVP.

---

## 2. MoSCoW Scope Classification

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            MOSCOW PRIORITIZATION                            │
├──────────────────────────────────────┬──────────────────────────────────────┤
│ 1. MUST-HAVE (MVP Core)              │ 2. SHOULD-HAVE (Post-MVP Polish)     │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ • Zero-download Next.js catalog link │ • Multi-item category filter tabs    │
│ • Bold Flash Code overlays (#A01)    │ • Customer order history search by   │
│ • Sticky cart bar & delivery drawer  │   phone number in seller app         │
│ • Unified atomic 15-min reservation  │ • ESC/POS Bluetooth print optimization│
│ • WhatsApp deep-link constructor     │ • Automated buyer SMS tracking alert │
│ • Static UPI QR fallback screen      │ • Advanced drop sales analytics      │
│ • Flutter rapid camera ingestion     │                                      │
│ • Client WebP compression (<250KB)   │                                      │
│ • 3-stage Visual Kanban pipeline     │                                      │
│ • Client-side 4×6 PDF label generator│                                      │
│ • Offline image upload queue         │                                      │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ 3. COULD-HAVE (Future Phase 3)       │ 4. WON'T-HAVE (Explicitly Deferred)  │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ • Multi-seller boutique subdomains   │ • Integrated payment gateways (0% UPI│
│ • Automated India Post / DTDC API    │   peer-to-peer is a core value)      │
│   tracking webhook updates           │ • Buyer login / password accounts    │
│ • Automated image enhancement (AI ring│ • Multi-quantity inventory splits    │
│   light exposure correction)         │ • Complex ERP integrations           │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

---

## 3. Phased Roadmap Alignment

### Phase 1: MVP Validation ("User Zero" Drop) — Target: Weeks 1–2
* Build lightweight Next.js web catalog linked to Supabase.
* Manually or semi-automatically ingest 25 garments for mother's next Facebook Live broadcast.
* Track buyer checkout completion and eliminate screenshot chaos.
* **Success Gate:** 100% elimination of ambiguous garment screenshots from buyers who use the link.

### Phase 2: Native Seller Operations App — Target: Weeks 3–4
* Implement Flutter release APK with rapid camera intake and auto-incremented flash codes.
* Build the Visual Kanban pipeline (`Pending` ➔ `Paid` ➔ `Dispatched`).
* Integrate client-side 4×6 inch PDF courier packing slip generation.
* **Success Gate:** Reduce post-live parcel packing and addressing time from 3+ hours to under 30 minutes.

### Phase 3: Multi-Boutique Expansion — Target: Month 2+
* Support multiple boutique accounts with independent subdomains (`boutique.livedrop.store`).
* Introduce automated buyer SMS/WhatsApp notifications with courier tracking links.
* Provide analytics dashboard (best-selling price brackets, top repeat buyers, drop revenue).
