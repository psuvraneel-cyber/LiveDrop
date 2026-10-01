/**
 * Layout Audit Script — captures screenshots and computed-style probes
 * for verifying the Tailwind v4 @layer base fix.
 *
 * Usage: node scripts/capture-layout-audit.mjs [before|after]
 * Requires: dev server running on http://localhost:3005
 */
import { chromium } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const phase = process.argv[2] || 'after';
const outputDir = join(__dirname, '..', 'scratch', 'layout-audit', phase);
mkdirSync(outputDir, { recursive: true });

const BASE_URL = 'http://localhost:3005';

const VIEWPORTS = [
  { width: 390, height: 844, label: '390x844' },
  { width: 1280, height: 800, label: '1280x800' },
];

const SURFACES = [
  { path: '/', label: 'home' },
  { path: '/shop', label: 'shop' },
];

async function main() {
  const browser = await chromium.launch({ headless: true });
  const results = { phase, timestamp: new Date().toISOString(), probes: {}, screenshots: [] };

  for (const vp of VIEWPORTS) {
    const context = await browser.newContext({ viewport: vp });
    const page = await context.newPage();

    for (const surface of SURFACES) {
      const url = `${BASE_URL}${surface.path}`;
      console.log(`Capturing ${surface.label} at ${vp.label}...`);

      try {
        await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });
      } catch {
        console.log(`  Warning: networkidle timeout for ${url}, proceeding with domcontentloaded`);
        try {
          await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 15000 });
        } catch (e2) {
          console.log(`  ERROR: Could not load ${url}: ${e2.message}`);
          continue;
        }
      }

      await page.waitForTimeout(2000);

      const filename = `${surface.label}_${vp.label}.png`;
      const filepath = join(outputDir, filename);
      await page.screenshot({ path: filepath, fullPage: true });
      results.screenshots.push(filename);
      console.log(`  Screenshot saved: ${filename}`);

      // Computed style probes
      if (surface.path === '/shop') {
        try {
          const shopProbe = await page.evaluate(() => {
            const main = document.querySelector('main');
            if (!main) return { error: 'no main element' };
            const style = getComputedStyle(main);
            return {
              paddingLeft: style.paddingLeft,
              paddingRight: style.paddingRight,
              marginLeft: style.marginLeft,
              marginRight: style.marginRight,
              maxWidth: style.maxWidth,
            };
          });
          results.probes[`shop_main_${vp.label}`] = shopProbe;
          console.log(`  /shop main probe:`, shopProbe);
        } catch (e) {
          console.log(`  Probe error: ${e.message}`);
        }
      }

      if (surface.path === '/') {
        try {
          const homeProbe = await page.evaluate(() => {
            // Check horizontal overflow
            const hasOverflow = document.documentElement.scrollWidth > window.innerWidth;

            // Category rail first item position
            const railItem = document.querySelector('[role="tablist"] button');
            const railRect = railItem ? railItem.getBoundingClientRect() : null;

            // Hero card position
            const heroSection = document.querySelector('#live-drops');
            const heroRect = heroSection ? heroSection.getBoundingClientRect() : null;

            // Section title position
            const sectionTitle = document.querySelector('#featured-products h2, #featured-products [class*="SectionTitle"]');
            const titleRect = sectionTitle ? sectionTitle.getBoundingClientRect() : null;

            return {
              hasHorizontalOverflow: hasOverflow,
              scrollWidth: document.documentElement.scrollWidth,
              viewportWidth: window.innerWidth,
              railFirstItemLeft: railRect ? railRect.left : null,
              heroLeft: heroRect ? heroRect.left : null,
              sectionTitleLeft: titleRect ? titleRect.left : null,
            };
          });
          results.probes[`home_alignment_${vp.label}`] = homeProbe;
          console.log(`  / home alignment probe:`, homeProbe);
        } catch (e) {
          console.log(`  Probe error: ${e.message}`);
        }
      }
    }

    await context.close();
  }

  await browser.close();

  const reportPath = join(outputDir, 'probe-results.json');
  writeFileSync(reportPath, JSON.stringify(results, null, 2));
  console.log(`\nResults saved to: ${reportPath}`);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
