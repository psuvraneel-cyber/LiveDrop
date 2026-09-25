import pkg from '../buyer-web/node_modules/@playwright/test/index.js';
const { chromium } = pkg;
import path from 'path';

const ARTIFACT_DIR = 'C:/Users/Sauvraneel Paul/.gemini/antigravity-ide/brain/246e4836-5bcc-4382-88f3-881f57db7b43';

async function main() {
  console.log('Launching browser for Final Production QA Screenshots...');
  const browser = await chromium.launch({ headless: true });

  const tasks = [
    { name: 'final_qa_home_mobile_390x844.png', url: 'http://localhost:3000', width: 390, height: 844 },
    { name: 'final_qa_home_mobile_412x915.png', url: 'http://localhost:3000', width: 412, height: 915 },
    { name: 'final_qa_home_desktop_1440x900.png', url: 'http://localhost:3000', width: 1440, height: 900 },
    { name: 'final_qa_shop_mobile_390x844.png', url: 'http://localhost:3000/shop', width: 390, height: 844 },
    { name: 'final_qa_shop_desktop_1440x900.png', url: 'http://localhost:3000/shop', width: 1440, height: 900 },
    { name: 'final_qa_checkout_mobile_390x844.png', url: 'http://localhost:3000/checkout', width: 390, height: 844 },
    { name: 'final_qa_order_tracking_mobile_390x844.png', url: 'http://localhost:3000/order', width: 390, height: 844 },
  ];

  for (const t of tasks) {
    const context = await browser.newContext({
      viewport: { width: t.width, height: t.height },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();
    console.log(`Capturing ${t.name} from ${t.url} (${t.width}x${t.height})...`);
    await page.goto(t.url, { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    const savePath = path.join(ARTIFACT_DIR, t.name);
    await page.screenshot({ path: savePath, fullPage: false });
    console.log(`Saved: ${savePath}`);
    await context.close();
  }

  // Capture Product Detail Modal on mobile 390x844
  {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();
    console.log('Capturing product detail modal...');
    await page.goto('http://localhost:3000', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);

    // Click on the first product card to open modal
    const firstCard = page.locator('article.ld-product-card').first();
    if (await firstCard.isVisible()) {
      await firstCard.click();
      await page.waitForTimeout(500);
      const modalSavePath = path.join(ARTIFACT_DIR, 'final_qa_product_detail_mobile_390x844.png');
      await page.screenshot({ path: modalSavePath });
      console.log(`Saved product detail: ${modalSavePath}`);
    } else {
      console.warn('No product card found to click for detail modal');
    }
    await context.close();
  }

  // Capture Cart Page on mobile 390x844 (/cart)
  {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();
    console.log('Capturing /cart page...');
    await page.goto('http://localhost:3000/cart', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    const cartPageSavePath = path.join(ARTIFACT_DIR, 'final_qa_cart_page_mobile_390x844.png');
    await page.screenshot({ path: cartPageSavePath });
    console.log(`Saved /cart page: ${cartPageSavePath}`);
    await context.close();
  }

  // Capture Drop Room on mobile 390x844
  {
    const context = await browser.newContext({
      viewport: { width: 390, height: 844 },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();
    console.log('Capturing drop room page...');
    await page.goto('http://localhost:3000/drop/festive-silk-handloom-collection', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);
    const dropSavePath = path.join(ARTIFACT_DIR, 'final_qa_drop_room_mobile_390x844.png');
    await page.screenshot({ path: dropSavePath });
    console.log(`Saved drop room: ${dropSavePath}`);

    // Click Add to Bag on the drop room to open Cart Drawer
    const addBtn = page.locator('button.ld-btn-add-cart-compact, button[data-testid^="cart-btn-"]').first();
    if (await addBtn.isVisible()) {
      await addBtn.click();
      await page.waitForTimeout(500);

      // Open Cart Drawer via StickyCartBar
      const viewCartBtn = page.locator('button[data-testid="sticky-view-cart-btn"]').first();
      if (await viewCartBtn.isVisible()) {
        await viewCartBtn.click();
        await page.waitForTimeout(500);
        const drawerSavePath = path.join(ARTIFACT_DIR, 'final_qa_cart_drawer_mobile_390x844.png');
        await page.screenshot({ path: drawerSavePath });
        console.log(`Saved cart drawer: ${drawerSavePath}`);
      }
    }
    await context.close();
  }

  await browser.close();
  console.log('All QA screenshots captured successfully!');
}

main().catch((err) => {
  console.error('Error during screenshot capture:', err);
  process.exit(1);
});
