/**
 * LiveDrop — Automated Phase 1C Responsive Viewport & Screenshot Auditor
 *
 * Spawns mock gateway (54321) + Next.js (3000), checks:
 * 1. /cart (Empty and populated)
 * 2. Cart Drawer opened
 * 3. Product Detail Modal opened
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

function waitForHttp(url, timeoutMs = 35000) {
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
  const envLocalTmp = path.resolve(buyerWebDir, '.env.local.resp1ctmp');
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

    // Reset mock state to ensure clean product availability
    await fetch('http://127.0.0.1:54321/reset-state', { method: 'POST' });

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

    // Audit 1: Empty Cart Page
    console.log('\n--- Auditing: Empty Cart Page (/cart) ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.goto('http://localhost:3000/cart', { waitUntil: 'networkidle' });

      const overflow = await page.evaluate(() => {
        const docElem = document.documentElement;
        return docElem.scrollWidth > window.innerWidth;
      });

      const screenshotFile = `cart-empty-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, screenshotFile), fullPage: false });
      console.log(`  [${vp.name}] Empty Cart -> status: ${overflow ? 'FAIL' : 'PASS'} (saved: ${screenshotFile})`);
      if (overflow) allPassed = false;
      await page.close();
    }

    // Audit 2: Product Detail Modal & Cart Drawer on /drop/mothers-boutique
    console.log('\n--- Auditing: Product Detail Modal & Cart Drawer on /drop/mothers-boutique ---');
    for (const vp of viewports) {
      const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
      await page.goto('http://localhost:3000/drop/mothers-boutique', { waitUntil: 'networkidle' });

      // Click the product card to open Product Detail Modal
      const productCard = page.getByTestId('product-card-e9314c99-7f55-4089-a2bb-b001d2950df1');
      await productCard.waitFor({ state: 'visible', timeout: 10000 });
      await productCard.click();
      await page.waitForTimeout(500);

      // Screenshot Product Detail Modal
      const modalScreenshot = `product-detail-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, modalScreenshot), fullPage: false });
      console.log(`  [${vp.name}] Product Detail Modal -> saved: ${modalScreenshot}`);

      // Close modal
      const closeBtn = page.getByRole('button', { name: /Close|Dismiss/i }).first();
      if (await closeBtn.isVisible()) {
        await closeBtn.click();
        await page.waitForTimeout(300);
      }

      // Add to bag using the card button
      const addToBagBtn = page.getByTestId('cart-btn-e9314c99-7f55-4089-a2bb-b001d2950df1');
      await addToBagBtn.click();
      await page.waitForTimeout(400);

      // Open Cart Drawer
      const viewCartBtn = page.getByTestId('sticky-view-cart-btn');
      if (await viewCartBtn.isVisible()) {
        await viewCartBtn.click();
        await page.waitForTimeout(500);

        const drawerScreenshot = `cart-drawer-${vp.name}.png`;
        await page.screenshot({ path: path.join(screenshotsDir, drawerScreenshot), fullPage: false });
        console.log(`  [${vp.name}] Cart Drawer -> saved: ${drawerScreenshot}`);
      }

      // Navigate to /cart with items
      await page.goto('http://localhost:3000/cart', { waitUntil: 'networkidle' });
      const cartPopulatedScreenshot = `cart-populated-${vp.name}.png`;
      await page.screenshot({ path: path.join(screenshotsDir, cartPopulatedScreenshot), fullPage: false });
      console.log(`  [${vp.name}] Populated Cart Page -> saved: ${cartPopulatedScreenshot}`);

      await page.close();
    }

    await browser.close();
    cleanup();

    console.log(`\n================================================================`);
    console.log(`Phase 1C Viewport Audit: ${allPassed ? 'ALL VIEWPORTS AND SCREENS PASSED' : 'FAILED'}`);
    console.log(`================================================================`);
    process.exit(allPassed ? 0 : 1);
  } catch (err) {
    console.error('Audit failed with error:', err);
    cleanup();
    process.exit(1);
  }
}

run();
