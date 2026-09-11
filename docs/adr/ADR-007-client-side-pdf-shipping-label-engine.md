# ADR-007: Client-Side 4×6 Thermal PDF Shipping Label Engine

## Status
**Accepted**

## Context
Once live orders are verified and marked "Paid", boutique sellers spend 2-3 hours manually handwriting delivery slips and tape labels onto courier parcels. A critical value proposition of LiveDrop is **1-tap shipping label generation**.

Logistics standards in India (Delhivery, Shiprocket, Blue Dart, DTDC, India Post) mandate **4×6 inch (100×150mm)** shipping labels featuring recipient PII, sender return address, item summary, and scannable barcodes.

Two architectural options exist for generating and printing labels:
1. Low-level ESC/POS byte streaming directly over Bluetooth RFCOMM sockets.
2. High-level vector PDF generation rendered via the native Android Print Spooler.

## Decision
Adopt **Client-Side Vector PDF Generation with Android Print Framework Integration**:

### 1. Vector PDF Layout
* The Flutter seller application generates standard 4×6 inch (100×150 mm) vector PDF documents locally using the pure-Dart `pdf` package.
* **Label Contents**:
  * Carrier-standard Header: LiveDrop Order ID & Date.
  * Barcode: **Code 128** standard encoding the alphanumeric Order ID.
  * Consignee Details: Customer Full Name, Primary Phone Number, Sanitized Multi-line Address, City, State, 6-digit PIN code.
  * Consignor Details: Boutique Business Name, Contact Phone, Return Warehouse Address.
  * Order Summary: Table listing SKU Flash-Codes, Product Titles, and Package Piece Count.
  * Pre-paid Badge: Prominent bold box stating **"PREPAID - DO NOT COLLECT CASH"**.

### 2. Print Execution & Sharing
* Utilizing the `printing` package in Flutter, the generated PDF document is handed directly to the **Android Print Spooler** (`Printing.layoutPdf(...)`).
* **Hardware Interoperability**: The Android Print Framework natively handles printer discovery, driver rendering, and page scaling across both Wi-Fi and Bluetooth thermal printers (e.g., Everycom, TVS, TSC, Zebra).
* **Zero-Printer Fallback**: If the seller does not own a thermal printer, the app provides a 1-tap "Share PDF via WhatsApp / Email" button, allowing the seller to forward batch PDF files to a cyber café or home desktop laser printer.

```
Paid Order in Flutter App
         │
         ▼
`pdf` package compiles 4x6" Vector Document in RAM (< 100ms)
         │
         ├──> Option A: Android Print Spooler (Bluetooth/Wi-Fi Thermal Printer)
         │
         └──> Option B: System Share Sheet (WhatsApp / Drive / Desktop Printer)
```

## Alternatives Considered
* **Raw ESC/POS Bluetooth Byte Streams**: Highly fragile across unbranded Chinese thermal printers common in India; requires managing raw RFCOMM socket lifecycles, baud rates, code pages, and character encodings. Rejected.
* **Server-Side PDF Generation (Puppeteer / Chromium / Edge Functions)**: Incurs heavy server costs, cold-start latency (3-5s), and bandwidth costs. Generating PDFs client-side in Flutter takes < 100ms and costs ₹0. Rejected.

## Consequences
* **Positive**: Generates carrier-compliant labels in < 100ms; zero backend costs; 100% hardware compatibility via Android print layer; easy sharing fallback.
* **Negative**: Formatting must strictly fit within 100×150mm bounds without page overflow.
