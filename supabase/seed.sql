-- ==============================================================================
-- LiveDrop Local Development & Integration Seed Data
-- ==============================================================================
--
-- STRICT DATA GOVERNANCE COMPLIANCE:
-- 1. All data is 100% synthetic (zero real customer PII or boutique credentials).
-- 2. All monetary values are strictly non-negative integers in Paisa (ADR-009).
-- 3. Conforms to all table check constraints, foreign keys, and unique indexes.
-- 4. Multi-seller storefront architecture demonstrating tenant isolation,
--    distinct storefront slugs, custom advance settings, and order state machine.
-- ==============================================================================

-- 1. Ensure auth schema and test seller users exist
INSERT INTO auth.users (
  id,
  email
) VALUES 
  ('8a329e71-4b10-4055-90d2-df8029d5b512'::uuid, 'seller.mother@livedrop.test'),
  ('7b218d60-3a09-4044-80c1-ce7018c4a401'::uuid, 'seller.artisan@livedrop.test'),
  ('6a107c50-2908-4033-70b0-bd6007b393f0'::uuid, 'seller.craft@livedrop.test')
ON CONFLICT (id) DO NOTHING;

-- 2. Seller Profiles (Demonstrating multi-seller storefront identity and advance policy variance)
INSERT INTO profiles (
  id,
  store_name,
  store_slug,
  phone_number,
  upi_id,
  upi_vpa,
  upi_display_name,
  upi_enabled,
  payment_instructions,
  upi_qr_url,
  return_address,
  default_shipping_fee_paisa,
  free_shipping_threshold_paisa,
  advance_confirmation_enabled,
  advance_amount_paisa,
  hold_duration_days
) VALUES 
  -- Seller A: Mother's Boutique (Default advance ₹250.00, 30 days hold)
  (
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    'Mother''s Boutique',
    'mothers-boutique',
    '919830012345',
    'mothersboutique@okaxis',
    'mothersboutique@okaxis',
    'Mother''s Boutique Official',
    true,
    'Please enter your LiveDrop order code in UPI transaction remarks.',
    'https://storage.livedrop.store/qrs/mb.webp',
    '12A Ballygunge Place, Kolkata - 700019',
    8000,   -- ₹80.00
    200000, -- ₹2,000.00
    true,
    25000,  -- ₹250.00
    30      -- 30 days hold
  ),
  -- Seller B: Artisan Silks (Custom advance ₹500.00, 14 days hold)
  (
    '7b218d60-3a09-4044-80c1-ce7018c4a401'::uuid,
    'Artisan Silks',
    'artisan-silks',
    '919830099999',
    'artisansilks@upi',
    'artisansilks@upi',
    'Artisan Silks Handlooms',
    true,
    'Scan and pay via any UPI app. Verification completed within 15 minutes.',
    'https://storage.livedrop.store/qrs/artisan.webp',
    '44 Gariahat Road, Kolkata - 700029',
    6000,
    150000,
    true,
    50000,  -- ₹500.00
    14      -- 14 days hold
  ),
  -- Seller C: Craft Weaves (Advance confirmation disabled - full payment only)
  (
    '6a107c50-2908-4033-70b0-bd6007b393f0'::uuid,
    'Craft Weaves',
    'craft-weaves',
    '919830077777',
    'craftweaves@icici',
    'craftweaves@icici',
    'Craft Weaves Kolkata',
    false,  -- UPI payments temporarily disabled
    'Currently accepting payments via alternate channels.',
    NULL,
    '18 Park Street, Kolkata - 700016',
    5000,
    NULL,
    false,  -- Advance disabled!
    25000,
    7
  )
ON CONFLICT (id) DO UPDATE SET
  store_name = EXCLUDED.store_name,
  store_slug = EXCLUDED.store_slug,
  phone_number = EXCLUDED.phone_number,
  upi_id = EXCLUDED.upi_id,
  upi_vpa = EXCLUDED.upi_vpa,
  upi_display_name = EXCLUDED.upi_display_name,
  upi_enabled = EXCLUDED.upi_enabled,
  payment_instructions = EXCLUDED.payment_instructions,
  upi_qr_url = EXCLUDED.upi_qr_url,
  return_address = EXCLUDED.return_address,
  default_shipping_fee_paisa = EXCLUDED.default_shipping_fee_paisa,
  free_shipping_threshold_paisa = EXCLUDED.free_shipping_threshold_paisa,
  advance_confirmation_enabled = EXCLUDED.advance_confirmation_enabled,
  advance_amount_paisa = EXCLUDED.advance_amount_paisa,
  hold_duration_days = EXCLUDED.hold_duration_days;

-- 3. Drops Across Multiple Sellers
-- Respects idx_drops_one_live_per_seller: only one live drop per seller
INSERT INTO drops (
  id,
  seller_id,
  title,
  slug,
  status,
  shipping_fee_paisa,
  free_shipping_threshold_paisa,
  advance_confirmation_enabled,
  advance_amount_paisa,
  hold_duration_days,
  live_started_at,
  closed_at
) VALUES 
  -- Seller A Draft drop
  (
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6800'::uuid,
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    'Upcoming Festive Silk Drop',
    'festive-silk-drop',
    'draft',
    8000,
    200000,
    NULL, NULL, NULL,
    NULL,
    NULL
  ),
  -- Seller A Active Live drop
  (
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    'Friday Silk Special',
    'mothers-boutique',
    'live',
    8000,
    200000,
    NULL, NULL, NULL,
    NOW() - INTERVAL '1 hour',
    NULL
  ),
  -- Seller A Closed drop
  (
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6802'::uuid,
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    'Past Clearance Collection',
    'past-clearance',
    'closed',
    8000,
    200000,
    NULL, NULL, NULL,
    NOW() - INTERVAL '3 days',
    NOW() - INTERVAL '2 days'
  ),
  -- Seller B Active Live drop (Demonstrating drop-level advance override: ₹300)
  (
    'b2e87c53-5e47-4e3c-8912-c6f2df4e7902'::uuid,
    '7b218d60-3a09-4044-80c1-ce7018c4a401'::uuid,
    'Banarasi Festive Edit',
    'banarasi-festive-edit',
    'live',
    6000,
    150000,
    true,
    30000, -- ₹300.00 override on drop
    21,    -- 21 days hold override
    NOW() - INTERVAL '30 minutes',
    NULL
  ),
  -- Seller C Active Live drop (Full-payment only seller)
  (
    'a3d98d64-6f58-4f4d-9023-d7e3ef5f8013'::uuid,
    '6a107c50-2908-4033-70b0-bd6007b393f0'::uuid,
    'Handmade Linen Edit',
    'handmade-linen-edit',
    'live',
    5000,
    NULL,
    false, -- Inherits disabled
    NULL,
    NULL,
    NOW() - INTERVAL '15 minutes',
    NULL
  )
ON CONFLICT (id) DO NOTHING;

-- 4. Initial Orders (Demonstrating multi-dimensional order state machine)
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
  confirmation_mode,
  advance_required_paisa,
  advance_paid_paisa,
  total_paid_paisa,
  balance_due_paisa,
  payment_status,
  fulfilment_status,
  status,
  hold_expires_at,
  advance_paid_at,
  paid_at
) VALUES
  -- 1. Advance Confirmed Order (Active hold on #A02, ₹250 paid, ₹580 balance due)
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
    83000,  -- ₹830.00 total
    'advance',
    25000,  -- ₹250.00 advance
    25000,  -- ₹250.00 paid
    25000,  -- ₹250.00 total paid
    58000,  -- ₹580.00 balance due (> 0: NOT ready to ship)
    'advance_paid',
    'not_ready',
    'confirmed',
    NOW() + INTERVAL '29 days',
    NOW() - INTERVAL '1 hour',
    NULL
  ),
  -- 2. Fully Paid Order (Purchased #A03, total paid ₹1,330, balance due 0, ready to ship)
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
    'full_payment',
    0,
    0,
    133000,
    0,
    'paid',
    'ready_to_ship',
    'paid',
    NOW() + INTERVAL '15 minutes',
    NULL,
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
    'advance',
    25000,
    0,
    0,
    58000,
    'unpaid',
    'not_ready',
    'cancelled',
    NOW() - INTERVAL '1 hour',
    NULL,
    NULL
  ),
  -- 4. Shipped Order (Full payment verified, dispatched to buyer)
  (
    '7e057823-0144-442e-d644-9e5d324fa045'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    'LD-SHP101',
    '6b34a155-e814-4f44-20dd-6f17284bd367'::uuid,
    'Ananya Roy',
    '9830100004',
    '12 Ballygunge Circular Rd, Kolkata',
    '700019',
    95000,
    8000,
    103000,
    'full_payment',
    0,
    0,
    103000,
    0,
    'paid',
    'shipped',
    'shipped',
    NOW() - INTERVAL '2 days',
    NULL,
    NOW() - INTERVAL '2 days'
  ),
  -- 5. Expired Order (Advance hold expired, product reclaimed, advance retained non-refundable)
  (
    '8f168934-1255-453f-e755-af6e435fa056'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    'LD-EXP202',
    '5c45b266-f925-4a55-31ee-7a28395ce478'::uuid,
    'Vikram Sen',
    '9830100005',
    '88 Southern Avenue, Kolkata',
    '700029',
    110000,
    8000,
    118000,
    'advance',
    25000,
    25000,
    25000,
    93000,
    'advance_paid',
    'not_ready',
    'expired',
    NOW() - INTERVAL '2 days',
    NOW() - INTERVAL '32 days',
    NULL
  ),
  -- 6. Pending Advance Order (Initial checkout reservation, awaiting advance payment)
  (
    '9a279045-2366-464a-f866-ba7f546fa067'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    'LD-PND303',
    '4b56c377-a036-4b66-42ff-8b39406df589'::uuid,
    'Debanjan Bose',
    '9830100006',
    '55 Lake Gardens, Kolkata',
    '700045',
    185000,
    8000,
    193000,
    'advance',
    25000,
    0,
    0,
    193000,
    'unpaid',
    'not_ready',
    'pending',
    NOW() + INTERVAL '14 minutes',
    NULL,
    NULL
  ),
  -- 7. Seller B Pending Order (Awaiting seller verification of buyer claim)
  (
    '7a389156-3477-475b-a977-cb8a657ab078'::uuid,
    'b2e87c53-5e47-4e3c-8912-c6f2df4e7902'::uuid,
    'LD-ART404',
    '3a45b166-9924-4a55-11dd-7a18294bd278'::uuid,
    'Kavita Verma',
    '9830100007',
    '10 Ballygunge Place, Kolkata',
    '700019',
    240000,
    6000,
    246000,
    'advance',
    30000,
    0,
    0,
    246000,
    'unpaid',
    'not_ready',
    'pending',
    NOW() + INTERVAL '14 minutes',
    NULL,
    NULL
  )
ON CONFLICT (id) DO NOTHING;

-- 5. Products on Drops Across Sellers
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
  -- Seller A Products
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
  (
    'a8219c11-1b22-4899-b1cc-c112d2950de2'::uuid,
    'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
    '#A02',
    'Chanderi Cotton Kurti',
    75000, -- ₹750.00
    'L',
    'https://images.livedrop.store/products/a821.webp',
    'reserved',
    NOW() - INTERVAL '1 hour',
    '4b724590-7811-419b-a311-6b2a091df012'::uuid,
    2
  ),
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
  ),
  -- Seller B Products
  (
    'd5318a22-4e66-4199-a3cc-f112e3061da5'::uuid,
    'b2e87c53-5e47-4e3c-8912-c6f2df4e7902'::uuid,
    '#B01',
    'Katan Silk Banarasi Saree',
    240000, -- ₹2,400.00
    'Free Size',
    'https://images.livedrop.store/products/d531.webp',
    'reserved',
    NOW() - INTERVAL '10 minutes',
    '7a389156-3477-475b-a977-cb8a657ab078'::uuid,
    1
  ),
  -- Seller C Products
  (
    'c4207b11-3d55-4088-92bb-e001d2950cf6'::uuid,
    'a3d98d64-6f58-4f4d-9023-d7e3ef5f8013'::uuid,
    '#C01',
    'Handspun Linen Shirt',
    110000, -- ₹1,100.00
    'XL',
    'https://images.livedrop.store/products/c420.webp',
    'available',
    NULL,
    NULL,
    1
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
  ),
  (
    '5c341f00-3366-4044-b233-0332e3061dc3'::uuid,
    '7e057823-0144-442e-d644-9e5d324fa045'::uuid,
    'b6415d99-2a33-4188-89bb-d110d2950dc4'::uuid,
    95000
  ),
  (
    '6d452011-4477-4155-c344-1443f4172ed4'::uuid,
    '7a389156-3477-475b-a977-cb8a657ab078'::uuid,
    'd5318a22-4e66-4199-a3cc-f112e3061da5'::uuid,
    240000
  )
ON CONFLICT (id) DO NOTHING;

-- 7. Order Payments Recording (Capturing historical transaction events)
INSERT INTO order_payments (
  id,
  order_id,
  payment_type,
  amount_paisa,
  status,
  reference_id,
  verified_at,
  verified_by
) VALUES
  -- Advance payment verified for order 4b724590
  (
    '1f238e77-9911-4233-88bb-a110e2849dc1'::uuid,
    '4b724590-7811-419b-a311-6b2a091df012'::uuid,
    'advance',
    25000,
    'verified',
    '428739182734',
    NOW() - INTERVAL '1 hour',
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid
  ),
  -- Full payment verified for order 5c835601
  (
    '2e349f88-0022-4344-99cc-b221f3950ed2'::uuid,
    '5c835601-8922-420c-b422-7c3b102ef023'::uuid,
    'full',
    133000,
    'verified',
    '428739182735',
    NOW() - INTERVAL '30 minutes',
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid
  ),
  -- Full payment verified for shipped order 7e057823
  (
    '3f45a099-1133-4455-aa00-c332a4061fe3'::uuid,
    '7e057823-0144-442e-d644-9e5d324fa045'::uuid,
    'full',
    103000,
    'verified',
    '428739182736',
    NOW() - INTERVAL '2 days',
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid
  ),
  -- Retained advance payment for expired order 8f168934
  (
    '4a56b100-2244-4566-bb11-d443b5172af4'::uuid,
    '8f168934-1255-453f-e755-af6e435fa056'::uuid,
    'advance',
    25000,
    'verified',
    '428739182737',
    NOW() - INTERVAL '32 days',
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid
  )
ON CONFLICT (id) DO NOTHING;

-- 8. Payment Attempts (TASK-2.4B Direct UPI & Manual Verification Tracking)
INSERT INTO payment_attempts (
  id,
  order_id,
  payment_type,
  payment_method,
  expected_amount_paisa,
  payee_vpa_snapshot,
  payee_display_name_snapshot,
  transaction_reference,
  status,
  buyer_claimed_at,
  buyer_submitted_utr,
  seller_verified_at,
  verified_by,
  expires_at
) VALUES
  -- Initial awaiting payment attempt for pending Order 6 (9a279045)
  (
    'a1000000-0000-0000-0000-000000000001'::uuid,
    '9a279045-2366-464a-f866-ba7f546fa067'::uuid,
    'advance',
    'upi',
    25000,
    'mothersboutique@okaxis',
    'Mother''s Boutique Official',
    'LD-PND303-ADV-1001',
    'awaiting_payment',
    NULL,
    NULL,
    NULL,
    NULL,
    NOW() + INTERVAL '14 minutes'
  ),
  -- Verified advance payment attempt for confirmed Order 2 (4b724590)
  (
    'a1000000-0000-0000-0000-000000000002'::uuid,
    '4b724590-7811-419b-a311-6b2a091df012'::uuid,
    'advance',
    'upi',
    25000,
    'mothersboutique@okaxis',
    'Mother''s Boutique Official',
    'LD-8F429B-ADV-1002',
    'verified',
    NOW() - INTERVAL '1 hour 5 minutes',
    '428739182734',
    NOW() - INTERVAL '1 hour',
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    NOW() + INTERVAL '30 days'
  ),
  -- Verified full payment attempt for paid Order 4 (5c835601)
  (
    'a1000000-0000-0000-0000-000000000003'::uuid,
    '5c835601-8922-420c-b422-7c3b102ef023'::uuid,
    'full',
    'upi',
    133000,
    'mothersboutique@okaxis',
    'Mother''s Boutique Official',
    'LD-2C304E-FUL-1003',
    'verified',
    NOW() - INTERVAL '35 minutes',
    '428739182735',
    NOW() - INTERVAL '30 minutes',
    '8a329e71-4b10-4055-90d2-df8029d5b512'::uuid,
    NOW() + INTERVAL '15 minutes'
  ),
  -- Awaiting seller verification payment claim for Seller B Order 7 (7a389156)
  (
    'a1000000-0000-0000-0000-000000000004'::uuid,
    '7a389156-3477-475b-a977-cb8a657ab078'::uuid,
    'advance',
    'upi',
    30000,
    'artisansilks@upi',
    'Artisan Silks Handlooms',
    'LD-ART404-ADV-1004',
    'awaiting_seller_verification',
    NOW() - INTERVAL '10 minutes',
    '428739182738',
    NULL,
    NULL,
    NOW() + INTERVAL '14 days'
  )
ON CONFLICT (id) DO NOTHING;

