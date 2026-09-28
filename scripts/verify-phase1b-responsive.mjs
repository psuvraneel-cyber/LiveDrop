/**
 * LiveDrop — Automated Phase 1B Responsive Viewport & Overflow Auditor
 *
 * Spawns mock gateway (54321) + Next.js (3000), checks:
 * 1. /[storeSlug] (/mothers-boutique)
 * 2. /drop/[slug] (/drop/mothers-boutique)
 * 3. / (Home)
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
  const envLocalTmp = path.resolve(buyerWebDir, '.env.local.resp1btmp');
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
    nextServerProcess = spawn('npx', ['next', 'start', '-p', '3000'], {
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

    const routes = [
      { path: '/mothers-boutique', label: 'storefront' },
      { path: '/drop/mothers-boutique', label: 'drop' },
      { path: '/', label: 'home' },
    ];

    let allPassed = true;

    for (const route of routes) {
      console.log(`\n--- Auditing Route: ${route.path} (${route.label}) ---`);
      for (const vp of viewports) {
        const page = await browser.newPage({
          viewport: { width: vp.width, height: vp.height },
        });

        await page.goto(`http://localhost:3000${route.path}`, { waitUntil: 'networkidle' });

        const overflowInfo = await page.evaluate(() => {
          const docElem = document.documentElement;
          const body = document.body;
          return {
            windowInnerWidth: window.innerWidth,
            docScrollWidth: docElem.scrollWidth,
            docClientWidth: docElem.clientWidth,
            bodyScrollWidth: body.scrollWidth,
            bodyClientWidth: body.clientWidth,
            hasOverflow: docElem.scrollWidth > window.innerWidth || body.scrollWidth > window.innerWidth,
          };
        });

        const screenshotFile = `${route.label}-${vp.name}.png`;
        const screenshotPath = path.join(screenshotsDir, screenshotFile);
        await page.screenshot({ path: screenshotPath, fullPage: false });

        const status = overflowInfo.hasOverflow ? 'FAIL (OVERFLOW)' : 'PASS';
        if (overflowInfo.hasOverflow) allPassed = false;

        console.log(
          `  [${vp.name}] ${vp.width}x${vp.height} -> docWidth=${overflowInfo.docScrollWidth}/${overflowInfo.docClientWidth} ` +
          `status: ${status} (saved: ${screenshotFile})`
        );

        await page.close();
      }
    }

    await browser.close();
    cleanup();

    console.log(`\n================================================================`);
    console.log(`Result: ${allPassed ? 'ALL VIEWPORTS AND ROUTES PASSED (0 horizontal overflow)' : 'FAILED'}`);
    console.log(`================================================================`);
    process.exit(allPassed ? 0 : 1);
  } catch (err) {
    console.error('Audit failed with error:', err);
    cleanup();
    process.exit(1);
  }
}

run();
