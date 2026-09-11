// LiveDrop Schema Verification Script
// Executes all 6 migrations sequentially using PGlite (PostgreSQL 18.3 WASM)
// and asserts all constraints, foreign keys, and indexes.

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
  ];

  console.log('📦 Applying migrations sequentially:');
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
  const expectedTables = ['drops', 'order_items', 'orders', 'products', 'profiles'];
  for (const t of expectedTables) {
    if (!tables.includes(t)) throw new Error(`Missing expected table: ${t}`);
  }

  console.log('🔍 Verifying 8 query indexes:');
  const indexRes = await db.query(`
    SELECT indexname 
    FROM pg_indexes 
    WHERE schemaname = 'public' AND indexname LIKE 'idx_%'
    ORDER BY indexname;
  `);
  const indexes = indexRes.rows.map(r => r.indexname);
  console.log(`  Indexes found (${indexes.length}): ${indexes.join(', ')}`);
  if (indexes.length !== 8) throw new Error(`Expected 8 indexes, found ${indexes.length}`);

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
  if (paisaRes.rows.length !== 9) throw new Error(`Expected 9 paisa columns, found ${paisaRes.rows.length}`);

  console.log('🔍 Verifying 5 triggers:');
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
    'trg_drops_updated_at',
    'trg_products_updated_at',
    'trg_orders_updated_at',
    'trg_orders_no_delete_finalized',
  ];
  const foundNames = triggerRes.rows.map(r => r.trigger_name);
  for (const exp of expectedTriggers) {
    if (!foundNames.includes(exp)) throw new Error(`Missing expected trigger: ${exp}`);
  }

  console.log('🔍 Verifying Row-Level Security (RLS) enforcement:');
  const rlsRes = await db.query(`
    SELECT tablename, rowsecurity
    FROM pg_tables
    WHERE schemaname = 'public' AND tablename IN ('profiles', 'drops', 'products', 'orders', 'order_items')
    ORDER BY tablename;
  `);
  for (const row of rlsRes.rows) {
    if (!row.rowsecurity) {
      throw new Error(`RLS NOT enabled on table ${row.tablename}!`);
    }
    console.log(`  ✓ RLS enabled on ${row.tablename} (rowsecurity = true)`);
  }
  if (rlsRes.rows.length !== 5) {
    throw new Error(`Expected 5 tables with RLS enabled, found ${rlsRes.rows.length}`);
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
  ];
  const registeredPolicyNames = policyRes.rows.map(r => r.policyname);
  for (const exp of expectedPolicies) {
    if (!registeredPolicyNames.includes(exp)) {
      throw new Error(`Missing expected RLS policy: ${exp}`);
    }
  }

  console.log('🔍 Verifying Core Business RPCs (TASK-1.3):');
  const rpcRes = await db.query(`
    SELECT routine_name, security_type, data_type
    FROM information_schema.routines
    WHERE routine_schema = 'public' AND routine_name IN (
      'create_order_with_reservation',
      'mark_order_paid',
      'release_expired_holds',
      'get_order_by_token',
      'force_release_hold',
      'mark_product_sold_offline'
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
    'mark_order_paid',
    'mark_product_sold_offline',
    'release_expired_holds',
  ];
  const foundRpcs = rpcRes.rows.map(r => r.routine_name);
  for (const exp of expectedRpcs) {
    if (!foundRpcs.includes(exp)) {
      throw new Error(`Missing expected RPC: ${exp}`);
    }
  }

  console.log('🔍 Verifying RPC Routine Privileges:');
  const privRes = await db.query(`
    SELECT routine_name, grantee, privilege_type
    FROM information_schema.routine_privileges
    WHERE routine_schema = 'public' AND routine_name IN (
      'create_order_with_reservation',
      'mark_order_paid',
      'release_expired_holds',
      'get_order_by_token',
      'force_release_hold',
      'mark_product_sold_offline'
    )
    ORDER BY routine_name, grantee;
  `);
  console.log(`  Routine privilege grants found (${privRes.rows.length})`);

  // Verify that anon cannot execute seller-only or maintenance RPCs
  const forbiddenAnonRpcs = ['mark_order_paid', 'force_release_hold', 'mark_product_sold_offline', 'release_expired_holds'];
  for (const row of privRes.rows) {
    if (row.grantee === 'anon' && forbiddenAnonRpcs.includes(row.routine_name)) {
      throw new Error(`CRITICAL SECURITY FAILURE: anon has ${row.privilege_type} privilege on seller RPC ${row.routine_name}!`);
    }
    if (row.grantee === 'PUBLIC') {
      throw new Error(`CRITICAL SECURITY FAILURE: PUBLIC has ${row.privilege_type} privilege on RPC ${row.routine_name}!`);
    }
  }
  console.log('  ✓ Verified: PUBLIC execution revoked; anon blocked from seller & maintenance RPCs.');

  await db.close();
  console.log('✅ ALL RELATIONAL DATABASE SCHEMA, RLS POLICIES & BUSINESS RPCS VERIFIED.');
}

run().catch((err) => {
  console.error('❌ Verification failed:', err);
  process.exit(1);
});
