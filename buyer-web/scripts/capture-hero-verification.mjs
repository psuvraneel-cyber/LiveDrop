import { chromium } from 'playwright';
import path from 'path';

const outDir = 'C:/Users/Sauvraneel Paul/.gemini/antigravity/brain/428e0571-33db-42f9-9617-830935cacb38';

const viewports = [
  { name: 'mobile_390x844', width: 390, height: 844 },
  { name: 'mobile_412x915', width: 412, height: 915 },
  { name: 'mobile_430x932', width: 430, height: 932 },
  { name: 'desktop_1440x900', width: 1440, height: 900 },
];

async function capture() {
  const browser = await chromium.launch();
  for (const vp of viewports) {
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();
    await page.goto('http://localhost:3005', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);

    // Capture hero element specifically
    const heroLocator = page.locator('#live-drops');
    if (await heroLocator.isVisible()) {
      const heroShotPath = path.join(outDir, `verify_hero_${vp.name}.png`);
      await heroLocator.screenshot({ path: heroShotPath });
      console.log(`Saved hero element: ${heroShotPath}`);
    }

    // Capture viewport top fold
    const viewportShotPath = path.join(outDir, `verify_fold_${vp.name}.png`);
    await page.screenshot({ path: viewportShotPath, fullPage: false });
    console.log(`Saved fold: ${viewportShotPath}`);

    await context.close();
  }
  await browser.close();
  console.log('Capture completed successfully!');
}

capture().catch((err) => {
  console.error(err);
  process.exit(1);
});
