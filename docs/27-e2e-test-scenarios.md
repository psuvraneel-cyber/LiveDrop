# 27 — End-to-End Real-World Business Scenarios: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Testing Strategy:** [`docs/25-testing-strategy.md`](file:///c:/LiveDrop/docs/25-testing-strategy.md)  
**Test Case Catalog:** [`docs/26-test-case-catalog.md`](file:///c:/LiveDrop/docs/26-test-case-catalog.md)  

---

## 1. Scenario A — The Happy Path: Normal Complete Sale

```
[Seller Ingestion] ──► [Live Drop Pin] ──► [Buyer Cart & Hold] ──► [WhatsApp Handshake] ──► [1-Tap Fulfillment]
  • Snap & Tag #A01       • Pin link on FB    • Buyer picks #A01      • Send UPI proof       • Seller verifies
  • Set price ₹1,850      • Host live drop    • 15-min hold locks     • Direct DM to seller  • 4x6 Label & Dispatch
```

1. **Pre-Live Setup:** Seller opens Flutter app, taps "Create New Drop" (*"Friday Handloom Special"*), snaps photo of Tussar Silk Saree, auto-fills `#A01`, inputs `1850`, and taps `Save & Next`.
2. **Broadcast & Discovery:** Seller pins `drop.store/mothers-boutique` in Facebook Live comments and holds up placard `#A01`. Buyer taps link inside Facebook; catalog loads in 1.1s.
3. **Cart & Hold:** Buyer taps `+ Add to Bag`, enters name, phone, address, and pincode, then taps `Confirm via WhatsApp`.
4. **Transaction:** RPC locks `#A01`, computes subtotal ₹1,850 + flat shipping ₹80 = ₹2,680 total, creates order `#LD-8942`, and redirects to WhatsApp.
5. **Payment:** WhatsApp opens with pre-filled order text. Buyer attaches UPI transaction screenshot.
6. **Fulfillment:** Order appears under "Pending" in seller Kanban. Seller checks bank app, taps `✓ Mark as Paid` (setting `#A01` to `sold`), taps `Courier Slip` (rendering 4×6 inch PDF), and prints label via Bluetooth thermal printer.
7. **Dispatch:** Seller hands package to DTDC courier, enters tracking number `DTDC882910`, and taps `Dispatched`. Order archives into "Shipped".

---

## 2. Scenario B — Simultaneous Direct Collision (2 Buyers / 1 Garment)

1. **Context:** Garment `#A07` (single-piece Chanderi dress, ₹1,450) is showcased on stream.
2. **Action:** Buyer A (Kolkata) and Buyer B (Howrah) tap `Confirm via WhatsApp` at the exact same sub-second interval ($t_0$).
3. **Database Arbitrage:** Both requests invoke `create_order_with_reservation` on PostgreSQL.
   * Transaction A acquires row lock first (`FOR UPDATE`). Validates `status = 'available'`. Locks `#A07`, sets `status = 'reserved'`.
   * Transaction B attempts lock. Finds row locked, waits milliseconds, then reads `status = 'reserved'`.
4. **Resolution:**
   * **Buyer A:** Receives `success: true`. WhatsApp launches seamlessly with pre-filled message.
   * **Buyer B:** Receives `success: false, error: 'STOCK_UNAVAILABLE'`. Client displays inline modal: *"Item #A07 was just reserved by another viewer."*. The dress is outlined in red with a `[Remove]` button. Zero double-booking occurs.

---

## 3. Scenario C — Multi-Item Bundle Partial Collision

1. **Context:** Buyer carts 3 items: `#A01` (Saree, ₹1,850), `#B04` (Kurti, ₹750), and `#C12` (Scarf, ₹350). Total: ₹2,950.
2. **Collision Event:** While Buyer is entering her delivery address, another viewer checks out `#B04`.
3. **Action:** Buyer taps `Confirm & Order via WhatsApp`.
4. **Database Execution:** RPC locks requested items. Detects `#A01` and `#C12` are available, but `#B04` is already `reserved`.
5. **System Response:** Transaction aborts all holds and returns:
   ```json
   {
     "success": false,
     "error": "STOCK_UNAVAILABLE",
     "unavailable_product_ids": ["uuid-for-B04"]
   }
   ```
6. **UI Graceful Recovery:**
   * An inline banner alerts: *"Item #B04 was claimed by another viewer while you were checking out."*
   * Item `#B04` is outlined in red with an inline `[Remove]` button.
   * Buyer taps `[Remove]`. Subtotal recalculates instantly to ₹2,200 + ₹80 shipping = ₹2,280.
   * All previously entered name and address details remain preserved.
   * Buyer taps `Confirm` again; reservation for `#A01` and `#C12` succeeds immediately.

---

## 4. Scenario D — Buyer Closes WhatsApp Immediately

1. **Context:** Buyer completes web checkout. Database creates order `#LD-1092` with `pending` status and holds pieces for 15 minutes.
2. **Abandonment:** Browser redirects to WhatsApp, but buyer gets distracted and closes WhatsApp without tapping "Send" and without sending payment proof.
3. **Seller Pipeline Visibility:** The order is already safely saved in Supabase. The seller app Kanban board displays the incoming order under "Pending" showing the buyer's name, phone number, and countdown timer (`13m left`).
4. **Resolution:**
   * Seller can tap the WhatsApp icon on the Kanban card to initiate a direct chat: *"Hi Priya, we noticed your reservation for #LD-1092. Please share UPI screenshot to confirm!"*.
   * If buyer ignores, the 15-minute timer expires, freeing the inventory back to the live stream automatically.

---

## 5. Scenario E — Reservation Expiration (Abandoned Cart)

1. **Context:** Buyer reserves Kurti `#B12` at 8:00 PM. Order `#LD-4412` created with `hold_expires_at = 8:15 PM`.
2. **Inactivity:** Buyer does not transfer payment.
3. **Reaper Execution:** At 8:15 PM, the automated database cron executes `release_expired_holds()`.
   * Order `#LD-4412` status transitions from `pending` to `cancelled`.
   * Product `#B12` resets from `reserved` to `available`.
4. **Realtime Broadcast:** Supabase Realtime pushes `status = 'available'` to all connected viewers.
5. **Catalog Presentation:** The product tile on all stream viewers' phones instantly changes from amber `Hold (0m)` back to bright green `Available`. Another buyer grabs it.

---

## 6. Scenario F — Seller Marks Order Paid After Expiration (Conflict Guard)

1. **Context:** Buyer A orders Saree `#A01` at 8:00 PM (expires 8:15 PM). Buyer A sends UPI screenshot at 8:14 PM.
2. **Delay:** Seller is busy demonstrating garments and does not open her phone until 8:22 PM.
3. **Contested Event:** At 8:15 PM, the hold expired. At 8:18 PM, Buyer B reserved `#A01`.
4. **Seller Action:** At 8:22 PM, Seller opens WhatsApp, sees Buyer A's screenshot, opens LiveDrop app, and taps `✓ Mark as Paid` on Buyer A's order.
5. **Database Conflict Detection:**
   * RPC `mark_order_paid` inspects `#A01`. It finds `#A01.status = 'reserved'` with `reserved_by_order_id = Order_B`.
   * The transaction strictly aborts and returns `PRODUCT_ALREADY_RECLAIMED`.
6. **Seller Resolution:** Seller app displays alert dialog: *"Conflict: Item #A01 was reserved by another buyer after this order expired. You must either refund Buyer A or contact Buyer B."* Double-selling is mathematically averted.

---

## 7. Scenario G — Pre-Live Offline Garment Ingestion

1. **Context:** Boutique is located in a basement or rural room with zero cellular data connectivity.
2. **Action:** Seller opens Flutter app, taps "Create Drop", and snaps photos of 20 garments.
3. **App Behavior:**
   * Camera captures, auto-crops to 1:1, compresses WebP to < 200 KB.
   * Saves image file to local device storage and inserts task into SQLite queue.
   * Viewfinder resets in < 0.8s per item. App shows: `☁ Offline — 20 uploads queued`.
4. **Sync Restoration:** Seller moves upstairs where Wi-Fi connects.
5. **Background Sync:** The background worker activates, uploads 20 images to Supabase Storage, inserts 20 product rows, and flashes notification: `✓ 20 garments uploaded to Friday Live Drop`.

---

## 8. Scenario H — Facebook In-App Browser Suppresses WhatsApp Redirect

1. **Context:** Buyer on Android opens catalog link from Facebook comment inside Facebook's built-in webview.
2. **Action:** Buyer submits delivery form. Database creates order `#LD-9021`.
3. **Webview Glitch:** Facebook webview blocks the programmatic `window.location = 'https://wa.me/...'` intent.
4. **Fallback Receipt Flow:**
   * Webfront detects redirect timeout (or immediately routes to `/order/[id]?token=[token]`).
   * Renders the receipt screen displaying:
     * Order reference `#LD-9021` with 15-minute countdown.
     * Large, high-contrast button: `[ Open WhatsApp Now ]`.
     * Static UPI QR code image and copyable UPI ID (`store@okaxis`).
5. **Resolution:** Buyer taps the prominent button manually, triggering native Android intent picker to launch WhatsApp.

---

## 9. Scenario I — Malicious Buyer Manipulation Attack

1. **Context:** Malicious user inspects web network calls and attempts three exploits:
   * **Exploit 1 (Price Tampering):** Calls RPC with client-side forged `subtotal = 1.00` for a ₹2,000 dress.
   * **Exploit 2 (Order Hijacking):** Attempts `GET /rest/v1/orders` to steal customer phone numbers and home addresses.
   * **Exploit 3 (Inventory Lock Spam):** Writes a Python script to order 50 items simultaneously without paying.
2. **System Defenses:**
   * **Exploit 1 Defeated:** The database RPC computes subtotal from internal `products.price` table rows; the client-submitted price is ignored. Order created for ₹2,080.
   * **Exploit 2 Defeated:** Supabase RLS denies unauthenticated reads without the matching `order_token`. The scraper receives `[]` (empty array).
   * **Exploit 3 Defeated:** Rate limiter throttles script after 5 orders. The 15-minute reaper cron frees held items automatically; seller long-presses to force-release holds in seconds.
