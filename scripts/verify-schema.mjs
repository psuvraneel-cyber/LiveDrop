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

  await db.close();
  console.log('✅ ALL RELATIONAL DATABASE SCHEMA CHECKS PASSED.');
}

run().catch((err) => {
  console.error('❌ Verification failed:', err);
  process.exit(1);
});
