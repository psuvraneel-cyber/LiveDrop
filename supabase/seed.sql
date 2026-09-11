-- ==============================================================================
-- LiveDrop Local Development & Integration Seed Data
-- ==============================================================================
--
-- STRICT DATA GOVERNANCE COMPLIANCE:
-- 1. All data is 100% synthetic (zero real customer PII or boutique credentials).
-- 2. All monetary values are strictly non-negative integers in Paisa (ADR-009).
-- 3. Conforms to all table check constraints, foreign keys, and unique indexes.
-- ==============================================================================

-- 1. Ensure auth schema and test seller user exist
INSERT INTO auth.users (
  id,
  email
) VALUES (
  '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
  'seller.mother@livedrop.test'
) ON CONFLICT (id) DO NOTHING;

-- 2. Seller Profile
INSERT INTO profiles (
  id,
  store_name,
  phone_number,
  upi_id,
  upi_qr_url,
  return_address,
  default_shipping_fee_paisa,
  free_shipping_threshold_paisa
) VALUES (
  '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
  'Mother''s Boutique',
  '919830012345',
  'mothersboutique@okaxis',
  'https://storage.livedrop.store/qrs/mb.webp',
  '12A Ballygunge Place, Kolkata - 700019',
  8000,   -- ₹80.00
  200000  -- ₹2,000.00
) ON CONFLICT (id) DO UPDATE SET
  store_name = EXCLUDED.store_name,
  phone_number = EXCLUDED.phone_number,
  upi_id = EXCLUDED.upi_id,
  upi_qr_url = EXCLUDED.upi_qr_url,
  return_address = EXCLUDED.return_address,
  default_shipping_fee_paisa = EXCLUDED.default_shipping_fee_paisa,
  free_shipping_threshold_paisa = EXCLUDED.free_shipping_threshold_paisa;

-- 3. Drops (1 Draft, 1 Live, 1 Closed)
-- Respects idx_drops_one_live_per_seller: only one live drop per seller
INSERT INTO drops (
  id,
  seller_id,
  title,
  slug,
  status,
  shipping_fee_paisa,
  free_shipping_threshold_paisa,
  live_started_at,
  closed_at
) VALUES 
  -- Draft drop
  (
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6800'::uuid,
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    'Upcoming Festive Silk Drop',
    'festive-silk-drop',
    'draft',
    8000,
    200000,
    NULL,
    NULL
  ),
  -- Active Live drop
  (
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    'Friday Silk Special',
    'mothers-boutique',
    'live',
    8000,
    200000,
    NOW() - INTERVAL '1 hour',
    NULL
  ),
  -- Closed drop
  (
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6802'::uuid,
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    'Past Clearance Collection',
    'past-clearance',
    'closed',
    8000,
    200000,
    NOW() - INTERVAL '3 days',
    NOW() - INTERVAL '2 days'
  )
ON CONFLICT (id) DO NOTHING;

-- 4. Initial Representative Orders (Insert before products so foreign keys can be referenced)
INSERT INTO orders (
  id,
  drop_id,
  order_code,
  order_token,
  buyer_name,
  buyer_phone,
  shipping_address,
  pincode,
  subtotal_paisa,
  shipping_paisa,
  total_paisa,
  status,
  hold_expires_at,
  paid_at
) VALUES
  -- 1. Pending Order (Active 15-min hold on #A02)
  (
    '4b724590-7811-419b-a311-6b2a091df012'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    'LD-8F429B',
    '9a01f822-b5e1-4c11-97aa-3d84951ea034'::uuid,
    'Sangeeta Mukherjee',
    '9830100001',
    'Flat 4B, Greenview Apts, Jadavpur',
    '700032',
    75000,  -- ₹750.00
    8000,   -- ₹80.00
    83000,  -- ₹830.00
    'pending',
    NOW() + INTERVAL '13 minutes',
    NULL
  ),
  -- 2. Paid Order (Purchased #A03)
  (
    '5c835601-8922-420c-b422-7c3b102ef023'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    'LD-3D911A',
    '8b12e933-c6f2-4d22-08bb-4e95062fb145'::uuid,
    'Priya Sharma',
    '9830100002',
    '15 Park Street, Kolkata',
    '700016',
    125000, -- ₹1,250.00
    8000,   -- ₹80.00
    133000, -- ₹1,330.00
    'paid',
    NOW() + INTERVAL '15 minutes',
    NOW() - INTERVAL '30 minutes'
  ),
  -- 3. Cancelled Order
  (
    '6d946712-9033-431d-c533-8d4c213fa034'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    'LD-7K102B',
    '7c23f044-d703-4e33-19cc-5f06173ac256'::uuid,
    'Rohan Das',
    '9830100003',
    '22 Gariahat Road, Kolkata',
    '700029',
    50000,
    8000,
    58000,
    'cancelled',
    NOW() - INTERVAL '1 hour',
    NULL
  )
ON CONFLICT (id) DO NOTHING;

-- 5. Products on the Live Drop
INSERT INTO products (
  id,
  drop_id,
  code,
  title,
  price_paisa,
  size,
  image_url,
  status,
  reserved_at,
  reserved_by_order_id,
  version
) VALUES
  -- Available piece
  (
    'e9314c99-7f55-4089-a2bb-b001d2950df1'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    '#A01',
    'Handloom Tussar Saree',
    185000, -- ₹1,850.00
    'Free Size',
    'https://images.livedrop.store/products/e931.webp',
    'available',
    NULL,
    NULL,
    1
  ),
  -- Reserved piece (held by order 4b724590)
  (
    'a8219c11-1b22-4899-b1cc-c112d2950de2'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    '#A02',
    'Chanderi Cotton Kurti',
    75000, -- ₹750.00
    'L',
    'https://images.livedrop.store/products/a821.webp',
    'reserved',
    NOW() - INTERVAL '2 minutes',
    '4b724590-7811-419b-a311-6b2a091df012'::uuid,
    2
  ),
  -- Sold piece (finalized by paid order 5c835601)
  (
    'f7105d88-3c44-4177-90aa-e221d2950da3'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    '#A03',
    'Pure Jamdani Silk Dupatta',
    125000, -- ₹1,250.00
    'Free Size',
    'https://images.livedrop.store/products/f710.webp',
    'sold',
    NULL,
    NULL,
    3
  ),
  -- Second sold piece (e.g. marked sold offline)
  (
    'b6415d99-2a33-4188-89bb-d110d2950dc4'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    '#A04',
    'Embroidered Pashmina Shawl',
    95000, -- ₹950.00
    'Free Size',
    'https://images.livedrop.store/products/b641.webp',
    'sold',
    NULL,
    NULL,
    2
  )
ON CONFLICT (id) DO NOTHING;

-- 6. Order Items
INSERT INTO order_items (
  id,
  order_id,
  product_id,
  price_at_purchase_paisa
) VALUES
  (
    '3a129d88-1144-4822-9011-e110d2950da1'::uuid,
    '4b724590-7811-419b-a311-6b2a091df012'::uuid,
    'a8219c11-1b22-4899-b1cc-c112d2950de2'::uuid,
    75000
  ),
  (
    '4b230e99-2255-4933-a122-f221d2950db2'::uuid,
    '5c835601-8922-420c-b422-7c3b102ef023'::uuid,
    'f7105d88-3c44-4177-90aa-e221d2950da3'::uuid,
    125000
  )
ON CONFLICT (id) DO NOTHING;
