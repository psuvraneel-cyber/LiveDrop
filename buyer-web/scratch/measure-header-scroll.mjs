import { chromium } from '@playwright/test';

async function measureHeaderScroll() {
  const browser = await chromium.launch({ headless: true });
  const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
  
  await page.goto('http://localhost:3000', { waitUntil: 'networkidle' });

  // Measure initial header state
  const initial = await page.evaluate(() => {
    const h = document.querySelector('.ld-luxury-header');
    if (!h) return null;
    const rect = h.getBoundingClientRect();
    const style = getComputedStyle(h);
    return {
      rect: { top: rect.top, height: rect.height, bottom: rect.bottom },
      position: style.position,
      top: style.top,
      transform: style.transform,
      transition: style.transition,
      classes: h.className,
    };
  });
  console.log('INITIAL HEADER STATE:', initial);

  // Simulate incremental scroll down and record class toggles and transforms
  const scrollSteps = [30, 80, 100, 120, 140, 150, 145, 140, 160, 200];
  const history = [];

  for (const y of scrollSteps) {
    await page.evaluate((scrollY) => window.scrollTo(0, scrollY), y);
    // wait a tick for scroll listener
    await page.waitForTimeout(50);
    const snap = await page.evaluate((targetY) => {
      const h = document.querySelector('.ld-luxury-header');
      if (!h) return null;
      const rect = h.getBoundingClientRect();
      const style = getComputedStyle(h);
      return {
        targetY,
        scrollY: window.scrollY,
        classes: h.className,
        rectTop: rect.top,
        transform: style.transform,
      };
    }, y);
    history.push(snap);
  }

  console.log('SCROLL HISTORY:', JSON.stringify(history, null, 2));

  await browser.close();
}

measureHeaderScroll().catch(console.error);
