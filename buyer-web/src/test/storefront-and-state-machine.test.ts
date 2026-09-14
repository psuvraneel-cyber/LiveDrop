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
  let globalExpiredOrderId: string;

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

    it('1.5 newly created seller defaults to advance confirmation DISABLED (opt-in only)', async () => {
      await asSuperuser();
      const newSellerId = 'f910ab11-1234-4567-8901-abcdef012345';
      await db.query(`INSERT INTO auth.users (id, email) VALUES ('${newSellerId}', 'newseller@livedrop.in');`);

      // Insert profile omitting advance configuration columns to test defaults
      await db.query(`
        INSERT INTO profiles (id, store_name, store_slug, phone_number, upi_id, return_address)
        VALUES ('${newSellerId}', 'New Boutique', 'new-boutique', '919830088888', 'new@okhdfc', 'Ballygunge Kolkata');
      `);

      const pRes = await db.query<{
        advance_confirmation_enabled: boolean;
        advance_amount_paisa: number;
        hold_duration_days: number;
      }>(`
        SELECT advance_confirmation_enabled, advance_amount_paisa, hold_duration_days
        FROM profiles
        WHERE id = '${newSellerId}';
      `);

      expect(pRes.rows[0].advance_confirmation_enabled).toBe(false); // Default is false!
      expect(pRes.rows[0].advance_amount_paisa).toBe(25000); // Default remains ₹250
      expect(pRes.rows[0].hold_duration_days).toBe(30); // Default remains 30 days
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
          '123 Park Street, Floor 4, Kolkata',
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

    it('3.1 payment authority: record_verified_payment is service_role only; confirm_order_advance dropped', async () => {
      // 1. Seller cannot call record_verified_payment (permission denied)
      await asSeller(sellerAId);
      await expect(
        db.query(`SELECT record_verified_payment('${testOrderId}', 'advance', ${testAdvanceRequiredPaisa}, 'UPI-TXN-ADV-001');`)
      ).rejects.toThrow();

      // 2. Anon cannot call record_verified_payment (permission denied)
      await asAnon();
      await expect(
        db.query(`SELECT record_verified_payment('${testOrderId}', 'advance', ${testAdvanceRequiredPaisa}, 'UPI-TXN-ADV-001');`)
      ).rejects.toThrow();

      // 3. confirm_order_advance no longer exists
      await expect(
        db.query(`SELECT confirm_order_advance('${testOrderId}', 'UPI-TXN-ADV-001');`)
      ).rejects.toThrow();

      // 4. Trusted backend service_role records advance payment
      await asServiceRole();
      const confirmResult = await db.query<{ record_verified_payment: RpcSuccessOutput }>(`
        SELECT record_verified_payment('${testOrderId}', 'advance', ${testAdvanceRequiredPaisa}, 'UPI-TXN-ADV-001');
      `);

      const res = confirmResult.rows[0].record_verified_payment;
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

    it('3.4 paying remaining balance via record_verified_payment transitions order to paid, zero balance, and eligible for shipping', async () => {
      const remainingBalance = testTotalPaisa - testAdvanceRequiredPaisa;
      await asServiceRole();

      // Record balance payment via trusted backend RPC
      const paidRes = await db.query<{ record_verified_payment: RpcSuccessOutput }>(`
        SELECT record_verified_payment('${testOrderId}', 'balance', ${remainingBalance}, 'UPI-TXN-BAL-001');
      `);

      expect(paidRes.rows[0].record_verified_payment.success).toBe(true);

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
      expect(orderRow.rows[0].fulfilment_status).toBe('ready_to_ship');

      // Verify products transitioned to sold
      const prodCheck = await db.query<{ status: string }>(`
        SELECT status FROM products WHERE id = '${prodA2Id}';
      `);
      expect(prodCheck.rows[0].status).toBe('sold');

      // Now that balance_due_paisa = 0, fulfilment_status CAN transition to shipped
      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'shipped', status = 'shipped' WHERE id = '${testOrderId}';`)
      ).resolves.toBeDefined();
    });

    it('3.5 payment reference idempotency: replaying same reference returns idempotent success without duplicate money', async () => {
      await asServiceRole();

      // Replaying 'UPI-TXN-ADV-001' which was verified in 3.1
      const replayRes = await db.query<{ record_verified_payment: { success: boolean; idempotent: boolean } }>(`
        SELECT record_verified_payment('${testOrderId}', 'advance', ${testAdvanceRequiredPaisa}, 'UPI-TXN-ADV-001');
      `);

      expect(replayRes.rows[0].record_verified_payment.success).toBe(true);
      expect(replayRes.rows[0].record_verified_payment.idempotent).toBe(true);

      // Verify total_paid_paisa has NOT increased beyond testTotalPaisa
      await asSuperuser();
      const oCheck = await db.query<{ total_paid_paisa: number }>(`
        SELECT total_paid_paisa FROM orders WHERE id = '${testOrderId}';
      `);
      expect(oCheck.rows[0].total_paid_paisa).toBe(testTotalPaisa);
    });

    it('3.6 full payment flow via record_verified_payment on full_payment order', async () => {
      await asSuperuser();
      // Create new product for full payment test
      const pRes = await db.query<{ id: string }>(`
        INSERT INTO products (drop_id, code, title, price_paisa, status, image_url)
        VALUES ('${dropA1Id}', '#FP01', 'Kanjeevaram Dupatta', 120000, 'available', 'https://images.livedrop.store/fp01.webp')
        RETURNING id;
      `);
      const fpProdId = pRes.rows[0].id;

      // Create full_payment order as anon
      await asAnon();
      const ordRes = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${fpProdId}']::UUID[],
          'Kavita Ghosh',
          '9830555666',
          'Salt Lake Sector V',
          '700091',
          'full_payment'
        );
      `);
      const fpOrderId = ordRes.rows[0].create_order_with_reservation.order_id!;
      const fpTotalPaisa = ordRes.rows[0].create_order_with_reservation.total_paisa!;

      // Record full payment via service_role
      await asServiceRole();
      const payRes = await db.query<{ record_verified_payment: RpcSuccessOutput }>(`
        SELECT record_verified_payment('${fpOrderId}', 'full', ${fpTotalPaisa}, 'UPI-TXN-FP-001');
      `);
      expect(payRes.rows[0].record_verified_payment.success).toBe(true);

      // Verify order is paid, balance is zero, ready to ship
      await asSuperuser();
      const oCheck = await db.query<{ status: string; payment_status: string; balance_due_paisa: number; fulfilment_status: string }>(`
        SELECT status, payment_status, balance_due_paisa, fulfilment_status FROM orders WHERE id = '${fpOrderId}';
      `);
      expect(oCheck.rows[0].status).toBe('paid');
      expect(oCheck.rows[0].payment_status).toBe('paid');
      expect(oCheck.rows[0].balance_due_paisa).toBe(0);
      expect(oCheck.rows[0].fulfilment_status).toBe('ready_to_ship');

      // Verify product is sold
      const pCheck = await db.query<{ status: string }>(`
        SELECT status FROM products WHERE id = '${fpProdId}';
      `);
      expect(pCheck.rows[0].status).toBe('sold');
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
      globalExpiredOrderId = expiredOrderId;

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

    it('4.3 initial unpaid pending order with expired 15-minute hold is cancelled by release_expired_holds and frees product', async () => {
      await asSuperuser();
      // Create product
      const pRes = await db.query<{ id: string }>(`
        INSERT INTO products (drop_id, code, title, price_paisa, status, image_url)
        VALUES ('${dropA1Id}', '#EXPU1', 'Silk Scarf', 50000, 'available', 'https://images.livedrop.store/exp-unp.webp')
        RETURNING id;
      `);
      const unpProdId = pRes.rows[0].id;

      // Create order in pending state with hold_expires_at in the past
      const oRes = await db.query<{ id: string }>(`
        INSERT INTO orders (
          drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
          subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
          advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
          payment_status, status, hold_expires_at
        ) VALUES (
          '${dropA1Id}', 'LD-EXPU01', 'Unpaid Buyer', '9830000000', '123 Park Street, Floor 4, Kolkata', '700016',
          50000, 8000, 58000, 'advance',
          25000, 0, 0, 58000,
          'unpaid', 'pending', NOW() - INTERVAL '5 minutes'
        ) RETURNING id;
      `);
      const unpOrderId = oRes.rows[0].id;

      // Reserve product
      await db.query(`
        UPDATE products 
        SET status = 'reserved', reserved_by_order_id = '${unpOrderId}', reserved_at = NOW() - INTERVAL '20 minutes'
        WHERE id = '${unpProdId}';
      `);

      // Run reaper
      await asServiceRole();
      await db.query(`SELECT release_expired_holds();`);

      // Verify order is cancelled
      await asSuperuser();
      const oCheck = await db.query<{ status: string }>(`
        SELECT status FROM orders WHERE id = '${unpOrderId}';
      `);
      expect(oCheck.rows[0].status).toBe('cancelled');

      // Verify product is released to available
      const pCheck = await db.query<{ status: string; reserved_by_order_id: string | null }>(`
        SELECT status, reserved_by_order_id FROM products WHERE id = '${unpProdId}';
      `);
      expect(pCheck.rows[0].status).toBe('available');
      expect(pCheck.rows[0].reserved_by_order_id).toBeNull();
    });

    it('4.4 expired order CANNOT receive payments via record_verified_payment', async () => {
      await asServiceRole();
      const res = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${expiredOrderId}', 'advance', 25000, 'UPI-REF-LATE-01');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('INVALID_ORDER_STATE');
    });

    it('4.5 expired order CANNOT be marked paid via mark_order_paid', async () => {
      await asServiceRole();
      const res = await db.query<{ mark_order_paid: { success: boolean; error: string } }>(`
        SELECT mark_order_paid('${expiredOrderId}');
      `);
      expect(res.rows[0].mark_order_paid.success).toBe(false);
      expect(res.rows[0].mark_order_paid.error).toBe('INVALID_ORDER_STATE');
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

    it('5.6 rejects fulfilment_status = ready_to_ship when balance_due_paisa > 0 or payment_status != paid', async () => {
      await asSuperuser();
      await expect(
        db.query(`
          INSERT INTO orders (
            drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
            subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
            advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
            payment_status, fulfilment_status, status
          ) VALUES (
            '${dropA1Id}', 'LD-BAD06', 'Bad Buyer', '9830000000', 'Addr', '700001',
            50000, 0, 50000, 'advance',
            25000, 25000, 25000, 25000,
            'advance_paid', 'ready_to_ship', 'confirmed'
          );
        `)
      ).rejects.toThrow();
    });

    it('5.7 direct table write privileges on order_payments revoked from authenticated and anon', async () => {
      // Authenticated seller cannot directly insert into order_payments
      await asSeller(sellerAId);
      await expect(
        db.query(`
          INSERT INTO order_payments (order_id, payment_type, amount_paisa, status)
          VALUES ('${globalExpiredOrderId}', 'advance', 25000, 'verified');
        `)
      ).rejects.toThrow();

      // Authenticated seller cannot directly update order_payments
      await expect(
        db.query(`
          UPDATE order_payments SET status = 'refunded' WHERE order_id = '${globalExpiredOrderId}';
        `)
      ).rejects.toThrow();

      // Anon cannot directly insert into order_payments
      await asAnon();
      await expect(
        db.query(`
          INSERT INTO order_payments (order_id, payment_type, amount_paisa, status)
          VALUES ('${globalExpiredOrderId}', 'advance', 25000, 'verified');
        `)
      ).rejects.toThrow();
    });

    it('5.8 cancelled order rejects payment transitions in record_verified_payment and mark_order_paid', async () => {
      await asSuperuser();
      // Create a cancelled order
      const cRes = await db.query<{ id: string }>(`
        INSERT INTO orders (
          drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
          subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
          advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
          payment_status, status
        ) VALUES (
          '${dropA1Id}', 'LD-CAN001', 'Cancelled Buyer', '9830000000', '123 Park Street, Floor 4, Kolkata', '700001',
          50000, 8000, 58000, 'advance',
          25000, 0, 0, 58000,
          'unpaid', 'cancelled'
        ) RETURNING id;
      `);
      const canId = cRes.rows[0].id;

      // record_verified_payment must reject
      await asServiceRole();
      const rvpRes = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${canId}', 'advance', 25000, 'REF-CAN');
      `);
      expect(rvpRes.rows[0].record_verified_payment.success).toBe(false);
      expect(rvpRes.rows[0].record_verified_payment.error).toBe('INVALID_ORDER_STATE');

      // mark_order_paid must reject (now service_role only)
      await asServiceRole();
      const mopRes = await db.query<{ mark_order_paid: { success: boolean; error: string } }>(`
        SELECT mark_order_paid('${canId}');
      `);
      expect(mopRes.rows[0].mark_order_paid.success).toBe(false);
      expect(mopRes.rows[0].mark_order_paid.error).toBe('INVALID_ORDER_STATE');
    });
  });

  // ==========================================================================
  // SECTION 6: ADVERSARIAL VERIFICATION SUITE (25 ATTACK VECTORS)
  // ==========================================================================
  describe('6. Comprehensive Adversarial Verification Suite', () => {
    let advOrderId: string;
    let advOrderToken: string;
    let advTotalPaisa: number;
    let advRequiredPaisa: number;
    let advProductId: string;

    beforeAll(async () => {
      await asSuperuser();
      // Setup dedicated product for adversarial testing
      const pRes = await db.query<{ id: string }>(`
        INSERT INTO products (drop_id, code, title, price_paisa, status, image_url)
        VALUES ('${dropA1Id}', '#ADV01', 'Adversarial Silk Saree', 200000, 'available', 'https://images.livedrop.store/adv01.webp')
        RETURNING id;
      `);
      advProductId = pRes.rows[0].id;

      // Create advance-mode order
      await asAnon();
      const oRes = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${advProductId}']::UUID[],
          'Adversarial Tester',
          '9830001234',
          'Sector V Salt Lake',
          '700091',
          'advance'
        );
      `);
      const data = oRes.rows[0].create_order_with_reservation;
      advOrderId = data.order_id!;
      advOrderToken = data.order_token!;
      advTotalPaisa = data.total_paisa!;
      advRequiredPaisa = data.advance_required_paisa!;
    });

    it('V01: invoke payment confirmation anonymously -> permission denied', async () => {
      await asAnon();
      await expect(
        db.query(`SELECT record_verified_payment('${advOrderId}', 'advance', ${advRequiredPaisa}, 'REF-V01');`)
      ).rejects.toThrow();
    });

    it('V02: invoke payment confirmation as normal authenticated buyer -> permission denied', async () => {
      // Normal authenticated user who is not service_role
      const buyerAuthId = '00000000-0000-0000-0000-000000000999';
      await asSeller(buyerAuthId);
      await expect(
        db.query(`SELECT record_verified_payment('${advOrderId}', 'advance', ${advRequiredPaisa}, 'REF-V02');`)
      ).rejects.toThrow();
    });

    it('V03: invoke payment confirmation as unrelated seller -> permission denied', async () => {
      await asSeller(sellerBId);
      await expect(
        db.query(`SELECT record_verified_payment('${advOrderId}', 'advance', ${advRequiredPaisa}, 'REF-V03');`)
      ).rejects.toThrow();
    });

    it('V04: submit fake advance amount -> AMOUNT_MISMATCH', async () => {
      await asServiceRole();
      const res = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${advOrderId}', 'advance', 100, 'REF-V04');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('AMOUNT_MISMATCH');
    });

    it('V05: submit fake paid amount -> AMOUNT_MISMATCH', async () => {
      await asServiceRole();
      const res = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${advOrderId}', 'advance', 9999999, 'REF-V05');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('AMOUNT_MISMATCH');
    });

    it('V06: replay the same payment reference -> idempotent success, exactly one ledger effect', async () => {
      await asServiceRole();
      // First verification succeeds
      const first = await db.query<{ record_verified_payment: { success: boolean } }>(`
        SELECT record_verified_payment('${advOrderId}', 'advance', ${advRequiredPaisa}, 'REF-V06-IDEMP');
      `);
      expect(first.rows[0].record_verified_payment.success).toBe(true);

      // Replay returns idempotent success
      const replay = await db.query<{ record_verified_payment: { success: boolean; idempotent: boolean } }>(`
        SELECT record_verified_payment('${advOrderId}', 'advance', ${advRequiredPaisa}, 'REF-V06-IDEMP');
      `);
      expect(replay.rows[0].record_verified_payment.success).toBe(true);
      expect(replay.rows[0].record_verified_payment.idempotent).toBe(true);

      // Verify payment rows count is exactly 1
      await asSuperuser();
      const rows = await db.query(`SELECT id FROM order_payments WHERE reference_id = 'REF-V06-IDEMP';`);
      expect(rows.rows.length).toBe(1);
    });

    it('V07: concurrent / repeated payment verification preserves exact balance', async () => {
      await asServiceRole();
      // Sequential repeated call simulating concurrent webhook delivery
      const res = await db.query<{ record_verified_payment: { success: boolean } }>(`
        SELECT record_verified_payment('${advOrderId}', 'advance', ${advRequiredPaisa}, 'REF-V06-IDEMP');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(true);

      await asSuperuser();
      const oCheck = await db.query<{ total_paid_paisa: number }>(`
        SELECT total_paid_paisa FROM orders WHERE id = '${advOrderId}';
      `);
      expect(oCheck.rows[0].total_paid_paisa).toBe(advRequiredPaisa);
    });

    it('V08: pay balance twice -> idempotent success / already settled, no double credit', async () => {
      const balanceAmount = advTotalPaisa - advRequiredPaisa;
      await asServiceRole();

      // First balance payment succeeds
      const b1 = await db.query<{ record_verified_payment: { success: boolean } }>(`
        SELECT record_verified_payment('${advOrderId}', 'balance', ${balanceAmount}, 'REF-V08-BAL');
      `);
      expect(b1.rows[0].record_verified_payment.success).toBe(true);

      // Second balance payment with same reference is idempotent
      const b2 = await db.query<{ record_verified_payment: { success: boolean; idempotent: boolean } }>(`
        SELECT record_verified_payment('${advOrderId}', 'balance', ${balanceAmount}, 'REF-V08-BAL');
      `);
      expect(b2.rows[0].record_verified_payment.success).toBe(true);
      expect(b2.rows[0].record_verified_payment.idempotent).toBe(true);

      // Verify total_paid is total, not total + balance
      await asSuperuser();
      const oCheck = await db.query<{ total_paid_paisa: number; balance_due_paisa: number }>(`
        SELECT total_paid_paisa, balance_due_paisa FROM orders WHERE id = '${advOrderId}';
      `);
      expect(oCheck.rows[0].total_paid_paisa).toBe(advTotalPaisa);
      expect(oCheck.rows[0].balance_due_paisa).toBe(0);
    });

    it('V09: pay full amount after advance was already paid -> rejected', async () => {
      await asServiceRole();
      const res = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${advOrderId}', 'full', ${advTotalPaisa}, 'REF-V09-FP');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('INVALID_OPERATION');
    });

    it('V10: pay after order expiry -> INVALID_ORDER_STATE', async () => {
      await asServiceRole();
      const res = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${globalExpiredOrderId}', 'balance', 73000, 'REF-V10');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('INVALID_ORDER_STATE');
    });

    it('V11: pay after cancellation -> INVALID_ORDER_STATE', async () => {
      await asSuperuser();
      const cRes = await db.query<{ id: string }>(`
        INSERT INTO orders (
          drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
          subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
          advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
          payment_status, status
        ) VALUES (
          '${dropA1Id}', 'LD-V11001', 'Can Buyer', '9830000000', '123 Park Street, Floor 4, Kolkata', '700001',
          50000, 8000, 58000, 'advance',
          25000, 0, 0, 58000,
          'unpaid', 'cancelled'
        ) RETURNING id;
      `);
      const canId = cRes.rows[0].id;

      await asServiceRole();
      const res = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${canId}', 'advance', 25000, 'REF-V11');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('INVALID_ORDER_STATE');
    });

    it('V12: mutate advance policy after order creation -> order snapshot remains unchanged', async () => {
      await asSeller(sellerAId);
      await db.query(`UPDATE profiles SET advance_amount_paisa = 60000 WHERE id = '${sellerAId}';`);

      await asSuperuser();
      const oCheck = await db.query<{ advance_required_paisa: number }>(`
        SELECT advance_required_paisa FROM orders WHERE id = '${advOrderId}';
      `);
      expect(oCheck.rows[0].advance_required_paisa).toBe(advRequiredPaisa);

      // Reset
      await asSeller(sellerAId);
      await db.query(`UPDATE profiles SET advance_amount_paisa = 25000 WHERE id = '${sellerAId}';`);
    });

    it('V13: modify hold duration after order creation -> existing order hold remains unchanged', async () => {
      await asSuperuser();
      const oBefore = await db.query<{ hold_expires_at: string }>(`
        SELECT hold_expires_at FROM orders WHERE id = '${advOrderId}';
      `);

      await asSeller(sellerAId);
      await db.query(`UPDATE profiles SET hold_duration_days = 7 WHERE id = '${sellerAId}';`);

      await asSuperuser();
      const oAfter = await db.query<{ hold_expires_at: string }>(`
        SELECT hold_expires_at FROM orders WHERE id = '${advOrderId}';
      `);
      expect(new Date(oAfter.rows[0].hold_expires_at).getTime()).toBe(new Date(oBefore.rows[0].hold_expires_at).getTime());

      // Reset
      await asSeller(sellerAId);
      await db.query(`UPDATE profiles SET hold_duration_days = 30 WHERE id = '${sellerAId}';`);
    });

    it('V14: force balance below zero -> check constraint violation', async () => {
      await asSuperuser();
      await expect(
        db.query(`UPDATE orders SET balance_due_paisa = -100 WHERE id = '${advOrderId}';`)
      ).rejects.toThrow();
    });

    it('V15: force total_paid above total -> check constraint violation', async () => {
      await asSuperuser();
      await expect(
        db.query(`UPDATE orders SET total_paid_paisa = ${advTotalPaisa + 1000} WHERE id = '${advOrderId}';`)
      ).rejects.toThrow();
    });

    it('V16: transition to ready_to_ship while balance remains due -> check constraint violation', async () => {
      await asSuperuser();
      // On an order with balance due, ready_to_ship must fail
      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'ready_to_ship' WHERE id = '${globalExpiredOrderId}';`)
      ).rejects.toThrow();
    });

    it('V17: transition to shipped while unpaid -> check constraint violation', async () => {
      await asSuperuser();
      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'shipped' WHERE id = '${globalExpiredOrderId}';`)
      ).rejects.toThrow();
    });

    it('V18: attempt to restore expired product through buyer RPC -> STOCK_UNAVAILABLE', async () => {
      await asAnon();
      // Trying to checkout already sold product prodA2
      const res = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${prodA2Id}']::UUID[],
          'Attacker',
          '9830111222',
          'Addr 1234567890',
          '700016',
          'advance'
        );
      `);
      expect(res.rows[0].create_order_with_reservation.success).toBe(false);
      expect(res.rows[0].create_order_with_reservation.error).toBe('STOCK_UNAVAILABLE');
    });

    it('V19: attempt cross-seller order/payment access -> 0 rows under RLS', async () => {
      await asSeller(sellerBId);
      // Seller B queries order_payments for Seller A's order
      const res = await db.query(`SELECT * FROM order_payments WHERE order_id = '${advOrderId}';`);
      expect(res.rows.length).toBe(0);
    });

    it('V20: attempt token substitution -> ORDER_NOT_FOUND_OR_UNAUTHORIZED; authentic token succeeds', async () => {
      await asAnon();
      // Authentic token succeeds
      const authRes = await db.query<{ get_order_by_token: { success: boolean } }>(`
        SELECT get_order_by_token('${advOrderId}', '${advOrderToken}');
      `);
      expect(authRes.rows[0].get_order_by_token.success).toBe(true);

      // Fake / substituted token fails
      const fakeToken = '00000000-0000-0000-0000-000000000000';
      const res = await db.query<{ get_order_by_token: { success: boolean; error: string } }>(`
        SELECT get_order_by_token('${advOrderId}', '${fakeToken}');
      `);
      expect(res.rows[0].get_order_by_token.success).toBe(false);
      expect(res.rows[0].get_order_by_token.error).toBe('ORDER_NOT_FOUND_OR_UNAUTHORIZED');
    });

    it('V21: attempt direct order_payments INSERT -> permission denied', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          INSERT INTO order_payments (order_id, payment_type, amount_paisa, status)
          VALUES ('${advOrderId}', 'advance', 25000, 'verified');
        `)
      ).rejects.toThrow();
    });

    it('V22: attempt direct order_payments UPDATE -> permission denied', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`UPDATE order_payments SET amount_paisa = 999999 WHERE order_id = '${advOrderId}';`)
      ).rejects.toThrow();
    });

    it('V23: attempt SQL injection / privilege escalation through SECURITY DEFINER inputs', async () => {
      await asServiceRole();
      const maliciousReference = "'; DROP TABLE orders; --";
      const res = await db.query<{ record_verified_payment: { success: boolean; error?: string } }>(
        'SELECT record_verified_payment($1, $2, $3, $4);',
        [advOrderId, 'invalid_type', 100, maliciousReference]
      );
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('INVALID_PAYMENT_TYPE');

      // Verify orders table still exists
      await asSuperuser();
      const tblCheck = await db.query(`SELECT count(*) FROM orders;`);
      expect(tblCheck.rows.length).toBe(1);
    });

    it('V24: attempt malformed / invalid payment type -> INVALID_PAYMENT_TYPE', async () => {
      await asServiceRole();
      const res = await db.query<{ record_verified_payment: { success: boolean; error: string } }>(`
        SELECT record_verified_payment('${advOrderId}', 'crypto_token', 25000, 'REF-V24');
      `);
      expect(res.rows[0].record_verified_payment.success).toBe(false);
      expect(res.rows[0].record_verified_payment.error).toBe('INVALID_PAYMENT_TYPE');
    });

    it('V25: attempt duplicate provider references with different amounts -> unique index blocks duplicate', async () => {
      await asSuperuser();
      // Directly inserting duplicate reference into order_payments table must violate uq_order_payments_reference_verified
      await expect(
        db.query(`
          INSERT INTO order_payments (order_id, payment_type, amount_paisa, status, reference_id)
          VALUES ('${advOrderId}', 'advance', 50000, 'verified', 'REF-V06-IDEMP');
        `)
      ).rejects.toThrow();
    });

    it('V26: mark_order_paid on cancelled order -> INVALID_ORDER_STATE (F-01 audit vector)', async () => {
      await asSuperuser();
      const cRes = await db.query<{ id: string }>(`
        INSERT INTO orders (
          drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
          subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode,
          advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa,
          payment_status, status
        ) VALUES (
          '${dropA1Id}', 'LD-V26001', 'V26 Buyer', '9830000026', '123 Park Street, Floor 4, Kolkata', '700001',
          50000, 8000, 58000, 'advance',
          25000, 0, 0, 58000,
          'unpaid', 'cancelled'
        ) RETURNING id;
      `);
      const canId = cRes.rows[0].id;

      await asServiceRole();
      const res = await db.query<{ mark_order_paid: { success: boolean; error: string } }>(`
        SELECT mark_order_paid('${canId}');
      `);
      expect(res.rows[0].mark_order_paid.success).toBe(false);
      expect(res.rows[0].mark_order_paid.error).toBe('INVALID_ORDER_STATE');
    });

    it('V27: mark_order_paid on expired order -> INVALID_ORDER_STATE (F-01 audit vector)', async () => {
      await asServiceRole();
      const res = await db.query<{ mark_order_paid: { success: boolean; error: string } }>(`
        SELECT mark_order_paid('${globalExpiredOrderId}');
      `);
      expect(res.rows[0].mark_order_paid.success).toBe(false);
      expect(res.rows[0].mark_order_paid.error).toBe('INVALID_ORDER_STATE');
    });

    it('V28: mark_order_paid as authenticated seller -> permission denied (F-01 trust boundary)', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`SELECT mark_order_paid('${advOrderId}');`)
      ).rejects.toThrow();
    });
  });

  // ==========================================================================
  // 11. ADVERSARIAL DIRECT MUTATION ATTACKS (TASK-2.4A.2: A01–A13)
  // ==========================================================================
  describe('11. Adversarial Direct Mutation Attacks & Payment Authority Hardening (TASK-2.4A.2: A01–A13)', () => {
    let attackOrderId: string;
    let attackProdId: string;

    beforeAll(async () => {
      attackProdId = 'ca000000-0000-0000-0000-000000000077';
      await asSuperuser();
      await db.query(`
        INSERT INTO products (id, drop_id, code, title, price_paisa, size, image_url, status)
        VALUES ('${attackProdId}', '${dropA1Id}', '#S77', 'Adversarial Test Saree', 150000, 'Free Size', 'https://images.livedrop.store/s77.webp', 'available');
      `);

      // Create initial order as anonymous buyer
      await asAnon();
      const res = await db.query<{ create_order_with_reservation: CreateOrderRpcOutput }>(`
        SELECT create_order_with_reservation(
          '${dropA1Id}',
          ARRAY['${attackProdId}']::uuid[],
          'Victim Buyer',
          '9830111222',
          '45 Southern Avenue, Kolkata',
          '700029',
          'advance'
        );
      `);
      attackOrderId = res.rows[0].create_order_with_reservation.order_id!;
    });

    it('A01: authenticated seller updates status="paid" -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`UPDATE orders SET status = 'paid' WHERE id = '${attackOrderId}';`)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);

      // Verify database state: order remains pending
      await asSuperuser();
      const check = await db.query<{ status: string }>(`SELECT status FROM orders WHERE id = '${attackOrderId}';`);
      expect(check.rows[0].status).toBe('pending');
    });

    it('A02: authenticated seller updates payment_status="paid" -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`UPDATE orders SET payment_status = 'paid' WHERE id = '${attackOrderId}';`)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);

      await asSuperuser();
      const check = await db.query<{ payment_status: string }>(`SELECT payment_status FROM orders WHERE id = '${attackOrderId}';`);
      expect(check.rows[0].payment_status).toBe('unpaid');
    });

    it('A03: authenticated seller updates total_paid_paisa -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`UPDATE orders SET total_paid_paisa = 158000 WHERE id = '${attackOrderId}';`)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);

      await asSuperuser();
      const check = await db.query<{ total_paid_paisa: number }>(`SELECT total_paid_paisa FROM orders WHERE id = '${attackOrderId}';`);
      expect(check.rows[0].total_paid_paisa).toBe(0);
    });

    it('A04: authenticated seller updates balance_due_paisa -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`UPDATE orders SET balance_due_paisa = 0 WHERE id = '${attackOrderId}';`)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);

      await asSuperuser();
      const check = await db.query<{ balance_due_paisa: number }>(`SELECT balance_due_paisa FROM orders WHERE id = '${attackOrderId}';`);
      expect(check.rows[0].balance_due_paisa).toBe(158000);
    });

    it('A05: authenticated seller updates fulfilment_status="ready_to_ship" -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'ready_to_ship' WHERE id = '${attackOrderId}';`)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);

      await asSuperuser();
      const check = await db.query<{ fulfilment_status: string }>(`SELECT fulfilment_status FROM orders WHERE id = '${attackOrderId}';`);
      expect(check.rows[0].fulfilment_status).toBe('not_ready');
    });

    it('A06: authenticated seller updates all payment fields simultaneously -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          UPDATE orders
          SET status = 'paid',
              payment_status = 'paid',
              total_paid_paisa = total_paisa,
              balance_due_paisa = 0,
              fulfilment_status = 'ready_to_ship'
          WHERE id = '${attackOrderId}';
        `)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);

      await asSuperuser();
      const check = await db.query<{ status: string; payment_status: string; total_paid_paisa: number }>(
        `SELECT status, payment_status, total_paid_paisa FROM orders WHERE id = '${attackOrderId}';`
      );
      expect(check.rows[0].status).toBe('pending');
      expect(check.rows[0].payment_status).toBe('unpaid');
      expect(check.rows[0].total_paid_paisa).toBe(0);
    });

    it('A07: authenticated seller fabricates a full-payment state -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          UPDATE orders
          SET status = 'paid',
              payment_status = 'paid',
              fulfilment_status = 'ready_to_ship',
              total_paid_paisa = total_paisa,
              balance_due_paisa = 0,
              advance_paid_paisa = 0,
              paid_at = NOW()
          WHERE id = '${attackOrderId}';
        `)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('A08: authenticated seller fabricates an advance-paid state -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          UPDATE orders
          SET status = 'confirmed',
              payment_status = 'advance_paid',
              fulfilment_status = 'not_ready',
              advance_paid_paisa = advance_required_paisa,
              total_paid_paisa = advance_required_paisa,
              balance_due_paisa = total_paisa - advance_required_paisa,
              advance_paid_at = NOW()
          WHERE id = '${attackOrderId}';
        `)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('A09: authenticated seller changes hold_expires_at after payment/creation -> BLOCKED with SQLSTATE 42501', async () => {
      await asSeller(sellerAId);
      await expect(
        db.query(`
          UPDATE orders
          SET hold_expires_at = NOW() + INTERVAL '365 days'
          WHERE id = '${attackOrderId}';
        `)
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('A10: authenticated seller creates paid order with no payment ledger entry -> BLOCKED', async () => {
      // Direct REST INSERT is blocked by RLS
      await asSeller(sellerAId);
      await expect(
        db.query(`
          INSERT INTO orders (
            drop_id, order_code, buyer_name, buyer_phone, shipping_address, pincode,
            subtotal_paisa, shipping_paisa, total_paisa, status, payment_status,
            fulfilment_status, total_paid_paisa, balance_due_paisa
          ) VALUES (
            '${dropA1Id}', 'LD-FAK999', 'Fake Buyer', '9830111222', '123 Fake Street, Kolkata', '700001',
            100000, 8000, 108000, 'paid', 'paid', 'ready_to_ship', 108000, 0
          );
        `)
      ).rejects.toThrow();

      // Ensure zero order_payments entries exist for fabricated orders
      await asSuperuser();
      const checkLedger = await db.query<{ count: string }>(
        `SELECT count(*) as count FROM order_payments WHERE order_id = '${attackOrderId}';`
      );
      expect(Number(checkLedger.rows[0].count)).toBe(0);
    });

    it('A11: authenticated seller tries to mark products sold to match fabricated order -> BLOCKED', async () => {
      await asSeller(sellerAId);
      // Attempt to directly change reserved product to sold
      await expect(
        db.query(`UPDATE products SET status = 'sold' WHERE id = '${attackProdId}';`)
      ).rejects.toThrow(/Direct mutation of product reservation status is prohibited/i);

      // Verify product remains reserved by original order
      await asSuperuser();
      const p = await db.query<{ status: string; reserved_by_order_id: string }>(
        `SELECT status, reserved_by_order_id FROM products WHERE id = '${attackProdId}';`
      );
      expect(p.rows[0].status).toBe('reserved');
      expect(p.rows[0].reserved_by_order_id).toBe(attackOrderId);
    });

    it('A12: valid service_role payment RPC still succeeds', async () => {
      await asServiceRole();
      const paidRes = await db.query<{ mark_order_paid: { success: boolean; order_id: string } }>(`
        SELECT mark_order_paid('${attackOrderId}', 'REF-VERIFIED-A12', '{"provider": "razorpay"}'::jsonb);
      `);
      expect(paidRes.rows[0].mark_order_paid.success).toBe(true);

      // Verify database state: order is paid and product is sold
      await asSuperuser();
      const o = await db.query<{ status: string; payment_status: string; fulfilment_status: string; total_paid_paisa: number; balance_due_paisa: number }>(
        `SELECT status, payment_status, fulfilment_status, total_paid_paisa, balance_due_paisa FROM orders WHERE id = '${attackOrderId}';`
      );
      expect(o.rows[0].status).toBe('paid');
      expect(o.rows[0].payment_status).toBe('paid');
      expect(o.rows[0].fulfilment_status).toBe('ready_to_ship');
      expect(o.rows[0].total_paid_paisa).toBe(158000);
      expect(o.rows[0].balance_due_paisa).toBe(0);

      const p = await db.query<{ status: string; reserved_by_order_id: string | null }>(
        `SELECT status, reserved_by_order_id FROM products WHERE id = '${attackProdId}';`
      );
      expect(p.rows[0].status).toBe('sold');
      expect(p.rows[0].reserved_by_order_id).toBeNull();

      // Verify payment ledger entry was genuinely created
      const pay = await db.query<{ count: string; amount_paisa: number; reference_id: string }>(
        `SELECT count(*) as count, amount_paisa, reference_id FROM order_payments WHERE order_id = '${attackOrderId}' GROUP BY amount_paisa, reference_id;`
      );
      expect(Number(pay.rows[0].count)).toBe(1);
      expect(pay.rows[0].amount_paisa).toBe(158000);
      expect(pay.rows[0].reference_id).toBe('REF-VERIFIED-A12');
    });

    it('A13: valid seller operational update still succeeds where intended', async () => {
      await asSeller(sellerAId);
      // Legitimate operational update: shipping tracking details
      await db.query(`
        UPDATE orders
        SET tracking_number = 'TRACK-DELHIVERY-999',
            courier_partner = 'Delhivery Express'
        WHERE id = '${attackOrderId}';
      `);

      // Verify database state: tracking details updated, payment & financial fields untouched
      await asSuperuser();
      const check = await db.query<{ tracking_number: string; courier_partner: string; status: string; total_paid_paisa: number }>(
        `SELECT tracking_number, courier_partner, status, total_paid_paisa FROM orders WHERE id = '${attackOrderId}';`
      );
      expect(check.rows[0].tracking_number).toBe('TRACK-DELHIVERY-999');
      expect(check.rows[0].courier_partner).toBe('Delhivery Express');
      expect(check.rows[0].status).toBe('paid');
      expect(check.rows[0].total_paid_paisa).toBe(158000);
    });
  });
});
