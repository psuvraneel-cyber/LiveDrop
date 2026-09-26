import { chromium } from '@playwright/test';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  
  // Navigate to checkout directly
  await page.goto('http://localhost:3000/checkout', { waitUntil: 'networkidle' });
  await page.screenshot({ path: 'scratch/mobile-checkout-empty.png' });

  await browser.close();
  console.log('Checkout screenshot captured!');
})();
