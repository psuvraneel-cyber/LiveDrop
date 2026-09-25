import { chromium } from 'playwright';
import path from 'path';

const outDir = 'C:/Users/Sauvraneel Paul/.gemini/antigravity-ide/brain/246e4836-5bcc-4382-88f3-881f57db7b43';

const viewports = [
  { name: 'mobile_360x800', width: 360, height: 800 },
  { name: 'mobile_375x812', width: 375, height: 812 },
  { name: 'mobile_390x844', width: 390, height: 844 },
  { name: 'mobile_412x915', width: 412, height: 915 },
  { name: 'mobile_430x932', width: 430, height: 932 },
  { name: 'desktop_1280x800', width: 1280, height: 800 },
  { name: 'desktop_1440x900', width: 1440, height: 900 },
];

async function run() {
  const browser = await chromium.launch();
  
  for (const vp of viewports) {
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();

    // 1. Capture Homepage
    await page.goto('http://localhost:3005', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    const homeScreenshotPath = path.join(outDir, `verify_${vp.name}_home.png`);
    await page.screenshot({ path: homeScreenshotPath, fullPage: false });
    console.log(`Saved: ${homeScreenshotPath}`);

    // If mobile 390x844, also capture scrolled state
    if (vp.name === 'mobile_390x844') {
      await page.evaluate(() => window.scrollBy(0, 350));
      await page.waitForTimeout(500);
      const scrolledPath = path.join(outDir, `verify_${vp.name}_scrolled.png`);
      await page.screenshot({ path: scrolledPath, fullPage: false });
      console.log(`Saved scrolled: ${scrolledPath}`);

      // Open Cart Drawer
      const bagButton = page.locator('[data-testid="header-cart-btn"], [aria-label*="Bag"], [aria-label*="Cart"]').first();
      if (await bagButton.isVisible()) {
        await bagButton.click();
        await page.waitForTimeout(600);
        const cartDrawerPath = path.join(outDir, `verify_${vp.name}_cart_drawer.png`);
        await page.screenshot({ path: cartDrawerPath, fullPage: false });
        console.log(`Saved cart drawer: ${cartDrawerPath}`);
      }
    }

    // 2. Capture /shop
    await page.goto('http://localhost:3005/shop', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    const shopScreenshotPath = path.join(outDir, `verify_${vp.name}_shop.png`);
    await page.screenshot({ path: shopScreenshotPath, fullPage: false });
    console.log(`Saved: ${shopScreenshotPath}`);

    // 3. Capture /cart
    await page.goto('http://localhost:3005/cart', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    const cartScreenshotPath = path.join(outDir, `verify_${vp.name}_cart.png`);
    await page.screenshot({ path: cartScreenshotPath, fullPage: false });
    console.log(`Saved: ${cartScreenshotPath}`);

    await context.close();
  }

  await browser.close();
  console.log('All screenshots captured successfully!');
}

run().catch(err => {
  console.error(err);
  process.exit(1);
});
