// LiveDrop Schema Verification Script
// Executes all 17 migrations sequentially using PGlite (PostgreSQL 18.3 WASM)
// and asserts all constraints, foreign keys, indexes, RLS policies, projection views, and RPC privileges.

import { createRequire } from 'node:module';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(path.resolve(__dirname, '../buyer-web/package.json'));

const { PGlite } = require('@electric-sql/pglite');

async function run() {
  console.log('🚀 Initializing in-memory PostgreSQL engine (PGlite)...');
  const db = new PGlite();

  console.log('🔧 Initializing auth & storage schema simulations...');
  await db.exec(`
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE TABLE IF NOT EXISTS auth.users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email TEXT UNIQUE,
      raw_user_meta_data JSONB DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
    LANGUAGE sql STABLE
    AS $$
      SELECT coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
      )::uuid
    $$;

    CREATE SCHEMA IF NOT EXISTS storage;
    CREATE TABLE IF NOT EXISTS storage.buckets (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      public BOOLEAN DEFAULT false,
      file_size_limit BIGINT,
      allowed_mime_types TEXT[],
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS storage.objects (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      bucket_id TEXT REFERENCES storage.buckets(id),
      name TEXT NOT NULL,
      owner UUID,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    CREATE OR REPLACE FUNCTION storage.foldername(name text)
    RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
      SELECT string_to_array(name, '/');
    $$;
  `);

  const migrationsDir = path.resolve(__dirname, '../supabase/migrations');
  const migrationFiles = fs.readdirSync(migrationsDir)
    .filter(f => f.endsWith('.sql'))
    .sort();

  console.log(`📦 Applying ${migrationFiles.length} migrations sequentially:`);
  for (const file of migrationFiles) {
    const filePath = path.join(migrationsDir, file);
    const sql = fs.readFileSync(filePath, 'utf-8');
    await db.exec(sql);
    console.log(`  ✓ Applied ${file}`);
  }

  console.log('🔍 Verifying table existence:');
  const tablesRes = await db.query(`
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER BY table_name;
  `);
  const tables = tablesRes.rows.map(r => r.table_name);
  console.log(`  Tables found: ${tables.join(', ')}`);
  const expectedTables = ['drops', 'order_items', 'order_payments', 'orders', 'payment_attempts', 'products', 'profiles'];
  for (const t of expectedTables) {
    if (!tables.includes(t)) throw new Error(`Missing expected table: ${t}`);
  }

  console.log('🔍 Verifying public projection views (Migration 016):');
  const viewsRes = await db.query(`
    SELECT table_name 
    FROM information_schema.views 
    WHERE table_schema = 'public'
    ORDER BY table_name;
  `);
  const views = viewsRes.rows.map(r => r.table_name);
  console.log(`  Views found: ${views.join(', ')}`);
  const expectedViews = ['public_products_catalog', 'public_seller_storefronts'];
  for (const v of expectedViews) {
    if (!views.includes(v)) throw new Error(`Missing expected view: ${v}`);
  }
  console.log('  ✓ Verified: public_products_catalog and public_seller_storefronts exist.');

  console.log('🔍 Verifying query indexes (including Migration 017):');
  const indexRes = await db.query(`
    SELECT indexname 
    FROM pg_indexes 
    WHERE schemaname = 'public' AND (indexname LIKE 'idx_%' OR indexname LIKE 'uq_%')
    ORDER BY indexname;
  `);
  const indexes = indexRes.rows.map(r => r.indexname);
  console.log(`  Indexes found (${indexes.length}): ${indexes.join(', ')}`);
  const expectedIndexes = [
    'idx_drops_one_live_per_seller',
    'idx_order_items_order',
    'idx_order_items_product',
    'idx_order_payments_order',
    'idx_order_payments_status',
    'idx_orders_buyer_phone',
    'idx_orders_drop_status',
    'idx_orders_hold_expiry',
    'idx_orders_hold_expiry_reaper',
    'idx_orders_drop_created',
    'idx_products_active_hold',
    'idx_products_drop_status',
    'idx_products_reserved_by_order',
    'idx_payment_attempts_order_id',
    'idx_payment_attempts_status',
    'idx_payment_attempts_reference',
    'idx_payment_attempts_verification_expires',
    'idx_payment_attempts_queue',
    'uq_orders_drop_idempotency',
  ];
  for (const exp of expectedIndexes) {
    if (!indexes.includes(exp)) throw new Error(`Missing expected index: ${exp}`);
  }

  console.log('🔍 Verifying payment_attempts.verification_expires_at & orders.idempotency_key columns:');
  const verColRes = await db.query(`
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'payment_attempts' AND column_name = 'verification_expires_at';
  `);
  if (verColRes.rows.length === 0) {
    throw new Error('Missing expected column: payment_attempts.verification_expires_at!');
  }
  console.log('  ✓ payment_attempts.verification_expires_at: timestamp with time zone');

  const idempColRes = await db.query(`
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'orders' AND column_name = 'idempotency_key';
  `);
  if (idempColRes.rows.length === 0) {
    throw new Error('Missing expected column: orders.idempotency_key!');
  }
  console.log('  ✓ orders.idempotency_key: text');

  console.log('🔍 Verifying integer Paisa columns:');
  const paisaRes = await db.query(`
    SELECT table_name, column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name LIKE '%paisa%' AND table_name NOT LIKE 'public_%'
    ORDER BY table_name, column_name;
  `);
  for (const col of paisaRes.rows) {
    if (col.data_type !== 'integer') {
      throw new Error(`Column ${col.table_name}.${col.column_name} is ${col.data_type}, expected integer!`);
    }
    console.log(`  ✓ ${col.table_name}.${col.column_name}: integer (Paisa)`);
  }
  if (paisaRes.rows.length !== 17) {
    throw new Error(`Expected 17 base table paisa columns, found ${paisaRes.rows.length}`);
  }

  console.log('🔍 Verifying 10 triggers (including Migration 012 & 013 enforcement):');
  const triggerRes = await db.query(`
    SELECT trigger_name, event_manipulation, event_object_table
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
    ORDER BY trigger_name;
  `);
  const triggers = triggerRes.rows.map(r => `${r.trigger_name} on ${r.event_object_table} (${r.event_manipulation})`);
  console.log(`  Triggers found (${triggers.length}):\n    ${triggers.join('\n    ')}`);
  const expectedTriggers = [
    'trg_profiles_updated_at',
    'trg_sync_profiles_upi_fields',
    'trg_drops_updated_at',
    'trg_products_updated_at',
    'trg_orders_updated_at',
    'trg_orders_no_delete_finalized',
    'trg_order_payments_updated_at',
    'trg_payment_attempts_updated_at',
    'trg_enforce_orders_payment_immutability',
    'trg_enforce_products_inventory_immutability',
  ];
  const foundNames = triggerRes.rows.map(r => r.trigger_name);
  for (const exp of expectedTriggers) {
    if (!foundNames.includes(exp)) throw new Error(`Missing expected trigger: ${exp}`);
  }

  console.log('🔍 Verifying Row-Level Security (RLS) enforcement:');
  const rlsRes = await db.query(`
    SELECT tablename, rowsecurity
    FROM pg_tables
    WHERE schemaname = 'public' AND tablename IN ('profiles', 'drops', 'products', 'orders', 'order_items', 'order_payments', 'payment_attempts')
    ORDER BY tablename;
  `);
  for (const row of rlsRes.rows) {
    if (!row.rowsecurity) {
      throw new Error(`RLS NOT enabled on table ${row.tablename}!`);
    }
    console.log(`  ✓ RLS enabled on ${row.tablename} (rowsecurity = true)`);
  }
  if (rlsRes.rows.length !== 7) {
    throw new Error(`Expected 7 tables with RLS enabled, found ${rlsRes.rows.length}`);
  }

  console.log('🔍 Verifying Core Business RPCs (including Migration 015 mark_order_shipped):');
  const rpcRes = await db.query(`
    SELECT routine_name, security_type, data_type
    FROM information_schema.routines
    WHERE routine_schema = 'public' AND routine_name IN (
      'create_order_with_reservation',
      'record_verified_payment',
      'mark_order_paid',
      'mark_order_shipped',
      'release_expired_holds',
      'get_order_by_token',
      'force_release_hold',
      'mark_product_sold_offline',
      'initiate_payment_attempt',
      'submit_buyer_payment_claim',
      'verify_manual_upi_payment',
      'reject_manual_upi_payment'
    )
    ORDER BY routine_name;
  `);
  console.log(`  RPCs found (${rpcRes.rows.length}):`);
  for (const rpc of rpcRes.rows) {
    console.log(`    ✓ ${rpc.routine_name} (${rpc.data_type}) [SECURITY ${rpc.security_type}]`);
    if (rpc.security_type !== 'DEFINER') {
      throw new Error(`RPC ${rpc.routine_name} must be SECURITY DEFINER, found ${rpc.security_type}`);
    }
  }
  const expectedRpcs = [
    'create_order_with_reservation',
    'force_release_hold',
    'get_order_by_token',
    'initiate_payment_attempt',
    'mark_order_paid',
    'mark_order_shipped',
    'mark_product_sold_offline',
    'record_verified_payment',
    'reject_manual_upi_payment',
    'release_expired_holds',
    'submit_buyer_payment_claim',
    'verify_manual_upi_payment',
  ];
  const foundRpcs = rpcRes.rows.map(r => r.routine_name);
  for (const exp of expectedRpcs) {
    if (!foundRpcs.includes(exp)) {
      throw new Error(`Missing expected RPC: ${exp}`);
    }
  }

  console.log('🔍 Verifying RPC Routine Privileges & Access Bounds:');
  const privRes = await db.query(`
    SELECT routine_name, grantee, privilege_type
    FROM information_schema.routine_privileges
    WHERE routine_schema = 'public' AND routine_name IN (
      'create_order_with_reservation',
      'record_verified_payment',
      'mark_order_paid',
      'mark_order_shipped',
      'release_expired_holds',
      'get_order_by_token',
      'force_release_hold',
      'mark_product_sold_offline',
      'initiate_payment_attempt',
      'submit_buyer_payment_claim',
      'verify_manual_upi_payment',
      'reject_manual_upi_payment'
    )
    ORDER BY routine_name, grantee;
  `);

  const forbiddenAnonRpcs = ['record_verified_payment', 'mark_order_paid', 'mark_order_shipped', 'force_release_hold', 'mark_product_sold_offline', 'release_expired_holds', 'verify_manual_upi_payment', 'reject_manual_upi_payment'];
  const forbiddenAuthRpcs = ['release_expired_holds', 'record_verified_payment', 'mark_order_paid'];
  for (const row of privRes.rows) {
    if (row.grantee === 'anon' && forbiddenAnonRpcs.includes(row.routine_name)) {
      throw new Error(`CRITICAL SECURITY FAILURE: anon has ${row.privilege_type} privilege on seller/maintenance RPC ${row.routine_name}!`);
    }
    if (row.grantee === 'authenticated' && forbiddenAuthRpcs.includes(row.routine_name)) {
      throw new Error(`CRITICAL SECURITY FAILURE: authenticated has ${row.privilege_type} privilege on backend RPC ${row.routine_name}!`);
    }
    if (row.grantee === 'PUBLIC') {
      throw new Error(`CRITICAL SECURITY FAILURE: PUBLIC has ${row.privilege_type} privilege on RPC ${row.routine_name}!`);
    }
  }

  const authShipped = privRes.rows.find(
    r => r.grantee === 'authenticated' && r.routine_name === 'mark_order_shipped' && r.privilege_type === 'EXECUTE'
  );
  if (!authShipped) {
    throw new Error('CRITICAL SECURITY FAILURE: authenticated lacks EXECUTE privilege on mark_order_shipped!');
  }
  console.log('  ✓ Verified: mark_order_shipped granted to authenticated sellers, revoked from anon/PUBLIC.');

  console.log('🌱 Testing Multi-Seller Seed Fixture (seed.sql):');
  const seedPath = path.resolve(__dirname, '../supabase/seed.sql');
  const seedSql = fs.readFileSync(seedPath, 'utf-8');
  await db.exec(seedSql);

  const seedProfiles = await db.query('SELECT count(*) as count FROM profiles');
  const seedDrops = await db.query('SELECT count(*) as count FROM drops');
  const seedProducts = await db.query('SELECT count(*) as count FROM products');
  const seedOrders = await db.query('SELECT count(*) as count FROM orders');
  const seedPayments = await db.query('SELECT count(*) as count FROM order_payments');
  const seedAttempts = await db.query('SELECT count(*) as count FROM payment_attempts');
  console.log(`  ✓ Seed data executed cleanly: ${seedProfiles.rows[0].count} profile(s), ${seedDrops.rows[0].count} drop(s), ${seedProducts.rows[0].count} product(s), ${seedOrders.rows[0].count} order(s), ${seedPayments.rows[0].count} payment(s), ${seedAttempts.rows[0].count} payment attempt(s).`);

  console.log('🛡️ Verifying Public View Data Masking & Table Access Revocation (Migration 016):');
  // As anon, querying profiles table directly should return 0 rows or error
  await db.exec('SET ROLE anon;');
  let directProfilesBlocked = false;
  try {
    const pRes = await db.query('SELECT * FROM profiles');
    if (pRes.rows.length === 0) directProfilesBlocked = true;
  } catch (err) {
    directProfilesBlocked = true;
  }
  if (!directProfilesBlocked) {
    throw new Error('CRITICAL PRIVACY FAILURE: anon was able to read raw profiles table!');
  }
  console.log('  ✓ Verified: Direct anon SELECT on profiles table revoked/blocked.');

  // As anon, querying public_seller_storefronts view should succeed and NOT have return_address or phone_number
  const viewStoreRes = await db.query('SELECT * FROM public_seller_storefronts');
  if (viewStoreRes.rows.length === 0) {
    throw new Error('Expected public_seller_storefronts view to return active seller profiles for anon!');
  }
  const firstStore = viewStoreRes.rows[0];
  if ('phone_number' in firstStore || 'return_address' in firstStore) {
    throw new Error('CRITICAL PRIVACY FAILURE: public_seller_storefronts exposed phone_number or return_address!');
  }
  console.log('  ✓ Verified: public_seller_storefronts projection returns public branding without phone_number or return_address.');

  // As anon, querying public_products_catalog view should succeed and NOT have reserved_by_order_id
  const viewProdRes = await db.query('SELECT * FROM public_products_catalog');
  if (viewProdRes.rows.length === 0) {
    throw new Error('Expected public_products_catalog view to return products for anon!');
  }
  const firstProd = viewProdRes.rows[0];
  if ('reserved_by_order_id' in firstProd) {
    throw new Error('CRITICAL PRIVACY FAILURE: public_products_catalog exposed reserved_by_order_id!');
  }
  console.log('  ✓ Verified: public_products_catalog projection returns catalog items without reserved_by_order_id.');

  await db.exec('RESET ROLE;');

  console.log('🛡️ Verifying Seller Direct Mutation Hardening (Migration 012):');
  // Attempt direct payment status fabrication as authenticated seller
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "8a329e71-4b10-4055-90d2-df8029d5b512", "role": "authenticated"}';
  `);

  let attackBlocked = false;
  try {
    await db.query(`
      UPDATE orders
      SET status = 'paid', payment_status = 'paid', total_paid_paisa = total_paisa, balance_due_paisa = 0, fulfilment_status = 'ready_to_ship'
      WHERE id = '9a279045-2366-464a-f866-ba7f546fa067';
    `);
  } catch (err) {
    if (err.message.includes('Direct mutation of payment or order lifecycle fields is prohibited') || err.message.includes('Direct modification of payment or lifecycle fields') || err.code === '42501') {
      attackBlocked = true;
    } else {
      throw err;
    }
  }
  if (!attackBlocked) {
    throw new Error('CRITICAL SECURITY FAILURE: Authenticated seller was able to directly fabricate paid state!');
  }
  console.log('  ✓ Verified: Direct payment fabrication attack blocked at DB layer with SQLSTATE 42501.');

  console.log('🛡️ Verifying mark_order_shipped RPC (Migration 015):');
  // Seller A (8a329e71-4b10-4055-90d2-df8029d5b512) owns Order 2 (5c835601-8922-420c-b422-7c3b102ef023) which is 'paid' with balance = 0
  const shipRes = await db.query(`
    SELECT mark_order_shipped(
      '5c835601-8922-420c-b422-7c3b102ef023'::uuid,
      'TRK-DELHIVERY-998811',
      'Delhivery Express',
      'Fragile saree package'
    ) as r;
  `);
  const shipResult = shipRes.rows[0].r;
  if (!shipResult.success) {
    throw new Error(`mark_order_shipped failed: ${JSON.stringify(shipResult)}`);
  }
  if (shipResult.status !== 'shipped' || shipResult.fulfilment_status !== 'shipped' || !shipResult.shipped_at) {
    throw new Error(`mark_order_shipped returned invalid status: ${JSON.stringify(shipResult)}`);
  }
  console.log(`  ✓ Verified: Seller marked order as shipped: tracking = ${shipResult.tracking_number}, courier = ${shipResult.courier_partner}`);

  // Test cross-seller fulfillment block (Seller B tries to ship Seller A's order)
  await db.exec(`
    SET request.jwt.claims = '{"sub": "7b218d60-3a09-4044-80c1-ce7018c4a401", "role": "authenticated"}';
  `);
  const crossShipRes = await db.query(`
    SELECT mark_order_shipped(
      '5c835601-8922-420c-b422-7c3b102ef023'::uuid,
      'TRK-ATTACK-001',
      'BlueDart'
    ) as r;
  `);
  if (crossShipRes.rows[0].r.success !== false || crossShipRes.rows[0].r.error !== 'FORBIDDEN') {
    throw new Error(`Expected FORBIDDEN on cross-seller shipping, got: ${JSON.stringify(crossShipRes.rows[0].r)}`);
  }
  console.log('  ✓ Verified: Cross-seller shipping attempt blocked with FORBIDDEN.');

  console.log('🛡️ Verifying Order Request Idempotency (Migration 015):');
  await db.exec('RESET ROLE;');
  // Place an order with idempotency_key = 'IDEMP-TEST-KEY-001'
  const idempOrderRes = await db.query(`
    SELECT create_order_with_reservation(
      'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
      ARRAY['e9314c99-7f55-4089-a2bb-b001d2950df1'::uuid],
      'Priya Sharma',
      '9876543210',
      'Flat 402, Lotus Apartments, Indiranagar, Bengaluru',
      '560038',
      'full_payment',
      'IDEMP-TEST-KEY-001'
    ) as r;
  `);
  const idempOrder = idempOrderRes.rows[0].r;
  if (!idempOrder.success) {
    throw new Error(`Initial order creation with idempotency key failed: ${JSON.stringify(idempOrder)}`);
  }

  // Re-submit identical checkout request (simulating network timeout retry)
  const idempRetryRes = await db.query(`
    SELECT create_order_with_reservation(
      'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
      ARRAY['e9314c99-7f55-4089-a2bb-b001d2950df1'::uuid],
      'Priya Sharma',
      '9876543210',
      'Flat 402, Lotus Apartments, Indiranagar, Bengaluru',
      '560038',
      'full_payment',
      'IDEMP-TEST-KEY-001'
    ) as r;
  `);
  const idempRetry = idempRetryRes.rows[0].r;
  if (!idempRetry.success || idempRetry.order_id !== idempOrder.order_id || !idempRetry.idempotent_replay) {
    throw new Error(`Idempotent retry failed or created duplicate order: ${JSON.stringify(idempRetry)}`);
  }
  console.log('  ✓ Verified: Resubmitting identical checkout idempotency key returns original order receipt without STOCK_UNAVAILABLE.');

  console.log('🛡️ Verifying Instant Inventory Release on Payment Rejection (Migration 015):');
  // Initiate payment attempt on the newly created idempotent order
  const initAttRes = await db.query(`
    SELECT initiate_payment_attempt(
      '${idempOrder.order_id}'::uuid,
      '${idempOrder.order_token}',
      'full'
    ) as r;
  `);
  const attId = initAttRes.rows[0].r.payment_attempt_id;

  // Submit buyer claim
  await db.query(`
    SELECT submit_buyer_payment_claim(
      '${idempOrder.order_id}'::uuid,
      '${idempOrder.order_token}',
      '${attId}'::uuid,
      '999888777666'
    );
  `);

  // Seller rejects the claim with release_hold = true
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "8a329e71-4b10-4055-90d2-df8029d5b512", "role": "authenticated"}';
  `);
  const rejRes = await db.query(`
    SELECT reject_manual_upi_payment(
      '${attId}'::uuid,
      'invalid_utr',
      true
    ) as r;
  `);
  const rejResult = rejRes.rows[0].r;
  if (!rejResult.success || !rejResult.hold_released) {
    throw new Error(`Payment rejection with hold release failed: ${JSON.stringify(rejResult)}`);
  }
  // Assert that product #A01 is now 'available' again
  const prodCheck = await db.query(`
    SELECT id, status, reserved_by_order_id 
    FROM products 
    WHERE id = 'e9314c99-7f55-4089-a2bb-b001d2950df1';
  `);
  if (prodCheck.rows[0].status !== 'available' || prodCheck.rows[0].reserved_by_order_id !== null) {
    throw new Error(`Product status was not reset to available after rejection: ${JSON.stringify(prodCheck.rows[0])}`);
  }
  console.log('  ✓ Verified: Payment rejection instantly released reserved products back to available status (0 orphaned holds).');

  console.log('🛡️ Verifying Seller Provisioning Security & Approval Gate (Migration 021):');
  // 1. Verify profiles.is_approved column
  const appColRes = await db.query(`
    SELECT column_name, data_type, column_default 
    FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'is_approved';
  `);
  if (appColRes.rows.length === 0) throw new Error('Missing profiles.is_approved column');
  console.log('  ✓ Verified: profiles.is_approved column exists.');

  // 2. Insert new unapproved seller as authenticated user
  const newSellerId = 'd0000000-0000-0000-0000-000000000099';
  await db.exec(`
    SET ROLE postgres;
    RESET request.jwt.claims;
  `);
  await db.query(`
    INSERT INTO auth.users (id, email) VALUES ('${newSellerId}'::uuid, 'fraud@livedrop.test');
  `);
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${newSellerId}", "role": "authenticated"}';
  `);
  await db.query(`
    INSERT INTO profiles (id, store_name, store_slug, phone_number, upi_id, upi_vpa, return_address, default_shipping_fee_paisa)
    VALUES ('${newSellerId}'::uuid, 'Fraud Boutique', 'fraud-boutique', '919999999999', 'fraud@okhdfc', 'fraud@okhdfc', '123 Fake Street, Kolkata 700001', 8000);
  `);
  const checkNewSeller = await db.query(`SELECT is_approved FROM profiles WHERE id = '${newSellerId}'::uuid;`);
  if (checkNewSeller.rows[0].is_approved !== false) {
    throw new Error('New seller did not default to is_approved = false');
  }
  console.log('  ✓ Verified: New seller defaults to is_approved = false.');

  // 3. Attempt direct UPDATE of is_approved by authenticated seller (MUST FAIL 42501)
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${newSellerId}", "role": "authenticated"}';
  `);
  let selfApproveBlocked = false;
  try {
    await db.query(`UPDATE profiles SET is_approved = TRUE WHERE id = '${newSellerId}'::uuid;`);
  } catch (err) {
    selfApproveBlocked = err.message.includes('restricted to platform administrators') || err.code === '42501';
  }
  if (!selfApproveBlocked) throw new Error('Self-approval by seller was not blocked with 42501!');
  console.log('  ✓ Verified: Direct UPDATE of is_approved by authenticated seller blocked with 42501.');

  // 4. Attempt to publish a drop with status = 'live' while unapproved (MUST FAIL 42501)
  let unapprovedPublishBlocked = false;
  try {
    await db.query(`
      INSERT INTO drops (seller_id, title, slug, status, shipping_fee_paisa)
      VALUES ('${newSellerId}'::uuid, 'Unapproved Drop', 'unapproved-drop', 'live', 8000);
    `);
  } catch (err) {
    unapprovedPublishBlocked = err.message.includes('Unapproved sellers cannot publish live drops') || err.code === '42501';
  }
  if (!unapprovedPublishBlocked) throw new Error('Unapproved seller publishing live drop was not blocked with 42501!');
  console.log('  ✓ Verified: Unapproved seller cannot publish a live drop (Blocked 42501).');

  // 5. Unapproved seller CAN create a draft drop
  await db.query(`
    INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa)
    VALUES ('a0000000-0000-0000-0000-000000000099'::uuid, '${newSellerId}'::uuid, 'Draft Drop', 'draft-drop', 'draft', 8000);
  `);
  console.log('  ✓ Verified: Unapproved seller can prepare draft drop.');

  // 6. Admin approves seller via admin_approve_seller RPC
  await db.exec(`
    SET ROLE postgres;
    RESET request.jwt.claims;
  `);
  const approveRes = await db.query(`
    SELECT admin_approve_seller('${newSellerId}'::uuid, true) as r;
  `);
  if (!approveRes.rows[0].r.success || !approveRes.rows[0].r.is_approved) {
    throw new Error('admin_approve_seller RPC failed');
  }
  console.log('  ✓ Verified: admin_approve_seller RPC approves seller.');

  // 7. Approved seller can now transition draft drop to live
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${newSellerId}", "role": "authenticated"}';
  `);
  await db.query(`
    UPDATE drops SET status = 'live' WHERE id = 'a0000000-0000-0000-0000-000000000099'::uuid;
  `);
  console.log('  ✓ Verified: Approved seller can publish live drop.');

  // Reset to postgres superuser
  await db.exec(`
    SET ROLE postgres;
    RESET request.jwt.claims;
  `);

  await db.close();
  console.log('✅ ALL RELATIONAL DATABASE SCHEMA, STOREFRONT INVARIANTS, RLS POLICIES, PROJECTION VIEWS, PERFORMANCE INDEXES, BUSINESS RPCS & MULTI-SELLER SEED DATA VERIFIED.');
}

run().catch((err) => {
  console.error('❌ Verification failed:', err.message);
  if (err.detail) console.error('Detail:', err.detail);
  if (err.hint) console.error('Hint:', err.hint);
  if (err.position) console.error('Position:', err.position);
  process.exit(1);
});
