import { createRequire } from 'node:module';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(path.resolve(__dirname, '../buyer-web/package.json'));
const { PGlite } = require('@electric-sql/pglite');

async function testAttacks() {
  const db = new PGlite();
  
  // Set up auth and storage schema simulation
  await db.exec(`
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE TABLE IF NOT EXISTS auth.users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email TEXT,
      raw_user_meta_data JSONB DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
    CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
      SELECT coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
      )::uuid
    $$ LANGUAGE sql STABLE;
    CREATE OR REPLACE FUNCTION auth.role() RETURNS TEXT AS $$
      SELECT COALESCE(
        NULLIF(current_setting('request.jwt.claim.role', true), ''),
        (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
        'anon'
      );
    $$ LANGUAGE sql STABLE;

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

  // Apply migrations 001 through 026
  const migrationsDir = path.resolve('supabase/migrations');
  const files = fs.readdirSync(migrationsDir).filter(f => f.endsWith('.sql')).sort();
  for (const file of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    await db.exec(sql);
  }

  // Apply seed
  const seedSql = fs.readFileSync(path.resolve('supabase/seed.sql'), 'utf8');
  await db.exec(seedSql);

  console.log('✅ Migrations & seed loaded.');

  // =========================================================================
  // ATTACK 1: Authenticated user self-approves via direct INSERT INTO profiles
  // =========================================================================
  console.log('\n--- ATTACK 1: Direct INSERT with is_approved = true ---');
  const hackerId = 'e0000000-0000-0000-0000-000000000001';
  await db.query(`INSERT INTO auth.users (id, email) VALUES ('${hackerId}'::uuid, 'hacker@test.com');`);
  
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${hackerId}", "role": "authenticated"}';
  `);

  try {
    await db.query(`
      INSERT INTO profiles (id, store_name, store_slug, phone_number, upi_id, return_address, is_approved)
      VALUES ('${hackerId}'::uuid, 'Hacker Store', 'hacker-store', '919876543210', 'hacker@upi', '123 Fake Street, Bengaluru', TRUE);
    `);
    const checkHacker = await db.query(`SELECT is_approved FROM profiles WHERE id = '${hackerId}'::uuid;`);
    console.log('ATTACK 1 RESULT: is_approved =', checkHacker.rows[0].is_approved);
    if (checkHacker.rows[0].is_approved === true) {
      console.log('🚨 VULNERABILITY CONFIRMED: Hacker was able to self-approve via direct INSERT!');
    }
  } catch (err) {
    console.log('ATTACK 1 BLOCKED:', err.message);
  }

  // =========================================================================
  // ATTACK 2: Direct UPDATE on products table by authenticated seller
  // =========================================================================
  console.log('\n--- ATTACK 2: Direct UPDATE on products by authenticated seller ---');
  const sellerA = '8a329e71-4b10-4055-90d2-df8029d5b512';
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${sellerA}", "role": "authenticated"}';
  `);
  
  try {
    await db.query(`
      UPDATE products 
      SET price_paisa = 100, title = 'Hacked Price'
      WHERE id = 'e9314c99-7f55-4089-a2bb-b001d2950df1';
    `);
    const checkProd = await db.query(`SELECT price_paisa, title FROM products WHERE id = 'e9314c99-7f55-4089-a2bb-b001d2950df1';`);
    console.log('ATTACK 2 RESULT: price_paisa =', checkProd.rows[0].price_paisa, 'title =', checkProd.rows[0].title);
    if (checkProd.rows[0].price_paisa === 100) {
      console.log('🚨 VULNERABILITY CONFIRMED: Direct PostgREST UPDATE on available products is NOT BLOCKED!');
    }
  } catch (err) {
    console.log('ATTACK 2 BLOCKED:', err.message);
  }

  // =========================================================================
  // ATTACK 3: Seller verifies late_claim_pending_review attempt
  // =========================================================================
  console.log('\n--- ATTACK 3: Verify late UPI claim ---');
  await db.exec(`
    SET ROLE postgres;
    RESET request.jwt.claims;
  `);

  // Create an expired order and expired payment attempt
  const expOrderId = 'f0000000-0000-0000-0000-000000000001';
  const expOrderToken = '11111111-1111-1111-1111-111111111111';
  const dropId = 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801';
  
  await db.query(`
    INSERT INTO orders (id, drop_id, order_code, order_token, buyer_name, buyer_phone, shipping_address, pincode, subtotal_paisa, shipping_paisa, total_paisa, confirmation_mode, advance_required_paisa, advance_paid_paisa, total_paid_paisa, balance_due_paisa, payment_status, fulfilment_status, status, hold_expires_at)
    VALUES ('${expOrderId}'::uuid, '${dropId}'::uuid, 'LD-EXPD01', '${expOrderToken}'::uuid, 'Late Buyer', '9876543210', '123 Expired St', '560001', 150000, 8000, 158000, 'advance', 25000, 0, 0, 158000, 'unpaid', 'not_ready', 'cancelled', NOW() - INTERVAL '10 minutes');
  `);

  const expAttId = 'f0000000-0000-0000-0000-000000000002';
  await db.query(`
    INSERT INTO payment_attempts (id, order_id, payment_type, expected_amount_paisa, status, payee_vpa_snapshot, payee_display_name_snapshot, transaction_reference, expires_at)
    VALUES ('${expAttId}'::uuid, '${expOrderId}'::uuid, 'advance', 25000, 'expired', 'mothersboutique@okaxis', 'Mother''s Boutique', 'TXN-LATE-123', NOW() - INTERVAL '10 minutes');
  `);

  // Buyer submits late claim
  const claimRes = await db.query(`
    SELECT submit_buyer_payment_claim(
      '${expOrderId}'::uuid,
      '${expOrderToken}',
      '${expAttId}'::uuid,
      'LATE-UTR-999000'
    ) as r;
  `);
  console.log('Late claim submission response:', claimRes.rows[0].r);

  // Seller A tries to verify this payment
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${sellerA}", "role": "authenticated"}';
  `);

  const verifyLateRes = await db.query(`
    SELECT verify_manual_upi_payment('${expAttId}'::uuid) as r;
  `);
  console.log('Seller verification response for late claim:', verifyLateRes.rows[0].r);
  if (!verifyLateRes.rows[0].r.success) {
    console.log('🚨 FLAW CONFIRMED: Seller CANNOT verify late UPI payment! Error:', verifyLateRes.rows[0].r.error, '-', verifyLateRes.rows[0].r.message);
  }

  // =========================================================================
  // SCENARIO 4: Check fulfilment_status upon full payment verification
  // =========================================================================
  console.log('\n--- SCENARIO 4: Full payment verification fulfilment_status ---');
  await db.exec(`
    SET ROLE postgres;
    RESET request.jwt.claims;
  `);

  // Place a new full_payment order with a fresh available product
  const prodIns = await db.query(`
    INSERT INTO products (drop_id, code, title, price_paisa, size, status, image_url)
    VALUES ('c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid, '#Z99', 'Test Item', 100000, 'M', 'available', 'https://example.com/test.jpg')
    RETURNING id;
  `);
  const freshProdId = prodIns.rows[0].id;

  const fullOrderRes = await db.query(`
    SELECT create_order_with_reservation(
      'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
      ARRAY['${freshProdId}'::uuid],
      'Full Buyer',
      '9876543210',
      '123 Main St, Bengaluru',
      '560001',
      'full_payment',
      'IDEMP-FULL-001'
    ) as r;
  `);
  const fullOrder = fullOrderRes.rows[0].r;
  console.log('fullOrder creation result:', fullOrder.success, fullOrder.order_id);

  const initFullAtt = await db.query(`
    SELECT initiate_payment_attempt(
      '${fullOrder.order_id}'::uuid,
      '${fullOrder.order_token}',
      'full'
    ) as r;
  `);
  const fullAttId = initFullAtt.rows[0].r.payment_attempt_id;

  await db.query(`
    SELECT submit_buyer_payment_claim(
      '${fullOrder.order_id}'::uuid,
      '${fullOrder.order_token}',
      '${fullAttId}'::uuid,
      'FULL-UTR-112233'
    );
  `);

  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${sellerA}", "role": "authenticated"}';
  `);

  const fullVerifyRes = await db.query(`
    SELECT verify_manual_upi_payment('${fullAttId}'::uuid) as r;
  `);
  console.log('Full payment verify response:', fullVerifyRes.rows[0].r);

  const fullOrderAfterVerify = await db.query(`SELECT status, payment_status, fulfilment_status FROM orders WHERE id = '${fullOrder.order_id}'::uuid;`);
  console.log('Order status after full payment verification:', fullOrderAfterVerify.rows[0]);
  if (fullOrderAfterVerify.rows[0].fulfilment_status === 'ready_to_ship') {
    console.log('🚨 FLAW CONFIRMED: Full payment verification directly set fulfilment_status to "ready_to_ship", bypassing packing!');
  }
  // =========================================================================
  // SCENARIO 5: Late claim verification when inventory was already sold
  // =========================================================================
  console.log('\n--- SCENARIO 5: Late claim with unavailable inventory ---');
  await db.exec(`
    SET ROLE postgres;
    RESET request.jwt.claims;
  `);

  const prodTakenIns = await db.query(`
    INSERT INTO products (drop_id, code, title, price_paisa, size, status, image_url)
    VALUES ('c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid, '#TAK1', 'Taken Item', 50000, 'S', 'available', 'https://example.com/taken.jpg')
    RETURNING id;
  `);
  const takenProdId = prodTakenIns.rows[0].id;

  // Buyer 1 reserves it
  const b1OrderRes = await db.query(`
    SELECT create_order_with_reservation(
      'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
      ARRAY['${takenProdId}'::uuid],
      'Buyer One',
      '9876543211',
      '123 Buyer One Road, Bengaluru',
      '560001',
      'full_payment',
      'IDEMP-LATE-TAKEN-01'
    ) as r;
  `);
  const b1Order = b1OrderRes.rows[0].r;

  const b1AttRes = await db.query(`
    SELECT initiate_payment_attempt('${b1Order.order_id}'::uuid, '${b1Order.order_token}', 'full') as r;
  `);
  const b1AttId = b1AttRes.rows[0].r.payment_attempt_id;

  // Hold expires and reaper runs (or manual expiry)
  await db.query(`
    UPDATE orders SET status = 'cancelled', hold_expires_at = NOW() - INTERVAL '1 hour' WHERE id = '${b1Order.order_id}'::uuid;
    UPDATE payment_attempts SET status = 'expired', expires_at = NOW() - INTERVAL '1 hour' WHERE id = '${b1AttId}'::uuid;
    UPDATE products SET status = 'available', reserved_at = NULL, reserved_by_order_id = NULL WHERE id = '${takenProdId}'::uuid;
  `);

  // Buyer 2 comes in and actually buys the product!
  const b2OrderRes = await db.query(`
    SELECT create_order_with_reservation(
      'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801'::uuid,
      ARRAY['${takenProdId}'::uuid],
      'Buyer Two',
      '9876543212',
      '456 Buyer Two Road, Bengaluru',
      '560001',
      'full_payment',
      'IDEMP-BUYER-TWO-01'
    ) as r;
  `);
  const b2Order = b2OrderRes.rows[0].r;
  const b2Att = await db.query(`
    SELECT initiate_payment_attempt('${b2Order.order_id}'::uuid, '${b2Order.order_token}', 'full') as r;
  `);
  await db.query(`
    SELECT submit_buyer_payment_claim('${b2Order.order_id}'::uuid, '${b2Order.order_token}', '${b2Att.rows[0].r.payment_attempt_id}'::uuid, 'B2-UTR-VALID-99');
  `);
  // Seller verifies buyer 2's payment
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${sellerA}", "role": "authenticated"}';
  `);
  await db.query(`
    SELECT verify_manual_upi_payment('${b2Att.rows[0].r.payment_attempt_id}'::uuid);
  `);

  // Verify takenProdId is now 'sold' to Buyer 2
  const prodCheck = await db.query(`SELECT status FROM products WHERE id = '${takenProdId}'::uuid;`);
  console.log('Product status after Buyer 2 purchase:', prodCheck.rows[0].status);

  // Now Buyer 1 submits late claim on their cancelled order
  await db.exec(`
    SET ROLE postgres;
    RESET request.jwt.claims;
  `);
  const lateClaimB1 = await db.query(`
    SELECT submit_buyer_payment_claim(
      '${b1Order.order_id}'::uuid,
      '${b1Order.order_token}',
      '${b1AttId}'::uuid,
      'B1-LATE-UTR-999'
    ) as r;
  `);
  console.log('Buyer 1 late claim response:', lateClaimB1.rows[0].r);

  // Seller verifies Buyer 1's late payment (confirming funds entered bank)
  await db.exec(`
    SET ROLE authenticated;
    SET request.jwt.claims = '{"sub": "${sellerA}", "role": "authenticated"}';
  `);
  const verifyLateTakenRes = await db.query(`
    SELECT verify_manual_upi_payment('${b1AttId}'::uuid) as r;
  `);
  console.log('Seller verification response for Buyer 1 late claim (inventory unavailable):', verifyLateTakenRes.rows[0].r);

  // Check product is STILL sold and was NOT corrupted
  const prodFinalCheck = await db.query(`SELECT status FROM products WHERE id = '${takenProdId}'::uuid;`);
  console.log('Product status after Buyer 1 late claim verification (must stay sold):', prodFinalCheck.rows[0].status);

  await db.close();
}

testAttacks().catch(console.error);
