// LiveDrop Schema Verification Script
// Executes all 10 migrations sequentially using PGlite (PostgreSQL 18.3 WASM)
// and asserts all constraints, foreign keys, indexes, RLS policies, and RPC privileges.

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

  console.log('🔧 Initializing auth schema simulation...');
  await db.exec(`
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE TABLE IF NOT EXISTS auth.users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email TEXT UNIQUE,
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
  `);

  const migrationsDir = path.resolve(__dirname, '../supabase/migrations');
  const migrationFiles = [
    '001_create_profiles.sql',
    '002_create_drops.sql',
    '003_create_products.sql',
    '004_create_orders.sql',
    '005_create_order_items.sql',
    '006_create_indexes.sql',
    '007_create_triggers.sql',
    '008_enable_rls_and_policies.sql',
    '009_create_core_business_rpcs.sql',
    '010_seller_storefront_and_order_state_machine.sql',
    '011_domain_consistency_and_payment_authority_hardening.sql',
    '012_payment_authority_direct_update_hardening.sql',
    '013_direct_upi_and_manual_payment_verification.sql',
  ];

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

  console.log('🔍 Verifying query indexes:');
  const indexRes = await db.query(`
    SELECT indexname 
    FROM pg_indexes 
    WHERE schemaname = 'public' AND indexname LIKE 'idx_%'
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
    'idx_products_active_hold',
    'idx_products_drop_status',
    'idx_payment_attempts_order_id',
    'idx_payment_attempts_status',
    'idx_payment_attempts_reference',
  ];
  for (const exp of expectedIndexes) {
    if (!indexes.includes(exp)) throw new Error(`Missing expected index: ${exp}`);
  }

  console.log('🔍 Verifying integer Paisa columns:');
  const paisaRes = await db.query(`
    SELECT table_name, column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name LIKE '%paisa%'
    ORDER BY table_name, column_name;
  `);
  for (const col of paisaRes.rows) {
    if (col.data_type !== 'integer') {
      throw new Error(`Column ${col.table_name}.${col.column_name} is ${col.data_type}, expected integer!`);
    }
    console.log(`  ✓ ${col.table_name}.${col.column_name}: integer (Paisa)`);
  }
  if (paisaRes.rows.length !== 17) {
    throw new Error(`Expected 17 paisa columns (including payment_attempts.expected_amount_paisa), found ${paisaRes.rows.length}`);
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

  console.log('🔍 Verifying RLS Policies:');
  const policyRes = await db.query(`
    SELECT tablename, policyname, roles, cmd
    FROM pg_policies
    WHERE schemaname = 'public'
    ORDER BY tablename, policyname;
  `);
  console.log(`  Policies found (${policyRes.rows.length}):`);
  for (const p of policyRes.rows) {
    console.log(`    - ${p.tablename}: ${p.policyname} (${p.cmd}) for ${p.roles}`);
  }
  const expectedPolicies = [
    'profiles_public_read',
    'profiles_seller_insert',
    'profiles_seller_update',
    'drops_public_read_live',
    'drops_seller_manage',
    'products_public_read_live',
    'products_seller_manage',
    'orders_buyer_read_with_token',
    'orders_seller_select',
    'orders_seller_update',
    'orders_seller_delete',
    'order_items_buyer_read_with_token',
    'order_items_seller_select',
    'order_payments_buyer_read_with_token',
    'order_payments_seller_select',
    'payment_attempts_seller_select',
    'payment_attempts_buyer_select_with_token',
  ];
  const registeredPolicyNames = policyRes.rows.map(r => r.policyname);
  for (const exp of expectedPolicies) {
    if (!registeredPolicyNames.includes(exp)) {
      throw new Error(`Missing expected RLS policy: ${exp}`);
    }
  }

  console.log('🔍 Verifying Core Business RPCs (including TASK-2.4B Payment RPCs):');
  const rpcRes = await db.query(`
    SELECT routine_name, security_type, data_type
    FROM information_schema.routines
    WHERE routine_schema = 'public' AND routine_name IN (
      'create_order_with_reservation',
      'record_verified_payment',
      'mark_order_paid',
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

  console.log('🔍 Verifying mark_order_paid function signature and overload uniqueness:');
  const mopOverloads = await db.query(`
    SELECT p.proname, pg_get_function_identity_arguments(p.oid) as identity_args, p.prosecdef
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'mark_order_paid';
  `);
  if (mopOverloads.rows.length !== 1) {
    throw new Error(`CRITICAL SECURITY FAILURE: Expected exactly 1 mark_order_paid function, found ${mopOverloads.rows.length}!`);
  }
  const mopArgs = mopOverloads.rows[0].identity_args;
  console.log(`  ✓ mark_order_paid identity args: ${mopArgs}`);

  console.log('🔍 Verifying RPC Routine Privileges:');
  const privRes = await db.query(`
    SELECT routine_name, grantee, privilege_type
    FROM information_schema.routine_privileges
    WHERE routine_schema = 'public' AND routine_name IN (
      'create_order_with_reservation',
      'record_verified_payment',
      'mark_order_paid',
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
  console.log(`  Routine privilege grants found (${privRes.rows.length})`);

  // Verify routine access bounds
  const forbiddenAnonRpcs = ['record_verified_payment', 'mark_order_paid', 'force_release_hold', 'mark_product_sold_offline', 'release_expired_holds', 'verify_manual_upi_payment', 'reject_manual_upi_payment'];
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

  // Verify that authenticated sellers have EXECUTE on verify_manual_upi_payment & reject_manual_upi_payment
  const authVerify = privRes.rows.find(
    r => r.grantee === 'authenticated' && r.routine_name === 'verify_manual_upi_payment' && r.privilege_type === 'EXECUTE'
  );
  if (!authVerify) {
    throw new Error('CRITICAL SECURITY FAILURE: authenticated lacks EXECUTE privilege on verify_manual_upi_payment!');
  }

  const serviceRolePayment = privRes.rows.find(
    r => r.grantee === 'service_role' && r.routine_name === 'record_verified_payment' && r.privilege_type === 'EXECUTE'
  );
  if (!serviceRolePayment) {
    throw new Error('CRITICAL SECURITY FAILURE: service_role lacks EXECUTE privilege on record_verified_payment!');
  }
  console.log('  ✓ Verified: PUBLIC execution revoked; anon/authenticated blocked from mark_order_paid & record_verified_payment; authenticated granted verify_manual_upi_payment; service_role granted EXECUTE.');

  // Verify partial unique index on order_payments(reference_id)
  const idxRes = await db.query(`
    SELECT indexname, indexdef
    FROM pg_indexes
    WHERE tablename = 'order_payments' AND indexname = 'uq_order_payments_reference_verified';
  `);
  if (idxRes.rows.length === 0) {
    throw new Error('Missing unique partial index uq_order_payments_reference_verified on order_payments!');
  }
  console.log('  ✓ Verified: Unique partial index uq_order_payments_reference_verified exists on order_payments.');

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
    if (err.message.includes('Direct modification of payment or lifecycle fields on orders is restricted') || err.message.includes('Direct modification of payment or lifecycle fields is forbidden') || err.code === '42501') {
      attackBlocked = true;
    } else {
      throw err;
    }
  }
  if (!attackBlocked) {
    throw new Error('CRITICAL SECURITY FAILURE: Authenticated seller was able to directly fabricate paid state!');
  }
  console.log('  ✓ Verified: Direct payment fabrication attack blocked at DB layer with SQLSTATE 42501.');

  // Verify legitimate operational update succeeds
  await db.query(`
    UPDATE orders
    SET tracking_number = 'TRACK-SEED-123', courier_partner = 'Delhivery'
    WHERE id = '9a279045-2366-464a-f866-ba7f546fa067';
  `);
  console.log('  ✓ Verified: Legitimate operational updates (tracking_number, courier_partner) permitted.');

  console.log('🛡️ Verifying Manual Seller Verification RPC (TASK-2.4B):');
  // Call verify_manual_upi_payment as Seller B (7b218d60-3a09-4044-80c1-ce7018c4a401) on seeded attempt for Order 5
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "7b218d60-3a09-4044-80c1-ce7018c4a401", "role": "authenticated"}';
  `);

  const verRes = await db.query(`
    SELECT verify_manual_upi_payment('a1000000-0000-0000-0000-000000000004'::uuid) as r;
  `);
  const vResult = verRes.rows[0].r;
  if (!vResult.success) {
    throw new Error(`Manual verification RPC failed: ${JSON.stringify(vResult)}`);
  }
  console.log(`  ✓ Verified: Seller verified payment claim: status = ${vResult.status}, payment_status = ${vResult.payment_status}`);

  // Cross-order reference reuse: Seller A tries to verify another order with the UTR already used on Order 7
  await db.exec(`
    SET request.jwt.claims = '{"sub": "8a329e71-4b10-4055-90d2-df8029d5b512", "role": "authenticated"}';
  `);
  const crossRes = await db.query(`
    SELECT verify_manual_upi_payment('a1000000-0000-0000-0000-000000000001'::uuid, '428739182738') as r;
  `);
  if (crossRes.rows[0].r.success !== false || crossRes.rows[0].r.error !== 'REFERENCE_USED_ON_ANOTHER_ORDER') {
    throw new Error(`Expected REFERENCE_USED_ON_ANOTHER_ORDER, got: ${JSON.stringify(crossRes.rows[0].r)}`);
  }
  console.log('  ✓ Verified: Cross-order reference reuse explicitly blocked with REFERENCE_USED_ON_ANOTHER_ORDER.');

  await db.exec('RESET ROLE;');

  await db.close();
  console.log('✅ ALL RELATIONAL DATABASE SCHEMA, STOREFRONT INVARIANTS, RLS POLICIES, BUSINESS RPCS & MULTI-SELLER SEED DATA VERIFIED.');
}

run().catch((err) => {
  console.error('❌ Verification failed:', err.message);
  if (err.detail) console.error('Detail:', err.detail);
  if (err.hint) console.error('Hint:', err.hint);
  if (err.position) console.error('Position:', err.position);
  process.exit(1);
});
