import { chromium } from 'playwright';

const urls = [
  { name: 'Live Vercel', url: 'https://livedrop-in.vercel.app/' },
];

const viewports = [
  { name: 'mobile_390x844', width: 390, height: 844 },
  { name: 'mobile_412x915', width: 412, height: 915 },
  { name: 'mobile_360x800', width: 360, height: 800 },
];

const selectors = [
  { key: 'header', selector: 'header, [data-testid="luxury-header"], [data-testid="global-buyer-header"]' },
  { key: 'hero', selector: '#live-drops, [data-testid="live-drop-hero"], [data-testid="spotlight-hero"]' },
  { key: 'hero_content', selector: '#live-drops > div.relative, [data-testid="live-drop-hero"] > div.relative, [data-testid="spotlight-hero"] > div.relative' },
  { key: 'category_rail', selector: '[data-testid="category-chips-rail"], section[aria-label="Product Categories"]' },
  { key: 'featured_heading', selector: 'section[aria-label="Featured Pieces"] h2, h2:has-text("Featured Pieces")' },
  { key: 'product_grid', selector: '[data-testid="featured-pieces-grid"], section[aria-label="Featured Pieces"] .grid' },
  { key: 'product_card_1', selector: '[data-testid^="product-card-"], section[aria-label="Featured Pieces"] article' },
  { key: 'boutique_section', selector: '[data-testid="boutiques-directory-section"], section[aria-label="Boutique Directory"]' },
  { key: 'trust_strip', selector: '[data-testid="trust-strip"], section[aria-label="Trust Signals"]' },
  { key: 'footer', selector: 'footer' },
  { key: 'bottom_nav', selector: '[data-testid="mobile-bottom-dock"], nav[aria-label="Mobile Bottom Navigation"]' },
];

async function measure() {
  const browser = await chromium.launch();
  const results = {};

  for (const site of urls) {
    results[site.name] = {};
    for (const vp of viewports) {
      const context = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        deviceScaleFactor: 2,
      });
      const page = await context.newPage();
      try {
        console.log(`Navigating to ${site.url} at ${vp.name}...`);
        await page.goto(site.url, { waitUntil: 'networkidle', timeout: 30000 });
        await page.waitForTimeout(1500);

        const pageMetrics = await page.evaluate(() => ({
          innerWidth: window.innerWidth,
          clientWidth: document.documentElement.clientWidth,
          scrollWidth: document.documentElement.scrollWidth,
          scrollHeight: document.documentElement.scrollHeight,
          hasHorizontalOverflow: document.documentElement.scrollWidth > window.innerWidth,
          overflowDelta: document.documentElement.scrollWidth - window.innerWidth,
        }));

        const elements = {};
        for (const sel of selectors) {
          const loc = page.locator(sel.selector).first();
          if (await loc.isVisible()) {
            const box = await loc.boundingBox();
            const computed = await loc.evaluate((el) => {
              const cs = window.getComputedStyle(el);
              return {
                paddingTop: cs.paddingTop,
                paddingRight: cs.paddingRight,
                paddingBottom: cs.paddingBottom,
                paddingLeft: cs.paddingLeft,
                marginTop: cs.marginTop,
                marginRight: cs.marginRight,
                marginBottom: cs.marginBottom,
                marginLeft: cs.marginLeft,
                lineHeight: cs.lineHeight,
                fontSize: cs.fontSize,
                gap: cs.gap,
              };
            });
            elements[sel.key] = { box, computed };
          } else {
            elements[sel.key] = null;
          }
        }

        results[site.name][vp.name] = { pageMetrics, elements };
      } catch (err) {
        console.error(`Error inspecting ${site.name} at ${vp.name}:`, err.message);
        results[site.name][vp.name] = { error: err.message };
      } finally {
        await context.close();
      }
    }
  }

  await browser.close();
  console.log(JSON.stringify(results, null, 2));
}

measure().catch(console.error);
