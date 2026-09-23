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
* **Success Response (200 OK):** `{"success": true}`

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
