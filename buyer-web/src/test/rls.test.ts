// @vitest-environment node
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { PGlite } from '@electric-sql/pglite';
import * as fs from 'node:fs';
import * as path from 'node:path';

describe('LiveDrop Row-Level Security & Access Control (TASK-1.2)', () => {
  let db: PGlite;

  const migrationsDir = path.resolve(__dirname, '../../../supabase/migrations');

  // Test Identities
  const sellerAId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
  const sellerBId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22';

  // Drop IDs
  const dropA1LiveId = 'd1000000-0000-0000-0000-000000000001';
  const dropA2DraftId = 'd1000000-0000-0000-0000-000000000002';
  const dropA3ClosedId = 'd1000000-0000-0000-0000-000000000003';
  const dropB1LiveId = 'd2000000-0000-0000-0000-000000000001';
  const dropB2DraftId = 'd2000000-0000-0000-0000-000000000002';

  // Product IDs (valid hex: 0-9, a-f)
  const prodA1LiveId = 'ca000000-0000-0000-0000-000000000001';
  const prodA2DraftId = 'ca000000-0000-0000-0000-000000000002';
  const prodB1LiveId = 'cb000000-0000-0000-0000-000000000001';
  const prodB2DraftId = 'cb000000-0000-0000-0000-000000000002';

  // Order & Token IDs
  const orderAId = 'ea000000-0000-0000-0000-000000000001';
  const orderAToken = 'fa000000-0000-0000-0000-000000000001';
  const orderBId = 'eb000000-0000-0000-0000-000000000001';
  const orderBToken = 'fb000000-0000-0000-0000-000000000001';

  const orderItemAId = 'aa000000-0000-0000-0000-000000000001';
  const orderItemBId = 'ab000000-0000-0000-0000-000000000001';

  // Helpers for switching authentication context in PGlite
  async function asSuperuser() {
    await db.exec(`
      RESET ROLE;
      SELECT set_config('request.jwt.claim.sub', '', false);
      SELECT set_config('request.headers', '', false);
    `);
  }

  async function asAnon(headerToken?: string) {
    const headerJson = headerToken ? JSON.stringify({ 'x-order-token': headerToken }) : '';
    await db.exec(`
      SET ROLE anon;
      SELECT set_config('request.jwt.claim.sub', '', false);
      SELECT set_config('request.headers', '${headerJson}', false);
    `);
  }

  async function asSeller(sellerId: string) {
    await db.exec(`
      SET ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub', '${sellerId}', false);
      SELECT set_config('request.headers', '', false);
    `);
  }

  beforeAll(async () => {
    db = new PGlite();

    // 1. Setup prerequisite auth schema and auth.uid() function
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

    // 2. Apply all 8 migrations sequentially
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

    for (const file of migrationFiles) {
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf-8');
      await db.exec(sql);
    }

    // 3. Seed Base Test Fixtures as superuser
    await asSuperuser();

    // Seed Auth Users
    await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [sellerAId, 'priya@boutique.in']);
    await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [sellerBId, 'ananya@silk.in']);

    // Seed Profiles
    await db.query(`
      INSERT INTO profiles (id, store_name, phone_number, upi_id, return_address, default_shipping_fee_paisa)
      VALUES ($1, 'Priya Trends', '9876543210', 'priya@okaxis', 'Indiranagar Bengaluru', 8000),
             ($2, 'Ananya Silks', '9876543211', 'ananya@okhdfcbank', 'T Nagar Chennai', 7000);
    `, [sellerAId, sellerBId]);

    // Seed Drops
    await db.query(`
      INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa)
      VALUES ($1, $2, 'Priya Live Drop', 'priya-live', 'live', 8000),
             ($3, $2, 'Priya Draft Drop', 'priya-draft', 'draft', 8000),
             ($4, $2, 'Priya Closed Drop', 'priya-closed', 'closed', 8000),
             ($5, $6, 'Ananya Live Drop', 'ananya-live', 'live', 7000),
             ($7, $6, 'Ananya Draft Drop', 'ananya-draft', 'draft', 7000);
    `, [dropA1LiveId, sellerAId, dropA2DraftId, dropA3ClosedId, dropB1LiveId, sellerBId, dropB2DraftId]);

    // Seed Products
    await db.query(`
      INSERT INTO products (id, drop_id, code, title, price_paisa, status, image_url)
      VALUES ($1, $2, '#01', 'Red Anarkali', 150000, 'available', 'https://cdn.livedrop.in/a1.jpg'),
             ($3, $4, '#02', 'Blue Saree Draft', 220000, 'available', 'https://cdn.livedrop.in/a2.jpg'),
             ($5, $6, '#03', 'Silk Dupatta', 80000, 'available', 'https://cdn.livedrop.in/b1.jpg'),
             ($7, $8, '#04', 'Kalamkari Kurti Draft', 120000, 'available', 'https://cdn.livedrop.in/b2.jpg');
    `, [prodA1LiveId, dropA1LiveId, prodA2DraftId, dropA2DraftId, prodB1LiveId, dropB1LiveId, prodB2DraftId, dropB2DraftId]);

    // Seed Orders
    await db.query(`
      INSERT INTO orders (id, drop_id, order_code, order_token, buyer_name, buyer_phone, shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa, status, hold_expires_at)
      VALUES ($1, $2, 'LD-A00001', $3, 'Rohan Sharma', '919876543201', '12 Park Street Kolkata', '700016', 150000, 8000, 158000, 'pending', NOW() + INTERVAL '15 minutes'),
             ($4, $5, 'LD-B00001', $6, 'Deepa Rao', '919876543202', '45 Anna Salai Chennai', '600002', 80000, 7000, 87000, 'pending', NOW() + INTERVAL '15 minutes');
    `, [orderAId, dropA1LiveId, orderAToken, orderBId, dropB1LiveId, orderBToken]);

    // Seed Order Items
    await db.query(`
      INSERT INTO order_items (id, order_id, product_id, price_at_purchase_paisa)
      VALUES ($1, $2, $3, 150000),
             ($4, $5, $6, 80000);
    `, [orderItemAId, orderAId, prodA1LiveId, orderItemBId, orderBId, prodB1LiveId]);
  });

  afterAll(async () => {
    if (db) {
      await asSuperuser();
      await db.close();
    }
  });

  // ============================================================================
  // 1. VERIFY RLS IS ACTUALLY ENABLED ON ALL TABLES
  // ============================================================================
  describe('1. Catalog RLS Enforcement Verification', () => {
    it('1.1 should verify rowsecurity = true for all 5 core tables in pg_tables', async () => {
      await asSuperuser();
      const res = await db.query<{ tablename: string; rowsecurity: boolean }>(`
        SELECT tablename, rowsecurity
        FROM pg_tables
        WHERE schemaname = 'public' AND tablename IN ('profiles', 'drops', 'products', 'orders', 'order_items')
        ORDER BY tablename;
      `);
      expect(res.rows.length).toBe(5);
      for (const row of res.rows) {
        expect(row.rowsecurity).toBe(true);
      }
    });

    it('1.2 should verify relrowsecurity = true for all 5 core tables in pg_class', async () => {
      await asSuperuser();
      const res = await db.query<{ relname: string; relrowsecurity: boolean }>(`
        SELECT relname, relrowsecurity
        FROM pg_class
        WHERE relnamespace = 'public'::regnamespace AND relname IN ('profiles', 'drops', 'products', 'orders', 'order_items')
        ORDER BY relname;
      `);
      expect(res.rows.length).toBe(5);
      for (const row of res.rows) {
        expect(row.relrowsecurity).toBe(true);
      }
    });
  });

  // ============================================================================
  // 2. SELLER ISOLATION (SELLER A CANNOT ACCESS SELLER B'S PRIVATE DATA)
  // ============================================================================
  describe('2. Seller Isolation & Multi-Tenancy Boundary', () => {
    it('2.1 [POL-DROP-03] Seller A can view their own drops (draft, live, closed) but NOT Seller B drops', async () => {
      await asSeller(sellerAId);
      const res = await db.query<{ id: string; seller_id: string }>(`SELECT id, seller_id FROM drops ORDER BY id;`);
      expect(res.rows.length).toBe(3);
      for (const row of res.rows) {
        expect(row.seller_id).toBe(sellerAId);
      }
      const dropIds = res.rows.map(r => r.id);
      expect(dropIds).toContain(dropA1LiveId);
      expect(dropIds).toContain(dropA2DraftId);
      expect(dropIds).toContain(dropA3ClosedId);
      expect(dropIds).not.toContain(dropB1LiveId);
      expect(dropIds).not.toContain(dropB2DraftId);
    });

    it('2.2 [POL-DROP-04] Seller A CANNOT UPDATE Seller B drop', async () => {
      await asSeller(sellerAId);
      const res = await db.query(`
        UPDATE drops SET title = 'Hacked Drop' WHERE id = $1 RETURNING id;
      `, [dropB1LiveId]);
      expect(res.rows.length).toBe(0);

      // Verify data remains untampered
      await asSuperuser();
      const check = await db.query<{ title: string }>(`SELECT title FROM drops WHERE id = $1;`, [dropB1LiveId]);
      expect(check.rows[0].title).toBe('Ananya Live Drop');
    });

    it('2.3 [POL-DROP-05] Seller A CANNOT DELETE Seller B drop', async () => {
      await asSeller(sellerAId);
      const res = await db.query(`DELETE FROM drops WHERE id = $1 RETURNING id;`, [dropB2DraftId]);
      expect(res.rows.length).toBe(0);

      // Verify drop still exists
      await asSuperuser();
      const check = await db.query(`SELECT id FROM drops WHERE id = $1;`, [dropB2DraftId]);
      expect(check.rows.length).toBe(1);
    });

    it('2.4 [POL-PROF-04] Seller A can UPDATE own profile but CANNOT UPDATE Seller B profile', async () => {
      await asSeller(sellerAId);
      // Own profile update succeeds
      const ownUpdate = await db.query(`
        UPDATE profiles SET store_name = 'Priya Luxury Trends' WHERE id = $1 RETURNING id, store_name;
      `, [sellerAId]);
      expect(ownUpdate.rows.length).toBe(1);

      // Cross-seller update fails (0 rows affected)
      const crossUpdate = await db.query(`
        UPDATE profiles SET store_name = 'Hacked Boutique' WHERE id = $1 RETURNING id;
      `, [sellerBId]);
      expect(crossUpdate.rows.length).toBe(0);

      // Verify Seller B profile is untouched
      await asSuperuser();
      const check = await db.query<{ store_name: string }>(`SELECT store_name FROM profiles WHERE id = $1;`, [sellerBId]);
      expect(check.rows[0].store_name).toBe('Ananya Silks');
    });

    it('2.5 [POL-PROD-03] Seller A can view products in own drops but NOT Seller B products', async () => {
      await asSeller(sellerAId);
      const res = await db.query<{ id: string; drop_id: string }>(`SELECT id, drop_id FROM products ORDER BY id;`);
      expect(res.rows.length).toBe(2);
      const productIds = res.rows.map(r => r.id);
      expect(productIds).toContain(prodA1LiveId);
      expect(productIds).toContain(prodA2DraftId);
      expect(productIds).not.toContain(prodB1LiveId);
      expect(productIds).not.toContain(prodB2DraftId);
    });

    it('2.6 [POL-PROD-04] Seller A CANNOT INSERT a product into Seller B drop', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          INSERT INTO products (drop_id, code, title, price_paisa, image_url)
          VALUES ($1, '#91', 'Malicious Product', 100000, 'https://cdn.livedrop.in/x1.jpg');
        `, [dropB1LiveId])
      ).rejects.toThrow(/violates row-level security policy/i);
    });

    it('2.7 [POL-PROD-05] Seller A CANNOT UPDATE Seller B product', async () => {
      await asSeller(sellerAId);
      const res = await db.query(`
        UPDATE products SET price_paisa = 1 WHERE id = $1 RETURNING id;
      `, [prodB1LiveId]);
      expect(res.rows.length).toBe(0);

      // Verify price remains 80000
      await asSuperuser();
      const check = await db.query<{ price_paisa: number }>(`SELECT price_paisa FROM products WHERE id = $1;`, [prodB1LiveId]);
      expect(check.rows[0].price_paisa).toBe(80000);
    });

    it('2.8 Seller A CANNOT DELETE Seller B product', async () => {
      await asSeller(sellerAId);
      const res = await db.query(`DELETE FROM products WHERE id = $1 RETURNING id;`, [prodB2DraftId]);
      expect(res.rows.length).toBe(0);

      // Verify product still exists
      await asSuperuser();
      const check = await db.query(`SELECT id FROM products WHERE id = $1;`, [prodB2DraftId]);
      expect(check.rows.length).toBe(1);
    });

    it('2.9 [POL-ORD-05] Seller A can view orders for Drop A but CANNOT see orders for Drop B', async () => {
      await asSeller(sellerAId);
      const res = await db.query<{ id: string; order_code: string }>(`SELECT id, order_code FROM orders ORDER BY id;`);
      expect(res.rows.length).toBe(1);
      expect(res.rows[0].id).toBe(orderAId);
      expect(res.rows[0].order_code).toBe('LD-A00001');
    });

    it('2.10 [POL-ORD-06] Seller A CANNOT UPDATE orders for Drop B', async () => {
      await asSeller(sellerAId);
      const res = await db.query(`
        UPDATE orders SET status = 'cancelled' WHERE id = $1 RETURNING id;
      `, [orderBId]);
      expect(res.rows.length).toBe(0);

      // Verify order status unchanged
      await asSuperuser();
      const check = await db.query<{ status: string }>(`SELECT status FROM orders WHERE id = $1;`, [orderBId]);
      expect(check.rows[0].status).toBe('pending');
    });

    it('2.11 [POL-ITEM-02] Seller A can view order items for Drop A but CANNOT view items for Drop B', async () => {
      await asSeller(sellerAId);
      const res = await db.query<{ order_id: string }>(`SELECT order_id FROM order_items;`);
      expect(res.rows.length).toBe(1);
      expect(res.rows[0].order_id).toBe(orderAId);
    });
  });

  // ============================================================================
  // 3. BUYER ISOLATION & PUBLIC CATALOG ACCESS (ANONYMOUS ROLE)
  // ============================================================================
  describe('3. Public Buyer Catalog Visibility (Anonymous Role)', () => {
    it('3.1 [POL-DROP-01] Public anon can view live drops, but CANNOT view draft or closed drops', async () => {
      await asAnon();
      const res = await db.query<{ id: string; status: string }>(`SELECT id, status FROM drops ORDER BY id;`);
      expect(res.rows.length).toBe(2);
      for (const row of res.rows) {
        expect(row.status).toBe('live');
      }
      const dropIds = res.rows.map(r => r.id);
      expect(dropIds).toContain(dropA1LiveId);
      expect(dropIds).toContain(dropB1LiveId);
      expect(dropIds).not.toContain(dropA2DraftId);
      expect(dropIds).not.toContain(dropA3ClosedId);
      expect(dropIds).not.toContain(dropB2DraftId);
    });

    it('3.2 [POL-PROD-01] Public anon can view products in live drops, but CANNOT view items in draft drops', async () => {
      await asAnon();
      const res = await db.query<{ id: string }>(`SELECT id FROM products ORDER BY id;`);
      expect(res.rows.length).toBe(2);
      const productIds = res.rows.map(r => r.id);
      expect(productIds).toContain(prodA1LiveId);
      expect(productIds).toContain(prodB1LiveId);
      expect(productIds).not.toContain(prodA2DraftId);
      expect(productIds).not.toContain(prodB2DraftId);
    });

    it('3.3 [POL-PROF-01] Public anon can view seller store branding & UPI information', async () => {
      await asAnon();
      const res = await db.query<{ store_name: string; upi_id: string }>(`
        SELECT store_name, upi_id FROM profiles ORDER BY store_name;
      `);
      expect(res.rows.length).toBe(2);
      expect(res.rows.map(r => r.store_name)).toContain('Ananya Silks');
      expect(res.rows.map(r => r.store_name)).toContain('Priya Luxury Trends');
    });

    it('3.4 [POL-PROF-02] Public anon CANNOT INSERT into profiles', async () => {
      await asAnon();
      await expect(
        db.query(`
          INSERT INTO profiles (id, store_name, phone_number, upi_id, return_address)
          VALUES (gen_random_uuid(), 'Anon Store', '9876543299', 'anon@upi', 'Nowhere Street');
        `)
      ).rejects.toThrow(/permission denied/i);
    });

    it('3.5 [POL-PROF-03] Public anon CANNOT UPDATE profiles', async () => {
      await asAnon();
      await expect(
        db.query(`UPDATE profiles SET store_name = 'Hacked' WHERE id = $1;`, [sellerAId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('3.6 [POL-DROP-02] Public anon CANNOT INSERT, UPDATE, or DELETE drops', async () => {
      await asAnon();
      await expect(
        db.query(`INSERT INTO drops (seller_id, title, slug) VALUES ($1, 'Anon Drop', 'anon-drop');`, [sellerAId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`UPDATE drops SET status = 'draft' WHERE id = $1;`, [dropA1LiveId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`DELETE FROM drops WHERE id = $1;`, [dropA1LiveId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('3.7 [POL-PROD-02] Public anon CANNOT INSERT, UPDATE, or DELETE products', async () => {
      await asAnon();
      await expect(
        db.query(`INSERT INTO products (drop_id, code, title, price_paisa, image_url) VALUES ($1, '#99', 'Item', 100, 'https://cdn.livedrop.in/x9.jpg');`, [dropA1LiveId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`UPDATE products SET price_paisa = 100 WHERE id = $1;`, [prodA1LiveId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`DELETE FROM products WHERE id = $1;`, [prodA1LiveId])
      ).rejects.toThrow(/permission denied/i);
    });
  });

  // ============================================================================
  // 4. ORDER PRIVACY & TOKEN-GATED RECEIPT ACCESS (DPDP ACT 2023)
  // ============================================================================
  describe('4. Order Privacy & Token Gating (India DPDP Act 2023)', () => {
    it('4.1 [POL-ORD-01] Anon querying orders WITHOUT x-order-token returns ZERO rows', async () => {
      await asAnon(); // No header token supplied
      const res = await db.query(`SELECT * FROM orders;`);
      expect(res.rows.length).toBe(0);
    });

    it('4.2 Anon querying orders with an INVALID/GUESSED x-order-token returns ZERO rows', async () => {
      await asAnon('00000000-0000-0000-0000-000000000000'); // Guessed UUID
      const res = await db.query(`SELECT * FROM orders;`);
      expect(res.rows.length).toBe(0);
    });

    it('4.3 [POL-ORD-02] Anon querying orders with VALID x-order-token retrieves ONLY their specific order', async () => {
      await asAnon(orderAToken); // Supply Order A's secret token
      const res = await db.query<{ id: string; buyer_name: string; total_paisa: number }>(`
        SELECT id, buyer_name, total_paisa FROM orders;
      `);
      expect(res.rows.length).toBe(1);
      expect(res.rows[0].id).toBe(orderAId);
      expect(res.rows[0].buyer_name).toBe('Rohan Sharma');
      expect(res.rows[0].total_paisa).toBe(158000);

      // Verify Order B is completely invisible
      const directQueryB = await db.query(`SELECT * FROM orders WHERE id = $1;`, [orderBId]);
      expect(directQueryB.rows.length).toBe(0);
    });

    it('4.4 [POL-ITEM-01] Anon querying order_items WITHOUT token returns ZERO rows', async () => {
      await asAnon(); // No header token supplied
      const res = await db.query(`SELECT * FROM order_items;`);
      expect(res.rows.length).toBe(0);
    });

    it('4.5 Anon querying order_items with VALID x-order-token retrieves ONLY their order items', async () => {
      await asAnon(orderAToken); // Supply Order A's secret token
      const res = await db.query<{ order_id: string; price_at_purchase_paisa: number }>(`
        SELECT order_id, price_at_purchase_paisa FROM order_items;
      `);
      expect(res.rows.length).toBe(1);
      expect(res.rows[0].order_id).toBe(orderAId);
      expect(res.rows[0].price_at_purchase_paisa).toBe(150000);
    });

    it('4.6 [POL-ORD-03] Anon CANNOT directly INSERT into orders (denied by privilege and RLS)', async () => {
      await asAnon();
      await expect(
        db.query(`
          INSERT INTO orders (drop_id, order_code, order_token, buyer_name, buyer_phone, shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa, hold_expires_at)
          VALUES ($1, 'LD-FAK001', gen_random_uuid(), 'Attacker', '919876543299', 'Fake Street', '110001', 100, 0, 100, NOW() + INTERVAL '15 min');
        `, [dropA1LiveId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('4.7 [POL-ORD-04] Anon CANNOT directly UPDATE orders even with valid token (denied by privilege and RLS)', async () => {
      await asAnon(orderAToken);
      await expect(
        db.query(`UPDATE orders SET status = 'paid' WHERE id = $1;`, [orderAId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('4.8 Anon CANNOT directly DELETE orders even with valid token', async () => {
      await asAnon(orderAToken);
      await expect(
        db.query(`DELETE FROM orders WHERE id = $1;`, [orderAId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('4.9 [POL-ITEM-03] Anon CANNOT directly INSERT, UPDATE, or DELETE order_items', async () => {
      await asAnon(orderAToken);
      await expect(
        db.query(`
          INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
          VALUES ($1, $2, 100);
        `, [orderAId, prodA1LiveId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`UPDATE order_items SET price_at_purchase_paisa = 100 WHERE order_id = $1;`, [orderAId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`DELETE FROM order_items WHERE order_id = $1;`, [orderAId])
      ).rejects.toThrow(/permission denied/i);
    });
  });

  // ============================================================================
  // 5. SELLER ORDER MANAGEMENT & WRITE CONTROLS
  // ============================================================================
  describe('5. Seller Order Management & Defense-in-Depth Controls', () => {
    it('5.1 Authenticated Seller CANNOT directly INSERT into orders via REST', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          INSERT INTO orders (drop_id, order_code, order_token, buyer_name, buyer_phone, shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa, hold_expires_at)
          VALUES ($1, 'LD-S99999', gen_random_uuid(), 'Direct Order', '919876543209', 'Direct St', '560001', 100000, 8000, 108000, NOW() + INTERVAL '15 min');
        `, [dropA1LiveId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('5.2 Authenticated Seller CANNOT directly INSERT, UPDATE, or DELETE order_items', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
          VALUES ($1, $2, 100);
        `, [orderAId, prodA1LiveId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`UPDATE order_items SET price_at_purchase_paisa = 100 WHERE order_id = $1;`, [orderAId])
      ).rejects.toThrow(/permission denied/i);

      await expect(
        db.query(`DELETE FROM order_items WHERE order_id = $1;`, [orderAId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('5.3 Seller A can UPDATE own order status and tracking details', async () => {
      await asSeller(sellerAId);
      const res = await db.query<{ id: string; status: string; tracking_number: string }>(`
        UPDATE orders 
        SET tracking_number = 'DELHIVERY12345'
        WHERE id = $1 
        RETURNING id, status, tracking_number;
      `, [orderAId]);
      expect(res.rows.length).toBe(1);
      expect(res.rows[0].tracking_number).toBe('DELHIVERY12345');
    });

    it('5.4 Seller A CANNOT transfer an order to Seller B drop (WITH CHECK violation)', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          UPDATE orders 
          SET drop_id = $1 
          WHERE id = $2;
        `, [dropB1LiveId, orderAId])
      ).rejects.toThrow(/violates row-level security policy/i);
    });

    it('5.5 Seller A CANNOT DELETE a finalized order (trigger trg_orders_no_delete_finalized)', async () => {
      await asSeller(sellerAId);
      // First update status to 'paid' (simulating payment completion)
      await db.query(`UPDATE orders SET status = 'paid' WHERE id = $1;`, [orderAId]);

      // Attempt deletion as seller
      await expect(
        db.query(`DELETE FROM orders WHERE id = $1;`, [orderAId])
      ).rejects.toThrow(/Cannot delete finalized order/i);
    });

    it('5.6 Seller A CAN DELETE an unfinalized order under own drop', async () => {
      const tempOrderId = 'ea000000-0000-0000-0000-000000000099';
      await asSuperuser();
      await db.query(`
        INSERT INTO orders (id, drop_id, order_code, order_token, buyer_name, buyer_phone, shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa, status, hold_expires_at)
        VALUES ($1, $2, 'LD-A99999', gen_random_uuid(), 'Cancel Buyer', '919876543211', '12 Test St Kolkata', '700001', 50000, 0, 50000, 'pending', NOW() + INTERVAL '15 min');
      `, [tempOrderId, dropA1LiveId]);

      await asSeller(sellerAId);
      const delRes = await db.query<{ id: string }>(`DELETE FROM orders WHERE id = $1 RETURNING id;`, [tempOrderId]);
      expect(delRes.rows.length).toBe(1);
      expect(delRes.rows[0].id).toBe(tempOrderId);
    });
  });
});
