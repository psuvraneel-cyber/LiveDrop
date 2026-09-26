import { chromium } from '@playwright/test';

(async () => {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  await page.goto('http://localhost:3000', { waitUntil: 'networkidle' });

  // Click on the first product card
  const firstCard = page.locator('[data-testid^="product-card-"]').first();
  await firstCard.click();
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'scratch/mobile-product-modal.png' });

  // Click 'Add to Bag' in the modal
  const addBtn = page.locator('[data-testid^="sheet-add-to-cart-"]').first();
  if (await addBtn.isVisible()) {
    await addBtn.click();
    await page.waitForTimeout(500);
  }

  // Close modal and click Bag tab in bottom dock
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  const bagTab = page.locator('[data-testid="dock-bag-tab"]');
  await bagTab.click();
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'scratch/mobile-cart-drawer.png' });

  await browser.close();
  console.log('Modal and Drawer captured successfully!');
})();
