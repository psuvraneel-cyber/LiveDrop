import { chromium } from 'playwright';
import path from 'path';
import fs from 'fs';

const artifactDir = 'C:/Users/Sauvraneel Paul/.gemini/antigravity/brain/428e0571-33db-42f9-9617-830935cacb38';

const viewports = [
  { name: 'mobile_390x844', width: 390, height: 844 },
  { name: 'desktop_1440x900', width: 1440, height: 900 },
  { name: 'desktop_1600x900', width: 1600, height: 900 },
];

async function verify() {
  const browser = await chromium.launch();
  const report = {};

  for (const vp of viewports) {
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();

    console.log(`Auditing viewport ${vp.name} (${vp.width}x${vp.height})...`);
    await page.goto('http://localhost:3005', { waitUntil: 'networkidle' });
    await page.waitForTimeout(1000);

    // 1. Page-level Metrics
    const pageMetrics = await page.evaluate(() => ({
      innerWidth: window.innerWidth,
      clientWidth: document.documentElement.clientWidth,
      scrollWidth: document.documentElement.scrollWidth,
      scrollHeight: document.documentElement.scrollHeight,
      hasHorizontalOverflow: document.documentElement.scrollWidth > window.innerWidth,
      overflowDelta: document.documentElement.scrollWidth - window.innerWidth,
    }));

    // 2. Elements measurements
    const elements = await page.evaluate(() => {
      const getElementBox = (el) => {
        if (!el) return null;
        const rect = el.getBoundingClientRect();
        const cs = window.getComputedStyle(el);
        return {
          visible: rect.width > 0 && rect.height > 0 && cs.display !== 'none' && cs.visibility !== 'hidden',
          width: Math.round(rect.width),
          height: Math.round(rect.height),
          top: Math.round(rect.top),
          left: Math.round(rect.left),
          display: cs.display,
          paddingLeft: cs.paddingLeft,
          paddingRight: cs.paddingRight,
        };
      };

      const getBox = (sel) => {
        return getElementBox(document.querySelector(sel));
      };

      const liveBadgeEl = Array.from(document.querySelectorAll('span')).find(
        (el) => el.textContent && el.textContent.trim().includes('LIVE NOW')
      );

      const getAllBoxes = (sel) => {
        return Array.from(document.querySelectorAll(sel)).map((el) => {
          const rect = el.getBoundingClientRect();
          const cs = window.getComputedStyle(el);
          return {
            width: Math.round(rect.width),
            height: Math.round(rect.height),
            visible: rect.width > 0 && rect.height > 0 && cs.display !== 'none',
          };
        });
      };

      return {
        heroWrap: getBox('.ld-home-hero-wrap'),
        categoryRail: getBox('section[aria-label="Product Categories"]'),
        mainContainer: getBox('.ld-home-main'),
        footer: getBox('footer'),
        footerNav: getBox('footer nav'),
        bottomDock: getBox('[data-testid="mobile-bottom-dock"]'),
        liveNowBadge: getElementBox(liveBadgeEl),
        heroTextContainer: getBox('.ld-hero-inner-content > div'),
        boutiqueCards: getAllBoxes('[data-testid^="boutique-card-"]'),
        boutiqueVisitBtns: getAllBoxes('[data-testid^="visit-boutique-"]'),
        boutiqueWaBtns: getAllBoxes('[data-testid^="whatsapp-store-"]'),
      };
    });

    report[vp.name] = { pageMetrics, elements };

    // Capture Top Screenshot
    const topPath = path.join(artifactDir, `verify_${vp.name}_top.png`);
    await page.screenshot({ path: topPath, fullPage: false });
    console.log(`Saved top screenshot: ${topPath}`);

    // Scroll to bottom and capture Bottom Screenshot
    await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
    await page.waitForTimeout(600);
    const bottomPath = path.join(artifactDir, `verify_${vp.name}_bottom.png`);
    await page.screenshot({ path: bottomPath, fullPage: false });
    console.log(`Saved bottom screenshot: ${bottomPath}`);

    await context.close();
  }

  await browser.close();
  console.log('\n=== GEOMETRIC VERIFICATION REPORT ===');
  console.log(JSON.stringify(report, null, 2));

  fs.writeFileSync(
    path.join(artifactDir, 'verification_metrics.json'),
    JSON.stringify(report, null, 2)
  );
}

verify().catch((err) => {
  console.error('Verification failed:', err);
  process.exit(1);
});
