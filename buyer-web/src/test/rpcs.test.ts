// @vitest-environment node
import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { PGlite } from '@electric-sql/pglite';
import * as fs from 'node:fs';
import * as path from 'node:path';

interface RpcResult {
  success: boolean;
  order_id?: string;
  order_code?: string;
  order_token?: string;
  subtotal_paisa?: number;
  shipping_paisa?: number;
  total_paisa?: number;
  hold_expires_at?: string;
  error?: string;
  message?: string;
  unavailable_product_ids?: string[];
  order?: {
    id: string;
    order_code: string;
    buyer_name: string;
    subtotal_paisa: number;
    shipping_paisa: number;
    total_paisa: number;
    status: string;
    hold_expires_at: string;
    store_name: string;
    upi_id: string;
    upi_qr_url: string;
    items: Array<{
      product_id: string;
      code: string;
      title: string;
      image_url: string;
      price_at_purchase_paisa: number;
    }>;
  };
}

interface RpcResponseRow {
  result?: RpcResult;
  r?: RpcResult;
  res?: RpcResult;
}

interface ProductRow {
  id?: string;
  status: string;
  reserved_by_order_id: string | null;
  reserved_at?: string | null;
}

interface OrderRow {
  id?: string;
  status: string;
  total_paisa?: number;
  paid_at?: string | null;
}

interface OrderItemRow {
  id?: string;
  product_id: string;
  price_at_purchase_paisa: number;
}

interface CountRow {
  count: string | number;
}

describe('LiveDrop Transactional Business RPCs (TASK-1.3)', () => {
  let db: PGlite;

  const migrationsDir = path.resolve(__dirname, '../../../supabase/migrations');

  // Identifiers
  const sellerAId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
  const sellerBId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22';

  const dropALiveId = 'd1000000-0000-0000-0000-000000000001';
  const dropADraftId = 'd1000000-0000-0000-0000-000000000002';
  const dropAClosedId = 'd1000000-0000-0000-0000-000000000003';
  const dropBLiveId = 'd2000000-0000-0000-0000-000000000001';

  const prodA1Id = 'ca000000-0000-0000-0000-000000000001'; // #A01, 185000
  const prodA2Id = 'ca000000-0000-0000-0000-000000000002'; // #A02, 75000
  const prodA3Id = 'ca000000-0000-0000-0000-000000000003'; // #A03, 50000
  const prodA4Id = 'ca000000-0000-0000-0000-000000000004'; // #A04, 120000
  const prodA5Id = 'ca000000-0000-0000-0000-000000000005'; // #A05, 99000
  const prodAReservedId = 'ca000000-0000-0000-0000-000000000090'; // #A90, 150000 (reserved)
  const prodASoldId = 'ca000000-0000-0000-0000-000000000099'; // #A99, 200000 (sold)
  const prodADraftId = 'cd000000-0000-0000-0000-000000000001'; // #D01 in draft drop
  const prodBLiveId = 'cb000000-0000-0000-0000-000000000001'; // #B01 in Seller B drop

  // Auth Context Helpers
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

  async function asServiceRole() {
    await db.exec(`
      SET ROLE service_role;
      SELECT set_config('request.jwt.claim.sub', '', false);
      SELECT set_config('request.headers', '', false);
    `);
  }

  // Setup PGlite Once for Entire Suite
  beforeAll(async () => {
    db = new PGlite();

    // 1. Auth schema & auth.uid() simulation
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

    // 2. Apply all 13 migrations sequentially (001 -> 013)
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
      '014_persistent_payment_claim_window.sql',
    ];

    for (const file of migrationFiles) {
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf-8');
      await db.exec(sql);
    }

    // 3. Seed test fixtures as superuser
    await asSuperuser();

    await db.query(`
      INSERT INTO auth.users (id, email) 
      VALUES ('${sellerAId}', 'priya@boutique.in'),
             ('${sellerBId}', 'ananya@silk.in');
    `);

    await db.query(`
      INSERT INTO profiles (
        id, store_name, store_slug, phone_number, upi_id, return_address, 
        default_shipping_fee_paisa, free_shipping_threshold_paisa,
        advance_confirmation_enabled, advance_amount_paisa, hold_duration_days
      )
      VALUES 
        ('${sellerAId}', 'Priya Trends', 'priya-trends', '9876543210', 'priya@okaxis', 'Indiranagar Bengaluru', 8000, 200000, true, 25000, 30),
        ('${sellerBId}', 'Ananya Silks', 'ananya-silks', '9876543211', 'ananya@okhdfcbank', 'T Nagar Chennai', 7000, 150000, true, 25000, 30);
    `);

    await db.query(`
      INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa, free_shipping_threshold_paisa)
      VALUES 
        ('${dropALiveId}', '${sellerAId}', 'Festive Silk Drop', 'festive-silk', 'live', 8000, 200000),
        ('${dropADraftId}', '${sellerAId}', 'Upcoming Cotton Drop', 'upcoming-cotton', 'draft', 8000, 200000),
        ('${dropAClosedId}', '${sellerAId}', 'Concluded Linen Drop', 'concluded-linen', 'closed', 8000, 200000),
        ('${dropBLiveId}', '${sellerBId}', 'Chennai Silk Drop', 'chennai-silk', 'live', 7000, 150000);
    `);

    await db.query(`
      INSERT INTO products (id, drop_id, code, title, price_paisa, size, image_url, status)
      VALUES 
        ('${prodA1Id}', '${dropALiveId}', '#A01', 'Tussar Silk Saree', 185000, 'Free Size', 'https://img.livedrop.store/a01.webp', 'available'),
        ('${prodA2Id}', '${dropALiveId}', '#A02', 'Chanderi Kurti', 75000, 'M', 'https://img.livedrop.store/a02.webp', 'available'),
        ('${prodA3Id}', '${dropALiveId}', '#A03', 'Cotton Dupatta', 50000, 'Free Size', 'https://img.livedrop.store/a03.webp', 'available'),
        ('${prodA4Id}', '${dropALiveId}', '#A04', 'Linen Tunic', 120000, 'L', 'https://img.livedrop.store/a04.webp', 'available'),
        ('${prodA5Id}', '${dropALiveId}', '#A05', 'Silk Stole', 99000, 'Free Size', 'https://img.livedrop.store/a05.webp', 'available'),
        ('${prodADraftId}', '${dropADraftId}', '#D01', 'Draft Garment', 100000, 'S', 'https://img.livedrop.store/d01.webp', 'available'),
        ('${prodBLiveId}', '${dropBLiveId}', '#B01', 'Kanchipuram Silk', 110000, 'Free Size', 'https://img.livedrop.store/b01.webp', 'available'),
        ('${prodAReservedId}', '${dropALiveId}', '#A90', 'Reserved Dress', 150000, 'M', 'https://img.livedrop.store/a90.webp', 'reserved'),
        ('${prodASoldId}', '${dropALiveId}', '#A99', 'Sold Dress', 200000, 'L', 'https://img.livedrop.store/a99.webp', 'sold');
    `);
  });

  // Fast Reset Before Each Test (< 5ms)
  beforeEach(async () => {
    await asSuperuser();
    // 1. Clear FK references from products first so orders can be deleted without RESTRICT violations
    await db.query(`
      UPDATE products 
      SET status = 'available', reserved_at = NULL, reserved_by_order_id = NULL;
    `);

    // 2. Delete payments and line items
    await db.query(`DELETE FROM order_payments;`);
    await db.query(`DELETE FROM order_items;`);

    // 3. Neutralize status to permit delete under prevent_finalized_order_deletion trigger and delete orders
    await db.query(`UPDATE orders SET status = 'cancelled';`);
    await db.query(`DELETE FROM orders;`);

    // 4. Re-establish reserved & sold controls
    await db.query(`
      UPDATE products 
      SET status = 'reserved', reserved_at = NOW(), reserved_by_order_id = NULL
      WHERE id = '${prodAReservedId}';
    `);
    await db.query(`
      UPDATE products 
      SET status = 'sold', reserved_at = NULL, reserved_by_order_id = NULL
      WHERE id = '${prodASoldId}';
    `);
  });

  afterAll(async () => {
    if (db) {
      await db.close();
    }
  });

  // ==========================================================================
  // 0. SCHEMA SANITY & MIGRATION STATE REGRESSION (TASK-2.4A.2)
  // ==========================================================================
  describe('0. Schema Sanity & Migration State Regression (TASK-2.4A.2)', () => {
    it('verifies that migrations 010, 011, and 012 are genuinely loaded into PGlite', async () => {
      // 1. Verify mark_order_paid signature (hardened in 011)
      const procRes = await db.query<{ proname: string; args: string; prosecdef: boolean }>(`
        SELECT p.proname, pg_get_function_arguments(p.oid) as args, p.prosecdef
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'mark_order_paid';
      `);
      expect(procRes.rows.length).toBe(1);
      expect(procRes.rows[0].args).toContain('p_reference_id text');
      expect(procRes.rows[0].args).toContain('p_metadata jsonb');
      expect(procRes.rows[0].prosecdef).toBe(true);

      // 2. Verify record_verified_payment exists (migration 010/011)
      const payRes = await db.query<{ proname: string; prosecdef: boolean }>(`
        SELECT p.proname, p.prosecdef
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'record_verified_payment';
      `);
      expect(payRes.rows.length).toBe(1);
      expect(payRes.rows[0].prosecdef).toBe(true);

      // 3. Verify obsolete confirm_order_advance is completely absent
      const advRes = await db.query<{ proname: string }>(`
        SELECT p.proname
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.proname = 'confirm_order_advance';
      `);
      expect(advRes.rows.length).toBe(0);

      // 4. Verify migration 012 triggers exist on orders and products
      const trgRes = await db.query<{ trigger_name: string }>(`
        SELECT trigger_name
        FROM information_schema.triggers
        WHERE trigger_schema = 'public' AND trigger_name IN (
          'trg_enforce_orders_payment_immutability',
          'trg_enforce_products_inventory_immutability'
        );
      `);
      expect(trgRes.rows.length).toBe(2);

      // 5. Verify orders table has state machine and financial columns from 010
      const colRes = await db.query<{ column_name: string }>(`
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'orders'
          AND column_name IN ('confirmation_mode', 'advance_required_paisa', 'advance_paid_paisa', 'total_paid_paisa', 'balance_due_paisa', 'payment_status', 'fulfilment_status');
      `);
      expect(colRes.rows.length).toBe(7);
    });
  });

  // ==========================================================================
  // 1. BASIC ORDER CREATION & RESERVATION TESTS
  // ==========================================================================
  describe('1. Basic Order Creation & Atomic Reservation (create_order_with_reservation)', () => {
    it('successfully reserves a single product with paid shipping (< threshold)', async () => {
      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], $3, $4, $5, $6
        ) AS result;
      `, [dropALiveId, prodA2Id, 'Sangeeta Mukherjee', '9830123456', 'Flat 4B, Greenview Apts, Jadavpur', '700032']);

      const result = res.rows[0].result!;
      expect(result.success).toBe(true);
      expect(result.order_id).toBeDefined();
      expect(result.order_code).toMatch(/^LD-[A-Z0-9]{6}$/);
      expect(result.order_token).toBeDefined();
      expect(result.subtotal_paisa).toBe(75000); // ₹750.00
      expect(result.shipping_paisa).toBe(8000); // ₹80.00
      expect(result.total_paisa).toBe(83000); // ₹830.00
      expect(result.hold_expires_at).toBeDefined();

      // Verify product state in database
      await asSuperuser();
      const prodRes = await db.query<ProductRow>(`SELECT status, reserved_by_order_id, reserved_at FROM products WHERE id = $1`, [prodA2Id]);
      expect(prodRes.rows[0].status).toBe('reserved');
      expect(prodRes.rows[0].reserved_by_order_id).toBe(result.order_id);
      expect(prodRes.rows[0].reserved_at).not.toBeNull();

      // Verify order record in database
      const orderRes = await db.query<OrderRow>(`SELECT status, total_paisa FROM orders WHERE id = $1`, [result.order_id]);
      expect(orderRes.rows[0].status).toBe('pending');
      expect(orderRes.rows[0].total_paisa).toBe(83000);

      // Verify order_items
      const itemsRes = await db.query<OrderItemRow>(`SELECT product_id, price_at_purchase_paisa FROM order_items WHERE order_id = $1`, [result.order_id]);
      expect(itemsRes.rows.length).toBe(1);
      expect(itemsRes.rows[0].product_id).toBe(prodA2Id);
      expect(itemsRes.rows[0].price_at_purchase_paisa).toBe(75000);
    });

    it('successfully bundles multiple products with free shipping (>= threshold)', async () => {
      await asAnon();
      // prodA1 (185000) + prodA2 (75000) = 260000 >= 200000 free shipping threshold
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], $4, $5, $6, $7
        ) AS result;
      `, [dropALiveId, prodA1Id, prodA2Id, 'Rina Roy', '919830999999', 'Sector 5, Salt Lake Kolkata', '700091']);

      const result = res.rows[0].result!;
      expect(result.success).toBe(true);
      expect(result.subtotal_paisa).toBe(260000);
      expect(result.shipping_paisa).toBe(0); // FREE SHIPPING
      expect(result.total_paisa).toBe(260000);

      // Verify both products reserved
      await asSuperuser();
      const p1 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      const p2 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA2Id]);
      expect(p1.rows[0].status).toBe('reserved');
      expect(p1.rows[0].reserved_by_order_id).toBe(result.order_id);
      expect(p2.rows[0].status).toBe('reserved');
      expect(p2.rows[0].reserved_by_order_id).toBe(result.order_id);

      const items = await db.query<OrderItemRow>(`SELECT product_id, price_at_purchase_paisa FROM order_items WHERE order_id = $1 ORDER BY price_at_purchase_paisa DESC`, [result.order_id]);
      expect(items.rows.length).toBe(2);
      expect(items.rows[0].price_at_purchase_paisa).toBe(185000);
      expect(items.rows[1].price_at_purchase_paisa).toBe(75000);
    });
  });

  // ==========================================================================
  // 2. INPUT VALIDATION & GUARDRAILS
  // ==========================================================================
  describe('2. Input Validation & Edge Case Rejections', () => {
    it('rejects empty product list with EMPTY_CART', async () => {
      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[]::uuid[], 'Anita Sen', '9830111111', 'Park Street 12 Kolkata', '700016'
        ) AS result;
      `, [dropALiveId]);
      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('EMPTY_CART');
    });

    it('rejects cart exceeding 10 items with EXCEEDS_CART_LIMIT', async () => {
      await asSuperuser();
      // Seed 11 products in Drop A
      const ids: string[] = [];
      for (let i = 10; i <= 21; i++) {
        const id = `ca000000-0000-0000-0000-0000000000${i}`;
        ids.push(id);
        await db.query(`
          INSERT INTO products (id, drop_id, code, title, price_paisa, size, image_url, status)
          VALUES ('${id}', '${dropALiveId}', '#B${i}', 'Bulk Dress', 50000, 'Free Size', 'https://img.livedrop.store/bulk.webp', 'available')
        `);
      }

      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, $2::uuid[], 'Bulk Buyer', '9830111111', 'Wholesale Market Bara Bazaar', '700001'
        ) AS result;
      `, [dropALiveId, ids.slice(0, 11)]);
      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('EXCEEDS_CART_LIMIT');
    });

    it('deduplicates duplicate product IDs and charges once', async () => {
      await asAnon();
      // Array has duplicates: [prodA3, prodA3, prodA3]
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $2, $2]::uuid[], 'Devika Das', '9830123456', 'Ballygunge Circular Road Flat 2', '700019'
        ) AS result;
      `, [dropALiveId, prodA3Id]);

      const result = res.rows[0].result!;
      expect(result.success).toBe(true);
      // prodA3 is 50000 paisa, shipping is 8000
      expect(result.subtotal_paisa).toBe(50000);
      expect(result.total_paisa).toBe(58000);

      // Verify only 1 order_item was created
      await asSuperuser();
      const items = await db.query<OrderItemRow>(`SELECT product_id, price_at_purchase_paisa FROM order_items WHERE order_id = $1`, [result.order_id]);
      expect(items.rows.length).toBe(1);
    });

    it('rejects order on draft drop with DROP_NOT_LIVE', async () => {
      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Kavita Ghosh', '9830123456', 'Alipore Kolkata Road 5', '700027'
        ) AS result;
      `, [dropADraftId, prodADraftId]);
      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('DROP_NOT_LIVE');
    });

    it('rejects order on closed drop with DROP_NOT_LIVE', async () => {
      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Kavita Ghosh', '9830123456', 'Alipore Kolkata Road 5', '700027'
        ) AS result;
      `, [dropAClosedId, prodA1Id]);
      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('DROP_NOT_LIVE');
    });

    it('rejects products belonging to a different drop with STOCK_UNAVAILABLE', async () => {
      await asAnon();
      // Requesting prodA1 (Drop A) and prodB1 (Drop B) inside dropALiveId
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], 'Pooja Bose', '9830123456', 'Lake Gardens Building 14', '700045'
        ) AS result;
      `, [dropALiveId, prodA1Id, prodBLiveId]);
      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('STOCK_UNAVAILABLE');
    });

    it('rejects already reserved product with STOCK_UNAVAILABLE', async () => {
      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Shreya Guha', '9830123456', 'Howrah Station Road Flat 10', '711101'
        ) AS result;
      `, [dropALiveId, prodAReservedId]);
      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('STOCK_UNAVAILABLE');
    });

    it('rejects already sold product with STOCK_UNAVAILABLE', async () => {
      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Shreya Guha', '9830123456', 'Howrah Station Road Flat 10', '711101'
        ) AS result;
      `, [dropALiveId, prodASoldId]);
      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('STOCK_UNAVAILABLE');
    });

    it('validates buyer input parameters (name, phone, address, pincode)', async () => {
      await asAnon();

      // Short buyer name (< 3 chars)
      const r1 = await db.query<RpcResponseRow>(`SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Al', '9830123456', 'Valid address 1234567890', '700001') AS res`, [dropALiveId, prodA1Id]);
      expect(r1.rows[0].res!.error).toBe('INVALID_BUYER_NAME');

      // Invalid Indian phone (starts with 5)
      const r2 = await db.query<RpcResponseRow>(`SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Alice Sen', '5830123456', 'Valid address 1234567890', '700001') AS res`, [dropALiveId, prodA1Id]);
      expect(r2.rows[0].res!.error).toBe('INVALID_BUYER_PHONE');

      // Short address (< 10 chars)
      const r3 = await db.query<RpcResponseRow>(`SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Alice Sen', '9830123456', 'Short', '700001') AS res`, [dropALiveId, prodA1Id]);
      expect(r3.rows[0].res!.error).toBe('INVALID_SHIPPING_ADDRESS');

      // Invalid pincode (not 6 digits)
      const r4 = await db.query<RpcResponseRow>(`SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Alice Sen', '9830123456', 'Valid address 1234567890', '7000') AS res`, [dropALiveId, prodA1Id]);
      expect(r4.rows[0].res!.error).toBe('INVALID_PINCODE');
    });
  });

  // ==========================================================================
  // 3. MULTI-ITEM ALL-OR-NOTHING ATOMICITY
  // ==========================================================================
  describe('3. All-or-Nothing Multi-Item Atomicity', () => {
    it('guarantees zero partial reservation when 1 of 3 products is unavailable', async () => {
      // prodA1 (available), prodA2 (available), prodAReserved (already reserved)
      await asAnon();
      const res = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3, $4]::uuid[], 'Sneha Mitra', '9830123456', 'Southern Avenue Kolkata Flat 1', '700029'
        ) AS result;
      `, [dropALiveId, prodA1Id, prodA2Id, prodAReservedId]);

      const result = res.rows[0].result!;
      expect(result.success).toBe(false);
      expect(result.error).toBe('STOCK_UNAVAILABLE');

      // Verify ATOMICITY in database:
      await asSuperuser();
      // 1. prodA1 must remain available
      const p1 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(p1.rows[0].status).toBe('available');
      expect(p1.rows[0].reserved_by_order_id).toBeNull();

      // 2. prodA2 must remain available
      const p2 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA2Id]);
      expect(p2.rows[0].status).toBe('available');
      expect(p2.rows[0].reserved_by_order_id).toBeNull();

      // 3. Zero orders created
      const orders = await db.query<CountRow>(`SELECT COUNT(*) as count FROM orders WHERE buyer_name = 'Sneha Mitra'`);
      expect(Number(orders.rows[0].count)).toBe(0);

      // 4. Zero order_items created
      const items = await db.query<CountRow>(`SELECT COUNT(*) as count FROM order_items WHERE product_id IN ($1, $2)`, [prodA1Id, prodA2Id]);
      expect(Number(items.rows[0].count)).toBe(0);
    });
  });

  // ==========================================================================
  // 4. PAYMENT CONFIRMATION (mark_order_paid & record_verified_payment)
  // ==========================================================================
  describe('4. Payment Authority & Confirmation (mark_order_paid & record_verified_payment)', () => {
    it('service_role successfully confirms payment transitioning order to paid and products to sold', async () => {
      // 1. Place order as buyer
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], 'Madhumita Ray', '9830123456', 'New Alipore Block G Kolkata', '700053'
        ) AS result;
      `, [dropALiveId, prodA1Id, prodA2Id]);
      const orderId = checkoutRes.rows[0].result!.order_id!;

      // 2. Mark order paid as trusted backend service_role
      await asServiceRole();
      const paidRes = await db.query<RpcResponseRow>(`
        SELECT mark_order_paid($1, 'REF-PAY-001', '{"gateway": "razorpay"}'::jsonb) AS result;
      `, [orderId]);
      const paidResult = paidRes.rows[0].result!;
      expect(paidResult.success).toBe(true);

      // 3. Verify database state
      await asSuperuser();
      const order = await db.query<{ status: string; payment_status: string; fulfilment_status: string; total_paid_paisa: number; balance_due_paisa: number; paid_at: string | null }>(
        `SELECT status, payment_status, fulfilment_status, total_paid_paisa, balance_due_paisa, paid_at FROM orders WHERE id = $1`, [orderId]
      );
      expect(order.rows[0].status).toBe('paid');
      expect(order.rows[0].payment_status).toBe('paid');
      expect(order.rows[0].fulfilment_status).toBe('ready_to_ship');
      expect(order.rows[0].total_paid_paisa).toBe(260000);
      expect(order.rows[0].balance_due_paisa).toBe(0);
      expect(order.rows[0].paid_at).not.toBeNull();

      const p1 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      const p2 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA2Id]);
      expect(p1.rows[0].status).toBe('sold');
      expect(p1.rows[0].reserved_by_order_id).toBeNull();
      expect(p2.rows[0].status).toBe('sold');
      expect(p2.rows[0].reserved_by_order_id).toBeNull();

      // Verify order_payments entry created
      const payRes = await db.query<{ count: string; amount_paisa: number; status: string }>(
        `SELECT count(*) as count, amount_paisa, status FROM order_payments WHERE order_id = $1 GROUP BY amount_paisa, status`, [orderId]
      );
      expect(Number(payRes.rows[0].count)).toBe(1);
      expect(payRes.rows[0].status).toBe('verified');
      expect(payRes.rows[0].amount_paisa).toBe(260000);
    });

    it('rejects mark_order_paid from authenticated seller role with permission denied (SQLSTATE 42501)', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Test Buyer', '9830123456', 'Address 1234567890', '700001'
        ) AS result;
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].result!.order_id!;

      // Authenticated seller attempts to execute mark_order_paid -> blocked by PostgreSQL privilege boundary
      await asSeller(sellerAId);
      await expect(
        db.query(`SELECT mark_order_paid($1) AS result;`, [orderId])
      ).rejects.toThrow(/permission denied for function mark_order_paid/i);
    });

    it('rejects mark_order_paid from anonymous caller with permission denied (SQLSTATE 42501)', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Test Buyer', '9830123456', 'Address 1234567890', '700001'
        ) AS result;
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].result!.order_id!;

      // Anon caller attempts mark_order_paid -> blocked by PostgreSQL privilege boundary
      await expect(
        db.query(`SELECT mark_order_paid($1) AS result;`, [orderId])
      ).rejects.toThrow(/permission denied for function mark_order_paid/i);
    });

    it('service_role execution is idempotent on already paid orders', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Test Buyer', '9830123456', 'Address 1234567890', '700001'
        ) AS result;
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].result!.order_id!;

      await asServiceRole();
      const first = await db.query<RpcResponseRow>(`SELECT mark_order_paid($1, 'REF-IDEMP-01', '{}'::jsonb) AS result;`, [orderId]);
      expect(first.rows[0].result!.success).toBe(true);

      // Second identical call
      const second = await db.query<RpcResponseRow>(`SELECT mark_order_paid($1, 'REF-IDEMP-01', '{}'::jsonb) AS result;`, [orderId]);
      expect(second.rows[0].result!.success).toBe(true);
    });

    it('strictly rejects mark_order_paid on cancelled or expired orders with INVALID_ORDER_STATE', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Late Payer', '9830123456', 'Ballygunge Circular Road 4', '700019'
        ) AS result;
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].result!.order_id!;

      // Simulate expiration: set hold_expires_at to past and run release_expired_holds as service_role
      await asSuperuser();
      await db.query(`UPDATE orders SET hold_expires_at = NOW() - INTERVAL '1 minute' WHERE id = $1`, [orderId]);
      await asServiceRole();
      await db.query(`SELECT release_expired_holds();`);

      // Verify order is cancelled and product is available
      await asSuperuser();
      const check = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [orderId]);
      expect(check.rows[0].status).toBe('cancelled');
      const prodCheck = await db.query<ProductRow>(`SELECT status FROM products WHERE id = $1`, [prodA1Id]);
      expect(prodCheck.rows[0].status).toBe('available');

      // Attempt to resurrect cancelled order via mark_order_paid -> MUST be rejected with INVALID_ORDER_STATE
      await asServiceRole();
      const paidRes = await db.query<RpcResponseRow>(`SELECT mark_order_paid($1, 'REF-RESURRECT', '{}'::jsonb) AS result;`, [orderId]);
      expect(paidRes.rows[0].result!.success).toBe(false);
      expect(paidRes.rows[0].result!.error).toBe('INVALID_ORDER_STATE');
    });

    it('service_role can execute record_verified_payment for advance payment', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Advance Buyer', '9830123456', 'Address 1234567890', '700001'
        ) AS result;
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].result!.order_id!;

      await asServiceRole();
      const payRes = await db.query<{ record_verified_payment: { success: boolean; advance_paid_paisa?: number; status?: string } }>(`
        SELECT record_verified_payment($1, 'advance', 25000, 'REF-ADV-001', '{}'::jsonb);
      `, [orderId]);
      expect(payRes.rows[0].record_verified_payment.success).toBe(true);

      // Verify database state: order confirmed, advance_paid, not_ready
      await asSuperuser();
      const o = await db.query<{ status: string; payment_status: string; fulfilment_status: string; advance_paid_paisa: number }>(
        `SELECT status, payment_status, fulfilment_status, advance_paid_paisa FROM orders WHERE id = $1`, [orderId]
      );
      expect(o.rows[0].status).toBe('confirmed');
      expect(o.rows[0].payment_status).toBe('advance_paid');
      expect(o.rows[0].fulfilment_status).toBe('not_ready');
      expect(o.rows[0].advance_paid_paisa).toBe(25000);
    });

    it('rejects record_verified_payment from authenticated seller role with permission denied (SQLSTATE 42501)', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Advance Buyer', '9830123456', 'Address 1234567890', '700001'
        ) AS result;
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].result!.order_id!;

      await asSeller(sellerAId);
      await expect(
        db.query(`SELECT record_verified_payment($1, 'advance', 25000, 'REF-ATTACK-001', '{}'::jsonb);`, [orderId])
      ).rejects.toThrow(/permission denied for function record_verified_payment/i);
    });
  });

  // ==========================================================================
  // 5. EXPIRATION & REAPER (release_expired_holds)
  // ==========================================================================
  describe('5. Expiration & Hold Reaper (release_expired_holds)', () => {
    it('leaves fresh unexpired reservations pending and releases only expired holds', async () => {
      await asAnon();
      // Order 1: unexpired
      const res1 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Fresh Buyer', '9830123456', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const freshOrderId = res1.rows[0].r!.order_id!;

      // Order 2: expired
      const res2 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Expired Buyer', '9830123457', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA2Id]);
      const expiredOrderId = res2.rows[0].r!.order_id!;

      // Set Order 2 to expired
      await asSuperuser();
      await db.query(`UPDATE orders SET hold_expires_at = NOW() - INTERVAL '5 minutes' WHERE id = $1`, [expiredOrderId]);

      // Run reaper
      await db.query(`SELECT release_expired_holds();`);

      // Verify Fresh Order untouched
      const freshOrder = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [freshOrderId]);
      expect(freshOrder.rows[0].status).toBe('pending');
      const freshProd = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(freshProd.rows[0].status).toBe('reserved');
      expect(freshProd.rows[0].reserved_by_order_id).toBe(freshOrderId);

      // Verify Expired Order cancelled & product freed
      const expOrder = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [expiredOrderId]);
      expect(expOrder.rows[0].status).toBe('cancelled');
      const expProd = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA2Id]);
      expect(expProd.rows[0].status).toBe('available');
      expect(expProd.rows[0].reserved_by_order_id).toBeNull();
    });

    it('expired-but-unreleased hold returns STOCK_UNAVAILABLE until cron reaper runs (F-02 fix)', async () => {
      await asAnon();
      // Step 1: Buyer 1 reserves prodA1
      const res1 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Buyer 1', '9830123456', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const order1Id = res1.rows[0].r!.order_id!;

      // Step 2: Simulate 15m expiration pass without manual cron
      await asSuperuser();
      await db.query(`UPDATE orders SET hold_expires_at = NOW() - INTERVAL '1 second' WHERE id = $1`, [order1Id]);

      // Step 3: Buyer 2 attempts checkout of prodA1
      // Inline reaper removed (F-02): product is still 'reserved' so checkout must fail
      await asAnon();
      const res2 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Buyer 2', '9830999999', 'Address 9876543210', '700002') AS r
      `, [dropALiveId, prodA1Id]);
      const result2 = res2.rows[0].r!;

      expect(result2.success).toBe(false);
      expect(result2.error).toBe('STOCK_UNAVAILABLE');

      // Step 4: Cron reaper runs and reclaims expired hold
      await asSuperuser();
      await db.query(`SELECT release_expired_holds();`);

      // Verify Buyer 1 order cancelled and product freed
      const o1 = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [order1Id]);
      expect(o1.rows[0].status).toBe('cancelled');
      const prodCheck = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(prodCheck.rows[0].status).toBe('available');
      expect(prodCheck.rows[0].reserved_by_order_id).toBeNull();

      // Step 5: Buyer 2 retries checkout successfully after reaper
      await asAnon();
      const res3 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Buyer 2', '9830999999', 'Address 9876543210', '700002') AS r
      `, [dropALiveId, prodA1Id]);
      const result3 = res3.rows[0].r!;

      expect(result3.success).toBe(true);
      expect(result3.order_id).not.toBe(order1Id);

      // Verify Buyer 2 now owns the hold
      await asSuperuser();
      const finalProd = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(finalProd.rows[0].status).toBe('reserved');
      expect(finalProd.rows[0].reserved_by_order_id).toBe(result3.order_id);
    });

    it('reaper preserves paid orders and non-expired holds while cancelling expired holds across multiple sellers', async () => {
      // Step 1: Create Order A1 (Paid)
      await asAnon();
      const resA1 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Paid Buyer', '9830123451', 'Address A 12345', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const orderA1Id = resA1.rows[0].r!.order_id!;

      await asServiceRole();
      await db.query(`SELECT mark_order_paid($1, 'REF-REAP-A1', '{}'::jsonb)`, [orderA1Id]);

      // Step 2: Create Order A2 (Expired)
      await asAnon();
      const resA2 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Expired A Buyer', '9830123452', 'Address A 67890', '700001') AS r
      `, [dropALiveId, prodA2Id]);
      const orderA2Id = resA2.rows[0].r!.order_id!;

      // Step 3: Create Order B1 (Expired, Seller B)
      const resB1 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Expired B Buyer', '9830123453', 'Address B 12345', '600001') AS r
      `, [dropBLiveId, prodBLiveId]);
      const orderB1Id = resB1.rows[0].r!.order_id!;

      // Mark A2 and B1 expired
      await asSuperuser();
      await db.query(`UPDATE orders SET hold_expires_at = NOW() - INTERVAL '10 minutes' WHERE id IN ($1, $2)`, [orderA2Id, orderB1Id]);

      // Step 4: Execute reaper as service_role
      await asServiceRole();
      await db.query(`SELECT release_expired_holds();`);

      // Verify states as superuser
      await asSuperuser();
      const oA1 = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [orderA1Id]);
      expect(oA1.rows[0].status).toBe('paid');
      const pA1 = await db.query<ProductRow>(`SELECT status FROM products WHERE id = $1`, [prodA1Id]);
      expect(pA1.rows[0].status).toBe('sold');

      // Verify A2 is cancelled and prodA2 is available
      const oA2 = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [orderA2Id]);
      expect(oA2.rows[0].status).toBe('cancelled');
      const pA2 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA2Id]);
      expect(pA2.rows[0].status).toBe('available');
      expect(pA2.rows[0].reserved_by_order_id).toBeNull();

      // Verify B1 is cancelled and prodBLive is available
      const oB1 = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [orderB1Id]);
      expect(oB1.rows[0].status).toBe('cancelled');
      const pB1 = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodBLiveId]);
      expect(pB1.rows[0].status).toBe('available');
      expect(pB1.rows[0].reserved_by_order_id).toBeNull();
    });
  });


  // ==========================================================================
  // 6. TOKEN-GATED RECEIPT RETRIEVAL (get_order_by_token)
  // ==========================================================================
  describe('6. Token-Gated Receipt Retrieval (get_order_by_token)', () => {
    it('retrieves complete order receipt and nested line items with matching token', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], 'Debolina Sen', '9830123456', 'Salt Lake Sector 1 Kolkata', '700064'
        ) AS r
      `, [dropALiveId, prodA1Id, prodA2Id]);
      const { order_id, order_token, order_code } = checkoutRes.rows[0].r!;

      // Call get_order_by_token as anonymous buyer
      const fetchRes = await db.query<RpcResponseRow>(`
        SELECT get_order_by_token($1, $2) AS r
      `, [order_id, order_token]);
      const fetchResult = fetchRes.rows[0].r!;

      expect(fetchResult.success).toBe(true);
      expect(fetchResult.order!.id).toBe(order_id);
      expect(fetchResult.order!.order_code).toBe(order_code);
      expect(fetchResult.order!.buyer_name).toBe('Debolina Sen');
      expect(fetchResult.order!.store_name).toBe('Priya Trends');
      expect(fetchResult.order!.upi_id).toBe('priya@okaxis');
      expect(fetchResult.order!.items.length).toBe(2);
      expect(fetchResult.order!.items[0].code).toBe('#A01');
      expect(fetchResult.order!.items[1].code).toBe('#A02');
    });

    it('rejects retrieval with invalid token or wrong order_id', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Debolina Sen', '9830123456', 'Address 1234567890', '700064') AS r
      `, [dropALiveId, prodA1Id]);
      const { order_id } = checkoutRes.rows[0].r!;

      // Forged random token
      const wrongToken = '00000000-0000-0000-0000-000000000000';
      const fetchRes = await db.query<RpcResponseRow>(`
        SELECT get_order_by_token($1, $2) AS r
      `, [order_id, wrongToken]);

      const fetchResult = fetchRes.rows[0].r!;
      expect(fetchResult.success).toBe(false);
      expect(fetchResult.error).toBe('ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    });

    it('verifies that sensitive PII (phone, address, pincode) is strictly excluded from receipt response', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Priya Mukherjee', '9830123456', 'Confidential Home Address 12345', '700001'
        ) AS r
      `, [dropALiveId, prodA1Id]);
      const { order_id, order_token } = checkoutRes.rows[0].r!;

      const fetchRes = await db.query<{ r: { success: boolean; order?: Record<string, unknown> } }>(`
        SELECT get_order_by_token($1, $2) AS r
      `, [order_id, order_token]);
      const orderPayload = fetchRes.rows[0].r.order!;

      // Necessary receipt greeting field is present
      expect(orderPayload.buyer_name).toBe('Priya Mukherjee');

      // Sensitive fulfillment PII is strictly excluded from the returned payload
      expect(orderPayload.buyer_phone).toBeUndefined();
      expect(orderPayload.shipping_address).toBeUndefined();
      expect(orderPayload.pincode).toBeUndefined();
    });

    it('cross-order token isolation: valid token from Order A cannot access Order B', async () => {
      await asAnon();
      // Create Order A
      const resA = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Buyer A', '9830123451', 'Address A 123456789', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const { order_token: orderTokenA } = resA.rows[0].r!;

      // Create Order B
      const resB = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Buyer B', '9830123452', 'Address B 123456789', '700002') AS r
      `, [dropALiveId, prodA2Id]);
      const { order_id: orderIdB } = resB.rows[0].r!;

      // Attempt to access Order B using Order A's secret token
      const fetchRes = await db.query<RpcResponseRow>(`
        SELECT get_order_by_token($1, $2) AS r
      `, [orderIdB, orderTokenA]);
      expect(fetchRes.rows[0].r!.success).toBe(false);
      expect(fetchRes.rows[0].r!.error).toBe('ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    });
  });


  // ==========================================================================
  // 7. SELLER AUXILIARY RPCS (force_release_hold, mark_product_sold_offline)
  // ==========================================================================
  describe('7. Seller Manual Overrides (force_release_hold, mark_product_sold_offline)', () => {
    it('seller force releases active hold, returning products to available and cancelling order', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Test Buyer', '9830123456', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].r!.order_id!;

      // Owning seller releases hold
      await asSeller(sellerAId);
      const releaseRes = await db.query<RpcResponseRow>(`SELECT force_release_hold($1) AS r`, [orderId]);
      expect(releaseRes.rows[0].r!.success).toBe(true);

      // Verify product is available and order cancelled
      await asSuperuser();
      const p = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(p.rows[0].status).toBe('available');
      expect(p.rows[0].reserved_by_order_id).toBeNull();

      const o = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [orderId]);
      expect(o.rows[0].status).toBe('cancelled');
    });

    it('rejects force_release_hold on already paid or shipped orders', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Test Buyer', '9830123456', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].r!.order_id!;

      await asServiceRole();
      await db.query(`SELECT mark_order_paid($1, 'REF-HOLD', '{}'::jsonb)`, [orderId]);

      await asSeller(sellerAId);
      const releaseRes = await db.query<RpcResponseRow>(`SELECT force_release_hold($1) AS r`, [orderId]);
      expect(releaseRes.rows[0].r!.success).toBe(false);
      expect(releaseRes.rows[0].r!.error).toBe('ONLY_PENDING_CAN_BE_RELEASED');
    });

    it('seller marks available product sold offline', async () => {
      await asSeller(sellerAId);
      const res = await db.query<RpcResponseRow>(`SELECT mark_product_sold_offline($1) AS r`, [prodA4Id]);
      expect(res.rows[0].r!.success).toBe(true);

      await asSuperuser();
      const p = await db.query<ProductRow>(`SELECT status FROM products WHERE id = $1`, [prodA4Id]);
      expect(p.rows[0].status).toBe('sold');

      // Calling again returns ALREADY_SOLD
      await asSeller(sellerAId);
      const res2 = await db.query<RpcResponseRow>(`SELECT mark_product_sold_offline($1) AS r`, [prodA4Id]);
      expect(res2.rows[0].r!.success).toBe(false);
      expect(res2.rows[0].r!.error).toBe('ALREADY_SOLD');
    });

    it('rejects mark_product_sold_offline from non-owning seller', async () => {
      await asSeller(sellerBId);
      const res = await db.query<RpcResponseRow>(`SELECT mark_product_sold_offline($1) AS r`, [prodA4Id]);
      expect(res.rows[0].r!.success).toBe(false);
      expect(res.rows[0].r!.error).toBe('PRODUCT_NOT_FOUND_OR_UNAUTHORIZED');
    });
  });

  // ==========================================================================
  // 8. CONCURRENCY & RACE CONDITIONS
  // ==========================================================================
  describe('8. High-Velocity Concurrency & Race Condition Simulation', () => {
    it('TC-CON-01: 2 concurrent buyers requesting the same single-piece garment', async () => {
      await asAnon();

      const call1 = db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Buyer One', '9830123451', 'Address Buyer One 123', '700001'
        ) AS r;
      `, [dropALiveId, prodA1Id]);

      const call2 = db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Buyer Two', '9830123452', 'Address Buyer Two 123', '700002'
        ) AS r;
      `, [dropALiveId, prodA1Id]);

      const [r1, r2] = await Promise.all([call1, call2]);
      const res1 = r1.rows[0].r!;
      const res2 = r2.rows[0].r!;

      const successes = [res1, res2].filter(r => r.success);
      const failures = [res1, res2].filter(r => !r.success);

      expect(successes.length).toBe(1);
      expect(failures.length).toBe(1);
      expect(failures[0].error).toBe('STOCK_UNAVAILABLE');

      // Verify exactly 1 reservation in database
      await asSuperuser();
      const p = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(p.rows[0].status).toBe('reserved');
      expect(p.rows[0].reserved_by_order_id).toBe(successes[0].order_id);
    });

    it('TC-CON-02: 5 concurrent buyers requesting the same single-piece garment', async () => {
      await asAnon();

      const calls = Array.from({ length: 5 }, (_, i) =>
        db.query<RpcResponseRow>(`
          SELECT create_order_with_reservation(
            $1, ARRAY[$2]::uuid[], $3, $4, $5, $6
          ) AS r;
        `, [dropALiveId, prodA3Id, `Buyer ${i}`, `983012345${i}`, `Address Buyer ${i}`, '700001'])
      );

      const responses = await Promise.all(calls);
      const parsed = responses.map(r => r.rows[0].r!);

      const successes = parsed.filter(r => r.success);
      const failures = parsed.filter(r => !r.success);

      expect(successes.length).toBe(1);
      expect(failures.length).toBe(4);
      for (const fail of failures) {
        expect(fail.error).toBe('STOCK_UNAVAILABLE');
      }
    });

    it('TC-CON-03: 20 concurrent buyers requesting the same single-piece garment (flash crowd)', async () => {
      await asAnon();

      const calls = Array.from({ length: 20 }, (_, i) =>
        db.query<RpcResponseRow>(`
          SELECT create_order_with_reservation(
            $1, ARRAY[$2]::uuid[], $3, $4, $5, $6
          ) AS r;
        `, [dropALiveId, prodA4Id, `Crowd Buyer ${i}`, `98301234${i.toString().padStart(2, '0')}`, `Address Crowd ${i}`, '700001'])
      );

      const responses = await Promise.all(calls);
      const parsed = responses.map(r => r.rows[0].r!);

      const successes = parsed.filter(r => r.success);
      const failures = parsed.filter(r => !r.success);

      expect(successes.length).toBe(1);
      expect(failures.length).toBe(19);
      for (const fail of failures) {
        expect(fail.error).toBe('STOCK_UNAVAILABLE');
      }

      // Verify exactly 1 order and exactly 1 reserved item
      await asSuperuser();
      const p = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA4Id]);
      expect(p.rows[0].status).toBe('reserved');
      expect(p.rows[0].reserved_by_order_id).toBe(successes[0].order_id);
    });

    it('TC-CON-04: Multi-item overlapping cart collision (Buyer A: [#01, #02], Buyer B: [#02, #03])', async () => {
      await asAnon();

      const callA = db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], 'Buyer A', '9830123451', 'Address A 123', '700001'
        ) AS r;
      `, [dropALiveId, prodA1Id, prodA2Id]);

      const callB = db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], 'Buyer B', '9830123452', 'Address B 123', '700002'
        ) AS r;
      `, [dropALiveId, prodA2Id, prodA3Id]);

      const [rA, rB] = await Promise.all([callA, callB]);
      const resA = rA.rows[0].r!;
      const resB = rB.rows[0].r!;

      const successes = [resA, resB].filter(r => r.success);
      const failures = [resA, resB].filter(r => !r.success);

      expect(successes.length).toBe(1);
      expect(failures.length).toBe(1);
      expect(failures[0].error).toBe('STOCK_UNAVAILABLE');
    });

    it('TC-CON-05: Deadlock prevention under opposite product sorting order', async () => {
      await asAnon();

      // Buyer A requests [prodA1, prodA2]
      const callA = db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], 'Buyer Normal', '9830123451', 'Address Normal 123', '700001'
        ) AS r;
      `, [dropALiveId, prodA1Id, prodA2Id]);

      // Buyer B requests [prodA2, prodA1] (reversed order in payload)
      const callB = db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2, $3]::uuid[], 'Buyer Reverse', '9830123452', 'Address Reverse 123', '700002'
        ) AS r;
      `, [dropALiveId, prodA2Id, prodA1Id]);

      // Because ORDER BY id ASC FOR UPDATE is enforced, no deadlock occurs
      const [rA, rB] = await Promise.all([callA, callB]);
      const resA = rA.rows[0].r!;
      const resB = rB.rows[0].r!;

      const successes = [resA, resB].filter(r => r.success);
      const failures = [resA, resB].filter(r => !r.success);

      expect(successes.length).toBe(1);
      expect(failures.length).toBe(1);
      expect(failures[0].error).toBe('STOCK_UNAVAILABLE');
    });
  });

  // ==========================================================================
  // 9. SECURITY DEFINER HARDENING & ROUTINE PRIVILEGE BOUNDARIES
  // ==========================================================================
  describe('9. Routine Privilege Boundaries & Security Definer Hardening', () => {
    it('anon role is strictly denied execution on force_release_hold (SQLSTATE 42501)', async () => {
      await asAnon();
      await expect(
        db.query(`SELECT force_release_hold('00000000-0000-0000-0000-000000000000'::uuid);`)
      ).rejects.toThrow(/permission denied for function force_release_hold/i);
    });

    it('anon role is strictly denied execution on mark_product_sold_offline (SQLSTATE 42501)', async () => {
      await asAnon();
      await expect(
        db.query(`SELECT mark_product_sold_offline('00000000-0000-0000-0000-000000000000'::uuid);`)
      ).rejects.toThrow(/permission denied for function mark_product_sold_offline/i);
    });

    it('anon role is strictly denied execution on release_expired_holds (SQLSTATE 42501)', async () => {
      await asAnon();
      await expect(
        db.query(`SELECT release_expired_holds();`)
      ).rejects.toThrow(/permission denied for function release_expired_holds/i);
    });

    it('authenticated seller role is strictly denied execution on release_expired_holds (SQLSTATE 42501)', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`SELECT release_expired_holds();`)
      ).rejects.toThrow(/permission denied for function release_expired_holds/i);
    });

    it('service_role is permitted execution on release_expired_holds', async () => {
      await asServiceRole();
      await expect(
        db.query(`SELECT release_expired_holds();`)
      ).resolves.toBeDefined();
    });

    it('anon role is permitted execution on create_order_with_reservation and get_order_by_token', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Anon Buyer', '9830123456', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      expect(checkoutRes.rows[0].r!.success).toBe(true);

      const { order_id, order_token } = checkoutRes.rows[0].r!;
      const fetchRes = await db.query<RpcResponseRow>(`SELECT get_order_by_token($1, $2) AS r;`, [order_id, order_token]);
      expect(fetchRes.rows[0].r!.success).toBe(true);
    });

    it('authenticated role can execute get_order_by_token with valid credentials', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Auth Buyer', '9830123456', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const { order_id, order_token } = checkoutRes.rows[0].r!;

      // An authenticated user (e.g. buyer who later registers) can query token-gated endpoint
      await asSeller(sellerBId);
      const res = await db.query<RpcResponseRow>(`SELECT get_order_by_token($1, $2) AS r;`, [order_id, order_token]);
      expect(res.rows[0].r!.success).toBe(true);
    });

    it('cross-seller force_release_hold is blocked with ORDER_NOT_FOUND_OR_UNAUTHORIZED', async () => {
      await asAnon();
      const checkoutRes = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Victim Buyer', '9830123456', 'Address 1234567890', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      const orderId = checkoutRes.rows[0].r!.order_id!;

      // Seller B attempts to force release Seller A's order
      await asSeller(sellerBId);
      const res = await db.query<RpcResponseRow>(`SELECT force_release_hold($1) AS r;`, [orderId]);
      expect(res.rows[0].r!.success).toBe(false);
      expect(res.rows[0].r!.error).toBe('ORDER_NOT_FOUND_OR_UNAUTHORIZED');

      // Verify product is still reserved by Buyer
      await asSuperuser();
      const p = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(p.rows[0].status).toBe('reserved');
      expect(p.rows[0].reserved_by_order_id).toBe(orderId);
    });
  });

  // ==========================================================================
  // 10. DUPLICATE CHECKOUT & IDEMPOTENCY SEMANTICS (MODEL B)
  // ==========================================================================
  describe('10. Duplicate Checkout & Idempotency Semantics (Model B)', () => {
    it('Model B: sequential duplicate checkout for 1-of-1 item fails on second attempt with STOCK_UNAVAILABLE', async () => {
      await asAnon();
      // First checkout attempt succeeds
      const res1 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Ankita Bose', '9830123456', 'Lake Gardens Kolkata', '700045'
        ) AS r
      `, [dropALiveId, prodA1Id]);
      expect(res1.rows[0].r!.success).toBe(true);
      const firstOrderId = res1.rows[0].r!.order_id!;

      // Identical sequential checkout attempt with identical payload
      const res2 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation(
          $1, ARRAY[$2]::uuid[], 'Ankita Bose', '9830123456', 'Lake Gardens Kolkata', '700045'
        ) AS r
      `, [dropALiveId, prodA1Id]);

      // Because the item is 1-of-1 and already reserved, the duplicate request is rejected at the inventory level
      expect(res2.rows[0].r!.success).toBe(false);
      expect(res2.rows[0].r!.error).toBe('STOCK_UNAVAILABLE');

      // Verify the first order remains unchanged and product is still held by Order 1
      await asSuperuser();
      const p = await db.query<ProductRow>(`SELECT status, reserved_by_order_id FROM products WHERE id = $1`, [prodA1Id]);
      expect(p.rows[0].status).toBe('reserved');
      expect(p.rows[0].reserved_by_order_id).toBe(firstOrderId);

      const o = await db.query<OrderRow>(`SELECT status FROM orders WHERE id = $1`, [firstOrderId]);
      expect(o.rows[0].status).toBe('pending');
    });

    it('Model B: distinct checkouts for different available items succeed independently', async () => {
      await asAnon();
      // Buyer places order for Product 1
      const res1 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Buyer One', '9830123451', 'Address One 12345', '700001') AS r
      `, [dropALiveId, prodA1Id]);
      expect(res1.rows[0].r!.success).toBe(true);

      // Same buyer places order for Product 2 (independent item)
      const res2 = await db.query<RpcResponseRow>(`
        SELECT create_order_with_reservation($1, ARRAY[$2]::uuid[], 'Buyer One', '9830123451', 'Address One 12345', '700001') AS r
      `, [dropALiveId, prodA2Id]);
      expect(res2.rows[0].r!.success).toBe(true);
      expect(res2.rows[0].r!.order_id).not.toBe(res1.rows[0].r!.order_id);
    });
  });
});

