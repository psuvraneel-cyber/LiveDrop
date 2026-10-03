# 14 — Shipping / Fulfilment Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Mark ready/packed, courier, tracking, label generation/printing/sharing, shipping status, buyer visibility, transition enforcement |
| Executed | SQL suite 12.8 (ready/ship guards); Flutter T03, T08, T21; code trace of `ShippingDialog`, `ShippingLabelScreen`, `PdfLabelService` |
| Not executed | Physical thermal printing, share sheet on a device, courier scanning |

## 1. Paths to "shipped"

| Entry point | Steps | Server calls | Issues |
|---|---|---|---|
| Orders → card → **Dispatch** (`order_card.dart:431-455`) | Dialog: tracking (required), courier (default "Delhivery Express"), notes → Confirm Dispatch | `mark_order_ready_to_ship` (if not ready) then `mark_order_shipped` | Offered for advance-paid orders (server rejects, T21); two calls, non-atomic (recoverable) |
| Order details → **"Mark as Ready"** (`order_details_screen.dart:285-305`) | Opens the same dispatch dialog | same | Label says "Mark as Ready" but ships (T03); shown for pending orders too |
| Home → **Shipping** tile (`main.dart:281-306`) | Opens `ShippingLabelScreen` for `orders.firstOrNull` (any status) → tracking pre-filled `DVA123456789` → **"Generate & Share Label"** ships immediately | `mark_order_shipped` only | Wrong order, fake AWB, no confirmation, button text lies (T08, SA-SHIP-001) |
| Label screen "Auto" | Generates `<3 letters of courier><clock digits>` | — | Fake tracking numbers reach buyers |
| Label screen Share / Print / Download | All three call the same `printLabel` | — | Share/Download do not exist |

## 2. Server enforcement (works)

| Rule | Result | Evidence |
|---|---|---|
| Ready requires full payment | `ORDER_NOT_PAID` for unpaid | 12.8b PASS |
| Ship requires paid + ready | `ORDER_NOT_PAID` / `ORDER_NOT_READY_TO_SHIP` | 12.8b PASS |
| Double ship | `ALREADY_SHIPPED` | 12.8c PASS |
| Shipment requires full payment (CHECK) | `chk_orders_shipment_requires_full_payment` | schema |

The brief's example bypass "Pending → Shipped" is **blocked by the server**. What the UI does wrong is (a) present impossible actions, (b) collapse "packed/ready" into "ship", and (c) let a placeholder tracking number through for orders that *are* shippable.

## 3. Label content (`pdf_label_service.dart`)

| Element | Current | Problem |
|---|---|---|
| Payment banner | Always "PREPAID - DO NOT COLLECT CASH" + order total | Wrong for advance-paid orders with balance due (SA-SHIP-002); combined with SA-PAY-001 a ₹250 advance ships as "prepaid ₹2,500" |
| Barcode | Tracking or `TRK-<order code>` | Placeholder barcode is not scannable by any courier |
| Date | `DateFormat('dd MMM yyyy, hh:mm a')` on UTC `createdAt` | 5 h 30 min off (SA-ORD-001) |
| Buyer block | Name, address, pincode, phone | OK (PII printed by necessity) |
| Return block | Seller return address + phone | OK |
| Courier | Free text default "DELHIVERY EXPRESS" | Wrong when not changed |
| Size | 4×6 in (288×432 pt) | Matches common thermal printers (device NOT TESTED) |

## 4. Buyer visibility
`mark_order_shipped` stores `tracking_number`, `courier_partner`, `shipped_at`; the buyer order page (`get_order_by_token`, 030) shows status and tracking. No tracking URL is generated (SA-SHIP-003). Fake AWBs from the label screen would be shown to buyers verbatim.

## 5. Recommended flow
Paid tab → **Pack** (mark ready; optional photo) → **Print label** (only when `balance_due = 0`; requires a real AWB or prints without barcode) → **Mark shipped** (confirm courier + AWB, generates tracking URL) — each a separate, reversible-until-shipped step; Home "Shipping due" opens the Ready list, never a random order.

## 6. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-SHIP-001 | HIGH | P1 | Shipping shortcut ships the first order with a placeholder AWB, no confirmation |
| SA-SHIP-002 | MEDIUM | P1 | "PREPAID" on balance-due orders; fake barcode; UTC date |
| SA-SHIP-003 | LOW | P2 | Courier default/free text; no tracking URL |
| SA-ORD-005 | MEDIUM | P1 | UI actions do not match server rules; no pack step |
