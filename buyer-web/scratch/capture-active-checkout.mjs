import { chromium } from '@playwright/test';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });

  // First go to homepage
  await page.goto('http://localhost:3000', { waitUntil: 'networkidle' });

  // Inject a valid cart item into localStorage
  await page.evaluate(() => {
    const cartData = {
      version: 1,
      dropId: 'd0000000-0000-0000-0000-000000000001',
      items: [
        {
          productId: 'p0000000-0000-0000-0000-000000000001',
          dropId: 'd0000000-0000-0000-0000-000000000001',
          code: '#A01',
          title: 'Banarasi Katan Silk Saree',
          pricePaisa: 245000,
          imageUrl: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=600&q=80',
          size: 'Free Size',
          addedAt: Date.now(),
        }
      ],
      orderNote: '',
      updatedAt: Date.now(),
    };
    localStorage.setItem('livedrop_buyer_cart_v1', JSON.stringify(cartData));
  });

  // Navigate to checkout
  await page.goto('http://localhost:3000/checkout', { waitUntil: 'networkidle' });
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'scratch/mobile-checkout-active.png', fullPage: true });

  await browser.close();
  console.log('Active checkout captured!');
})();
