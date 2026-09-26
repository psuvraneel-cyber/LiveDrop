import { chromium } from '@playwright/test';

async function capturePhase1() {
  const browser = await chromium.launch({ headless: true });
  
  // 1. Mobile viewport (iPhone 14 / standard 390x844)
  const mobileContext = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 2,
  });
  const mobilePage = await mobileContext.newPage();
  await mobilePage.goto('http://localhost:3000', { waitUntil: 'networkidle' });
  
  // Measure computed styles on root elements
  const computed = await mobilePage.evaluate(() => {
    const root = document.documentElement;
    const body = document.body;
    const style = getComputedStyle(root);
    const bodyStyle = getComputedStyle(body);
    const buttons = document.querySelectorAll('button');
    const firstButton = buttons[0];
    const buttonFont = firstButton ? getComputedStyle(firstButton).fontFamily : 'none';

    return {
      bgToken: style.getPropertyValue('--ld-bg').trim(),
      surfaceToken: style.getPropertyValue('--ld-surface').trim(),
      goldToken: style.getPropertyValue('--ld-gold').trim(),
      bodyBg: bodyStyle.backgroundColor,
      bodyFont: bodyStyle.fontFamily,
      buttonFont: buttonFont,
    };
  });
  console.log('COMPUTED_TOKENS:', JSON.stringify(computed, null, 2));

  await mobilePage.screenshot({ path: 'scratch/phase1-mobile-home.png', fullPage: false });
  await mobileContext.close();

  // 2. Desktop viewport (1280x800)
  const desktopContext = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
  });
  const desktopPage = await desktopContext.newPage();
  await desktopPage.goto('http://localhost:3000', { waitUntil: 'networkidle' });
  await desktopPage.screenshot({ path: 'scratch/phase1-desktop-home.png', fullPage: false });
  await desktopContext.close();

  await browser.close();
}

capturePhase1().catch(err => {
  console.error(err);
  process.exit(1);
});
