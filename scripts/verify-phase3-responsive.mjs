/**
 * LiveDrop — Automated Phase 3 Responsive Viewport & Screenshot Auditor
 *
 * Spawns mock gateway (54321) + Next.js (3000), checks:
 * 1. /order (Order Lookup Directory & Form)
 * 2. /order/[id] with Pending State (Unpaid, awaiting UPI verification)
 * 3. /order/[id] with Advance-Paid State (Balance due notice, shipment held)
 * 4. /order/[id] with Fully-Paid State (Payment complete, ready to ship)
 * 5. /order/[id] with Shipped State (Courier partner & tracking AWB details)
 * 6. /order/[id] with Expired/Cancelled State (Terminal cancellation banner)
 *
 * Viewports audited:
 * - 360px (Small Android)
 * - 375px (iPhone SE)
 * - 390px (iPhone 14)
 * - 412px (Galaxy S20)
 * - 430px (iPhone Pro Max)
 * - 1280px (Desktop Wide)
 */

import { spawn } from 'child_process';
import http from 'http';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { chromium } from '../buyer-web/node_modules/@playwright/test/index.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const buyerWebDir = path.resolve(rootDir, 'buyer-web');
const screenshotsDir = 'C:\\Users\\Sauvraneel Paul\\.gemini\\antigravity-ide\\brain\\cc1746b2-101a-4597-bdf1-678cf32c988c\\screenshots';

function waitForHttp(url, timeoutMs = 45000) {
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      http
        .get(url, (res) => {
          if (res.statusCode && res.statusCode < 500) resolve();
          else retry();
        })
        .on('error', retry);
    };
    const retry = () => {
      if (Date.now() - startTime > timeoutMs) {
        reject(new Error(`Timeout waiting for ${url}`));
      } else {
        setTimeout(check, 500);
      }
    };
    check();
  });
}

const baseOrderReceipt = {
  id: 'd9b73f2a-7182-4912-9c1e-3f5e1823901a',
  order_code: 'LD-9281',
  buyer_name: 'Priyanka Sharma',
  subtotal_paisa: 249900,
  shipping_paisa: 0,
  total_paisa: 249900,
  confirmation_mode: 'full',
  advance_required_paisa: 0,
  advance_paid_paisa: 0,
  total_paid_paisa: 0,
  balance_due_paisa: 249900,
  payment_status: 'unpaid',
  fulfilment_status: 'not_ready',
  status: 'pending',
  hold_expires_at: new Date(Date.now() + 45 * 60 * 1000).toISOString(),
  shipped_at: null,
  tracking_number: null,
  courier_partner: null,
  notes: null,
  store_name: 'Varanasi Silk Heritage',
  store_slug: 'varanasi-silk-heritage',
  upi_id: 'varanasiheritage@okaxis',
  upi_qr_url: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?w=400&q=80',
  upi_enabled: true,
  upi_uri: 'upi://pay?pa=varanasiheritage@okaxis&pn=Varanasi%20Silk%20Heritage&am=2499.00&cu=INR&tr=LD-9281-FULL',
  payment_instructions: 'Please pay via UPI within 45 minutes to guarantee hold reservation.',
  whatsapp_number: '919876543210',
  active_payment_attempt: null,
  payment_attempt: null,
  items: [
    {
      id: 'item-101',
      product_id: 'prod-101',
      code: '#V01',
      title: 'Handloom Katan Silk Banarasi Saree',
      price_paisa: 249900,
      size: 'Free Size',
      image_url: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?w=400&q=80',
    },
  ],
};

async function run() {
  if (!fs.existsSync(screenshotsDir)) {
    fs.mkdirSync(screenshotsDir, { recursive: true });
  }

  const envLocal = path.resolve(buyerWebDir, '.env.local');
  const envLocalTmp = path.resolve(buyerWebDir, '.env.local.resp3tmp');
  let renamedEnv = false;
  let mockServerProcess = null;
  let nextServerProcess = null;

  const cleanup = () => {
    if (mockServerProcess) {
      mockServerProcess.kill();
      mockServerProcess = null;
    }
    if (nextServerProcess) {
      nextServerProcess.kill();
      nextServerProcess = null;
    }
    if (renamedEnv && fs.existsSync(envLocalTmp)) {
      try {
        fs.renameSync(envLocalTmp, envLocal);
        renamedEnv = false;
      } catch (e) {
        console.error('Failed to restore .env.local:', e);
      }
    }
  };

  process.on('SIGINT', () => { cleanup(); process.exit(1); });
  process.on('SIGTERM', () => { cleanup(); process.exit(1); });

  try {
    if (fs.existsSync(envLocal)) {
      fs.renameSync(envLocal, envLocalTmp);
      renamedEnv = true;
    }

    console.log('1. Starting Mock Gateway (54321)...');
    mockServerProcess = spawn('node', ['scripts/dev-mock-supabase.mjs'], {
      cwd: rootDir,
      stdio: 'pipe',
      env: { ...process.env, PORT: '54321' },
      shell: true,
    });
    await waitForHttp('http://127.0.0.1:54321');

    console.log('2. Starting Next.js Buyer Web (3000)...');
    nextServerProcess = spawn('npx', ['next', 'dev', '-p', '3000'], {
      cwd: buyerWebDir,
      stdio: 'pipe',
      env: {
        ...process.env,
        PORT: '3000',
        NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
        NEXT_PUBLIC_SUPABASE_ANON_KEY: 'test-anon-key',
        NEXT_PUBLIC_APP_ENV: 'development',
      },
      shell: true,
    });
    await waitForHttp('http://127.0.0.1:3000');
    console.log('Servers ready. Launching Chromium...');

    const browser = await chromium.launch({ headless: true });
    const viewports = [
      { name: '360px', width: 360, height: 740 },
      { name: '375px', width: 375, height: 667 },
      { name: '390px', width: 390, height: 844 },
      { name: '412px', width: 412, height: 915 },
      { name: '430px', width: 430, height: 932 },
      { name: '1280px', width: 1280, height: 800 },
    ];

    let allPassed = true;

    // Audit 1: /order (Order Lookup Directory & Form)
    console.log('\n--- Auditing: /order (Order Lookup & Directory) ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.goto('http://localhost:3000/order', { waitUntil: 'networkidle' });

      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const screenshotFile = `order-lookup-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] /order -> overflow check: ${overflow ? 'FAIL' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    // Audit 2: /order/[id] with Pending State
    console.log('\n--- Auditing: /order/[id] Pending State ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.route('**/rest/v1/rpc/get_order_by_token', async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            order: {
              ...baseOrderReceipt,
              status: 'pending',
              payment_status: 'unpaid',
              fulfilment_status: 'not_ready',
            },
          }),
        });
      });

      await page.goto('http://localhost:3000/order/d9b73f2a-7182-4912-9c1e-3f5e1823901a?token=valid-secret-token-1', {
        waitUntil: 'networkidle',
      });
      await page.waitForSelector('[data-testid="checkout-success-view"]', { timeout: 10000 });

      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const screenshotFile = `order-tracking-pending-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] /order/[id] Pending -> overflow check: ${overflow ? 'FAIL' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    // Audit 3: /order/[id] with Advance-Paid State
    console.log('\n--- Auditing: /order/[id] Advance-Paid State ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.route('**/rest/v1/rpc/get_order_by_token', async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            order: {
              ...baseOrderReceipt,
              confirmation_mode: 'advance',
              status: 'confirmed',
              payment_status: 'advance_paid',
              advance_required_paisa: 50000,
              advance_paid_paisa: 50000,
              total_paid_paisa: 50000,
              balance_due_paisa: 199900,
              fulfilment_status: 'not_ready',
            },
          }),
        });
      });

      await page.goto('http://localhost:3000/order/d9b73f2a-7182-4912-9c1e-3f5e1823901a?token=valid-secret-token-1', {
        waitUntil: 'networkidle',
      });
      await page.waitForSelector('[data-testid="advance-paid-balance-notice"]', { timeout: 10000 });

      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const screenshotFile = `order-tracking-advance-paid-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] /order/[id] Advance-Paid -> overflow check: ${overflow ? 'FAIL' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    // Audit 4: /order/[id] with Fully-Paid State
    console.log('\n--- Auditing: /order/[id] Fully-Paid State ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.route('**/rest/v1/rpc/get_order_by_token', async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            order: {
              ...baseOrderReceipt,
              status: 'paid',
              payment_status: 'paid',
              total_paid_paisa: 249900,
              balance_due_paisa: 0,
              fulfilment_status: 'ready_to_ship',
            },
          }),
        });
      });

      await page.goto('http://localhost:3000/order/d9b73f2a-7182-4912-9c1e-3f5e1823901a?token=valid-secret-token-1', {
        waitUntil: 'networkidle',
      });
      await page.waitForSelector('[data-testid="order-fully-paid-notice"]', { timeout: 10000 });

      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const screenshotFile = `order-tracking-fully-paid-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] /order/[id] Fully-Paid -> overflow check: ${overflow ? 'FAIL' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    // Audit 5: /order/[id] with Shipped State
    console.log('\n--- Auditing: /order/[id] Shipped State ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.route('**/rest/v1/rpc/get_order_by_token', async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            order: {
              ...baseOrderReceipt,
              status: 'shipped',
              payment_status: 'paid',
              total_paid_paisa: 249900,
              balance_due_paisa: 0,
              fulfilment_status: 'shipped',
              shipped_at: '2026-09-29T10:30:00Z',
              courier_partner: 'BlueDart Express',
              tracking_number: 'BLUEDART-882910472',
              notes: 'Dispatched via premium air cargo packaging',
            },
          }),
        });
      });

      await page.goto('http://localhost:3000/order/d9b73f2a-7182-4912-9c1e-3f5e1823901a?token=valid-secret-token-1', {
        waitUntil: 'networkidle',
      });
      await page.waitForSelector('[data-testid="shipment-tracking-card"]', { timeout: 10000 });

      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const screenshotFile = `order-tracking-shipped-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] /order/[id] Shipped -> overflow check: ${overflow ? 'FAIL' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    // Audit 6: /order/[id] with Expired / Cancelled State
    console.log('\n--- Auditing: /order/[id] Expired / Cancelled State ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.route('**/rest/v1/rpc/get_order_by_token', async (route) => {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({
            success: true,
            order: {
              ...baseOrderReceipt,
              status: 'expired',
              payment_status: 'unpaid',
              fulfilment_status: 'not_ready',
              hold_expires_at: '2026-09-28T12:00:00Z',
            },
          }),
        });
      });

      await page.goto('http://localhost:3000/order/d9b73f2a-7182-4912-9c1e-3f5e1823901a?token=valid-secret-token-1', {
        waitUntil: 'networkidle',
      });
      await page.waitForSelector('[data-testid="order-expired-banner"]', { timeout: 10000 });

      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const screenshotFile = `order-tracking-expired-cancelled-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] /order/[id] Expired/Cancelled -> overflow check: ${overflow ? 'FAIL' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    await browser.close();
    cleanup();

    console.log(`\n================================================================`);
    console.log(`Phase 3 Responsive & Presentation Audit: ${allPassed ? 'ALL VIEWPORTS & STATES PASSED WITH ZERO OVERFLOW' : 'FAILED'}`);
    console.log(`================================================================`);
    process.exit(allPassed ? 0 : 1);
  } catch (err) {
    console.error('Audit failed with error:', err);
    cleanup();
    process.exit(1);
  }
}

run();
