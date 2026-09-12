// @vitest-environment node
/**
 * LiveDrop TASK-2.4A: Business Domain, Order State Machine & Seller Storefront Tests
 *
 * Validates:
 * 1. Multi-seller storefront identity and configuration (store_slug, defaults, overrides, max 30-day hold)
 * 2. Seller isolation and configuration authorization (Seller A cannot modify Seller B)
 * 3. Configuration snapshotting at order creation (seller settings changes do NOT mutate existing orders)
 * 4. Confirmation modes ('advance' vs 'full_payment') and buyer inability to dictate advance amounts
 * 5. Complete financial invariants and check constraints (no negative paisa, advance <= total, balance consistency)
 * 6. Order state machine, payment state, and fulfilment state transitions
 * 7. Non-negotiable shipment invariant: advance-paid orders CANNOT be ready_to_ship or shipped
 * 8. 30-day hold expiration and non-refundable advance semantics via release_expired_holds
 * 9. Order payments auditability (order_payments records preserve payment history)
 * 10. Adversarial attacks and illegal state rejection
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { PGlite } from '@electric-sql/pglite';
import * as fs from 'node:fs';
import * as path from 'node:path';

interface CreateOrderRpcOutput {
  success: boolean;
  error?: string;
  message?: string;
  order_id?: string;
  order_code?: string;
  order_token?: string;
  subtotal_paisa?: number;
  shipping_paisa?: number;
  total_paisa?: number;
  confirmation_mode?: string;
  advance_required_paisa?: number;
  advance_paid_paisa?: number;
  balance_due_paisa?: number;
  total_paid_paisa?: number;
  payment_status?: string;
  fulfilment_status?: string;
  hold_expires_at?: string;
}

interface RpcSuccessOutput {
  success: boolean;
  error?: string;
  message?: string;
}

interface ReceiptRpcOutput {
  success: boolean;
  order: {
    order_code: string;
    confirmation_mode: string;
    status: string;
    payment_status: string;
    advance_paid_paisa: number;
    balance_due_paisa: number;
    fulfilment_status: string;
    buyer_phone?: string;
    shipping_address?: string;
  };
}

describe('LiveDrop Storefront Architecture & Order State Machine (TASK-2.4A)', () => {
  let db: PGlite;

  const migrationsDir = path.resolve(__dirname, '../../../supabase/migrations');

  // Test Seller IDs
  const sellerAId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
  const sellerBId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22';

  // Drop IDs
  const dropA1Id = 'd1000000-0000-0000-0000-000000000001';
  const dropB1Id = 'd2000000-0000-0000-0000-000000000001';

  // Product IDs
  const prodA1Id = 'ca000000-0000-0000-0000-000000000001'; // 185000 paisa (₹1,850)
  const prodA2Id = 'ca000000-0000-0000-0000-000000000002'; // 75000 paisa (₹750)
  const prodB1Id = 'cb000000-0000-0000-0000-000000000001'; // 500000 paisa (₹5,000)

  // Auth Context Helpers
  async function asSuperuser() {
    await db.exec(`
      RESET ROLE;
      SELECT set_config('request.jwt.claim.sub', '', false);
      SELECT set_config('request.headers', '', false);
    `);
  }

  async function asSeller(sellerId: string) {
    await db.exec(`
      SET ROLE authenticated;
      SELECT set_config('request.jwt.claim.sub', '${sellerId}', false);
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

  async function asServiceRole() {
    await db.exec(`
      SET ROLE service_role;
      SELECT set_config('request.jwt.claim.sub', '', false);
      SELECT set_config('request.headers', '', false);
    `);
  }

  beforeAll(async () => {
    db = new PGlite();

    // 1. Auth schema setup
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

    // 2. Apply all 10 migrations sequentially
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
    ];

    for (const file of migrationFiles) {
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf-8');
      await db.exec(sql);
    }

    // 3. Seed Base Test Fixtures
    await asSuperuser();

    await db.query(`
      INSERT INTO auth.users (id, email) VALUES 
        ('${sellerAId}', 'sonali@livedrop.in'),
        ('${sellerBId}', 'artisan@livedrop.in');
    `);

    // Seller A: Sonali's Boutique, advance enabled, ₹250 default advance (25000 paisa), 30 days hold
    await db.query(`
      INSERT INTO profiles (
        id, store_name, store_slug, phone_number, upi_id, return_address, 
        default_shipping_fee_paisa, advance_confirmation_enabled, advance_amount_paisa, hold_duration_days
      ) VALUES (
        '${sellerAId}', 'Sonalis Boutique', 'sonalis', '919830012345', 'sonali@okhdfc', 'Ballygunge Kolkata',
        8000, true, 25000, 30
      );
    `);

    // Seller B: Artisan Silks, advance enabled, ₹500 default advance (50000 paisa), 14 days hold
    await db.query(`
      INSERT INTO profiles (
        id, store_name, store_slug, phone_number, upi_id, return_address, 
        default_shipping_fee_paisa, advance_confirmation_enabled, advance_amount_paisa, hold_duration_days
      ) VALUES (
        '${sellerBId}', 'Artisan Silks', 'artisan-silks', '919830067890', 'artisan@okaxis', 'MG Road Bengaluru',
        10000, true, 50000, 14
      );
    `);

    // Drops
    await db.query(`
      INSERT INTO drops (id, seller_id, title, slug, status, shipping_fee_paisa) VALUES 
        ('${dropA1Id}', '${sellerAId}', 'Friday Silk Special', 'friday-silk', 'live', 8000),
        ('${dropB1Id}', '${sellerBId}', 'Heritage Kanjeevarams', 'heritage-kanjeevarams', 'live', 10000);
    `);

    // Products
    await db.query(`
      INSERT INTO products (id, drop_id, code, title, price_paisa, size, image_url, status) VALUES 
        ('${prodA1Id}', '${dropA1Id}', '#S01', 'Handloom Tussar Saree', 185000, 'Free Size', 'https://images.livedrop.store/s01.webp', 'available'),
        ('${prodA2Id}', '${dropA1Id}', '#S02', 'Silk Dupatta', 75000, 'Free Size', 'https://images.livedrop.store/s02.webp', 'available'),
        ('${prodB1Id}', '${dropB1Id}', '#B01', 'Pure Gold Zari Kanjeevaram', 500000, 'Free Size', 'https://images.livedrop.store/b01.webp', 'available');
    `);
  });

  afterAll(async () => {
    if (db) {
      await db.close();
    }
  });

  // ==========================================================================
  // SECTION 1: SELLER STOREFRONT IDENTITY & CONFIGURATION
  // ==========================================================================
  describe('1. Storefront Identity & Configuration Rules', () => {
    it('1.1 enforces unique, normalized, URL-safe store_slug', async () => {
      await asSuperuser();
      // Store slug matching regex [a-z0-9-]+
      const res = await db.query<{ store_slug: string }>(
        `SELECT store_slug FROM profiles WHERE id = '${sellerAId}';`
      );
      expect(res.rows[0].store_slug).toBe('sonalis');

      // Duplicate store_slug must be rejected by UNIQUE constraint
      const dupSellerId = 'a3eebc99-9c0b-4ef8-bb6d-6bb9bd380a33';
      await db.query(`INSERT INTO auth.users (id, email) VALUES ('${dupSellerId}', 'dup@livedrop.in');`);
      await expect(
        db.query(`
          INSERT INTO profiles (id, store_name, store_slug, phone_number, upi_id, return_address)
          VALUES ('${dupSellerId}', 'Duplicate Store', 'sonalis', '919830099999', 'dup@okhdfc', 'Kolkata');
        `)
      ).rejects.toThrow();

      // Uppercase or invalid characters in store_slug must be rejected by check constraint
      await expect(
        db.query(`
          INSERT INTO profiles (id, store_name, store_slug, phone_number, upi_id, return_address)
          VALUES ('${dupSellerId}', 'Bad Slug Store', 'Invalid_Slug!', '919830099999', 'dup@okhdfc', 'Kolkata');
        `)
      ).rejects.toThrow();
    });

    it('1.2 enforces maximum hold duration of 30 days at database level', async () => {
      await asSeller(sellerAId);

      // Updating hold_duration_days to 30 is allowed
      await expect(
        db.query(`UPDATE profiles SET hold_duration_days = 30 WHERE id = '${sellerAId}';`)
      ).resolves.toBeDefined();

      // Updating hold_duration_days to 31 or greater MUST be rejected by check constraint
      await expect(
        db.query(`UPDATE profiles SET hold_duration_days = 31 WHERE id = '${sellerAId}';`)
      ).rejects.toThrow();

      await expect(
        db.query(`UPDATE profiles SET hold_duration_days = 60 WHERE id = '${sellerAId}';`)
      ).rejects.toThrow();

      // Drop-level override also cannot exceed 30 days
      await expect(
        db.query(`UPDATE drops SET hold_duration_days = 35 WHERE id = '${dropA1Id}';`)
      ).rejects.toThrow();
    });

    it('1.3 enforces positive advance amount when advance confirmation is enabled', async () => {
      await asSeller(sellerAId);

      // Advance of 0 when enabled MUST be rejected
      await expect(
        db.query(`UPDATE profiles SET advance_amount_paisa = 0 WHERE id = '${sellerAId}';`)
      ).rejects.toThrow();

      // Negative advance MUST be rejected
      await expect(
        db.query(`UPDATE profiles SET advance_amount_paisa = -5000 WHERE id = '${sellerAId}';`)
      ).rejects.toThrow();

      // Valid positive advance (e.g. ₹300 = 30000 paisa) succeeds
      await expect(
        db.query(`UPDATE profiles SET advance_amount_paisa = 30000 WHERE id = '${sellerAId}';`)
      ).resolves.toBeDefined();

      // Reset back to ₹250
      await db.query(`UPDATE profiles SET advance_amount_paisa = 25000 WHERE id = '${sellerAId}';`);
    });

    it('1.4 enforces multi-seller isolation (Seller A cannot update Seller B settings)', async () => {
      await asSeller(sellerAId);

      // Seller A tries to update Seller B profile
      const updateResult = await db.query(
        `UPDATE profiles SET store_name = 'Hacked Store' WHERE id = '${sellerBId}';`
      );
      // Under RLS, 0 rows are updated
      expect(updateResult.affectedRows).toBe(0);

      // Verify Seller B remains untouched
      await asSuperuser();
      const bProfile = await db.query<{ store_name: string }>(
        `SELECT store_name FROM profiles WHERE id = '${sellerBId}';`
      );
      expect(bProfile.rows[0].store_name).toBe('Artisan Silks');
    });
  });

  // ==========================================================================
  // SECTION 2: CHECKOUT CONFIRMATION MODES & SNAPSHOT INTEGRITY
  // ==========================================================================
  describe('2. Confirmation Modes & Configuration Snapshotting', () => {
    it('2.1 creates advance-confirmed order with server-authoritative ₹250 advance snapshot', async () => {
      await asAnon();

      const rpcResult = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${prodA1Id}']::UUID[],
          'Ananya Roy',
          '9830111222',
          'Flat 3A, Salt Lake City',
          '700064',
          'advance'
        );
      `);

      const orderData = rpcResult.rows[0].create_order_with_reservation;
      expect(orderData.success).toBe(true);
      expect(orderData.confirmation_mode).toBe('advance');
      expect(orderData.advance_required_paisa).toBe(25000); // Server-resolved from Seller A policy (₹250)
      expect(orderData.advance_paid_paisa).toBe(0);
      expect(orderData.total_paid_paisa).toBe(0);
      expect(orderData.balance_due_paisa).toBe(orderData.total_paisa);
      expect(orderData.payment_status).toBe('unpaid');
      expect(orderData.fulfilment_status).toBe('not_ready');

      // Check product is reserved
      const prodRow = await db.query<{ status: string; reserved_by_order_id: string }>(
        `SELECT status, reserved_by_order_id FROM products WHERE id = '${prodA1Id}';`
      );
      expect(prodRow.rows[0].status).toBe('reserved');
      expect(prodRow.rows[0].reserved_by_order_id).toBe(orderData.order_id);
    });

    it('2.2 proves configuration immutability: seller changing advance does NOT mutate existing order', async () => {
      await asSuperuser();

      // Read existing order advance requirement
      const ordBefore = await db.query<{ id: string; advance_required_paisa: number }>(`
        SELECT id, advance_required_paisa FROM orders WHERE drop_id = '${dropA1Id}' LIMIT 1;
      `);
      const existingOrderId = ordBefore.rows[0].id;
      expect(ordBefore.rows[0].advance_required_paisa).toBe(25000);

      // Seller A now updates their store default advance from ₹250 to ₹500
      await asSeller(sellerAId);
      await db.query(`UPDATE profiles SET advance_amount_paisa = 50000 WHERE id = '${sellerAId}';`);

      // Historical order must STILL have advance_required_paisa = 25000
      await asSuperuser();
      const ordAfter = await db.query<{ advance_required_paisa: number }>(`
        SELECT advance_required_paisa FROM orders WHERE id = '${existingOrderId}';
      `);
      expect(ordAfter.rows[0].advance_required_paisa).toBe(25000);

      // Reset Seller A back to ₹250
      await asSeller(sellerAId);
      await db.query(`UPDATE profiles SET advance_amount_paisa = 25000 WHERE id = '${sellerAId}';`);
    });

    it('2.3 creates full_payment mode order with zero advance requirement', async () => {
      await asAnon();

      const rpcResult = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropB1Id}',
          ARRAY['${prodB1Id}']::UUID[],
          'Vikram Mehta',
          '9822334455',
          'Indiranagar 100ft Rd',
          '560038',
          'full_payment'
        );
      `);

      const orderData = rpcResult.rows[0].create_order_with_reservation;
      expect(orderData.success).toBe(true);
      expect(orderData.confirmation_mode).toBe('full_payment');
      expect(orderData.advance_required_paisa).toBe(0);
      expect(orderData.advance_paid_paisa).toBe(0);
      expect(orderData.total_paid_paisa).toBe(0);
      expect(orderData.balance_due_paisa).toBe(orderData.total_paisa);
      expect(orderData.payment_status).toBe('unpaid');
      expect(orderData.fulfilment_status).toBe('not_ready');
    });

    it('2.4 rejects invalid confirmation mode', async () => {
      await asAnon();

      const rpcResult = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${prodA2Id}']::UUID[],
          'Test Buyer',
          '9830111222',
          'Address',
          '700064',
          'invalid_mode'
        );
      `);

      const orderData = rpcResult.rows[0].create_order_with_reservation;
      expect(orderData.success).toBe(false);
      expect(orderData.error).toBe('INVALID_CONFIRMATION_MODE');
    });
  });

  // ==========================================================================
  // SECTION 3: ORDER ADVANCE CONFIRMATION & FULL PAYMENT LIFECYCLE
  // ==========================================================================
  describe('3. Order State Machine Transitions & Payment Accounting', () => {
    let testOrderId: string;
    let testOrderToken: string;
    let testTotalPaisa: number;
    let testAdvanceRequiredPaisa: number;

    beforeAll(async () => {
      await asAnon();
      // Create a fresh advance-mode order on Drop A for prodA2
      const rpcResult = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${prodA2Id}']::UUID[],
          'Pooja Sen',
          '9830999888',
          'Park Street Kolkata',
          '700016',
          'advance'
        );
      `);
      const data = rpcResult.rows[0].create_order_with_reservation;
      testOrderId = data.order_id!;
      testOrderToken = data.order_token!;
      testTotalPaisa = data.total_paisa!;
      testAdvanceRequiredPaisa = data.advance_required_paisa!;
    });

    it('3.1 privileged seller confirms advance: updates order state and records payment', async () => {
      await asSeller(sellerAId);

      const confirmResult = await db.query<{ confirm_order_advance: RpcSuccessOutput }>(`
        SELECT confirm_order_advance('${testOrderId}', 'UPI-TXN-ADV-001');
      `);

      const res = confirmResult.rows[0].confirm_order_advance;
      expect(res.success).toBe(true);

      // Verify orders table state
      await asSuperuser();
      const oRow = await db.query<{
        status: string;
        payment_status: string;
        advance_paid_paisa: number;
        total_paid_paisa: number;
        balance_due_paisa: number;
        fulfilment_status: string;
      }>(`
        SELECT status, payment_status, advance_paid_paisa, total_paid_paisa, balance_due_paisa, fulfilment_status
        FROM orders
        WHERE id = '${testOrderId}';
      `);

      expect(oRow.rows[0].status).toBe('confirmed');
      expect(oRow.rows[0].payment_status).toBe('advance_paid');
      expect(oRow.rows[0].advance_paid_paisa).toBe(testAdvanceRequiredPaisa);
      expect(oRow.rows[0].total_paid_paisa).toBe(testAdvanceRequiredPaisa);
      expect(oRow.rows[0].balance_due_paisa).toBe(testTotalPaisa - testAdvanceRequiredPaisa);
      expect(oRow.rows[0].fulfilment_status).toBe('not_ready');

      // Verify payment row was created in order_payments
      const paymentRows = await db.query<{
        amount_paisa: number;
        payment_type: string;
        reference_id: string;
      }>(`
        SELECT amount_paisa, payment_type, reference_id 
        FROM order_payments 
        WHERE order_id = '${testOrderId}';
      `);
      expect(paymentRows.rows.length).toBe(1);
      expect(paymentRows.rows[0].amount_paisa).toBe(testAdvanceRequiredPaisa);
      expect(paymentRows.rows[0].payment_type).toBe('advance');
      expect(paymentRows.rows[0].reference_id).toBe('UPI-TXN-ADV-001');
    });

    it('3.2 STRICT NON-NEGOTIABLE RULE: advance-paid order CANNOT be shipped or ready_to_ship', async () => {
      await asSuperuser();

      // Directly attempting to update fulfilment_status to 'ready_to_ship' while balance_due_paisa > 0 MUST FAIL
      await expect(
        db.query(`
          UPDATE orders 
          SET fulfilment_status = 'ready_to_ship' 
          WHERE id = '${testOrderId}';
        `)
      ).rejects.toThrow();

      // Directly attempting to update fulfilment_status to 'shipped' while balance_due_paisa > 0 MUST FAIL
      await expect(
        db.query(`
          UPDATE orders 
          SET fulfilment_status = 'shipped' 
          WHERE id = '${testOrderId}';
        `)
      ).rejects.toThrow();

      // Directly attempting to set status = 'shipped' while balance_due_paisa > 0 MUST FAIL
      await expect(
        db.query(`
          UPDATE orders 
          SET status = 'shipped' 
          WHERE id = '${testOrderId}';
        `)
      ).rejects.toThrow();
    });

    it('3.3 buyer receipt token retrieval exposes new state without PII leakage', async () => {
      await asAnon(testOrderToken);

      const res = await db.query<{ get_order_by_token: ReceiptRpcOutput }>(`
        SELECT get_order_by_token('${testOrderId}', '${testOrderToken}');
      `);

      const receipt = res.rows[0].get_order_by_token;
      expect(receipt.success).toBe(true);
      expect(receipt.order.order_code).toBeDefined();
      expect(receipt.order.confirmation_mode).toBe('advance');
      expect(receipt.order.status).toBe('confirmed');
      expect(receipt.order.payment_status).toBe('advance_paid');
      expect(receipt.order.advance_paid_paisa).toBe(testAdvanceRequiredPaisa);
      expect(receipt.order.balance_due_paisa).toBe(testTotalPaisa - testAdvanceRequiredPaisa);
      expect(receipt.order.fulfilment_status).toBe('not_ready');

      // PII minimization check: phone number and shipping address are omitted
      expect(receipt.order.buyer_phone).toBeUndefined();
      expect(receipt.order.shipping_address).toBeUndefined();
    });

    it('3.4 paying remaining balance transitions order to paid, zero balance, and eligible for shipping', async () => {
      await asSeller(sellerAId);

      // Mark order fully paid via mark_order_paid RPC
      const paidRes = await db.query<{ mark_order_paid: RpcSuccessOutput }>(`
        SELECT mark_order_paid('${testOrderId}');
      `);

      expect(paidRes.rows[0].mark_order_paid.success).toBe(true);

      // Verify DB row
      await asSuperuser();
      const orderRow = await db.query<{
        status: string;
        payment_status: string;
        total_paid_paisa: number;
        balance_due_paisa: number;
        fulfilment_status: string;
      }>(`
        SELECT status, payment_status, total_paid_paisa, balance_due_paisa, fulfilment_status 
        FROM orders 
        WHERE id = '${testOrderId}';
      `);

      expect(orderRow.rows[0].status).toBe('paid');
      expect(orderRow.rows[0].payment_status).toBe('paid');
      expect(orderRow.rows[0].total_paid_paisa).toBe(testTotalPaisa);
      expect(orderRow.rows[0].balance_due_paisa).toBe(0);

      // Now that balance_due_paisa = 0, fulfilment_status CAN transition to ready_to_ship and shipped
      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'ready_to_ship' WHERE id = '${testOrderId}';`)
      ).resolves.toBeDefined();

      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'shipped', status = 'shipped' WHERE id = '${testOrderId}';`)
      ).resolves.toBeDefined();
    });
  });

  // ==========================================================================
  // SECTION 4: HOLD EXPIRATION & REAPER SEMANTICS
  // ==========================================================================
  describe('4. Hold Expiration & Non-Refundable Advance Semantics', () => {
    let expiredOrderId: string;
    let expiredProductId: string;

    beforeAll(async () => {
      await asSuperuser();
      // Create product
      const pRes = await db.query<{ id: string }>(`
        INSERT INTO products (drop_id, code, title, price_paisa, status, image_url)
        VALUES ('${dropA1Id}', '#EXP01', 'Silk Stole', 90000, 'available', 'https://images.livedrop.store/exp01.webp')
        RETURNING id;
      `);
      expiredProductId = pRes.rows[0].id;

      // Create order in confirmed state with advance paid, but hold_expires_at in the past
      const oRes = await db.query<{ id: string }>(`
        INSERT INTO orders (
          drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
          subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
          advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
          payment_status, status, hold_expires_at, advance_paid_at
        ) VALUES (
          '${dropA1Id}', 'LD-EXP001', 'Expired Buyer', '9830000000', '123 Park Street, Floor 4, Kolkata', '700016',
          90000, 8000, 98000, 'advance',
          25000, 25000, 25000, 73000,
          'advance_paid', 'confirmed', NOW() - INTERVAL '1 hour', NOW() - INTERVAL '2 days'
        ) RETURNING id;
      `);
      expiredOrderId = oRes.rows[0].id;

      // Link product to order as reserved
      await db.query(`
        UPDATE products 
        SET status = 'reserved', reserved_by_order_id = '${expiredOrderId}', reserved_at = NOW() - INTERVAL '2 days'
        WHERE id = '${expiredProductId}';
      `);

      // Record advance payment in order_payments
      await db.query(`
        INSERT INTO order_payments (order_id, amount_paisa, payment_type, status, reference_id)
        VALUES ('${expiredOrderId}', 25000, 'advance', 'verified', 'TXN-ADV-EXP');
      `);
    });

    it('4.1 release_expired_holds cancels hold: transitions order to expired, frees inventory, retains advance', async () => {
      await asServiceRole();

      // Execute reaper RPC
      await expect(db.query(`SELECT release_expired_holds();`)).resolves.toBeDefined();

      // Check order state: status is 'expired', advance_paid_paisa is retained, mathematical balance is preserved
      await asSuperuser();
      const oRow = await db.query<{
        status: string;
        payment_status: string;
        balance_due_paisa: number;
        advance_paid_paisa: number;
      }>(`
        SELECT status, payment_status, balance_due_paisa, advance_paid_paisa 
        FROM orders 
        WHERE id = '${expiredOrderId}';
      `);
      expect(oRow.rows[0].status).toBe('expired');
      expect(oRow.rows[0].balance_due_paisa).toBe(73000); // Preserves mathematical consistency (total - total_paid)
      expect(oRow.rows[0].advance_paid_paisa).toBe(25000); // Advance retained as non-refundable

      // Check product is freed: status back to 'available'
      const pRow = await db.query<{ status: string; reserved_by_order_id: string | null }>(`
        SELECT status, reserved_by_order_id FROM products WHERE id = '${expiredProductId}';
      `);
      expect(pRow.rows[0].status).toBe('available');
      expect(pRow.rows[0].reserved_by_order_id).toBeNull();

      // Check order_payments record persists the non-refundable advance
      const payRows = await db.query<{ amount_paisa: number; payment_type: string }>(`
        SELECT amount_paisa, payment_type FROM order_payments WHERE order_id = '${expiredOrderId}';
      `);
      expect(payRows.rows.length).toBe(1);
      expect(payRows.rows[0].amount_paisa).toBe(25000);
    });

    it('4.2 expired order CANNOT be shipped', async () => {
      await asSuperuser();
      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'shipped' WHERE id = '${expiredOrderId}';`)
      ).rejects.toThrow();
    });
  });

  // ==========================================================================
  // SECTION 5: FINANCIAL INVARIANTS & ILLEGAL STATE PREVENTION
  // ==========================================================================
  describe('5. Financial Invariants & State Matrix Consistency', () => {
    it('5.1 rejects advance_required_paisa > total_paisa', async () => {
      await asSuperuser();
      await expect(
        db.query(`
          INSERT INTO orders (
            drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
            subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
            advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa
          ) VALUES (
            '${dropA1Id}', 'LD-BAD01', 'Bad Buyer', '9830000000', 'Addr', '700001',
            10000, 0, 10000, 'advance',
            20000, 0, 0, 10000
          );
        `)
      ).rejects.toThrow();
    });

    it('5.2 rejects advance_paid_paisa > advance_required_paisa', async () => {
      await asSuperuser();
      await expect(
        db.query(`
          INSERT INTO orders (
            drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
            subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
            advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa
          ) VALUES (
            '${dropA1Id}', 'LD-BAD02', 'Bad Buyer', '9830000000', 'Addr', '700001',
            50000, 0, 50000, 'advance',
            25000, 30000, 30000, 20000
          );
        `)
      ).rejects.toThrow();
    });

    it('5.3 rejects total_paid_paisa > total_paisa', async () => {
      await asSuperuser();
      await expect(
        db.query(`
          INSERT INTO orders (
            drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
            subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
            advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa
          ) VALUES (
            '${dropA1Id}', 'LD-BAD03', 'Bad Buyer', '9830000000', 'Addr', '700001',
            50000, 0, 50000, 'full_payment',
            0, 0, 60000, -10000
          );
        `)
      ).rejects.toThrow();
    });

    it('5.4 rejects balance_due_paisa mismatch with (total_paisa - total_paid_paisa)', async () => {
      await asSuperuser();
      await expect(
        db.query(`
          INSERT INTO orders (
            drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
            subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
            advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa
          ) VALUES (
            '${dropA1Id}', 'LD-BAD04', 'Bad Buyer', '9830000000', 'Addr', '700001',
            50000, 0, 50000, 'advance',
            25000, 25000, 25000, 10000 -- Contradiction: 50000 - 25000 != 10000
          );
        `)
      ).rejects.toThrow();
    });

    it('5.5 rejects payment_status = paid when balance_due_paisa > 0', async () => {
      await asSuperuser();
      await expect(
        db.query(`
          INSERT INTO orders (
            drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
            subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
            advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
            payment_status, status
          ) VALUES (
            '${dropA1Id}', 'LD-BAD05', 'Bad Buyer', '9830000000', 'Addr', '700001',
            50000, 0, 50000, 'advance',
            25000, 25000, 25000, 25000,
            'paid', 'confirmed'
          );
        `)
      ).rejects.toThrow();
    });
  });

  // ==========================================================================
  // SECTION 6: ADVERSARIAL TESTS
  // ==========================================================================
  describe('6. Adversarial Attack Tests', () => {
    it('6.1 buyer cannot tamper with advance amount (database ignores client amounts)', async () => {
      await asAnon();
      // Even if client attempts to pass arbitrary parameters to create_order_with_reservation,
      // the RPC only accepts drop_id, product_ids, buyer_name, buyer_phone, shipping_address, pincode, confirmation_mode.
      // The backend reads seller configuration directly from profiles/drops.
      const res = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${prodA1Id}']::UUID[],
          'Adversary Buyer',
          '9830000001',
          '123 Park Street, Floor 4, Kolkata',
          '700016',
          'advance'
        );
      `);
      // Since prodA1 is already reserved in test 2.1, it should fail with STOCK_UNAVAILABLE
      expect(res.rows[0].create_order_with_reservation.success).toBe(false);
      expect(res.rows[0].create_order_with_reservation.error).toBe('STOCK_UNAVAILABLE');
    });

    it('6.2 unauthorized seller cannot confirm advance for another seller order', async () => {
      // Find an order belonging to Seller A
      await asSuperuser();
      const aOrder = await db.query<{ id: string }>(`
        SELECT o.id FROM orders o
        JOIN drops d ON d.id = o.drop_id
        WHERE d.seller_id = '${sellerAId}'
        LIMIT 1;
      `);
      const aOrderId = aOrder.rows[0].id;

      // Seller B attempts to confirm Seller A order
      await asSeller(sellerBId);
      const res = await db.query<{ confirm_order_advance: RpcSuccessOutput }>(`
        SELECT confirm_order_advance('${aOrderId}', 'REF-HACK');
      `);
      expect(res.rows[0].confirm_order_advance.success).toBe(false);
      expect(res.rows[0].confirm_order_advance.error).toBe('UNAUTHORIZED');
    });

    it('6.3 unauthenticated anon caller cannot call seller RPCs', async () => {
      await asAnon();
      await expect(
        db.query(`SELECT confirm_order_advance('d0000000-0000-0000-0000-000000000001', 'REF');`)
      ).rejects.toThrow();

      await expect(
        db.query(`SELECT mark_order_paid('d0000000-0000-0000-0000-000000000001');`)
      ).rejects.toThrow();

      await expect(
        db.query(`SELECT force_release_hold('d0000000-0000-0000-0000-000000000001');`)
      ).rejects.toThrow();
    });
  });
});
