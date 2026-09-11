// @vitest-environment node
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { PGlite } from '@electric-sql/pglite';
import * as fs from 'node:fs';
import * as path from 'node:path';

interface ProfileRow {
  id: string;
  store_name: string;
  phone_number: string;
  default_shipping_fee_paisa: number;
  free_shipping_threshold_paisa: number | null;
}

interface DropRow {
  id: string;
  seller_id: string;
  title: string;
  slug: string;
  status: string;
  shipping_fee_paisa: number;
}

interface ProductRow {
  id: string;
  drop_id: string;
  code: string;
  price_paisa: number;
  status: string;
  version: number;
  reserved_by_order_id: string | null;
}

interface OrderRow {
  id: string;
  order_code: string;
  order_token: string;
  subtotal_paisa: number;
  shipping_paisa: number;
  total_paisa: number;
  status: string;
  hold_expires_at: string;
}

interface OrderItemRow {
  id: string;
  order_id: string;
  product_id: string;
  price_at_purchase_paisa: number;
}

interface ColumnMetaRow {
  table_name: string;
  column_name: string;
  data_type: string;
}

interface IndexMetaRow {
  indexname: string;
  tablename: string;
}

describe('LiveDrop Relational Database Schema (TASK-1.1)', () => {
  let db: PGlite;

  const migrationsDir = path.resolve(__dirname, '../../../supabase/migrations');

  beforeAll(async () => {
    db = new PGlite();

    // 1. Setup prerequisite auth schema, table, and auth.uid() function
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

    // 2. Read and apply all 8 migration files in deterministic sequential order
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
      expect(fs.existsSync(filePath), `Migration file ${file} must exist`).toBe(true);
      const sql = fs.readFileSync(filePath, 'utf-8');
      await db.exec(sql);
    }
  });

  afterAll(async () => {
    if (db) {
      await db.close();
    }
  });

  // ==========================================================================
  // SECTION 1: POSITIVE TESTS (Valid Records & Relationships)
  // ==========================================================================

  it('1. should successfully insert a valid boutique seller profile', async () => {
    const userId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, $2)`, [userId, 'seller@livedrop.in']);

    const res = await db.query<ProfileRow>(`
      INSERT INTO profiles (
        id, store_name, phone_number, upi_id, upi_qr_url, return_address, 
        default_shipping_fee_paisa, free_shipping_threshold_paisa
      ) VALUES (
        $1, 'Priya Boutique', '9876543210', 'priya@okaxis', 'https://cdn.livedrop.in/qr.png',
        '42 MG Road, Indiranagar, Bengaluru, Karnataka 560038', 8000, 200000
      ) RETURNING *;
    `, [userId]);

    expect(res.rows.length).toBe(1);
    const profile = res.rows[0];
    expect(profile.store_name).toBe('Priya Boutique');
    expect(profile.phone_number).toBe('9876543210');
    expect(profile.default_shipping_fee_paisa).toBe(8000);
    expect(profile.free_shipping_threshold_paisa).toBe(200000);
  });

  it('2. should successfully insert a valid drop linked to seller profile', async () => {
    const sellerId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';

    const res = await db.query<DropRow>(`
      INSERT INTO drops (
        id, seller_id, title, slug, status, shipping_fee_paisa, free_shipping_threshold_paisa
      ) VALUES (
        $1, $2, 'Friday Silk Festival', 'friday-silk-festival', 'live', 8000, 200000
      ) RETURNING *;
    `, [dropId, sellerId]);

    expect(res.rows.length).toBe(1);
    const drop = res.rows[0];
    expect(drop.slug).toBe('friday-silk-festival');
    expect(drop.status).toBe('live');
    expect(drop.shipping_fee_paisa).toBe(8000);
  });

  it('3. should successfully insert a valid product with flash code and integer paisa price', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    const productId = 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33';

    const res = await db.query<ProductRow>(`
      INSERT INTO products (
        id, drop_id, code, title, price_paisa, size, image_url, status, version
      ) VALUES (
        $1, $2, '#A01', 'Pure Kanjivaram Silk', 145000, 'Free Size', 'https://cdn.livedrop.in/a01.webp', 'available', 1
      ) RETURNING *;
    `, [productId, dropId]);

    expect(res.rows.length).toBe(1);
    const product = res.rows[0];
    expect(product.code).toBe('#A01');
    expect(product.price_paisa).toBe(145000);
    expect(product.status).toBe('available');
    expect(product.version).toBe(1);
  });

  it('4. should successfully insert a valid customer order with balanced integer paisa totals', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    const orderId = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a44';

    const res = await db.query<OrderRow>(`
      INSERT INTO orders (
        id, drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa, status
      ) VALUES (
        $1, $2, 'LD-7K92MF', 'Ananya Sharma', '9123456789',
        'Flat 402, Palm Grove Apts, Koramangala, Bengaluru', '560034',
        145000, 8000, 153000, 'pending'
      ) RETURNING *;
    `, [orderId, dropId]);

    expect(res.rows.length).toBe(1);
    const order = res.rows[0];
    expect(order.order_code).toBe('LD-7K92MF');
    expect(order.subtotal_paisa).toBe(145000);
    expect(order.shipping_paisa).toBe(8000);
    expect(order.total_paisa).toBe(153000);
    expect(order.status).toBe('pending');
    expect(order.order_token).toBeDefined();
    expect(order.hold_expires_at).toBeDefined();
  });

  it('5. should successfully insert a valid order_item with immutable price snapshot', async () => {
    const orderId = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a44';
    const productId = 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33';

    const res = await db.query<OrderItemRow>(`
      INSERT INTO order_items (
        order_id, product_id, price_at_purchase_paisa
      ) VALUES (
        $1, $2, 145000
      ) RETURNING *;
    `, [orderId, productId]);

    expect(res.rows.length).toBe(1);
    const item = res.rows[0];
    expect(item.price_at_purchase_paisa).toBe(145000);
    expect(item.order_id).toBe(orderId);
    expect(item.product_id).toBe(productId);
  });

  // ==========================================================================
  // SECTION 2: NEGATIVE TESTS (Integrity Constraints & Validations)
  // ==========================================================================

  it('6. should reject duplicate drop slug', async () => {
    const sellerId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    await expect(db.query(`
      INSERT INTO drops (seller_id, title, slug)
      VALUES ($1, 'Another Drop with same slug', 'friday-silk-festival');
    `, [sellerId])).rejects.toThrow();
  });

  it('7. should reject duplicate product flash code within the same drop', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#A01', 120000, 'https://cdn.livedrop.in/duplicate.webp');
    `, [dropId])).rejects.toThrow();
  });

  it('8. should allow the same product flash code in a DIFFERENT drop', async () => {
    const sellerId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    const dropRes = await db.query<DropRow>(`
      INSERT INTO drops (seller_id, title, slug)
      VALUES ($1, 'Saturday Cotton Special', 'saturday-cotton-special')
      RETURNING id, seller_id, title, slug, status, shipping_fee_paisa;
    `, [sellerId]);
    const secondDropId = dropRes.rows[0].id;

    const prodRes = await db.query<ProductRow>(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#A01', 99000, 'https://cdn.livedrop.in/diff_drop.webp')
      RETURNING id, drop_id, code, price_paisa, status, version, reserved_by_order_id;
    `, [secondDropId]);

    expect(prodRes.rows.length).toBe(1);
    expect(prodRes.rows[0].code).toBe('#A01');
  });

  it('9. should reject invalid product status', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url, status)
      VALUES ($1, '#A02', 120000, 'https://cdn.livedrop.in/img.webp', 'archived');
    `, [dropId])).rejects.toThrow();
  });

  it('10. should reject invalid order status', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa, status
      ) VALUES (
        $1, 'LD-INVALID', 'Test Buyer', '9876543210', '123 Address Lane', '560001',
        10000, 0, 10000, 'refunded'
      );
    `, [dropId])).rejects.toThrow();
  });

  it('11. should reject non-positive product price (price_paisa <= 0)', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#FREE01', 0, 'https://cdn.livedrop.in/free.webp');
    `, [dropId])).rejects.toThrow();

    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#NEG01', -5000, 'https://cdn.livedrop.in/neg.webp');
    `, [dropId])).rejects.toThrow();
  });

  it('12. should reject order total mismatch (total_paisa != subtotal_paisa + shipping_paisa)', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-BADTOT', 'Math Test', '9876543210', '123 Address Lane', '560001',
        100000, 8000, 105000 -- Wrong total: 100000 + 8000 != 105000
      );
    `, [dropId])).rejects.toThrow();
  });

  it('13. should reject negative subtotal or shipping in order', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-NEGSUB', 'Negative Subtotal', '9876543210', '123 Address Lane', '560001',
        -1000, 1000, 0
      );
    `, [dropId])).rejects.toThrow();
  });

  it('14. should reject malformed product flash codes', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    // Missing '#'
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, 'A02', 10000, 'https://cdn.livedrop.in/bad.webp');
    `, [dropId])).rejects.toThrow();

    // Too long (> 6 alphanumeric chars after #)
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#TOOLONG123', 10000, 'https://cdn.livedrop.in/bad.webp');
    `, [dropId])).rejects.toThrow();
  });

  it('15. should reject malformed order code', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    // Wrong prefix
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'ORD-123456', 'Buyer Name', '9876543210', '123 Address Lane', '560001',
        10000, 0, 10000
      );
    `, [dropId])).rejects.toThrow();

    // Wrong length (5 instead of 6 chars after LD-)
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-12345', 'Buyer Name', '9876543210', '123 Address Lane', '560001',
        10000, 0, 10000
      );
    `, [dropId])).rejects.toThrow();
  });

  it('16. should reject invalid phone numbers and pincodes', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    // Invalid phone: doesn't start with 6-9
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-BADPH1', 'Buyer Name', '5555555555', '123 Address Lane', '560001',
        10000, 0, 10000
      );
    `, [dropId])).rejects.toThrow();

    // Invalid pincode: not 6 digits
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-BADPIN', 'Buyer Name', '9876543210', '123 Address Lane', '5600',
        10000, 0, 10000
      );
    `, [dropId])).rejects.toThrow();
  });

  it('17. should reject orphaned product with invalid foreign key', async () => {
    const nonExistentDropId = '99999999-9999-9999-9999-999999999999';
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#ORPH01', 50000, 'https://cdn.livedrop.in/orph.webp');
    `, [nonExistentDropId])).rejects.toThrow();
  });

  it('18. should reject duplicate item in same order', async () => {
    const orderId = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a44';
    const productId = 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33';

    // c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33 was already added in test 5
    await expect(db.query(`
      INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
      VALUES ($1, $2, 145000);
    `, [orderId, productId])).rejects.toThrow();
  });

  it('19. should enforce ON DELETE RESTRICT on products referenced in order_items', async () => {
    const productId = 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33';
    // Trying to delete a product that has been ordered must be rejected
    await expect(db.query(`
      DELETE FROM products WHERE id = $1;
    `, [productId])).rejects.toThrow();
  });

  it('20. should enforce ON DELETE RESTRICT on drops referenced in orders', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    // Trying to delete a drop that has orders must be rejected
    await expect(db.query(`
      DELETE FROM drops WHERE id = $1;
    `, [dropId])).rejects.toThrow();
  });

  it('21. should enforce ON DELETE CASCADE on orders -> order_items', async () => {
    // Create a disposable order and order_item to verify CASCADE deletion
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    
    // Create a new product
    const pRes = await db.query<ProductRow>(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#CAS01', 50000, 'https://cdn.livedrop.in/cas.webp')
      RETURNING id, drop_id, code, price_paisa, status, version, reserved_by_order_id;
    `, [dropId]);
    const pId = pRes.rows[0].id;

    // Create a new order
    const oRes = await db.query<OrderRow>(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-CASC01', 'Cascade Buyer', '9876543210', '123 Address Lane', '560001',
        50000, 0, 50000
      ) RETURNING id, order_code, order_token, subtotal_paisa, shipping_paisa, total_paisa, status, hold_expires_at;
    `, [dropId]);
    const oId = oRes.rows[0].id;

    // Add order item
    await db.query(`
      INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
      VALUES ($1, $2, 50000);
    `, [oId, pId]);

    // Deleting the order should cascade to delete the order_item
    await db.query(`DELETE FROM orders WHERE id = $1;`, [oId]);

    const remainingItems = await db.query<OrderItemRow>(`
      SELECT id, order_id, product_id, price_at_purchase_paisa FROM order_items WHERE order_id = $1;
    `, [oId]);
    expect(remainingItems.rows.length).toBe(0);

    // The product still exists and can now be deleted if needed
    const remainingProduct = await db.query<ProductRow>(`
      SELECT id, drop_id, code, price_paisa, status, version, reserved_by_order_id FROM products WHERE id = $1;
    `, [pId]);
    expect(remainingProduct.rows.length).toBe(1);
  });

  it('22. should reject orphaned order item with non-existent foreign keys', async () => {
    const validOrderId = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a44';
    const fakeId = '88888888-8888-8888-8888-888888888888';

    // Invalid product_id
    await expect(db.query(`
      INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
      VALUES ($1, $2, 50000);
    `, [validOrderId, fakeId])).rejects.toThrow();

    // Invalid order_id
    await expect(db.query(`
      INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
      VALUES ($1, $2, 50000);
    `, [fakeId, 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33'])).rejects.toThrow();
  });

  it('23. should enforce ON DELETE RESTRICT on orders referenced by products (reserved_by_order_id)', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';

    // Create a product
    const pRes = await db.query<ProductRow>(`
      INSERT INTO products (drop_id, code, price_paisa, image_url, status)
      VALUES ($1, '#RES01', 75000, 'https://cdn.livedrop.in/res.webp', 'reserved')
      RETURNING id, drop_id, code, price_paisa, status, version, reserved_by_order_id;
    `, [dropId]);
    const productId = pRes.rows[0].id;

    // Create an order that holds the reservation
    const oRes = await db.query<OrderRow>(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-RESV01', 'Reserve Buyer', '9876543210', '123 Address Lane', '560001',
        75000, 0, 75000
      ) RETURNING id, order_code, order_token, subtotal_paisa, shipping_paisa, total_paisa, status, hold_expires_at;
    `, [dropId]);
    const orderId = oRes.rows[0].id;

    // Link product to order
    await db.query(`
      UPDATE products SET reserved_by_order_id = $1 WHERE id = $2;
    `, [orderId, productId]);

    const checkBefore = await db.query<ProductRow>(`SELECT id, drop_id, code, price_paisa, status, version, reserved_by_order_id FROM products WHERE id = $1;`, [productId]);
    expect(checkBefore.rows[0].reserved_by_order_id).toBe(orderId);

    // Attempting to delete the order should be BLOCKED by RESTRICT
    await expect(db.query(`DELETE FROM orders WHERE id = $1;`, [orderId])).rejects.toThrow();

    // Verify product and order both still exist
    const checkAfter = await db.query<ProductRow>(`SELECT id, drop_id, code, price_paisa, status, version, reserved_by_order_id FROM products WHERE id = $1;`, [productId]);
    expect(checkAfter.rows[0].reserved_by_order_id).toBe(orderId);
  });

  it('24. should strictly verify all monetary columns are typed integer (Paisa)', async () => {
    const res = await db.query<ColumnMetaRow>(`
      SELECT table_name, column_name, data_type
      FROM information_schema.columns
      WHERE table_schema = 'public' 
        AND column_name LIKE '%paisa%'
      ORDER BY table_name, column_name;
    `);

    expect(res.rows.length).toBe(9);
    for (const col of res.rows) {
      expect(col.data_type, `Column ${col.table_name}.${col.column_name} must be integer`).toBe('integer');
    }
  });

  it('25. should verify all indexes exist in pg_indexes', async () => {
    const res = await db.query<IndexMetaRow>(`
      SELECT indexname, tablename
      FROM pg_indexes
      WHERE schemaname = 'public' AND indexname LIKE 'idx_%';
    `);

    const indexNames = res.rows.map((r) => r.indexname);

    const expectedIndexes = [
      'idx_products_drop_status',
      'idx_products_active_hold',
      'idx_orders_drop_status',
      // idx_orders_order_token removed: UNIQUE constraint creates implicit index
      'idx_orders_hold_expiry',
      'idx_orders_buyer_phone',
      'idx_order_items_order',
      'idx_order_items_product',
      'idx_drops_one_live_per_seller',
    ];

    for (const exp of expectedIndexes) {
      expect(indexNames, `Expected index ${exp} to be present in pg_indexes`).toContain(exp);
    }
    expect(indexNames.length).toBe(8);
  });

  // ==========================================================================
  // SECTION 3: POST-REMEDIATION VERIFICATION TESTS
  // ==========================================================================

  it('26. should enforce one-live-drop-per-seller invariant at the database level', async () => {
    // Setup Seller 1 and Seller 2
    const seller1Id = 'a1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';
    const seller2Id = 'a2eebc99-9c0b-4ef8-bb6d-6bb9bd380a02';
    await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 's1@live.in'), ($2, 's2@live.in');`, [seller1Id, seller2Id]);
    await db.query(`
      INSERT INTO profiles (id, store_name, phone_number, upi_id, return_address)
      VALUES 
        ($1, 'Seller One Store', '9811111111', 's1@okhdfc', '100 Road, Bengaluru 560001'),
        ($2, 'Seller Two Store', '9822222222', 's2@okhdfc', '200 Road, Bengaluru 560002');
    `, [seller1Id, seller2Id]);

    // 1. Seller 1 creates their first live drop -> SUCCESS
    const drop1Res = await db.query<DropRow>(`
      INSERT INTO drops (seller_id, title, slug, status)
      VALUES ($1, 'Seller 1 Live Drop 1', 's1-live-drop-1', 'live')
      RETURNING *;
    `, [seller1Id]);
    expect(drop1Res.rows.length).toBe(1);
    const drop1Id = drop1Res.rows[0].id;

    // 2. Seller 1 attempts to create a second live drop -> BLOCKED by partial unique index
    await expect(db.query(`
      INSERT INTO drops (seller_id, title, slug, status)
      VALUES ($1, 'Seller 1 Live Drop 2', 's1-live-drop-2', 'live');
    `, [seller1Id])).rejects.toThrow();

    // 3. Seller 1 CAN create a draft drop while having a live drop -> SUCCESS
    const draftRes = await db.query<DropRow>(`
      INSERT INTO drops (seller_id, title, slug, status)
      VALUES ($1, 'Seller 1 Draft Drop', 's1-draft-drop', 'draft')
      RETURNING *;
    `, [seller1Id]);
    expect(draftRes.rows.length).toBe(1);
    const draftDropId = draftRes.rows[0].id;

    // 4. Seller 2 CAN have their own live drop simultaneously -> SUCCESS
    const s2DropRes = await db.query<DropRow>(`
      INSERT INTO drops (seller_id, title, slug, status)
      VALUES ($1, 'Seller 2 Live Drop', 's2-live-drop', 'live')
      RETURNING *;
    `, [seller2Id]);
    expect(s2DropRes.rows.length).toBe(1);

    // 5. Seller 1 attempts to transition their draft drop to 'live' while drop 1 is still 'live' -> BLOCKED
    await expect(db.query(`
      UPDATE drops SET status = 'live' WHERE id = $1;
    `, [draftDropId])).rejects.toThrow();

    // 6. Seller 1 closes their first live drop -> SUCCESS
    await db.query(`UPDATE drops SET status = 'closed', closed_at = NOW() WHERE id = $1;`, [drop1Id]);

    // 7. Now Seller 1 CAN transition their draft drop to 'live' -> SUCCESS
    const activatedRes = await db.query<DropRow>(`
      UPDATE drops SET status = 'live' WHERE id = $1 RETURNING *;
    `, [draftDropId]);
    expect(activatedRes.rows[0].status).toBe('live');

    // 8. Reopening closed drop 1 while draftDrop is live -> BLOCKED deterministically
    await expect(db.query(`
      UPDATE drops SET status = 'live' WHERE id = $1;
    `, [drop1Id])).rejects.toThrow();
  });

  it('27. should enforce ON DELETE RESTRICT on profiles referenced by drops', async () => {
    // Seller 1 has drops created above; attempting to delete seller profile must be blocked
    const seller1Id = 'a1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';
    await expect(db.query(`DELETE FROM profiles WHERE id = $1;`, [seller1Id])).rejects.toThrow();

    // Verify profile still exists
    const checkRes = await db.query(`SELECT id FROM profiles WHERE id = $1;`, [seller1Id]);
    expect(checkRes.rows.length).toBe(1);
  });

  it('28. should enforce ON DELETE RESTRICT on drops referenced by products', async () => {
    // Drop b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22 has products from earlier tests
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    await expect(db.query(`DELETE FROM drops WHERE id = $1;`, [dropId])).rejects.toThrow();

    // Verify drop still exists
    const checkRes = await db.query(`SELECT id FROM drops WHERE id = $1;`, [dropId]);
    expect(checkRes.rows.length).toBe(1);
  });

  it('29. should enforce finalized-order deletion guard trigger (cannot delete paid or shipped orders)', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';

    // 1. Create paid order
    const paidRes = await db.query<OrderRow>(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa, status, paid_at
      ) VALUES (
        $1, 'LD-PDTEST', 'Paid Buyer', '9876543210', '123 Address Lane', '560001',
        100000, 0, 100000, 'paid', NOW()
      ) RETURNING id;
    `, [dropId]);
    const paidOrderId = paidRes.rows[0].id;

    // Deleting paid order must be aborted by trigger
    await expect(db.query(`DELETE FROM orders WHERE id = $1;`, [paidOrderId])).rejects.toThrow(/Cannot delete finalized order/);

    // 2. Create shipped order
    const shippedRes = await db.query<OrderRow>(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa, status, paid_at, shipped_at
      ) VALUES (
        $1, 'LD-SHPTST', 'Shipped Buyer', '9876543210', '123 Address Lane', '560001',
        100000, 0, 100000, 'shipped', NOW(), NOW()
      ) RETURNING id;
    `, [dropId]);
    const shippedOrderId = shippedRes.rows[0].id;

    // Deleting shipped order must be aborted by trigger
    await expect(db.query(`DELETE FROM orders WHERE id = $1;`, [shippedOrderId])).rejects.toThrow(/Cannot delete finalized order/);

    // 3. Create and delete cancelled order -> Allowed (if no foreign key restriction)
    const cancelledRes = await db.query<OrderRow>(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa, status
      ) VALUES (
        $1, 'LD-CNLTST', 'Cancelled Buyer', '9876543210', '123 Address Lane', '560001',
        100000, 0, 100000, 'cancelled'
      ) RETURNING id;
    `, [dropId]);
    const cancelledOrderId = cancelledRes.rows[0].id;

    await expect(db.query(`DELETE FROM orders WHERE id = $1;`, [cancelledOrderId])).resolves.toBeDefined();
  });

  it('30. should verify updated_at trigger updates timestamp, preserves created_at, and overrides application values', async () => {
    // 1. Check profile updated_at trigger
    const profileId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    const beforeProfile = (await db.query<{ created_at: string; updated_at: string }>(
      `SELECT created_at, updated_at FROM profiles WHERE id = $1;`, [profileId]
    )).rows[0];

    // Wait a tiny moment to ensure timestamp ticks forward
    await new Promise((r) => setTimeout(r, 20));

    // Even if application explicitly passes an old timestamp, trigger MUST overwrite with NOW()
    const pastTimestamp = '2020-01-01T00:00:00Z';
    const afterProfile = (await db.query<{ created_at: string; updated_at: string }>(`
      UPDATE profiles 
      SET store_name = 'Priya Luxury Boutique', updated_at = $2 
      WHERE id = $1 
      RETURNING created_at, updated_at;
    `, [profileId, pastTimestamp])).rows[0];

    expect(new Date(afterProfile.updated_at).getTime()).toBeGreaterThan(new Date(beforeProfile.updated_at).getTime());
    expect(afterProfile.updated_at).not.toBe(pastTimestamp);
    expect(new Date(afterProfile.created_at).getTime()).toBe(new Date(beforeProfile.created_at).getTime());

    // 2. Check drops updated_at trigger
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';
    const beforeDrop = (await db.query<{ created_at: string; updated_at: string }>(
      `SELECT created_at, updated_at FROM drops WHERE id = $1;`, [dropId]
    )).rows[0];

    await new Promise((r) => setTimeout(r, 20));

    const afterDrop = (await db.query<{ created_at: string; updated_at: string }>(`
      UPDATE drops SET title = 'Friday Silk Gala Updated' WHERE id = $1 RETURNING created_at, updated_at;
    `, [dropId])).rows[0];

    expect(new Date(afterDrop.updated_at).getTime()).toBeGreaterThan(new Date(beforeDrop.updated_at).getTime());
    expect(new Date(afterDrop.created_at).getTime()).toBe(new Date(beforeDrop.created_at).getTime());

    // 3. Check products updated_at trigger
    const productId = 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33';
    const beforeProduct = (await db.query<{ created_at: string; updated_at: string }>(
      `SELECT created_at, updated_at FROM products WHERE id = $1;`, [productId]
    )).rows[0];

    await new Promise((r) => setTimeout(r, 20));

    const afterProduct = (await db.query<{ created_at: string; updated_at: string }>(`
      UPDATE products SET title = 'Updated Title' WHERE id = $1 RETURNING created_at, updated_at;
    `, [productId])).rows[0];

    expect(new Date(afterProduct.updated_at).getTime()).toBeGreaterThan(new Date(beforeProduct.updated_at).getTime());
    expect(new Date(afterProduct.created_at).getTime()).toBe(new Date(beforeProduct.created_at).getTime());

    // 4. Check orders updated_at trigger
    const orderId = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a44';
    const beforeOrder = (await db.query<{ created_at: string; updated_at: string }>(
      `SELECT created_at, updated_at FROM orders WHERE id = $1;`, [orderId]
    )).rows[0];

    await new Promise((r) => setTimeout(r, 20));

    const afterOrder = (await db.query<{ created_at: string; updated_at: string }>(`
      UPDATE orders SET buyer_name = 'Ananya Sharma Updated' WHERE id = $1 RETURNING created_at, updated_at;
    `, [orderId])).rows[0];

    expect(new Date(afterOrder.updated_at).getTime()).toBeGreaterThan(new Date(beforeOrder.updated_at).getTime());
    expect(new Date(afterOrder.created_at).getTime()).toBe(new Date(beforeOrder.created_at).getTime());
  });

  it('31. should strictly enforce subtotal positivity and monetary constraints', async () => {
    const dropId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22';

    // 1. subtotal_paisa = 0 must be REJECTED (F10 remediation: subtotal_paisa > 0)
    await expect(db.query(`
      INSERT INTO orders (
        drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
        subtotal_paisa, shipping_paisa, total_paisa
      ) VALUES (
        $1, 'LD-ZERO01', 'Zero Buyer', '9876543210', '123 Address Lane', '560001',
        0, 8000, 8000
      );
    `, [dropId])).rejects.toThrow();

    // 2. price_at_purchase_paisa <= 0 in order_items must be REJECTED
    const validOrderId = 'd0eebc99-9c0b-4ef8-bb6d-6bb9bd380a44';
    // Create new product
    const pRes = await db.query<ProductRow>(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#MON01', 50000, 'https://cdn.livedrop.in/mon.webp')
      RETURNING id;
    `, [dropId]);
    const pId = pRes.rows[0].id;

    await expect(db.query(`
      INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
      VALUES ($1, $2, 0);
    `, [validOrderId, pId])).rejects.toThrow();

    await expect(db.query(`
      INSERT INTO order_items (order_id, product_id, price_at_purchase_paisa)
      VALUES ($1, $2, -5000);
    `, [validOrderId, pId])).rejects.toThrow();
  });

  it('32. should enforce string length and regex validations (UPI, slug, image_url)', async () => {
    const sellerId = 'a2eebc99-9c0b-4ef8-bb6d-6bb9bd380a02';

    // 1. UPI validation: rejects invalid format or length
    const badUserId = 'e0eebc99-9c0b-4ef8-bb6d-6bb9bd380a99';
    await db.query(`INSERT INTO auth.users (id, email) VALUES ($1, 'badupi@test.com');`, [badUserId]);

    // Invalid UPI (no @)
    await expect(db.query(`
      INSERT INTO profiles (id, store_name, phone_number, upi_id, return_address)
      VALUES ($1, 'Store Name', '9876543210', 'invalidvpa', '123 Address Lane 560001');
    `, [badUserId])).rejects.toThrow();

    // Invalid UPI (username exceeds 255 chars)
    const longUpi = 'a'.repeat(256) + '@okhdfc';
    await expect(db.query(`
      INSERT INTO profiles (id, store_name, phone_number, upi_id, return_address)
      VALUES ($1, 'Store Name', '9876543210', $2, '123 Address Lane 560001');
    `, [badUserId, longUpi])).rejects.toThrow();

    // 2. Slug length validation: rejects slug < 3 chars or > 60 chars (F6 remediation)
    // Slug too short (< 3 chars)
    await expect(db.query(`
      INSERT INTO drops (seller_id, title, slug)
      VALUES ($1, 'Short Slug Drop', 'ab');
    `, [sellerId])).rejects.toThrow();

    // Slug too long (> 60 chars)
    const longSlug = 'a'.repeat(61);
    await expect(db.query(`
      INSERT INTO drops (seller_id, title, slug)
      VALUES ($1, 'Long Slug Drop', $2);
    `, [sellerId, longSlug])).rejects.toThrow();

    // Valid slug of length 60
    const validSlug60 = 'a'.repeat(60);
    const validDrop = await db.query<DropRow>(`
      INSERT INTO drops (seller_id, title, slug)
      VALUES ($1, 'Valid 60 Char Slug Drop', $2)
      RETURNING id, slug;
    `, [sellerId, validSlug60]);
    expect(validDrop.rows.length).toBe(1);
    const validDropId = validDrop.rows[0].id;

    // 3. image_url length validation: rejects empty or > 2048 chars (F8 remediation)
    // Empty image_url
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#IMG01', 50000, '');
    `, [validDropId])).rejects.toThrow();

    // image_url > 2048 chars
    const longUrl = 'https://cdn.livedrop.in/' + 'x'.repeat(2048);
    await expect(db.query(`
      INSERT INTO products (drop_id, code, price_paisa, image_url)
      VALUES ($1, '#IMG02', 50000, $2);
    `, [validDropId, longUrl])).rejects.toThrow();
  });

  it('33. should verify all 5 database triggers exist in information_schema.triggers', async () => {
    const res = await db.query<{ trigger_name: string; event_object_table: string }>(`
      SELECT trigger_name, event_object_table
      FROM information_schema.triggers
      WHERE trigger_schema = 'public'
      ORDER BY trigger_name;
    `);

    const expectedTriggers = [
      'trg_drops_updated_at',
      'trg_orders_no_delete_finalized',
      'trg_orders_updated_at',
      'trg_products_updated_at',
      'trg_profiles_updated_at',
    ];

    const foundNames = res.rows.map((r) => r.trigger_name);
    for (const exp of expectedTriggers) {
      expect(foundNames, `Trigger ${exp} must exist`).toContain(exp);
    }
    expect(res.rows.length).toBe(5);
  });
});
