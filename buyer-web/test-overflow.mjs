import { chromium } from '@playwright/test';

async function compareHomeAndShop() {
  const browser = await chromium.launch({ headless: true });
  
  const pageHome = await browser.newPage({ viewport: { width: 360, height: 800 } });
  await pageHome.goto('http://localhost:3000/', { waitUntil: 'networkidle' });
  const homeBoutiqueContainer = await pageHome.evaluate(() => {
    const el = document.querySelector('[data-testid="boutiques-rail"]');
    if (!el) return null;
    const parent = el.parentElement;
    return {
      elClasses: el.className,
      elStyle: window.getComputedStyle(el).overflowX,
      parentTag: parent?.tagName,
      parentClasses: parent?.className,
      parentStyle: parent ? window.getComputedStyle(parent).overflowX : null
    };
  });
  console.log('Home boutique container:', homeBoutiqueContainer);
  await pageHome.close();

  const pageShop = await browser.newPage({ viewport: { width: 360, height: 800 } });
  await pageShop.goto('http://localhost:3000/shop', { waitUntil: 'networkidle' });
  const shopBoutiqueContainer = await pageShop.evaluate(() => {
    const el = document.querySelector('[data-testid="shop-boutiques-section"] > div');
    if (!el) return null;
    const parent = el.parentElement;
    return {
      elClasses: el.className,
      elStyle: window.getComputedStyle(el).overflowX,
      parentTag: parent?.tagName,
      parentClasses: parent?.className,
      parentStyle: parent ? window.getComputedStyle(parent).overflowX : null
    };
  });
  console.log('Shop boutique container:', shopBoutiqueContainer);
  await pageShop.close();

  await browser.close();
}

compareHomeAndShop();
