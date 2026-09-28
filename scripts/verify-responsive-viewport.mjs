/**
 * LiveDrop — Automated Responsive Viewport & Horizontal Overflow Auditor
 *
 * Launches Next.js standalone, opens headless Chromium at:
 * - 360px (Small Android / Galaxy S8)
 * - 375px (iPhone SE / iPhone Mini)
 * - 390px (iPhone 12/13/14 Baseline)
 * - 412px (Samsung Galaxy S20 / Pixel 7)
 * - 430px (iPhone 14/15 Pro Max)
 * - 1280px (Desktop Wide)
 *
 * Verifies:
 * 1. Zero horizontal overflow (scrollWidth <= clientWidth).
 * 2. Captures visual evidence screenshots to artifact directory.
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

function waitForHttp(url, timeoutMs = 20000) {
  const startTime = Date.now();
  return new Promise((resolve, reject) => {
    const check = () => {
      http.get(url, (res) => {
        if (res.statusCode && res.statusCode < 500) resolve();
        else retry();
      }).on('error', retry);
    };
    const retry = () => {
      if (Date.now() - startTime > timeoutMs) reject(new Error(`Timeout waiting for ${url}`));
      else setTimeout(check, 400);
    };
    check();
  });
}

async function run() {
  if (!fs.existsSync(screenshotsDir)) {
    fs.mkdirSync(screenshotsDir, { recursive: true });
  }

  console.log('Starting Next.js server on port 3000 for responsive check...');
  const nextServer = spawn('npx', ['next', 'start', '-p', '3000'], {
    cwd: buyerWebDir,
    stdio: 'pipe',
    shell: true,
  });

  try {
    await waitForHttp('http://localhost:3000', 25000);
    console.log('Next.js server is ready.');

    const browser = await chromium.launch({ headless: true });
    const viewports = [
      { name: 'mobile-360px', width: 360, height: 740 },
      { name: 'mobile-375px', width: 375, height: 667 },
      { name: 'mobile-390px', width: 390, height: 844 },
      { name: 'mobile-412px', width: 412, height: 915 },
      { name: 'mobile-430px', width: 430, height: 932 },
      { name: 'desktop-1280px', width: 1280, height: 800 },
    ];

    const results = [];

    for (const vp of viewports) {
      const page = await browser.newPage({
        viewport: { width: vp.width, height: vp.height },
      });

      await page.goto('http://localhost:3000', { waitUntil: 'networkidle' });

      // Check horizontal overflow
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

      const screenshotPath = path.join(screenshotsDir, `homepage-${vp.name}.png`);
      await page.screenshot({ path: screenshotPath, fullPage: false });

      console.log(
        `Viewport ${vp.name} (${vp.width}x${vp.height}): ` +
        `scrollWidth=${overflowInfo.docScrollWidth}, clientWidth=${overflowInfo.docClientWidth} ` +
        `-> Overflow: ${overflowInfo.hasOverflow ? 'FAIL' : 'PASS'}`
      );

      results.push({ ...vp, ...overflowInfo });
      await page.close();
    }

    await browser.close();

    const allPassed = results.every((r) => !r.hasOverflow);
    console.log(`\nResponsive audit completed: ${allPassed ? 'ALL VIEWPORTS PASSED (0 overflow)' : 'FAILED'}`);
    process.exit(allPassed ? 0 : 1);
  } finally {
    if (nextServer && nextServer.pid) {
      try {
        process.kill(nextServer.pid);
      } catch {}
    }
  }
}

run().catch((err) => {
  console.error('Error during responsive verification:', err);
  process.exit(1);
});
