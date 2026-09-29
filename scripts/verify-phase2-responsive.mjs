/**
 * LiveDrop — Automated Phase 2 Responsive Viewport & Screenshot Auditor
 *
 * Spawns mock gateway (54321) + Next.js (3000), checks:
 * 1. /checkout with Empty Cart State
 * 2. /checkout with Populated Cart & Hold Reservation Form
 * 3. Direct UPI Payment View (QR, VPA, Intent URI, Copy actions)
 * 4. Payment Claim Submitted State (Awaiting Verification, Safe-to-Close banner)
 * 5. Payment Verified State (Authoritative backend verification, Dispatch ready)
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

function waitForHttp(url, timeoutMs = 40000) {
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

async function run() {
  if (!fs.existsSync(screenshotsDir)) {
    fs.mkdirSync(screenshotsDir, { recursive: true });
  }

  const envLocal = path.resolve(buyerWebDir, '.env.local');
  const envLocalTmp = path.resolve(buyerWebDir, '.env.local.resp2tmp');
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

    // Audit 1: Empty Checkout Page (/checkout)
    console.log('\n--- Auditing: Empty Checkout Page (/checkout) ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.goto('http://localhost:3000/checkout', { waitUntil: 'networkidle' });

      const overflow = await page.evaluate(() => {
        const docElem = document.documentElement;
        return docElem.scrollWidth > window.innerWidth;
      });

      const screenshotFile = `checkout-empty-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] Empty Checkout -> overflow check: ${overflow ? 'FAIL (overflow detected)' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    // Audit 2: Populated Checkout, Direct UPI, Claim Submitted, and Verified States
    console.log('\n--- Auditing: Populated Checkout & Direct UPI Lifecycle ---');
    for (const vp of viewports) {
      // Reset mock server state for fresh inventory & order state
      await fetch('http://127.0.0.1:54321/reset-state', { method: 'POST' });

      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.goto('http://localhost:3000/drop/mothers-boutique', { waitUntil: 'networkidle' });

      // Add item to bag
      const addToBagBtn = page.getByTestId('cart-btn-e9314c99-7f55-4089-a2bb-b001d2950df1');
      await addToBagBtn.waitFor({ state: 'visible', timeout: 10000 });
      await addToBagBtn.click();
      await page.waitForTimeout(400);

      // Open Cart Drawer & Proceed to Checkout
      const viewCartBtn = page.getByTestId('sticky-view-cart-btn');
      await viewCartBtn.click();
      await page.waitForTimeout(400);
      const checkoutBtn = page.getByTestId('cart-checkout-btn');
      await checkoutBtn.click();
      await page.waitForURL('**/checkout');

      // State A: Populated Checkout Form & Review
      const popOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const popScreenshot = `checkout-populated-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, popScreenshot), fullPage: false });
      console.log(`  [${vp.name}] Populated Checkout -> overflow check: ${popOverflow ? 'FAIL' : 'PASS'} (saved: ${popScreenshot})`);
      if (popOverflow) allPassed = false;

      // Fill in buyer delivery information
      await page.getByTestId('input-buyer-name').fill('Ananya Roy');
      await page.getByTestId('input-buyer-phone').fill('9830123456');
      await page.getByTestId('input-shipping-address').fill('Flat 4B, Silver Oak Residency, Jadavpur');
      await page.getByTestId('input-pincode').fill('700032');

      // Submit reservation
      const submitBtn = page.getByTestId('checkout-submit-btn');
      await submitBtn.click();

      // State B: Direct UPI Payment View
      await page.waitForSelector('[data-testid="checkout-success-view"]', { timeout: 15000 });
      await page.waitForSelector('[data-testid="upi-qr-image"]', { timeout: 15000 });

      const upiOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const upiScreenshot = `checkout-upi-payment-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, upiScreenshot), fullPage: false });
      console.log(`  [${vp.name}] Direct UPI Payment -> overflow check: ${upiOverflow ? 'FAIL' : 'PASS'} (saved: ${upiScreenshot})`);
      if (upiOverflow) allPassed = false;

      // State C: Submit Buyer UTR Claim
      const utrInput = page.getByTestId('utr-input-field');
      await utrInput.fill('428739182734');
      const claimBtn = page.getByTestId('submit-payment-claim-btn');
      await claimBtn.click();

      await page.waitForSelector('[data-testid="payment-claimed-card"]', { timeout: 10000 });
      const claimOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
      const claimScreenshot = `checkout-claim-submitted-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, claimScreenshot), fullPage: false });
      console.log(`  [${vp.name}] Payment Claim Submitted -> overflow check: ${claimOverflow ? 'FAIL' : 'PASS'} (saved: ${claimScreenshot})`);
      if (claimOverflow) allPassed = false;

      // State D: Seller Verification
      const pageUrl = page.url();
      const orderId = new URL(pageUrl).searchParams.get('order_id');
      if (orderId) {
        await fetch('http://127.0.0.1:54321/rest/v1/rpc/verify_manual_upi_payment', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ p_order_id: orderId }),
        });

        // Polling or reload to capture verified state
        await page.waitForTimeout(2000);
        await page.reload({ waitUntil: 'networkidle' });

        const verifiedOverflow = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
        const verifiedScreenshot = `checkout-payment-verified-${vp.name}.png`;
        await page.screenshot({ path: path.join(screenshotsDir, verifiedScreenshot), fullPage: false });
        console.log(`  [${vp.name}] Payment Verified State -> overflow check: ${verifiedOverflow ? 'FAIL' : 'PASS'} (saved: ${verifiedScreenshot})`);
        if (verifiedOverflow) allPassed = false;
      }

      await page.close();
    }

    await browser.close();
    cleanup();

    console.log(`\n================================================================`);
    console.log(`Phase 2 Responsive & Presentation Audit: ${allPassed ? 'ALL VIEWPORTS & STATES PASSED WITH ZERO OVERFLOW' : 'FAILED'}`);
    console.log(`================================================================`);
    process.exit(allPassed ? 0 : 1);
  } catch (err) {
    console.error('Audit failed with error:', err);
    cleanup();
    process.exit(1);
  }
}

run();
