# 13 — API Contract Specification: LiveDrop

**Document Version:** 2.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline (Paisa Standard Reconciled via ADR-009)  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Architectural Access Protocol & Surface Isolation

LiveDrop isolates API interactions into two strict surfaces:
1. **Buyer Public Surface (Unauthenticated):** Read-only access to active catalog feeds; transactional RPC calls for atomic checkout; token-gated receipt retrieval. Direct write operations to database tables are strictly blocked by RLS.
2. **Seller Surface (Authenticated JWT):** Complete REST CRUD and privileged RPCs on drops, products, and orders owned by the authenticated seller session (`auth.uid()`).
3. **Monetary Standardization (ADR-009):** All prices, subtotals, shipping charges, and order totals are represented strictly as non-negative integers in **Paisa** (₹1.00 = 100 Paisa). Floating-point numeric types are strictly prohibited.

---

## 2. Buyer API Operations (Unauthenticated Surface)

### 2.1 Get Active Drop Catalog
* **Endpoint:** `GET /rest/v1/drops?slug=eq.{slug}&status=eq.live&select=id,title,slug,status,shipping_fee_paisa,free_shipping_threshold_paisa,seller_id,profiles(store_name,phone_number,upi_id,upi_qr_url,default_shipping_fee_paisa,free_shipping_threshold_paisa)`
* **Actor:** Public Buyer.
* **Authentication:** Anon Key (`apikey` header).
* **Authorization:** Permitted by RLS policy `drops_public_read_active`.
* **Response (200 OK):**
  ```json
  [
    {
      "id": "c1f76d42-4f36-4d2b-9801-b5e1cf3e6801",
      "title": "Friday Silk Special",
      "slug": "mothers-boutique",
      "status": "live",
      "shipping_fee_paisa": 8000,
      "free_shipping_threshold_paisa": 200000,
      "seller_id": "8a329e71-4b10-4055-90d2-df8029d5b512",
      "profiles": {
        "store_name": "Mother's Boutique",
        "phone_number": "919830012345",
        "upi_id": "mothersboutique@okaxis",
        "upi_qr_url": "https://storage.livedrop.store/qrs/mb.webp",
        "default_shipping_fee_paisa": 8000,
        "free_shipping_threshold_paisa": 200000
      }
    }
  ]
  ```
* **Error States:**
  * `200 OK []` (Drop not found or not currently `live`). Client displays "Broadcast ended" screen.

---

### 2.2 Get Products for Drop
* **Endpoint:** `GET /rest/v1/products?drop_id=eq.{drop_id}&select=id,code,title,price_paisa,size,image_url,status,reserved_at,version&order=code.asc`
* **Actor:** Public Buyer.
* **Authentication:** Anon Key.
* **Authorization:** Permitted by RLS policy `products_public_read_live`.
* **Response (200 OK):**
  ```json
  [
    {
      "id": "e9314c99-7f55-4089-a2bb-b001d2950df1",
      "code": "#A01",
      "title": "Handloom Tussar Saree",
      "price_paisa": 185000,
      "size": "Free Size",
      "image_url": "https://images.livedrop.store/products/e931.webp",
      "status": "available",
      "reserved_at": null,
      "version": 1
    },
    {
      "id": "a8219c11-1b22-4899-b1cc-c112d2950de2",
      "code": "#A02",
      "title": "Chanderi Cotton Kurti",
      "price_paisa": 75000,
      "size": "L",
      "image_url": "https://images.livedrop.store/products/a821.webp",
      "status": "reserved",
      "reserved_at": "2026-09-11T14:32:00Z",
      "version": 2
    }
  ]
  ```

---

### 2.3 Create Order with Atomic Reservation (RPC)
* **Endpoint:** `POST /rest/v1/rpc/create_order_with_reservation`
* **Actor:** Public Buyer.
* **Authentication:** Anon Key.
* **Concurrency:** Strictly serializable via PostgreSQL row-level locks (`SELECT ... FOR UPDATE ORDER BY id ASC`).
* **Request Body:**
  ```json
  {
    "p_drop_id": "c1f76d42-4f36-4d2b-9801-b5e1cf3e6801",
    "p_product_ids": [
      "e9314c99-7f55-4089-a2bb-b001d2950df1",
      "f7105d88-3c44-4177-90aa-e221d2950da3"
    ],
    "p_buyer_name": "Sangeeta Mukherjee",
    "p_buyer_phone": "9830123456",
    "p_shipping_address": "Flat 4B, Greenview Apts, Jadavpur",
    "p_pincode": "700032"
  }
  ```
* **Success Response (200 OK):**
  ```json
  {
    "success": true,
    "order_id": "4b724590-7811-419b-a311-6b2a091df012",
    "order_code": "LD-8F429B",
    "order_token": "9a01f822-b5e1-4c11-97aa-3d84951ea034",
    "subtotal_paisa": 260000,
    "shipping_paisa": 8000,
    "total_paisa": 268000,
    "hold_expires_at": "2026-09-11T14:47:00Z"
  }
  ```
* **Conflict / Collision Response (200 OK with business failure):**
  ```json
  {
    "success": false,
    "error": "STOCK_UNAVAILABLE",
    "unavailable_product_ids": [
      "e9314c99-7f55-4089-a2bb-b001d2950df1"
    ]
  }
  ```
* **Validation Errors:**
  * `DROP_NOT_ACTIVE`: Drop is concluded or still in draft.
  * `EMPTY_CART`: No valid product IDs provided.
  * `EXCEEDS_CART_LIMIT`: Cart contains more than 10 distinct items.
  * `SELLER_SUSPENDED` (since migration 038, SA-ONB-002): the drop's seller is not approved. No order is created. `initiate_payment_attempt` returns the same code instead of payee details.

---

### 2.4 Get Order Receipt by Token (RPC & RLS)
* **Primary Endpoint (Hardened Token RPC):** `POST /rest/v1/rpc/get_order_by_token`
* **Actor:** Public Buyer possessing `order_token`.
* **Authentication:** Anon Key.
* **Request Body:**
  ```json
  {
    "p_order_id": "4b724590-7811-419b-a311-6b2a091df012",
    "p_order_token": "9a01f822-b5e1-4c11-97aa-3d84951ea034"
  }
  ```
* **Success Response (200 OK):**
  ```json
  {
    "success": true,
    "order": {
      "id": "4b724590-7811-419b-a311-6b2a091df012",
      "order_code": "LD-8F429B",
      "buyer_name": "Sangeeta Mukherjee",
      "subtotal_paisa": 260000,
      "shipping_paisa": 8000,
      "total_paisa": 268000,
      "status": "pending",
      "hold_expires_at": "2026-09-11T14:47:00Z",
      "store_name": "Mother's Boutique",
      "upi_id": "mothersboutique@okaxis",
      "upi_qr_url": "https://storage.livedrop.store/qrs/mb.webp",
      "items": [
        {
          "product_id": "e9314c99-7f55-4089-a2bb-b001d2950df1",
          "code": "#A01",
          "title": "Handloom Tussar Saree",
          "image_url": "https://images.livedrop.store/products/e931.webp",
          "price_at_purchase_paisa": 185000
        },
        {
          "product_id": "f7105d88-3c44-4177-90aa-e221d2950da3",
          "code": "#A02",
          "title": "Chanderi Cotton Kurti",
          "image_url": "https://images.livedrop.store/products/f710.webp",
          "price_at_purchase_paisa": 75000
        }
      ]
    }
  }
  ```
* **Error Response:** `{"success": false, "error": "ORDER_NOT_FOUND_OR_UNAUTHORIZED"}`.

---

## 3. Seller API Operations (Authenticated JWT Surface)

### 3.1 List Drops for Seller
* **Endpoint:** `GET /rest/v1/drops?seller_id=eq.{seller_id}&order=created_at.desc`
* **Actor:** Authenticated Seller (`auth.uid() = seller_id`).
* **Authentication:** Bearer JWT.
* **Authorization:** RLS policy `drops_seller_manage`.
* **Response (200 OK):** Array of seller drops.

---

### 3.2 Create Drop Session
* **Endpoint:** `POST /rest/v1/drops`
* **Actor:** Authenticated Boutique Seller.
* **Authentication:** Bearer JWT (`auth.uid() = seller_id`).
* **Request Body:**
  ```json
  {
    "title": "Sunday Silk Festive Drop",
    "slug": "sunday-silk-festive",
    "status": "draft",
    "shipping_fee_paisa": 8000,
    "free_shipping_threshold_paisa": 200000
  }
  ```
* **Response (201 Created):** Full drop record.

---

### 3.3 Update Drop Lifecycle Status
* **Endpoint:** `PATCH /rest/v1/drops?id=eq.{drop_id}`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Request Body:**
  ```json
  {
    "status": "live",
    "live_started_at": "2026-09-11T18:00:00Z"
  }
  ```
* **Response (200 OK):** Updated drop record.

---

### 3.4 Create Product with Ingestion Upload
* **Step 1 (Image Upload):** `POST /storage/v1/object/products/{drop_id}/{code}.webp`  
  * Returns CDN public URL.
* **Step 2 (Record Insert):** `POST /rest/v1/products`
* **Request Body:**
  ```json
  {
    "drop_id": "c1f76d42-4f36-4d2b-9801-b5e1cf3e6801",
    "code": "#A15",
    "title": "Tussar Silk / Free Size",
    "price_paisa": 125000,
    "size": "Free Size",
    "image_url": "https://images.livedrop.store/products/drop1/A15.webp",
    "status": "available"
  }
  ```
* **Response (201 Created):** Created product record.

---

### 3.5 Query Orders for Drop (Kanban Order Pipeline)
* **Endpoint:** `GET /rest/v1/orders?drop_id=eq.{drop_id}&select=id,order_code,buyer_name,buyer_phone,shipping_address,pincode,subtotal_paisa,shipping_paisa,total_paisa,status,hold_expires_at,paid_at,shipped_at,tracking_number,courier_partner,order_items(id,product_id,price_at_purchase_paisa,products(code,title,image_url))&order=created_at.desc`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Response (200 OK):** Array of complete order records with line items.

---

### 3.6 Confirm Payment via Conflict-Guarded RPC
* **Endpoint:** `POST /rest/v1/rpc/mark_order_paid`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Request Body:**
  ```json
  {
    "p_order_id": "4b724590-7811-419b-a311-6b2a091df012"
  }
  ```
* **Success Response (200 OK):** `{"success": true}`
* **Conflict Response (200 OK):**
  ```json
  {
    "success": false,
    "error": "PRODUCT_ALREADY_RECLAIMED",
    "message": "One or more items in this order were claimed by another buyer after the hold expired."
  }
  ```

---

### 3.7 Manual Offline Sale Override (RPC)
* **Endpoint:** `POST /rest/v1/rpc/mark_product_sold_offline`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Request Body:**
  ```json
  {
    "p_product_id": "e9314c99-7f55-4089-a2bb-b001d2950df1"
  }
  ```
* **Success Response (200 OK):** `{"success": true}`
* **Error Response:** `{"success": false, "error": "ALREADY_SOLD"}`

---

### 3.8 Force Release Hold (RPC)
* **Endpoint:** `POST /rest/v1/rpc/force_release_hold`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Request Body:**
  ```json
  {
    "p_order_id": "4b724590-7811-419b-a311-6b2a091df012"
  }
  ```
* **Success Response (200 OK):** `{"success": true}`. On release, the order is cancelled, its pieces return to `available` and its unclaimed attempts (`created`, `awaiting_payment`) are set to `expired`.
* **Errors:** `UNAUTHORIZED`, `ORDER_NOT_FOUND_OR_UNAUTHORIZED`, `ONLY_PENDING_CAN_BE_RELEASED`, and (since migration 035, SA-PAY-005) `PAYMENT_CLAIM_PENDING`:
  ```json
  {
    "success": false,
    "error": "PAYMENT_CLAIM_PENDING",
    "message": "The buyer has already submitted a payment for this order. Verify or reject it in Payments before releasing the piece.",
    "payment_attempt_id": "…",
    "buyer_submitted_utr": "819000000010"
  }
  ```
  Returned whenever any attempt of the order is `buyer_claimed`, `awaiting_seller_verification` or `late_claim_pending_review`. Nothing is changed. The seller app hides Release while a claim exists.

---

### 3.9 Mark Order Ready to Ship (RPC)
* **Endpoint:** `POST /rest/v1/rpc/mark_order_ready_to_ship`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Request Body:**
  ```json
  {
    "p_order_id": "4b724590-7811-419b-a311-6b2a091df012"
  }
  ```
* **Success Response (200 OK):** `{"success": true}`
* **Error Response:**
  - `{"success": false, "error": "ORDER_NOT_FULLY_PAID"}`: Order has balance due or payment is unverified.
  - `{"success": false, "error": "FORBIDDEN"}`: Caller does not own the drop.

---

### 3.10 Dispatch Order & Attach Courier Tracking (RPC)
* **Endpoint:** `POST /rest/v1/rpc/mark_order_shipped`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Request Body:**
  ```json
  {
    "p_order_id": "4b724590-7811-419b-a311-6b2a091df012",
    "p_tracking_number": "DTDC19284711",
    "p_courier_name": "DTDC Express"
  }
  ```
* **Success Response (200 OK):** `{"success": true}`
* **Error Response:**
  - `{"success": false, "error": "ORDER_NOT_READY_TO_SHIP"}`: Order has not been marked ready to ship (SEC-05).
  - `{"success": false, "error": "INVALID_SHIPPING_DETAILS"}`: Empty tracking or courier name.
  - `{"success": false, "error": "FORBIDDEN"}`: Caller does not own the drop.

---

### 3.11 Update Product Details (RPC)
* **Endpoint:** `POST /rest/v1/rpc/update_product`
* **Actor:** Owning Seller.
* **Authentication:** Bearer JWT.
* **Request Body:**
  ```json
  {
    "p_product_id": "e9314c99-7f55-4089-a2bb-b001d2950df1",
    "p_title": "Pure Handloom Tussar Silk Saree",
    "p_price_paisa": 195000,
    "p_size": "Free Size"
  }
  ```
* **Success Response (200 OK):** `{"success": true, "version": 2}`
* **Error Response:**
  - `{"success": false, "error": "CANNOT_EDIT_RESERVED_OR_SOLD"}`: Item is in `reserved` or `sold` status.
  - `{"success": false, "error": "FORBIDDEN"}`: Caller does not own the drop.

---

### 3.12 Admin Approve Seller (RPC)
* **Endpoint:** `POST /rest/v1/rpc/admin_approve_seller`
* **Actor:** Platform Administrator (`service_role`).
* **Authentication:** Service Role Secret.
* **Request Body:**
  ```json
  {
    "p_seller_id": "11111111-1111-1111-1111-111111111111"
  }
  ```
* **Success Response (200 OK):** `{"success": true}`
* **Suspension (since migration 038, SA-ONB-002):** `p_approved = false` (or any update that sets `profiles.is_approved` from true to false) closes every live drop of the seller through the `close_drop` safe-closure path. Unpaid, unclaimed holds are released; claims in flight and paid orders are kept. Re-approval does not reopen drops.


---

### 3.13 Verify Manual UPI Payment (RPC) — response contract since migration 035
* **Endpoint:** `POST /rest/v1/rpc/verify_manual_upi_payment`
* **Actor:** Owning Seller. **Authentication:** Bearer JWT.
* **Request Body:** `{"p_payment_attempt_id": "uuid", "p_utr": "optional text"}` (signature unchanged).
* **Behaviour:**
  * Claimed attempts (`buyer_claimed`, `awaiting_seller_verification`, `late_claim_pending_review`) stay verifiable after `verification_expires_at` / `expires_at`. Unclaimed attempts past expiry still return `PAYMENT_ATTEMPT_EXPIRED`.
  * Late claim, pieces still free (or reserved by this order): advance → order `confirmed/advance_paid` with a new hold; full/balance → `paid`.
  * Late claim, pieces sold to someone else: the payment is recorded in the ledger, the order stays cancelled/expired, and a refund obligation is set (`refund_required = true`). Another buyer's piece is never taken (ADR-010).
* **Success Response (200 OK)** — every key is always present:
  ```json
  {
    "success": true, "idempotent": false, "is_late_claim": true,
    "inventory_available": false, "refund_required": true, "refund_amount_paisa": 158000,
    "order_id": "…", "order_code": "LD-7K92MF", "order_status": "cancelled", "status": "cancelled",
    "payment_status": "paid", "fulfilment_status": "…",
    "total_paid_paisa": 158000, "balance_due_paisa": 0, "advance_paid_paisa": 0,
    "payment_type": "full", "amount_paisa": 158000,
    "payment_attempt_id": "…", "attempt_id": "…", "payment_id": "…", "message": "…"
  }
  ```
  `inventory_available` is `null` when not evaluated. `status` equals `order_status`. A replay returns `idempotent: true` with the same keys and adds no ledger row.
* **Errors (new in 035):** `INVENTORY_CONFLICT` (an on-time order no longer holds all its pieces, no writes), `PAYMENT_AMOUNT_MISMATCH`, `LEDGER_INCONSISTENT` (stored paid amount differs from the verified ledger, no writes). Existing errors such as `PAYMENT_ATTEMPT_EXPIRED`, `INVALID_ORDER_STATE`, `REFERENCE_USED_ON_ANOTHER_ORDER` and `ORDER_NOT_FOUND_OR_UNAUTHORIZED` are unchanged.
* **UTR normalisation (since migration 038, SA-PAY-011):** `p_utr` and stored claims are compared after removing whitespace and upper-casing (`normalize_payment_reference`). `REFERENCE_USED_ON_ANOTHER_ORDER` therefore also covers case and spacing variants. `submit_buyer_payment_claim` stores the normalised UTR and returns `REFERENCE_USED_ON_ANOTHER_ORDER` when that UTR is already verified on a different order.

### 3.14 Record Refund (RPC) — new in migration 035
* **Endpoint:** `POST /rest/v1/rpc/record_refund`
* **Actor:** Owning Seller (drop's `seller_id = auth.uid()`) or `service_role`. Not executable by `anon`.
* **Request Body:**
  ```json
  { "p_order_id": "uuid", "p_refund_reference": "UPI-REF 9876/01", "p_note": "optional" }
  ```
  `p_refund_reference` is trimmed, 4–64 characters, `^[A-Za-z0-9_./ -]+$`. `p_note` is appended to `orders.notes`.
* **Precondition:** `refund_status = 'required'`. Sets `refund_status = 'refunded'`, `refund_reference`, `refunded_at = now()`, `refund_recorded_by = auth.uid()`.
* **Success Response (200 OK):**
  ```json
  { "success": true, "idempotent": false, "order_id": "…", "order_code": "LD-…",
    "refund_status": "refunded", "refund_amount_paisa": 128000,
    "refund_reference": "UPI-REF 9876/01", "refunded_at": "…" }
  ```
  Already refunded with the same reference → `idempotent: true`. With a different reference → `NO_REFUND_DUE`.
* **Errors:** `UNAUTHORIZED`, `ORDER_NOT_FOUND_OR_UNAUTHORIZED`, `NO_REFUND_DUE`, `INVALID_REFUND_REFERENCE`.

### 3.15 Reject Manual UPI Payment (RPC) — change in migration 035
`reject_manual_upi_payment(p_payment_attempt_id, p_rejection_reason, p_release_hold)` keeps the hold and returns `hold_released: false` while another claim on the same order is still in flight, even if `p_release_hold` is true.

### 3.16 Internal Functions (not part of the client API)
`release_stale_hold(p_order_id uuid) RETURNS boolean`, `apply_upi_payment_transition(...)`, `upi_verification_response(...)` and (since 038) `close_drop_safely(p_drop_id uuid) RETURNS int` are `SECURITY DEFINER` helpers with EXECUTE revoked from `PUBLIC`, `anon`, `authenticated` and `service_role`; a client call returns `permission denied`. `release_expired_holds()` is called by pg_cron (migration 036) and by the backup GitHub Actions reaper (`scripts/run-reaper.mjs`, service role).
