import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const BASE_URL = 'http://localhost:3000';
const VIEWPORTS = [
  { name: '360x800 (Small Mobile)', width: 360, height: 800, isMobile: true },
  { name: '375x812 (iPhone Mini)', width: 375, height: 812, isMobile: true },
  { name: '390x844 (iPhone Standard)', width: 390, height: 844, isMobile: true },
  { name: '412x915 (Android Flagship)', width: 412, height: 915, isMobile: true },
  { name: '430x932 (iPhone Pro Max)', width: 430, height: 932, isMobile: true },
  { name: '1280x800 (Desktop Laptop)', width: 1280, height: 800, isMobile: false },
  { name: '1440x900 (Desktop Large)', width: 1440, height: 900, isMobile: false },
];

async function runAcceptance() {
  console.log('=== LIVE DROP PHASE 2 ACCEPTANCE & STABILITY VERIFICATION ===\n');
  const browser = await chromium.launch({ headless: true });
  const results = {
    viewports: [],
    scrollStability: null,
    routeCoverage: [],
    drawers: [],
  };

  const screenshotsDir = path.resolve('scratch/screenshots');
  fs.mkdirSync(screenshotsDir, { recursive: true });

  // ---------------------------------------------------------------------------
  // 1. MULTI-VIEWPORT VERIFICATION
  // ---------------------------------------------------------------------------
  console.log('--- 1. Multi-Viewport Acceptance Tests ---');
  for (const vp of VIEWPORTS) {
    const page = await browser.newPage({ viewport: { width: vp.width, height: vp.height } });
    await page.goto(`${BASE_URL}/`, { waitUntil: 'networkidle' });

    const data = await page.evaluate((isMobile) => {
      const header = document.querySelector('header');
      const headers = document.querySelectorAll('header');
      const dock = document.querySelector('.ld-bottom-dock');
      const doc = document.documentElement;

      const headerRect = header ? header.getBoundingClientRect() : null;
      const dockRect = dock ? dock.getBoundingClientRect() : null;

      const hasHorizontalOverflow = doc.scrollWidth > window.innerWidth;
      const headerZIndex = header ? window.getComputedStyle(header).zIndex : null;
      const dockZIndex = dock ? window.getComputedStyle(dock).zIndex : null;

      return {
        headerCount: headers.length,
        headerHeight: headerRect ? Math.round(headerRect.height) : 0,
        headerTop: headerRect ? Math.round(headerRect.top) : 0,
        headerZIndex,
        hasHorizontalOverflow,
        scrollWidth: doc.scrollWidth,
        innerWidth: window.innerWidth,
        dockPresent: Boolean(dock),
        dockHeight: dockRect ? Math.round(dockRect.height) : 0,
        dockZIndex,
      };
    }, vp.isMobile);

    const expectedHeight = vp.isMobile ? 56 : 60;
    const heightPass = Math.abs(data.headerHeight - expectedHeight) <= 1;
    const headerCountPass = data.headerCount === 1;
    const overflowPass = !data.hasHorizontalOverflow;

    console.log(
      `Viewport [${vp.name}]: HeaderCount=${data.headerCount} (${headerCountPass ? 'PASS' : 'FAIL'}), Height=${data.headerHeight}px (Expected ~${expectedHeight}px, ${heightPass ? 'PASS' : 'FAIL'}), H-Overflow=${data.hasHorizontalOverflow ? 'FAIL' : 'PASS'}, DockPresent=${data.dockPresent}, Header-Z=${data.headerZIndex}, Dock-Z=${data.dockZIndex}`
    );

    await page.screenshot({ path: path.join(screenshotsDir, `home_${vp.width}x${vp.height}.png`) });

    results.viewports.push({
      ...vp,
      ...data,
      passed: heightPass && headerCountPass && overflowPass,
    });

    await page.close();
  }

  // ---------------------------------------------------------------------------
  // 2. SCROLL FLICKER & REVERSE DIRECTION STABILITY (Android 412x915)
  // ---------------------------------------------------------------------------
  console.log('\n--- 2. Scroll Flicker & Jitter Measurement (412x915 Android) ---');
  {
    const page = await browser.newPage({ viewport: { width: 412, height: 915 } });
    await page.goto(`${BASE_URL}/`, { waitUntil: 'networkidle' });

    const scrollSteps = [];

    // Measure at rest
    scrollSteps.push(
      await page.evaluate(() => {
        const h = document.querySelector('header');
        const r = h.getBoundingClientRect();
        return { action: 'initial-rest', scrollY: window.scrollY, top: Math.round(r.top), height: Math.round(r.height), classes: h.className };
      })
    );

    // Slow scroll down (20 steps of 8px)
    for (let i = 1; i <= 20; i++) {
      await page.mouse.wheel(0, 8);
      await page.waitForTimeout(16);
      const m = await page.evaluate((step) => {
        const h = document.querySelector('header');
        const r = h.getBoundingClientRect();
        return { action: `slow-down-${step}`, scrollY: window.scrollY, top: Math.round(r.top), height: Math.round(r.height), classes: h.className };
      }, i);
      scrollSteps.push(m);
    }

    // Rapid fast scroll down (300px increments)
    for (const delta of [300, 400, 500]) {
      await page.mouse.wheel(0, delta);
      await page.waitForTimeout(30);
      const m = await page.evaluate((d) => {
        const h = document.querySelector('header');
        const r = h.getBoundingClientRect();
        return { action: `rapid-down-${d}`, scrollY: window.scrollY, top: Math.round(r.top), height: Math.round(r.height), classes: h.className };
      }, delta);
      scrollSteps.push(m);
    }

    // Rapid reverse scroll oscillation (down 60px, up 50px x 10 times)
    for (let i = 1; i <= 10; i++) {
      await page.mouse.wheel(0, 60);
      await page.waitForTimeout(20);
      await page.mouse.wheel(0, -50);
      await page.waitForTimeout(20);
      const m = await page.evaluate((cycle) => {
        const h = document.querySelector('header');
        const r = h.getBoundingClientRect();
        return { action: `oscillate-${cycle}`, scrollY: window.scrollY, top: Math.round(r.top), height: Math.round(r.height), classes: h.className };
      }, i);
      scrollSteps.push(m);
    }

    // Analyze results
    const anyHiddenClass = scrollSteps.some((s) => s.classes.includes('hidden'));
    const anyHeightChange = scrollSteps.some((s) => s.height !== 56);
    const anyTopDetachment = scrollSteps.some((s) => s.top !== 0);

    console.log(`Scroll measurement steps recorded: ${scrollSteps.length}`);
    console.log(`Hidden class toggled anywhere? ${anyHiddenClass ? 'YES (FAIL)' : 'NO (PASS)'}`);
    console.log(`Height changed from 56px? ${anyHeightChange ? 'YES (FAIL)' : 'NO (PASS)'}`);
    console.log(`Header top detached from 0? ${anyTopDetachment ? 'YES (FAIL)' : 'NO (PASS)'}`);

    results.scrollStability = {
      totalSteps: scrollSteps.length,
      anyHiddenClass,
      anyHeightChange,
      anyTopDetachment,
      passed: !anyHiddenClass && !anyHeightChange && !anyTopDetachment,
    };

    await page.close();
  }

  // ---------------------------------------------------------------------------
  // 3. ROUTE CONSISTENCY & UNIFIED HEADER COVERAGE
  // ---------------------------------------------------------------------------
  console.log('\n--- 3. Route Consistency Verification ---');
  const routesToTest = [
    { path: '/', label: 'Home' },
    { path: '/shop', label: 'Shop Catalog' },
    { path: '/cart', label: 'Cart Page' },
    { path: '/checkout', label: 'Checkout' },
    { path: '/order', label: 'Order Lookup' },
    { path: '/order/test-id-123', label: 'Order Tracking Direct' },
  ];

  for (const rt of routesToTest) {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    try {
      const resp = await page.goto(`${BASE_URL}${rt.path}`, { waitUntil: 'networkidle', timeout: 10000 });
      const status = resp?.status();
      await page.waitForSelector('header', { timeout: 5000 }).catch(() => {});

      const routeData = await page.evaluate(() => {
        const header = document.querySelector('header');
        const headers = document.querySelectorAll('header');
        const headerRect = header ? header.getBoundingClientRect() : null;
        const dock = document.querySelector('.ld-bottom-dock');
        return {
          headerCount: headers.length,
          headerHeight: headerRect ? Math.round(headerRect.height) : 0,
          headerClass: header ? header.className : 'NONE',
          hasDock: Boolean(dock),
        };
      });

      console.log(
        `Route [${rt.label} (${rt.path})]: HTTP=${status}, HeaderCount=${routeData.headerCount}, Height=${routeData.headerHeight}px, Class="${routeData.headerClass.slice(0, 35)}...", Dock=${routeData.hasDock}`
      );

      results.routeCoverage.push({
        ...rt,
        status,
        ...routeData,
        passed: routeData.headerCount === 1 && routeData.headerHeight === 56,
      });
    } catch (e) {
      console.log(`Route [${rt.label} (${rt.path})]: ERROR ${e.message}`);
    } finally {
      await page.close();
    }
  }

  // ---------------------------------------------------------------------------
  // 4. DRAWERS & MODALS INTERACTION (Search & Cart Drawer)
  // ---------------------------------------------------------------------------
  console.log('\n--- 4. Drawers & Navigation Interactions ---');
  {
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    await page.goto(`${BASE_URL}/`, { waitUntil: 'networkidle' });

    // Test Search Expansion
    const searchBtn = page.locator('.ld-header-search-trigger').first();
    if (await searchBtn.isVisible()) {
      await searchBtn.click();
      await page.waitForTimeout(100);
      const searchInput = page.locator('[data-testid="platform-search-input"]').first();
      const isInputVisible = await searchInput.isVisible();
      console.log(`Search Trigger Click: Input expanded & visible? ${isInputVisible ? 'PASS' : 'FAIL'}`);
      results.drawers.push({ name: 'Search Expansion', passed: isInputVisible });
    }

    // Test Cart Drawer Trigger
    const bagBtn = page.locator('[data-testid="luxury-bag-btn"]').first();
    if (await bagBtn.isVisible()) {
      await bagBtn.click();
      await page.waitForTimeout(200);
      const cartDrawer = page.locator('[data-testid="cart-drawer"]');
      const isDrawerVisible = await cartDrawer.isVisible();

      const drawerZIndex = await page.evaluate(() => {
        const backdrop = document.querySelector('[data-testid="cart-drawer-backdrop"]');
        return backdrop ? window.getComputedStyle(backdrop).zIndex : null;
      });

      console.log(`Bag Button Click: CartDrawer visible? ${isDrawerVisible ? 'PASS' : 'FAIL'}, Backdrop Z-Index=${drawerZIndex}`);

      // Close drawer
      const closeBtn = page.locator('[data-testid="cart-back-btn"]').first();
      if (await closeBtn.isVisible()) {
        await closeBtn.click();
        await page.waitForTimeout(200);
        const isDrawerClosed = !(await cartDrawer.isVisible());
        console.log(`Cart Drawer Close: Closed cleanly? ${isDrawerClosed ? 'PASS' : 'FAIL'}`);
        results.drawers.push({ name: 'Cart Drawer Open/Close', passed: isDrawerVisible && isDrawerClosed && drawerZIndex === '50' });
      }
    }

    // Test Bottom Navigation Tab Link
    const shopTab = page.locator('[data-testid="dock-shop-tab"]');
    if (await shopTab.isVisible()) {
      await shopTab.click();
      await page.waitForURL('**/shop');
      const onShop = page.url().includes('/shop');
      console.log(`Bottom Dock Navigation: Navigated to /shop? ${onShop ? 'PASS' : 'FAIL'}`);
      results.drawers.push({ name: 'Bottom Dock Tab Navigation', passed: onShop });
    }

    await page.close();
  }

  await browser.close();

  // Summary
  console.log('\n=== VERIFICATION SUMMARY ===');
  const allViewportsPass = results.viewports.every((v) => v.passed);
  const scrollPass = results.scrollStability.passed;
  const routesPass = results.routeCoverage.every((r) => r.passed);
  const drawersPass = results.drawers.every((d) => d.passed);

  console.log(`Multi-Viewport Checks: ${allViewportsPass ? 'ALL PASSED (7/7)' : 'FAILURES DETECTED'}`);
  console.log(`Scroll Stability & Flicker Immunity: ${scrollPass ? 'PASSED (Zero flicker, zero height shift)' : 'FAIL'}`);
  console.log(`Route Consistency: ${routesPass ? 'ALL PASSED' : 'FAILURES DETECTED'}`);
  console.log(`Drawers & Dock Navigation: ${drawersPass ? 'ALL PASSED' : 'FAILURES DETECTED'}`);

  fs.writeFileSync('scratch/acceptance-results.json', JSON.stringify(results, null, 2));
}

runAcceptance().catch((err) => {
  console.error('Acceptance run failed:', err);
  process.exit(1);
});
