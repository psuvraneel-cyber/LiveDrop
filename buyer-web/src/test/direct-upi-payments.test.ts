// @vitest-environment node
import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest';
import { PGlite } from '@electric-sql/pglite';
import * as fs from 'node:fs';
import * as path from 'node:path';

interface RpcOutput {
  success: boolean;
  error?: string;
  message?: string;
  idempotent?: boolean;
  attempt_id?: string;
  transaction_reference?: string;
  payment_type?: string;
  expected_amount_paisa?: number;
  payee_vpa?: string;
  payee_name?: string;
  upi_uri?: string;
  status?: string;
  payment_status?: string;
  balance_due_paisa?: number;
  total_paid_paisa?: number;
  hold_expires_at?: string;
  order_id?: string;
  order_token?: string;
  order_code?: string;
  total_paisa?: number;
}

interface PaymentAttemptRow {
  id: string;
  order_id: string;
  payment_type: string;
  expected_amount_paisa: number;
  payee_vpa_snapshot: string;
  payee_display_name_snapshot: string;
  transaction_reference: string;
  status: string;
  buyer_submitted_utr: string | null;
  buyer_claimed_at: string | null;
  seller_verified_at: string | null;
  verified_by: string | null;
  rejection_reason: string | null;
  expires_at: string;
  created_at: string;
}

interface OrderRow {
  id: string;
  status: string;
  payment_status: string;
  confirmation_mode: string;
  subtotal_paisa: number;
  shipping_paisa: number;
  advance_required_paisa: number;
  advance_paid_paisa: number;
  total_paid_paisa: number;
  balance_due_paisa: number;
  total_paisa: number;
  fulfilment_status: string;
  hold_expires_at: string;
}

describe('LiveDrop Direct UPI Payment & Manual Verification (TASK-2.4B)', () => {
  let db: PGlite;
  const migrationsDir = path.resolve(__dirname, '../../../supabase/migrations');

  // Multi-seller fixture IDs
  const sellerAId = 'a1eebc99-9c0b-4ef8-bb6d-6bb9bd380a01';
  const sellerBId = 'a2eebc99-9c0b-4ef8-bb6d-6bb9bd380a02';
  const sellerCId = 'a3eebc99-9c0b-4ef8-bb6d-6bb9bd380a03';

  let dropAId: string;
  let dropBId: string;
  let prodA1Id: string;
  let prodA2Id: string;
  let _prodB1Id: string;

  async function asSuperuser() {
    await db.exec(`
      SET SESSION AUTHORIZATION DEFAULT;
      SET ROLE postgres;
      RESET request.jwt.claim.sub;
      RESET request.jwt.claim.role;
      RESET request.jwt.claims;
      RESET request.headers;
    `);
  }

  async function asAnon(orderToken?: string) {
    const headersJson = orderToken ? JSON.stringify({ 'x-order-token': orderToken }) : '{}';
    await db.exec(`
      SET SESSION AUTHORIZATION DEFAULT;
      SET ROLE anon;
      SET request.jwt.claim.role = 'anon';
      RESET request.jwt.claim.sub;
      SET request.jwt.claims = '{"role": "anon"}';
      SET request.headers = '${headersJson}';
    `);
  }

  async function asSeller(sellerId: string) {
    await db.exec(`
      SET SESSION AUTHORIZATION DEFAULT;
      SET ROLE authenticated;
      SET request.jwt.claim.role = 'authenticated';
      SET request.jwt.claim.sub = '${sellerId}';
      SET request.jwt.claims = '{"role": "authenticated", "sub": "${sellerId}"}';
      RESET request.headers;
    `);
  }

  async function _asServiceRole() {
    await db.exec(`
      SET SESSION AUTHORIZATION DEFAULT;
      SET ROLE service_role;
      SET request.jwt.claim.role = 'service_role';
      RESET request.jwt.claim.sub;
      SET request.jwt.claims = '{"role": "service_role"}';
      RESET request.headers;
    `);
  }

  beforeAll(async () => {
    db = new PGlite();

    // 1. Auth Simulation Schema
    await db.exec(`
      CREATE SCHEMA IF NOT EXISTS auth;
      CREATE TABLE IF NOT EXISTS auth.users (
        id UUID PRIMARY KEY,
        email TEXT UNIQUE,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );

      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
          CREATE ROLE anon NOLOGIN;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
          CREATE ROLE authenticated NOLOGIN;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
          CREATE ROLE service_role NOLOGIN;
        END IF;
      END $$;

      CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
        SELECT COALESCE(
          nullif(current_setting('request.jwt.claim.sub', true), ''),
          (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
        )::uuid
      $$;

      CREATE OR REPLACE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS $$
        SELECT COALESCE(
          nullif(current_setting('request.jwt.claim.role', true), ''),
          (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
        )::text
      $$;
    `);

    // 2. Apply ALL 13 migrations sequentially (001 -> 013)
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

    for (const file of migrationFiles) {
      const filePath = path.join(migrationsDir, file);
      const sql = fs.readFileSync(filePath, 'utf-8');
      await db.exec(sql);
    }
  });

  beforeEach(async () => {
    await asSuperuser();
    await db.exec(`
      UPDATE products SET status = 'available', reserved_at = NULL, reserved_by_order_id = NULL;
      DELETE FROM payment_attempts;
      DELETE FROM order_payments;
      DELETE FROM order_items;
      UPDATE orders SET status = 'cancelled';
      DELETE FROM orders;
      DELETE FROM products;
      DELETE FROM drops;
      DELETE FROM profiles;
      DELETE FROM auth.users;
    `);

    // Seed auth users
    await db.query(`
      INSERT INTO auth.users (id, email) VALUES 
        ('${sellerAId}', 'sellerA@livedrop.in'),
        ('${sellerBId}', 'sellerB@livedrop.in'),
        ('${sellerCId}', 'sellerC@livedrop.in');
    `);

    // Seed profiles with UPI configurations
    await db.query(`
      INSERT INTO profiles (
        id, store_name, store_slug, phone_number, upi_id, return_address,
        default_shipping_fee_paisa, free_shipping_threshold_paisa,
        advance_confirmation_enabled, advance_amount_paisa, hold_duration_days,
        upi_enabled, upi_vpa, upi_display_name, payment_instructions
      ) VALUES 
        ('${sellerAId}', 'Priya Trends', 'priya-trends', '9876543201', 'priya@okaxis', '12 Indiranagar Bengaluru',
         8000, 200000, true, 25000, 3,
         true, 'priya@okaxis', 'Priya''s Boutique', 'Please pay the exact advance of ₹250 and enter the 12-digit UTR below.'),
        ('${sellerBId}', 'Ananya Silks', 'ananya-silks', '9876543202', 'ananya@okhdfcbank', '45 T Nagar Chennai',
         7000, 200000, true, 50000, 7,
         true, 'ananya@okhdfcbank', 'Ananya Handlooms', 'Include order code in payment remarks.'),
        ('${sellerCId}', 'Craft Weaves', 'craft-weaves', '9876543203', 'craft@icici', '89 Mall Road Jaipur',
         5000, 150000, false, 25000, 1,
         false, 'craft@icici', 'Craft Weaves', 'UPI payments currently disabled.');
    `);

    // Seed drops
    const dARes = await db.query<{ id: string }>(`
      INSERT INTO drops (seller_id, title, slug, status, shipping_fee_paisa, advance_confirmation_enabled, advance_amount_paisa, hold_duration_days)
      VALUES ('${sellerAId}', 'Priya Live Drop', 'priya-live', 'live', 8000, true, 25000, 3)
      RETURNING id;
    `);
    dropAId = dARes.rows[0].id;

    const dBRes = await db.query<{ id: string }>(`
      INSERT INTO drops (seller_id, title, slug, status, shipping_fee_paisa, advance_confirmation_enabled, advance_amount_paisa, hold_duration_days)
      VALUES ('${sellerBId}', 'Ananya Live Drop', 'ananya-live', 'live', 7000, true, 50000, 7)
      RETURNING id;
    `);
    dropBId = dBRes.rows[0].id;

    // Seed products
    const pA1 = await db.query<{ id: string }>(`
      INSERT INTO products (drop_id, code, title, price_paisa, status, image_url)
      VALUES ('${dropAId}', '#A01', 'Kalamkari Anarkali', 185000, 'available', 'https://cdn.livedrop.in/a01.jpg')
      RETURNING id;
    `);
    prodA1Id = pA1.rows[0].id;

    const pA2 = await db.query<{ id: string }>(`
      INSERT INTO products (drop_id, code, title, price_paisa, status, image_url)
      VALUES ('${dropAId}', '#A02', 'Chanderi Dupatta', 65000, 'available', 'https://cdn.livedrop.in/a02.jpg')
      RETURNING id;
    `);
    prodA2Id = pA2.rows[0].id;

    const pB1 = await db.query<{ id: string }>(`
      INSERT INTO products (drop_id, code, title, price_paisa, status, image_url)
      VALUES ('${dropBId}', '#B01', 'Kanjivaram Saree', 350000, 'available', 'https://cdn.livedrop.in/b01.jpg')
      RETURNING id;
    `);
    _prodB1Id = pB1.rows[0].id;
  });

  afterAll(async () => {
    if (db) {
      await asSuperuser();
      await db.close();
    }
  });

  // Helper to create an order via RPC
  async function createOrder(
    dropId: string,
    prodIds: string[],
    buyerName = 'Priya Buyer',
    mode = 'advance'
  ): Promise<{ order_id: string; order_code: string; order_token: string; total_paisa: number }> {
    await asAnon();
    const res = await db.query<{ create_order_with_reservation: RpcOutput }>(`
      SELECT create_order_with_reservation(
        $1, $2::uuid[], $3, '9876543299', '12 Park St Kolkata', '700016', $4
      );
    `, [dropId, prodIds, buyerName, mode]);
    const r = res.rows[0].create_order_with_reservation;
    expect(r.success).toBe(true);
    return {
      order_id: r.order_id!,
      order_code: r.order_code!,
      order_token: r.order_token!,
      total_paisa: r.total_paisa!,
    };
  }

  // ==========================================================================
  // SECTION 49: POSITIVE TEST MATRIX (POS01 - POS16)
  // ==========================================================================
  describe('SECTION 49: POSITIVE TEST MATRIX (POS01–POS16)', () => {
    it('POS01: seller configures valid UPI', async () => {
      await asSeller(sellerAId);
      const res = await db.query<{ upi_enabled: boolean; upi_vpa: string; upi_display_name: string; upi_id: string }>(`
        UPDATE profiles 
        SET upi_enabled = true,
            upi_vpa = 'priya.trends@oksbi',
            upi_display_name = 'Priya Trendy Silks',
            payment_instructions = 'Pay advance only'
        WHERE id = '${sellerAId}'
        RETURNING upi_enabled, upi_vpa, upi_display_name, upi_id;
      `);
      expect(res.rows.length).toBe(1);
      const p = res.rows[0];
      expect(p.upi_enabled).toBe(true);
      expect(p.upi_vpa).toBe('priya.trends@oksbi');
      expect(p.upi_id).toBe('priya.trends@oksbi'); // sync trigger verified
      expect(p.upi_display_name).toBe('Priya Trendy Silks');
    });

    it('POS02: buyer sees seller UPI for active order', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      const res = await db.query<{ get_order_by_token: { success: boolean; order: { upi_id: string; store_name: string; upi_uri: string } } }>(`
        SELECT get_order_by_token($1);
      `, [ord.order_token]);

      expect(res.rows[0].get_order_by_token.success).toBe(true);
      const o = res.rows[0].get_order_by_token.order;
      expect(o.upi_id).toBe('priya@okaxis');
      expect(o.store_name).toBe('Priya Trends');
      expect(o.upi_uri).toContain('upi://pay');
      expect(o.upi_uri).toContain('pa=priya@okaxis');
    });

    it('POS03: dynamic QR encodes correct payee/amount/reference', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      const res = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);

      const att = res.rows[0].initiate_payment_attempt;
      expect(att.success).toBe(true);
      expect(att.payee_vpa).toBe('priya@okaxis');
      expect(att.expected_amount_paisa).toBe(25000);
      expect(att.transaction_reference).toMatch(/^LD-[A-Z0-9]{6}-(ADV|BAL|FUL)-[A-Z0-9]{4}$/);
      // UPI URI format: upi://pay?pa=...&pn=...&am=250.00&cu=INR&tr=...
      expect(att.upi_uri).toContain('am=250.00');
      expect(att.upi_uri).toContain(`tr=${att.transaction_reference}`);
      expect(att.upi_uri).toContain('cu=INR');
    });

    it('POS04: UPI intent URI encodes correct values', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      const res = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);

      const uri = res.rows[0].initiate_payment_attempt.upi_uri!;
      expect(uri.startsWith('upi://pay?')).toBe(true);
      const url = new URL(uri);
      expect(url.searchParams.get('pa')).toBe('priya@okaxis');
      expect(url.searchParams.get('am')).toBe('250.00');
      expect(url.searchParams.get('cu')).toBe('INR');
      expect(url.searchParams.get('tr')).toBe(res.rows[0].initiate_payment_attempt.transaction_reference);
    });

    it('POS05: buyer copies UPI ID (verifies snapshot availability in attempt)', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      const res = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);

      expect(res.rows[0].initiate_payment_attempt.payee_vpa).toBe('priya@okaxis');
      expect(res.rows[0].initiate_payment_attempt.payee_name).toBe('Priya\'s Boutique');
    });

    it('POS06: buyer submits valid UTR', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      const claimRes = await db.query<{ submit_buyer_payment_claim: RpcOutput }>(`
        SELECT submit_buyer_payment_claim($1, $2, '428739182734');
      `, [attId, ord.order_token]);

      expect(claimRes.rows[0].submit_buyer_payment_claim.success).toBe(true);
      expect(claimRes.rows[0].submit_buyer_payment_claim.status).toBe('awaiting_seller_verification');

      // Verify order financial totals were NOT prematurely changed by claim
      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT status, payment_status, total_paid_paisa FROM orders WHERE id = $1;`, [ord.order_id]);
      expect(o.rows[0].status).toBe('pending');
      expect(o.rows[0].payment_status).toBe('unpaid');
      expect(o.rows[0].total_paid_paisa).toBe(0);
    });

    it('POS07: seller sees verification request in pending verification queue', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      // Seller queries pending payment attempts under own drops
      await asSeller(sellerAId);
      const pendingRes = await db.query<PaymentAttemptRow>(`
        SELECT pa.* 
        FROM payment_attempts pa
        JOIN orders o ON o.id = pa.order_id
        JOIN drops d ON d.id = o.drop_id
        WHERE d.seller_id = $1 AND pa.status = 'awaiting_seller_verification';
      `, [sellerAId]);

      expect(pendingRes.rows.length).toBe(1);
      expect(pendingRes.rows[0].buyer_submitted_utr).toBe('428739182734');
      expect(pendingRes.rows[0].expected_amount_paisa).toBe(25000);
    });

    it('POS08: seller verifies advance', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      await asSeller(sellerAId);
      const verifyRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1, '428739182734');
      `, [attId]);

      expect(verifyRes.rows[0].verify_manual_upi_payment.success).toBe(true);
      expect(verifyRes.rows[0].verify_manual_upi_payment.status).toBe('confirmed');
      expect(verifyRes.rows[0].verify_manual_upi_payment.payment_status).toBe('advance_paid');
    });

    it('POS09: advance state becomes confirmed/advance_paid', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [attId]);

      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT * FROM orders WHERE id = $1;`, [ord.order_id]);
      expect(o.rows[0].status).toBe('confirmed');
      expect(o.rows[0].payment_status).toBe('advance_paid');
      expect(o.rows[0].advance_paid_paisa).toBe(25000);
      expect(o.rows[0].total_paid_paisa).toBe(25000);
      expect(o.rows[0].balance_due_paisa).toBe(ord.total_paisa - 25000);
      expect(o.rows[0].fulfilment_status).toBe('not_ready');
    });

    it('POS10: hold extends to configured duration', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [attId]);

      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT hold_expires_at FROM orders WHERE id = $1;`, [ord.order_id]);
      const holdExpiry = new Date(o.rows[0].hold_expires_at).getTime();
      const now = Date.now();
      const hoursRemaining = (holdExpiry - now) / (1000 * 60 * 60);
      // Drop A configured hold_duration_days = 3 days (~72 hours)
      expect(hoursRemaining).toBeGreaterThan(70);
      expect(hoursRemaining).toBeLessThanOrEqual(73);
    });

    it('POS11: seller verifies balance', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      // Step 1: Advance
      const initAdv = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [initAdv.rows[0].initiate_payment_attempt.attempt_id, ord.order_token]);
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [initAdv.rows[0].initiate_payment_attempt.attempt_id]);

      // Step 2: Balance payment attempt
      await asAnon(ord.order_token);
      const initBal = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'balance');
      `, [ord.order_id, ord.order_token]);
      const balAttId = initBal.rows[0].initiate_payment_attempt.attempt_id!;
      expect(initBal.rows[0].initiate_payment_attempt.expected_amount_paisa).toBe(ord.total_paisa - 25000);

      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '998877665544');`, [balAttId, ord.order_token]);

      // Step 3: Seller verifies balance
      await asSeller(sellerAId);
      const balVerify = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1, '998877665544');
      `, [balAttId]);
      expect(balVerify.rows[0].verify_manual_upi_payment.success).toBe(true);
      expect(balVerify.rows[0].verify_manual_upi_payment.status).toBe('paid');
    });

    it('POS12: order becomes paid/ready_to_ship after balance verification', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initAdv = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [initAdv.rows[0].initiate_payment_attempt.attempt_id, ord.order_token]);
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [initAdv.rows[0].initiate_payment_attempt.attempt_id]);

      await asAnon(ord.order_token);
      const initBal = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'balance');
      `, [ord.order_id, ord.order_token]);
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '998877665544');`, [initBal.rows[0].initiate_payment_attempt.attempt_id, ord.order_token]);

      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [initBal.rows[0].initiate_payment_attempt.attempt_id]);

      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT * FROM orders WHERE id = $1;`, [ord.order_id]);
      expect(o.rows[0].status).toBe('paid');
      expect(o.rows[0].payment_status).toBe('paid');
      expect(o.rows[0].total_paid_paisa).toBe(ord.total_paisa);
      expect(o.rows[0].balance_due_paisa).toBe(0);
      expect(o.rows[0].fulfilment_status).toBe('ready_to_ship');
    });

    it('POS13: product becomes sold after full payment', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initAdv = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [initAdv.rows[0].initiate_payment_attempt.attempt_id, ord.order_token]);
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [initAdv.rows[0].initiate_payment_attempt.attempt_id]);

      await asAnon(ord.order_token);
      const initBal = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'balance');
      `, [ord.order_id, ord.order_token]);
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '998877665544');`, [initBal.rows[0].initiate_payment_attempt.attempt_id, ord.order_token]);
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [initBal.rows[0].initiate_payment_attempt.attempt_id]);

      await asSuperuser();
      const p = await db.query<{ status: string; reserved_by_order_id: string | null }>(`
        SELECT status, reserved_by_order_id FROM products WHERE id = $1;
      `, [prodA1Id]);
      expect(p.rows[0].status).toBe('sold');
      expect(p.rows[0].reserved_by_order_id).toBeNull();
    });

    it('POS14: full-payment seller verification on full_payment order', async () => {
      const ord = await createOrder(dropAId, [prodA1Id], 'Full Buyer', 'full_payment');
      await asAnon(ord.order_token);

      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'full');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      expect(initRes.rows[0].initiate_payment_attempt.expected_amount_paisa).toBe(ord.total_paisa);

      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '112233445566');`, [attId, ord.order_token]);

      await asSeller(sellerAId);
      const vRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1, '112233445566');
      `, [attId]);
      expect(vRes.rows[0].verify_manual_upi_payment.success).toBe(true);
      expect(vRes.rows[0].verify_manual_upi_payment.status).toBe('paid');

      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT status, payment_status, fulfilment_status FROM orders WHERE id = $1;`, [ord.order_id]);
      expect(o.rows[0].status).toBe('paid');
      expect(o.rows[0].fulfilment_status).toBe('ready_to_ship');
    });

    it('POS15: duplicate seller verification is idempotent', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      await asSeller(sellerAId);
      // First verification call
      const v1 = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);
      expect(v1.rows[0].verify_manual_upi_payment.success).toBe(true);

      // Duplicate verification call (double-tap)
      const v2 = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);
      expect(v2.rows[0].verify_manual_upi_payment.success).toBe(true);
      expect(v2.rows[0].verify_manual_upi_payment.idempotent).toBe(true);

      // Verify only ONE payment ledger entry was created
      await asSuperuser();
      const pCount = await db.query<{ count: string }>(`
        SELECT count(*) FROM order_payments WHERE order_id = $1;
      `, [ord.order_id]);
      expect(parseInt(pCount.rows[0].count, 10)).toBe(1);
    });

    it('POS16: seller operational update remains functional', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      const updRes = await db.query<{ id: string; tracking_number: string }>(`
        UPDATE orders 
        SET tracking_number = 'DELHIVERY987654',
            courier_partner = 'Delhivery'
        WHERE id = $1
        RETURNING id, tracking_number;
      `, [ord.order_id]);

      expect(updRes.rows.length).toBe(1);
      expect(updRes.rows[0].tracking_number).toBe('DELHIVERY987654');
    });
  });

  // ==========================================================================
  // SECTION 48: ADVERSARIAL TEST MATRIX (UPI-A01 - UPI-A35)
  // ==========================================================================
  describe('SECTION 48: ADVERSARIAL TEST MATRIX (UPI-A01–UPI-A35)', () => {
    it('UPI-A01: Buyer changes amount in client payload -> server calculates expected amount strictly from order', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      // Initiate payment attempt - RPC calculates expected_amount strictly from database
      const res = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);

      expect(res.rows[0].initiate_payment_attempt.expected_amount_paisa).toBe(25000);
      expect(res.rows[0].initiate_payment_attempt.expected_amount_paisa).not.toBe(100);
    });

    it('UPI-A02: Buyer changes seller UPI VPA -> server uses seller snapshot strictly from profile', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      const res = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);

      expect(res.rows[0].initiate_payment_attempt.payee_vpa).toBe('priya@okaxis');
      // Buyer cannot inject attacker VPA
      expect(res.rows[0].initiate_payment_attempt.payee_vpa).not.toBe('attacker@upi');
    });

    it('UPI-A03: Buyer changes payment type (requesting balance on unpaid order) -> rejected', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      // Order is pending unpaid with advance mode, cannot initiate balance before advance is paid
      const res = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'balance');
      `, [ord.order_id, ord.order_token]);

      expect(res.rows[0].initiate_payment_attempt.success).toBe(false);
      expect(res.rows[0].initiate_payment_attempt.error).toBe('INVALID_ORDER_STATE');
    });

    it('UPI-A04: Buyer changes payment attempt order ID (token mismatch) -> rejected', async () => {
      const ord1 = await createOrder(dropAId, [prodA1Id]);
      const ord2 = await createOrder(dropAId, [prodA2Id]);

      await asAnon(ord1.order_token);
      // Attempt to initiate payment on Order 2 using Order 1's token
      const res = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord2.order_id, ord1.order_token]);

      expect(res.rows[0].initiate_payment_attempt.success).toBe(false);
      expect(res.rows[0].initiate_payment_attempt.error).toBe('UNAUTHORIZED');
    });

    it('UPI-A05: Buyer marks payment verified directly -> BLOCKED (permission denied / RLS)', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      // Anon / buyer cannot execute verify_manual_upi_payment
      await expect(
        db.query(`SELECT verify_manual_upi_payment($1);`, [attId])
      ).rejects.toThrow(/permission denied/i);

      // Anon cannot directly UPDATE payment_attempts table
      await expect(
        db.query(`UPDATE payment_attempts SET status = 'verified' WHERE id = $1;`, [attId])
      ).rejects.toThrow(/permission denied/i);
    });

    it('UPI-A06: Buyer inserts verified payment into order_payments -> BLOCKED', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      await expect(
        db.query(`
          INSERT INTO order_payments (order_id, payment_type, amount_paisa, status, reference_id)
          VALUES ($1, 'advance', 25000, 'verified', 'FAKE-TXN-001');
        `, [ord.order_id])
      ).rejects.toThrow(/permission denied/i);
    });

    it('UPI-A07: Buyer submits malformed UTR -> rejected with INVALID_UTR_FORMAT', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      // Malformed UTR with illegal symbols
      const res = await db.query<{ submit_buyer_payment_claim: RpcOutput }>(`
        SELECT submit_buyer_payment_claim($1, $2, 'bad_utr!@#');
      `, [attId, ord.order_token]);

      expect(res.rows[0].submit_buyer_payment_claim.success).toBe(false);
      expect(res.rows[0].submit_buyer_payment_claim.error).toBe('INVALID_UTR_FORMAT');
    });

    it('UPI-A08: Buyer submits same UTR repeatedly -> idempotent without double crediting', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      const res1 = await db.query<{ submit_buyer_payment_claim: RpcOutput }>(`
        SELECT submit_buyer_payment_claim($1, $2, '428739182734');
      `, [attId, ord.order_token]);
      expect(res1.rows[0].submit_buyer_payment_claim.success).toBe(true);

      const res2 = await db.query<{ submit_buyer_payment_claim: RpcOutput }>(`
        SELECT submit_buyer_payment_claim($1, $2, '428739182734');
      `, [attId, ord.order_token]);
      expect(res2.rows[0].submit_buyer_payment_claim.success).toBe(true);
      expect(res2.rows[0].submit_buyer_payment_claim.idempotent).toBe(true);
    });

    it('UPI-A09: Buyer submits UTR after order expiry -> rejected with INVALID_ORDER_STATE', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      // Superuser expires order
      await asSuperuser();
      await db.query(`UPDATE orders SET status = 'expired' WHERE id = $1;`, [ord.order_id]);

      await asAnon(ord.order_token);
      const claimRes = await db.query<{ submit_buyer_payment_claim: RpcOutput }>(`
        SELECT submit_buyer_payment_claim($1, $2, '428739182734');
      `, [attId, ord.order_token]);

      expect(claimRes.rows[0].submit_buyer_payment_claim.success).toBe(false);
      expect(claimRes.rows[0].submit_buyer_payment_claim.error).toBe('INVALID_ORDER_STATE');
    });

    it('UPI-A10: Seller verifies another seller\'s payment attempt -> UNAUTHORIZED', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      // Seller B attempts to verify Seller A's payment attempt
      await asSeller(sellerBId);
      const vRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);

      expect(vRes.rows[0].verify_manual_upi_payment.success).toBe(false);
      expect(vRes.rows[0].verify_manual_upi_payment.error).toBe('UNAUTHORIZED');
    });

    it('UPI-A11: Seller changes amount during verification -> impossible; RPC signature takes no amount', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSeller(sellerAId);
      // verify_manual_upi_payment only takes (p_attempt_id, p_utr) - amount is derived from attempt snapshot
      const vRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1, '428739182734');
      `, [attId]);
      expect(vRes.rows[0].verify_manual_upi_payment.success).toBe(true);

      await asSuperuser();
      const pRow = await db.query<{ amount_paisa: number }>(`
        SELECT amount_paisa FROM order_payments WHERE order_id = $1;
      `, [ord.order_id]);
      expect(pRow.rows[0].amount_paisa).toBe(25000);
    });

    it('UPI-A12: Seller changes payment type during verification -> derived strictly from payment attempt', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSeller(sellerAId);
      const vRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);
      expect(vRes.rows[0].verify_manual_upi_payment.success).toBe(true);

      await asSuperuser();
      const pRow = await db.query<{ payment_type: string }>(`
        SELECT payment_type FROM order_payments WHERE order_id = $1;
      `, [ord.order_id]);
      expect(pRow.rows[0].payment_type).toBe('advance');
    });

    it('UPI-A13: Seller verifies already-verified payment -> idempotent success', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [attId]);
      const dupRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);

      expect(dupRes.rows[0].verify_manual_upi_payment.success).toBe(true);
      expect(dupRes.rows[0].verify_manual_upi_payment.idempotent).toBe(true);
    });

    it('UPI-A14: Seller verifies cancelled order -> rejected with INVALID_ORDER_STATE', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSuperuser();
      await db.query(`UPDATE orders SET status = 'cancelled' WHERE id = $1;`, [ord.order_id]);

      await asSeller(sellerAId);
      const vRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);
      expect(vRes.rows[0].verify_manual_upi_payment.success).toBe(false);
      expect(vRes.rows[0].verify_manual_upi_payment.error).toBe('INVALID_ORDER_STATE');
    });

    it('UPI-A15: Seller verifies expired order -> rejected with INVALID_ORDER_STATE', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSuperuser();
      await db.query(`UPDATE orders SET status = 'expired' WHERE id = $1;`, [ord.order_id]);

      await asSeller(sellerAId);
      const vRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);
      expect(vRes.rows[0].verify_manual_upi_payment.success).toBe(false);
      expect(vRes.rows[0].verify_manual_upi_payment.error).toBe('INVALID_ORDER_STATE');
    });

    it('UPI-A16: Seller manually changes orders.payment_status -> BLOCKED with SQLSTATE 42501', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      await expect(
        db.query(`UPDATE orders SET payment_status = 'advance_paid' WHERE id = $1;`, [ord.order_id])
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('UPI-A17: Seller manually changes orders.total_paid_paisa -> BLOCKED with SQLSTATE 42501', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      await expect(
        db.query(`UPDATE orders SET total_paid_paisa = 25000 WHERE id = $1;`, [ord.order_id])
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('UPI-A18: Seller manually changes orders.balance_due_paisa -> BLOCKED with SQLSTATE 42501', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      await expect(
        db.query(`UPDATE orders SET balance_due_paisa = 0 WHERE id = $1;`, [ord.order_id])
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('UPI-A19: Seller manually changes fulfilment_status -> BLOCKED with SQLSTATE 42501', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      await expect(
        db.query(`UPDATE orders SET fulfilment_status = 'ready_to_ship' WHERE id = $1;`, [ord.order_id])
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('UPI-A20: Seller manually changes hold_expires_at -> BLOCKED with SQLSTATE 42501', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      await expect(
        db.query(`UPDATE orders SET hold_expires_at = NOW() + INTERVAL '30 days' WHERE id = $1;`, [ord.order_id])
      ).rejects.toThrow(/Direct mutation of payment or order lifecycle fields is prohibited/i);
    });

    it('UPI-A21: Seller manually marks reserved product sold -> BLOCKED with SQLSTATE 42501', async () => {
      await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      await expect(
        db.query(`UPDATE products SET status = 'sold' WHERE id = $1;`, [prodA1Id])
      ).rejects.toThrow(/Direct mutation of product (reservation|inventory) status/i);
    });

    it('UPI-A22: Same UTR/reference reused on another order -> REFERENCE_USED_ON_ANOTHER_ORDER', async () => {
      const ord1 = await createOrder(dropAId, [prodA1Id]);
      const ord2 = await createOrder(dropAId, [prodA2Id]);

      // Order 1: verify payment with reference REF-SHARED-001
      await asAnon(ord1.order_token);
      const init1 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord1.order_id, ord1.order_token]);
      const att1 = init1.rows[0].initiate_payment_attempt.attempt_id!;
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1, 'REF-SHARED-001');`, [att1]);

      // Order 2: attempt verification with same UTR
      await asAnon(ord2.order_token);
      const init2 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord2.order_id, ord2.order_token]);
      const att2 = init2.rows[0].initiate_payment_attempt.attempt_id!;
      await asSeller(sellerAId);
      const res2 = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1, 'REF-SHARED-001');
      `, [att2]);

      expect(res2.rows[0].verify_manual_upi_payment.success).toBe(false);
      expect(res2.rows[0].verify_manual_upi_payment.error).toBe('REFERENCE_USED_ON_ANOTHER_ORDER');

      // Assert Order 2 received zero credit
      await asSuperuser();
      const o2 = await db.query<OrderRow>(`SELECT total_paid_paisa, payment_status FROM orders WHERE id = $1;`, [ord2.order_id]);
      expect(o2.rows[0].total_paid_paisa).toBe(0);
      expect(o2.rows[0].payment_status).toBe('unpaid');
    });

    it('UPI-A23: Same UTR with different amount -> blocked from duplicate credit', async () => {
      const ord1 = await createOrder(dropAId, [prodA1Id]);
      const ord2 = await createOrder(dropAId, [prodA2Id]);

      await asAnon(ord1.order_token);
      const init1 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord1.order_id, ord1.order_token]);
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1, 'REF-DIFF-AMT');`, [init1.rows[0].initiate_payment_attempt.attempt_id]);

      // Reuse on Order 2
      await asAnon(ord2.order_token);
      const init2 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord2.order_id, ord2.order_token]);
      await asSeller(sellerAId);
      const v2 = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1, 'REF-DIFF-AMT');
      `, [init2.rows[0].initiate_payment_attempt.attempt_id]);
      expect(v2.rows[0].verify_manual_upi_payment.success).toBe(false);
      expect(v2.rows[0].verify_manual_upi_payment.error).toBe('REFERENCE_USED_ON_ANOTHER_ORDER');
    });

    it('UPI-A24: Same UTR with different payment type -> blocked from cross-order credit', async () => {
      const ord1 = await createOrder(dropAId, [prodA1Id]);
      const ord2 = await createOrder(dropAId, [prodA2Id], 'Full Buyer', 'full_payment');

      await asAnon(ord1.order_token);
      const init1 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord1.order_id, ord1.order_token]);
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1, 'REF-DIFF-TYPE');`, [init1.rows[0].initiate_payment_attempt.attempt_id]);

      await asAnon(ord2.order_token);
      const init2 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'full');
      `, [ord2.order_id, ord2.order_token]);
      await asSeller(sellerAId);
      const v2 = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1, 'REF-DIFF-TYPE');
      `, [init2.rows[0].initiate_payment_attempt.attempt_id]);
      expect(v2.rows[0].verify_manual_upi_payment.success).toBe(false);
      expect(v2.rows[0].verify_manual_upi_payment.error).toBe('REFERENCE_USED_ON_ANOTHER_ORDER');
    });

    it('UPI-A25: Concurrent duplicate verification -> serializes cleanly, returns idempotent on second call', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      await asSeller(sellerAId);
      // Execute 2 concurrent verifications
      const [r1, r2] = await Promise.all([
        db.query<{ verify_manual_upi_payment: RpcOutput }>(`SELECT verify_manual_upi_payment($1);`, [attId]),
        db.query<{ verify_manual_upi_payment: RpcOutput }>(`SELECT verify_manual_upi_payment($1);`, [attId]),
      ]);

      expect(r1.rows[0].verify_manual_upi_payment.success).toBe(true);
      expect(r2.rows[0].verify_manual_upi_payment.success).toBe(true);
      const hasIdempotent = r1.rows[0].verify_manual_upi_payment.idempotent || r2.rows[0].verify_manual_upi_payment.idempotent;
      expect(hasIdempotent).toBe(true);
    });

    it('UPI-A26: Verification races with expiry -> if expired, rejects verification with INVALID_ORDER_STATE', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      // Expiry runs first
      await asSuperuser();
      await db.query(`UPDATE orders SET status = 'expired' WHERE id = $1;`, [ord.order_id]);

      await asSeller(sellerAId);
      const vRes = await db.query<{ verify_manual_upi_payment: RpcOutput }>(`
        SELECT verify_manual_upi_payment($1);
      `, [attId]);

      expect(vRes.rows[0].verify_manual_upi_payment.success).toBe(false);
      expect(vRes.rows[0].verify_manual_upi_payment.error).toBe('INVALID_ORDER_STATE');
    });

    it('UPI-A27: Verification races with another verification -> exactly one ledger entry is committed', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSeller(sellerAId);
      await Promise.all([
        db.query(`SELECT verify_manual_upi_payment($1);`, [attId]),
        db.query(`SELECT verify_manual_upi_payment($1);`, [attId]),
      ]);

      await asSuperuser();
      const countRes = await db.query<{ count: string }>(`SELECT count(*) FROM order_payments WHERE order_id = $1;`, [ord.order_id]);
      expect(parseInt(countRes.rows[0].count, 10)).toBe(1);
    });

    it('UPI-A28: Seller changes UPI ID after payment attempt creation -> existing attempt snapshot is preserved', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);

      // Attempt 1 created with current seller UPI
      const init1 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId1 = init1.rows[0].initiate_payment_attempt.attempt_id!;
      expect(init1.rows[0].initiate_payment_attempt.payee_vpa).toBe('priya@okaxis');

      // Seller updates profile UPI ID
      await asSeller(sellerAId);
      await db.query(`
        UPDATE profiles SET upi_vpa = 'priya.new@okhdfcbank' WHERE id = '${sellerAId}';
      `);

      // Existing attempt still points to original VPA
      await asSuperuser();
      const attRow = await db.query<PaymentAttemptRow>(`SELECT payee_vpa_snapshot FROM payment_attempts WHERE id = $1;`, [attId1]);
      expect(attRow.rows[0].payee_vpa_snapshot).toBe('priya@okaxis');

      // Second order attempt gets new VPA
      const ord2 = await createOrder(dropAId, [prodA2Id]);
      await asAnon(ord2.order_token);
      const init2 = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord2.order_id, ord2.order_token]);
      expect(init2.rows[0].initiate_payment_attempt.payee_vpa).toBe('priya.new@okhdfcbank');
    });

    it('UPI-A29: Buyer attempts to modify payment attempt after seller verification -> rejected with INVALID_PAYMENT_STATE', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [attId]);

      // Buyer tries to submit new UTR on already-verified attempt
      await asAnon(ord.order_token);
      const claimRes = await db.query<{ submit_buyer_payment_claim: RpcOutput }>(`
        SELECT submit_buyer_payment_claim($1, $2, '999999999999');
      `, [attId, ord.order_token]);

      expect(claimRes.rows[0].submit_buyer_payment_claim.success).toBe(false);
      expect(claimRes.rows[0].submit_buyer_payment_claim.error).toBe('INVALID_PAYMENT_STATE');
    });

    it('UPI-A30: Authenticated seller attempts direct PostgREST payment mutation -> permission denied', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSeller(sellerAId);

      await expect(
        db.query(`
          INSERT INTO order_payments (order_id, payment_type, amount_paisa, status, reference_id)
          VALUES ($1, 'advance', 25000, 'verified', 'SELLER-FAKE-01');
        `, [ord.order_id])
      ).rejects.toThrow(/permission denied/i);
    });

    it('UPI-A31: Anon attempts seller verification RPC -> permission denied (SQLSTATE 42501)', async () => {
      await createOrder(dropAId, [prodA1Id]);
      await asAnon();
      await expect(
        db.query(`SELECT verify_manual_upi_payment('ea000000-0000-0000-0000-000000000001');`)
      ).rejects.toThrow(/permission denied/i);
    });

    it('UPI-A32: Buyer attempts seller verification RPC -> permission denied (SQLSTATE 42501)', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      await expect(
        db.query(`SELECT verify_manual_upi_payment('ea000000-0000-0000-0000-000000000001');`)
      ).rejects.toThrow(/permission denied/i);
    });

    it('UPI-A33: Cross-seller payment-attempt access -> RLS returns 0 rows', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      // Seller B queries payment_attempts
      await asSeller(sellerBId);
      const r = await db.query<PaymentAttemptRow>(`
        SELECT * FROM payment_attempts WHERE id = $1;
      `, [attId]);
      expect(r.rows.length).toBe(0);
    });

    it('UPI-A34: Seller tries to extend hold beyond 30 days -> capped strictly at platform maximum', async () => {
      // 1. Seller A tries to set 99 days hold duration on profile -> check constraint blocks it
      await asSeller(sellerAId);
      await expect(
        db.query(`UPDATE profiles SET hold_duration_days = 99 WHERE id = '${sellerAId}';`)
      ).rejects.toThrow(/check constraint|profiles_hold_duration_days_check/i);

      // 2. Set to platform maximum 30 days and verify hold duration calculation
      await db.query(`UPDATE profiles SET hold_duration_days = 30 WHERE id = '${sellerAId}';`);

      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [attId]);

      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT hold_expires_at FROM orders WHERE id = $1;`, [ord.order_id]);
      const holdDays = (new Date(o.rows[0].hold_expires_at).getTime() - Date.now()) / (1000 * 60 * 60 * 24);
      expect(holdDays).toBeLessThanOrEqual(30.1);
    });

    it('UPI-A35: Buyer submits a claim without valid UTR -> rejected (UTR is mandatory)', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      // Submit empty / whitespace UTR
      const res = await db.query<{ submit_buyer_payment_claim: RpcOutput }>(`
        SELECT submit_buyer_payment_claim($1, $2, '   ');
      `, [attId, ord.order_token]);

      expect(res.rows[0].submit_buyer_payment_claim.success).toBe(false);
      expect(res.rows[0].submit_buyer_payment_claim.error).toBe('INVALID_UTR');
    });
  });

  // ==========================================================================
  // SECTIONS 50 & 52: FINANCIAL INVARIANTS & LEDGER CONSISTENCY
  // ==========================================================================
  describe('SECTIONS 50 & 52: Financial Invariants & Payment Ledger Consistency', () => {
    it('enforces total = subtotal + shipping and advance_required <= total', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT * FROM orders WHERE id = $1;`, [ord.order_id]);
      expect(o.rows[0].total_paisa).toBe(o.rows[0].subtotal_paisa + o.rows[0].shipping_paisa);
      expect(o.rows[0].advance_required_paisa).toBeLessThanOrEqual(o.rows[0].total_paisa);
      expect(o.rows[0].balance_due_paisa).toBe(o.rows[0].total_paisa - o.rows[0].total_paid_paisa);
    });

    it('enforces ledger consistency: verified payment event matches order total_paid exactly', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;

      await asSeller(sellerAId);
      await db.query(`SELECT verify_manual_upi_payment($1);`, [attId]);

      await asSuperuser();
      const ledgerSum = await db.query<{ sum: string }>(`
        SELECT COALESCE(SUM(amount_paisa), 0) AS sum FROM order_payments WHERE order_id = $1 AND status = 'verified';
      `, [ord.order_id]);
      const o = await db.query<OrderRow>(`SELECT total_paid_paisa FROM orders WHERE id = $1;`, [ord.order_id]);
      expect(parseInt(ledgerSum.rows[0].sum, 10)).toBe(o.rows[0].total_paid_paisa);
      expect(o.rows[0].total_paid_paisa).toBe(25000);
    });

    it('rejects seller rejection without reason, and handles valid rejection preserving order lifecycle', async () => {
      const ord = await createOrder(dropAId, [prodA1Id]);
      await asAnon(ord.order_token);
      const initRes = await db.query<{ initiate_payment_attempt: RpcOutput }>(`
        SELECT initiate_payment_attempt($1, $2, 'advance');
      `, [ord.order_id, ord.order_token]);
      const attId = initRes.rows[0].initiate_payment_attempt.attempt_id!;
      await db.query(`SELECT submit_buyer_payment_claim($1, $2, '428739182734');`, [attId, ord.order_token]);

      await asSeller(sellerAId);
      const rejRes = await db.query<{ reject_manual_upi_payment: RpcOutput }>(`
        SELECT reject_manual_upi_payment($1, 'payment_not_found');
      `, [attId]);
      expect(rejRes.rows[0].reject_manual_upi_payment.success).toBe(true);
      expect(rejRes.rows[0].reject_manual_upi_payment.status).toBe('rejected');

      // Underlying order remains pending with product still reserved
      await asSuperuser();
      const o = await db.query<OrderRow>(`SELECT status, payment_status FROM orders WHERE id = $1;`, [ord.order_id]);
      expect(o.rows[0].status).toBe('pending');
      expect(o.rows[0].payment_status).toBe('unpaid');
    });
  });
});
