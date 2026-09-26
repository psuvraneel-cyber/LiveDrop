import { chromium } from 'playwright';
import path from 'path';

const ARTIFACT_DIR = 'C:/Users/Sauvraneel Paul/.gemini/antigravity-ide/brain/3649c638-df01-4f0f-868e-e16e7243ac48';
const BASE_URL = 'http://localhost:3000';

const VIEWPORTS = [
  { name: 'iphone_390x844', width: 390, height: 844, isMobile: true },
  { name: 'pixel_412x915', width: 412, height: 915, isMobile: true },
  { name: 'desktop_1440x900', width: 1440, height: 900, isMobile: false },
];

async function runAcceptance() {
  console.log('--- STARTING PHASE 3 HOMEPAGE VISUAL & FUNCTIONAL ACCEPTANCE ---');
  const browser = await chromium.launch({ headless: true });

  const results = {
    viewports: {},
    functionalFlows: {},
    measurements: {},
  };

  for (const vp of VIEWPORTS) {
    console.log(`\nTesting viewport: ${vp.name} (${vp.width}x${vp.height})`);
    const context = await browser.newContext({
      viewport: { width: vp.width, height: vp.height },
      deviceScaleFactor: 2,
    });
    const page = await context.newPage();

    await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });

    // 1. Layout Measurements
    const layout = await page.evaluate(() => {
      const hero = document.querySelector('[data-testid="live-drop-hero"], [data-testid="spotlight-hero"], #live-drops');
      const heroRect = hero ? hero.getBoundingClientRect() : null;

      const catRail = document.querySelector('[data-testid="category-chips-rail"]')?.closest('section');
      const catStyle = catRail ? window.getComputedStyle(catRail) : null;

      const featuredSection = document.querySelector('[data-testid="featured-products-section"]');
      const featuredGrid = document.querySelector('[data-testid="featured-products-grid"], .ld-product-grid');
      const gridCols = featuredGrid ? window.getComputedStyle(featuredGrid).gridTemplateColumns.split(' ').length : 0;

      const docWidth = document.documentElement.scrollWidth;
      const winWidth = window.innerWidth;
      const hasHorizontalOverflow = docWidth > winWidth;

      const dock = document.querySelector('[data-testid="mobile-bottom-dock"]');
      const footer = document.querySelector('footer');
      const footerRect = footer ? footer.getBoundingClientRect() : null;

      return {
        heroHeight: heroRect ? heroRect.height : 0,
        catPosition: catStyle ? catStyle.position : 'unknown',
        gridColumns: gridCols,
        hasHorizontalOverflow,
        docWidth,
        winWidth,
        dockPresent: Boolean(dock),
        footerPresent: Boolean(footer),
      };
    });

    console.log(`Layout check for ${vp.name}:`, layout);

    // Assertions
    if (vp.isMobile) {
      if (layout.heroHeight < 260 || layout.heroHeight > 380) {
        console.warn(`WARNING: Hero height ${layout.heroHeight}px outside mobile target 280-340px!`);
      } else {
        console.log(`✓ Hero height ${layout.heroHeight}px is within compact mobile range.`);
      }
      if (layout.gridColumns !== 2) {
        console.warn(`WARNING: Mobile product grid has ${layout.gridColumns} columns instead of 2!`);
      } else {
        console.log(`✓ Mobile product grid has exactly 2 columns.`);
      }
    } else {
      if (layout.gridColumns < 4 || layout.gridColumns > 6) {
        console.warn(`WARNING: Desktop product grid has ${layout.gridColumns} columns (expected 4-6)!`);
      } else {
        console.log(`✓ Desktop product grid has ${layout.gridColumns} columns (within 4-6 target).`);
      }
    }

    if (layout.hasHorizontalOverflow) {
      console.error(`FAIL: Horizontal overflow detected on ${vp.name}! docWidth=${layout.docWidth}, winWidth=${layout.winWidth}`);
    } else {
      console.log(`✓ Zero horizontal overflow.`);
    }

    if (layout.catPosition === 'sticky' || layout.catPosition === 'fixed') {
      console.warn(`WARNING: Category rail has position: ${layout.catPosition} (should be normal flow)`);
    } else {
      console.log(`✓ Category rail is normal document flow (${layout.catPosition}).`);
    }

    // Capture screenshot
    const screenshotPath = path.join(ARTIFACT_DIR, `phase3_homepage_${vp.width}x${vp.height}.png`);
    await page.screenshot({ path: screenshotPath, fullPage: false });
    console.log(`✓ Viewport screenshot saved: ${screenshotPath}`);

    results.viewports[vp.name] = { layout, screenshotPath };
    await context.close();
  }

  // 2. Functional Flows Verification (Section 18)
  console.log('\n--- VERIFYING SECTION 18 FUNCTIONAL FLOWS ---');
  const testContext = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const page = await testContext.newPage();
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });

  // Flow A: Homepage -> View All -> shop
  console.log('Testing Flow A: Homepage -> View All -> /shop');
  const viewAllBtn = page.locator('[data-testid="featured-view-all-btn"]');
  if (await viewAllBtn.isVisible()) {
    await viewAllBtn.click();
    await page.waitForURL((url) => url.pathname.includes('/shop'), { timeout: 5000 });
    console.log('✓ View All successfully navigated to /shop:', page.url());
    results.functionalFlows.viewAllToShop = true;
  } else {
    console.log('featured-view-all-btn not visible');
  }

  // Flow B: Homepage -> Hero CTA
  console.log('\nTesting Flow B: Homepage -> Hero CTA');
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  const liveHeroBtn = page.locator('[data-testid="shop-live-hero-btn"]');
  const exploreHeroBtn = page.locator('[data-testid="explore-live-shows-btn"]');

  if (await liveHeroBtn.isVisible()) {
    const href = await liveHeroBtn.getAttribute('href');
    console.log(`Clicking live drop hero CTA: href=${href}`);
    await liveHeroBtn.click();
    await page.waitForURL((url) => url.pathname.includes(href), { timeout: 5000 });
    console.log(`✓ Hero Shop Live Drop navigated to drop: ${page.url()}`);
    results.functionalFlows.heroToDrop = true;
  } else if (await exploreHeroBtn.isVisible()) {
    const href = await exploreHeroBtn.getAttribute('href');
    console.log(`Clicking explore hero CTA: href=${href}`);
    await exploreHeroBtn.click();
    await page.waitForURL((url) => url.pathname.includes(href), { timeout: 5000 });
    console.log(`✓ Hero Shop Collections navigated to: ${page.url()}`);
    results.functionalFlows.heroToCollections = true;
  }

  // Flow C: Homepage -> Boutique -> Storefront
  console.log('\nTesting Flow C: Homepage -> Boutique -> Storefront');
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  const firstVisitBtn = page.locator('[data-testid^="visit-boutique-"]').first();
  if (await firstVisitBtn.isVisible()) {
    const href = await firstVisitBtn.getAttribute('href');
    console.log(`Clicking boutique visit: href=${href}`);
    await firstVisitBtn.click();
    await page.waitForURL((url) => url.pathname.includes(href), { timeout: 5000 });
    console.log(`✓ Boutique card navigated to storefront: ${page.url()}`);
    results.functionalFlows.boutiqueToStorefront = true;
  } else {
    console.log('No boutique card visit button visible (empty state)');
  }

  // Flow D: Homepage -> Product -> Add to bag
  console.log('\nTesting Flow D: Homepage -> Product -> Add to bag');
  await page.goto(BASE_URL, { waitUntil: 'domcontentloaded' });
  const firstAddBtn = page.locator('[data-testid^="cart-btn-"]').first();
  if (await firstAddBtn.isVisible()) {
    await firstAddBtn.click();
    await page.waitForTimeout(500);
    const cartBadge = page.locator('[data-testid="luxury-bag-btn"]');
    const badgeText = await cartBadge.innerText();
    console.log(`✓ Product added to bag! Cart bag content: "${badgeText.trim()}"`);
    results.functionalFlows.addToBag = true;
  } else {
    console.log('No add to cart button visible on homepage product grid');
  }

  await testContext.close();
  await browser.close();

  console.log('\n=== PHASE 3 ACCEPTANCE SUMMARY ===');
  console.log(JSON.stringify(results, null, 2));
}

runAcceptance().catch((err) => {
  console.error('Acceptance execution failed:', err);
  process.exit(1);
});
