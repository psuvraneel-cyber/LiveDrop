import { chromium } from '@playwright/test';

async function testSrOnly() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 360, height: 800 } });
  await page.goto('http://localhost:3000/shop', { waitUntil: 'networkidle' });

  console.log('Before fix scrollWidth:', await page.evaluate(() => document.documentElement.scrollWidth));

  // Test 1: Add relative to boutique cards or remove sr-only
  await page.addStyleTag({
    content: `
      [data-testid="shop-boutiques-section"] a {
        position: relative !important;
      }
      .sr-only {
        position: absolute !important;
        left: 0 !important;
        top: 0 !important;
      }
    `
  });

  console.log('After position:relative + left:0 on sr-only -> scrollWidth:', await page.evaluate(() => document.documentElement.scrollWidth));

  await browser.close();
}

testSrOnly();
