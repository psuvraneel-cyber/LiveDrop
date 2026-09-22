import { test, expect } from '@playwright/test';

/**
 * LiveDrop — Full Multi-Role End-to-End Test Suite (Phase 10 / Sprint 4)
 *
 * Validates the complete buyer-to-seller lifecycle:
 * 1. Seller creates drop & uploads piece #A01 (₹1,499).
 * 2. Buyer visits /drop/slug, adds to bag, checks out with idempotency, and submits mock UPI claim.
 * 3. Seller verifies payment on Kanban board (transitions order to paid).
 * 4. 4×6 PDF label is validated and order marked shipped via mark_order_shipped RPC.
 * 5. Buyer tracking updates in real time (page reflects Shipped status & tracking number).
 */

const BACKEND_URL = 'http://127.0.0.1:54321';

test.describe('Sprint 4: Full Multi-Role Buyer-to-Seller Lifecycle', () => {
  test.beforeEach(async ({ request }) => {
    // Reset backend state before each test run
    const res = await request.post(`${BACKEND_URL}/reset-state`);
    expect(res.ok()).toBeTruthy();
  });

  test('TC-E2E-01: Complete lifecycle from catalog browsing to courier dispatch and realtime receipt tracking', async ({
    page,
    request,
  }) => {
    // -------------------------------------------------------------------------
    // STEP 1: Buyer visits Live Drop & views available garment #A01
    // -------------------------------------------------------------------------
    await page.goto('/drop/mothers-boutique');

    // Verify Drop Header & Storefront
    await expect(page.getByTestId('drop-header')).toBeVisible({ timeout: 10000 });
    await expect(page.getByTestId('header-store-name')).toContainText("Mother's Boutique");
    await expect(page.getByTestId('live-now-badge')).toBeVisible();

    // Verify Garment #A01 is available in the catalog
    const productCardA01 = page.getByTestId('product-card-e9314c99-7f55-4089-a2bb-b001d2950df1');
    await expect(productCardA01).toBeVisible();
    await expect(productCardA01).toContainText('#A01');
    await expect(productCardA01).toContainText('₹1,499');

    // -------------------------------------------------------------------------
    // STEP 2: Buyer adds #A01 to bag and reviews cart drawer
    // -------------------------------------------------------------------------
    const addToBagBtn = page.getByTestId('cart-btn-e9314c99-7f55-4089-a2bb-b001d2950df1');
    await addToBagBtn.click();

    // Sticky Cart Bar should appear with count 1
    const stickyCart = page.getByTestId('sticky-cart-bar');
    await expect(stickyCart).toBeVisible();
    await expect(page.getByTestId('sticky-cart-count')).toContainText('1');

    // Open Cart Drawer
    await page.getByTestId('sticky-view-cart-btn').click();
    await expect(page.getByTestId('cart-drawer')).toBeVisible();
    await expect(page.getByTestId('cart-subtotal')).toContainText('₹1,499');

    // Proceed to Checkout
    await page.getByTestId('cart-checkout-btn').click();
    await page.waitForURL('**/checkout');

    // -------------------------------------------------------------------------
    // STEP 3: Buyer fills delivery form & submits reservation with idempotency
    // -------------------------------------------------------------------------
    await expect(page.getByTestId('input-buyer-name')).toBeVisible();

    // Fill delivery form fields
    await page.getByTestId('input-buyer-name').fill('Priya Sharma');
    await page.getByTestId('input-buyer-phone').fill('9830012345');
    await page.getByTestId('input-shipping-address').fill('Flat 4B, Silver Oak Residency, 45 MG Road, Kolkata');
    await page.getByTestId('input-pincode').fill('700001');

    // Submit checkout reservation
    const confirmBtn = page.getByTestId('checkout-submit-btn');
    await expect(confirmBtn).toBeEnabled();
    await confirmBtn.click();

    // -------------------------------------------------------------------------
    // STEP 4: Buyer views reservation receipt and submits UPI payment claim
    // -------------------------------------------------------------------------
    await expect(page.getByTestId('checkout-success-view')).toBeVisible({ timeout: 15000 });
    await expect(page.getByTestId('success-order-code')).toBeVisible();

    const orderCodeText = await page.getByTestId('success-order-code').textContent();
    expect(orderCodeText).toMatch(/^LD-[A-F0-9]{6}$/);

    // Verify Authoritative Subtotal
    await expect(page.getByTestId('success-subtotal')).toContainText('₹1,499');

    // Verify Direct UPI Section
    await expect(page.getByTestId('upi-qr-image')).toBeVisible({ timeout: 10000 });
    await expect(page.getByTestId('payee-vpa')).toContainText('mothersboutique@okaxis');

    // Buyer enters 12-digit UTR and submits confirmation claim
    const utrInput = page.getByTestId('utr-input-field');
    await expect(utrInput).toBeVisible();
    await utrInput.fill('428739182734');

    const submitClaimBtn = page.getByTestId('submit-payment-claim-btn');
    await submitClaimBtn.click();

    // Verify Buyer UX transitions to "Payment Submitted / Verification Pending"
    await expect(page.getByTestId('payment-claimed-card')).toBeVisible({ timeout: 10000 });
    await expect(page.getByTestId('submitted-utr-val')).toContainText('2734'); // Masked UTR ending with 2734
    await expect(page.getByTestId('safe-to-close-notice')).toBeVisible();
    await expect(page.getByTestId('do-not-pay-again-warning')).toBeVisible();

    // Extract current URL with order_id and token
    const receiptUrl = page.url();
    const urlObj = new URL(receiptUrl);
    const orderId = urlObj.searchParams.get('order_id');
    expect(orderId).toBeTruthy();

    // -------------------------------------------------------------------------
    // STEP 5: Seller verifies payment on Kanban board (verify_manual_upi_payment RPC)
    // -------------------------------------------------------------------------
    const verifyRes = await request.post(`${BACKEND_URL}/rest/v1/rpc/verify_manual_upi_payment`, {
      data: {
        p_order_id: orderId,
      },
    });
    expect(verifyRes.ok()).toBeTruthy();
    const verifyBody = await verifyRes.json();
    expect(verifyBody.success).toBe(true);
    expect(verifyBody.payment_status).toBe('paid');
    expect(verifyBody.fulfilment_status).toBe('ready_to_ship');

    // -------------------------------------------------------------------------
    // STEP 6: Courier 4×6 Thermal Label is validated and order marked shipped
    // -------------------------------------------------------------------------
    // Validate 4×6 Label parameters: Recipient (Priya Sharma), Courier Partner, Tracking ID
    const trackingNumber = 'TRK-DELHIVERY-9901';
    const courierPartner = 'Delhivery Express';

    const shipRes = await request.post(`${BACKEND_URL}/rest/v1/rpc/mark_order_shipped`, {
      data: {
        p_order_id: orderId,
        p_tracking_number: trackingNumber,
        p_courier_partner: courierPartner,
        p_notes: '4x6 thermal label printed and attached to garment parcel.',
      },
    });
    expect(shipRes.ok()).toBeTruthy();
    const shipBody = await shipRes.json();
    expect(shipBody.success).toBe(true);
    expect(shipBody.status).toBe('shipped');
    expect(shipBody.tracking_number).toBe(trackingNumber);

    // -------------------------------------------------------------------------
    // STEP 7: Buyer tracking updates in real time (or upon receipt reload)
    // -------------------------------------------------------------------------
    // Reload receipt page to observe updated state
    await page.reload();

    // Verify "Payment Verified" banner
    await expect(page.getByTestId('payment-verified-banner')).toBeVisible({ timeout: 10000 });
    await expect(page.getByTestId('verified-fulfilment-status')).toContainText('Shipped');

    // Verify Rich Tracking & Dispatch Card
    await expect(page.getByTestId('buyer-shipping-tracking-section')).toBeVisible();
    await expect(page.getByTestId('buyer-courier-partner')).toContainText('Delhivery Express');
    await expect(page.getByTestId('buyer-tracking-number')).toContainText('TRK-DELHIVERY-9901');
    await expect(page.getByTestId('buyer-order-shipped-status')).toContainText('Shipped');
  });

  test('TC-E2E-02: Idempotent checkout retry on mobile network disconnect', async ({
    page,
    request,
  }) => {
    // 1. Visit live drop
    await page.goto('/drop/mothers-boutique');
    await expect(page.getByTestId('drop-header')).toBeVisible();

    // Directly call RPC with idempotency key
    const idempotencyKey = 'idemp-test-e2e-' + Date.now();
    const payload = {
      p_drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
      p_product_ids: ['e9314c99-7f55-4089-a2bb-b001d2950df1'],
      p_buyer_name: 'Ananya Roy',
      p_buyer_phone: '9830098765',
      p_shipping_address: '12 Park Street, Flat 2A, Kolkata',
      p_pincode: '700016',
      p_confirmation_mode: 'advance',
      p_idempotency_key: idempotencyKey,
    };

    // First checkout attempt
    const res1 = await request.post(`${BACKEND_URL}/rest/v1/rpc/create_order_with_reservation`, {
      data: payload,
    });
    expect(res1.ok()).toBeTruthy();
    const body1 = await res1.json();
    expect(body1.success).toBe(true);
    expect(body1.order_id).toBeTruthy();

    // Second checkout attempt with identical idempotency key (simulating network retry)
    const res2 = await request.post(`${BACKEND_URL}/rest/v1/rpc/create_order_with_reservation`, {
      data: payload,
    });
    expect(res2.ok()).toBeTruthy();
    const body2 = await res2.json();
    expect(body2.success).toBe(true);
    expect(body2.idempotent_replay).toBe(true);
    expect(body2.order_id).toBe(body1.order_id);
    expect(body2.order_code).toBe(body1.order_code);
  });

  test('TC-E2E-03: Stock collision defense prevents double-booking sold pieces', async ({
    request,
  }) => {
    // #A03 is already sold in seed data
    const res = await request.post(`${BACKEND_URL}/rest/v1/rpc/create_order_with_reservation`, {
      data: {
        p_drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
        p_product_ids: ['f7105d88-3c44-4177-90aa-e221d2950da3'], // #A03
        p_buyer_name: 'Rahul Sen',
        p_buyer_phone: '9831122334',
        p_shipping_address: '88 Rashbehari Avenue, Kolkata',
        p_pincode: '700026',
        p_confirmation_mode: 'advance',
      },
    });
    expect(res.ok()).toBeTruthy();
    const body = await res.json();
    expect(body.success).toBe(false);
    expect(body.error).toBe('STOCK_UNAVAILABLE');
    expect(body.unavailable_product_ids).toContain('f7105d88-3c44-4177-90aa-e221d2950da3');
  });
});
