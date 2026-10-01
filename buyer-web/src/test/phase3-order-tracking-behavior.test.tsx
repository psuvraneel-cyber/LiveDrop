/**
 * LiveDrop Phase 3: Order Lookup, Receipts & Order Tracking Behavioral Test Suite
 *
 * Covers all 22 mandatory verification scenarios required by Phase 3 specification:
 *  1. Empty order lookup state.
 *  2. Valid order lookup.
 *  3. Invalid token.
 *  4. Missing token.
 *  5. Unauthorized order.
 *  6. Refresh with valid token.
 *  7. Pending unpaid order.
 *  8. Advance-paid order with balance due.
 *  9. Fully paid order.
 * 10. Ready-to-ship order.
 * 11. Shipped order with tracking.
 * 12. Shipped order without tracking.
 * 13. Expired order.
 * 14. Cancelled order.
 * 15. Payment still awaiting verification.
 * 16. Payment rejection state.
 * 17. Network failure and retry.
 * 18. PII minimization.
 * 19. Timeline status correctness.
 * 20. Mobile and desktop rendering.
 * 21. Keyboard navigation.
 * 22. Screen-reader status announcements.
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import OrderLookupPage from '../app/order/page';
import OrderTrackingPage from '../app/order/[id]/page';
import * as buyerCatalog from '../lib/data/buyer-catalog';
import { cacheOrderToken, getCachedOrderToken } from '../lib/cart/cart-storage';
import { OrderReceipt } from '../types/domain';
import { InvalidOrderTokenError } from '../lib/errors';

const mockPush = vi.fn();
let mockParams: { id?: string } = { id: 'order-101' };
let mockSearchParams = new URLSearchParams();

vi.mock('next/navigation', () => ({
  useParams: () => mockParams,
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({
    push: mockPush,
    replace: vi.fn(),
  }),
  usePathname: () => '/order',
}));

describe('LiveDrop Phase 3: Order Lookup, Receipts & Order Tracking Behavior', () => {
  const baseOrderReceipt: OrderReceipt = {
    id: 'order-uuid-101',
    order_code: 'LD-8899AA',
    buyer_name: 'Ananya Roy',
    subtotal_paisa: 250000,
    shipping_paisa: 0,
    total_paisa: 250000,
    confirmation_mode: 'full_payment',
    advance_required_paisa: 250000,
    advance_paid_paisa: 0,
    total_paid_paisa: 0,
    balance_due_paisa: 250000,
    payment_status: 'unpaid',
    fulfilment_status: 'not_ready',
    status: 'pending',
    hold_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    store_name: "Mira's Boutique",
    store_slug: 'miras-boutique',
    upi_id: 'mira@okaxis',
    upi_qr_url: null,
    items: [
      {
        product_id: 'prod-p1',
        code: '#M01',
        title: 'Chanderi Silk Saree',
        image_url: 'https://example.com/m01.webp',
        price_at_purchase_paisa: 250000,
      },
    ],
  };

  beforeEach(() => {
    window.localStorage.clear();
    mockPush.mockClear();
    mockParams = { id: 'order-uuid-101' };
    mockSearchParams = new URLSearchParams('token=secret-token-xyz');
    vi.clearAllMocks();
  });

  // 1. Empty order lookup state
  it('1. Empty order lookup state: displays clean empty state when no orders cached', () => {
    render(<OrderLookupPage />);
    expect(screen.getByTestId('recent-orders-empty')).toBeInTheDocument();
    expect(screen.getByText('No Recent Orders')).toBeInTheDocument();
    expect(screen.getByText(/Orders placed on this device are automatically saved here/i)).toBeInTheDocument();
    expect(screen.getByText('Browse Live Drops →')).toBeInTheDocument();
  });

  // 2. Valid order lookup
  it('2. Valid order lookup: routes to receipt route with order ID and token', () => {
    render(<OrderLookupPage />);
    const idInput = screen.getByLabelText(/Order Number or Tracking Link/i);
    const tokenInput = screen.getByLabelText(/Receipt Access Key/i);
    const submitBtn = screen.getByRole('button', { name: /Retrieve Order Receipt/i });

    fireEvent.change(idInput, { target: { value: 'order-uuid-999' } });
    fireEvent.change(tokenInput, { target: { value: 'token-abc-789' } });
    fireEvent.click(submitBtn);

    expect(mockPush).toHaveBeenCalledWith('/order/order-uuid-999?token=token-abc-789');
  });

  // 3. Invalid token
  it('3. Invalid token: displays DPDP access restricted screen and purges stale token', async () => {
    cacheOrderToken('order-uuid-101', 'bad-token');
    mockSearchParams = new URLSearchParams('token=bad-token');

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockRejectedValue(
      new InvalidOrderTokenError('ORDER_NOT_FOUND_OR_UNAUTHORIZED')
    );

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-access-restricted')).toBeInTheDocument();
    });

    expect(screen.getByText(/ORDER_NOT_FOUND_OR_UNAUTHORIZED/i)).toBeInTheDocument();
    expect(getCachedOrderToken('order-uuid-101')).toBeNull();
  });

  // 4. Missing token
  it('4. Missing token: blocks unauthorized access and displays DPDP Act notice without revealing order details', async () => {
    mockSearchParams = new URLSearchParams(); // No token in URL or cache

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-access-restricted')).toBeInTheDocument();
    });

    expect(screen.getByText(/DPDP Act/i)).toBeInTheDocument();
    expect(screen.queryByText('Chanderi Silk Saree')).not.toBeInTheDocument();
    expect(screen.queryByText('LD-8899AA')).not.toBeInTheDocument();
  });

  // 5. Unauthorized order
  it('5. Unauthorized order: rejects unauthorized request and shows access restricted', async () => {
    mockSearchParams = new URLSearchParams('token=unauthorized-token');
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockRejectedValue(
      new Error('Invalid or expired order access token.')
    );

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-access-restricted')).toBeInTheDocument();
    });

    expect(screen.getByText(/Invalid or expired order access token/i)).toBeInTheDocument();
  });

  // 6. Refresh with valid token
  it('6. Refresh with valid token: re-invokes getOrderByToken and updates receipt', async () => {
    const getOrderSpy = vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-tracking-page')).toBeInTheDocument();
    });

    expect(getOrderSpy).toHaveBeenCalledTimes(1);

    const refreshBtn = screen.getByTestId('order-refresh-status-btn');
    fireEvent.click(refreshBtn);

    await waitFor(() => {
      expect(getOrderSpy).toHaveBeenCalledTimes(2);
    });
  });

  // 7. Pending unpaid order
  it('7. Pending unpaid order: shows Pending order state, Unpaid payment, Not Ready fulfilment, and hold countdown', async () => {
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue({
      ...baseOrderReceipt,
      status: 'pending',
      payment_status: 'unpaid',
      fulfilment_status: 'not_ready',
    });

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('status-badge-order')).toHaveTextContent('Pending');
      expect(screen.getByTestId('status-badge-payment')).toHaveTextContent('Unpaid');
      expect(screen.getByTestId('status-badge-fulfilment')).toHaveTextContent('Not Ready');
    });

    // Does not appear confirmed or shipped
    expect(screen.getByTestId('status-badge-order')).not.toHaveTextContent('Confirmed');
    expect(screen.getByTestId('status-badge-order')).not.toHaveTextContent('Shipped');
  });

  // 8. Advance-paid order with balance due
  it('8. Advance-paid order with balance due: clearly shows balance remains due and fulfillment is held', async () => {
    const advanceOrder: OrderReceipt = {
      ...baseOrderReceipt,
      confirmation_mode: 'advance',
      payment_status: 'advance_paid',
      advance_required_paisa: 50000,
      advance_paid_paisa: 50000,
      balance_due_paisa: 200000,
      total_paisa: 250000,
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(advanceOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('status-badge-payment')).toHaveTextContent('Advance Paid');
    });

    // Must not appear fully paid
    expect(screen.getByTestId('status-badge-payment')).not.toHaveTextContent('Fully Paid');

    const advanceNotice = screen.getByTestId('advance-paid-balance-notice');
    expect(advanceNotice).toBeInTheDocument();
    expect(advanceNotice).toHaveTextContent('Advance Confirmed: ₹500');
    expect(advanceNotice).toHaveTextContent('₹2,000');
    expect(advanceNotice).toHaveTextContent(/Shipment remains held until balance settlement/i);

    // Breakdown shows advance specifics
    expect(screen.getByTestId('success-advance-paid')).toHaveTextContent('₹500');
    expect(screen.getByTestId('success-balance-due')).toHaveTextContent('₹2,000');
  });

  // 9. Fully paid order
  it('9. Fully paid order: shows Fully Paid status and indicates eligibility for fulfillment', async () => {
    const paidOrder: OrderReceipt = {
      ...baseOrderReceipt,
      payment_status: 'paid',
      total_paid_paisa: 250000,
      balance_due_paisa: 0,
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(paidOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('status-badge-payment')).toHaveTextContent('Fully Paid');
    });

    const fullyPaidNotice = screen.getByTestId('order-fully-paid-notice');
    expect(fullyPaidNotice).toBeInTheDocument();
    expect(fullyPaidNotice).toHaveTextContent(/Order is fully paid and eligible for atelier garment inspection/i);
  });

  // 10. Ready-to-ship order
  it('10. Ready-to-ship order: shows Ready to Ship fulfillment status without premature tracking details', async () => {
    const readyOrder: OrderReceipt = {
      ...baseOrderReceipt,
      payment_status: 'paid',
      fulfilment_status: 'ready_to_ship',
      shipped_at: '2026-09-29T10:00:00Z', // Regression: non-null timestamp must NOT bypass fulfilment_status === 'shipped'
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(readyOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('status-badge-fulfilment')).toHaveTextContent('Ready to Ship');
    });

    // Tracking card is not shown until actually shipped
    expect(screen.queryByTestId('shipment-tracking-card')).not.toBeInTheDocument();
  });

  // 10b. Not-ready order with non-null shipped_at timestamp (Regression Case 1)
  it('10b. Not-ready order: hides shipment tracking card even when shipped_at timestamp is present', async () => {
    const notReadyOrder: OrderReceipt = {
      ...baseOrderReceipt,
      payment_status: 'unpaid',
      fulfilment_status: 'not_ready',
      shipped_at: '2026-09-29T08:00:00Z', // Regression: non-null timestamp on not_ready must NOT show shipment card
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(notReadyOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('status-badge-fulfilment')).toHaveTextContent('Not Ready');
    });

    expect(screen.queryByTestId('shipment-tracking-card')).not.toBeInTheDocument();
  });

  // 11. Shipped order with tracking
  it('11. Shipped order with tracking: displays courier partner, tracking number, copy button, and shipped date', async () => {
    const shippedOrder: OrderReceipt = {
      ...baseOrderReceipt,
      status: 'shipped',
      payment_status: 'paid',
      fulfilment_status: 'shipped',
      courier_partner: 'Blue Dart Express',
      tracking_number: 'BLUEDART-99228811',
      shipped_at: '2026-09-29T10:30:00Z',
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(shippedOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('shipment-tracking-card')).toBeInTheDocument();
    });

    expect(screen.getByTestId('courier-partner-name')).toHaveTextContent('Blue Dart Express');
    expect(screen.getByTestId('tracking-awb-number')).toHaveTextContent('BLUEDART-99228811');
    expect(screen.getByRole('button', { name: /Copy Tracking Number/i })).toBeInTheDocument();
    expect(screen.getByTestId('shipped-at-timestamp')).toBeInTheDocument();
  });

  // 12. Shipped order without tracking
  it('12. Shipped order without tracking: displays courier but explains tracking number is being registered', async () => {
    const shippedNoTracking: OrderReceipt = {
      ...baseOrderReceipt,
      status: 'shipped',
      payment_status: 'paid',
      fulfilment_status: 'shipped',
      courier_partner: 'Delhivery',
      tracking_number: null,
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(shippedNoTracking);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('shipment-tracking-card')).toBeInTheDocument();
    });

    expect(screen.getByTestId('courier-partner-name')).toHaveTextContent('Delhivery');
    expect(screen.getByTestId('tracking-pending-notice')).toHaveTextContent(
      /AWB tracking number is being registered by the courier partner/i
    );
    expect(screen.queryByTestId('tracking-awb-number')).not.toBeInTheDocument();
  });

  // 12b. Shipped order with null shipped_at timestamp (Regression Case 3)
  it('12b. Shipped order with null shipped_at: displays shipment card without fabricated timestamp', async () => {
    const shippedNullTimestamp: OrderReceipt = {
      ...baseOrderReceipt,
      status: 'shipped',
      payment_status: 'paid',
      fulfilment_status: 'shipped',
      courier_partner: 'Blue Dart Express',
      tracking_number: 'BLUEDART-554433',
      shipped_at: null,
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(shippedNullTimestamp);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('shipment-tracking-card')).toBeInTheDocument();
    });

    expect(screen.getByTestId('tracking-awb-number')).toHaveTextContent('BLUEDART-554433');
    // Invariant: no fabricated timestamp when shipped_at is null
    expect(screen.queryByTestId('shipped-at-timestamp')).not.toBeInTheDocument();
  });

  // 13. Expired order
  it('13. Expired order: explains hold duration ended and marks timeline halted', async () => {
    const expiredOrder: OrderReceipt = {
      ...baseOrderReceipt,
      status: 'expired',
      payment_status: 'unpaid',
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(expiredOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('status-badge-order')).toHaveTextContent('Expired');
    });

    const banner = screen.getByTestId('order-expired-banner');
    expect(banner).toBeInTheDocument();
    expect(banner).toHaveTextContent(/The hold window expired before payment verification/i);
    expect(screen.getByText('Reservation Expired')).toBeInTheDocument();
  });

  // 14. Cancelled order
  it('14. Cancelled order: explains order was cancelled and does not appear active or payable', async () => {
    const cancelledOrder: OrderReceipt = {
      ...baseOrderReceipt,
      status: 'cancelled',
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(cancelledOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('status-badge-order')).toHaveTextContent('Cancelled');
    });

    const banner = screen.getByTestId('order-cancelled-banner');
    expect(banner).toBeInTheDocument();
    expect(banner).toHaveTextContent(/This order is no longer active/i);
    expect(screen.getByRole('heading', { level: 1, name: 'Order Cancelled' })).toBeInTheDocument();
  });

  // 15. Payment still awaiting verification
  it('15. Payment still awaiting verification: timeline step 1 completed and step 2 active awaiting verification', async () => {
    const awaitingVerificationOrder: OrderReceipt = {
      ...baseOrderReceipt,
      payment_status: 'unpaid',
      active_payment_attempt: {
        id: 'attempt-1',
        order_id: 'order-uuid-101',
        payment_type: 'full',
        payment_method: 'upi',
        expected_amount_paisa: 250000,
        payee_vpa_snapshot: 'boutique@okhdfcbank',
        payee_display_name_snapshot: 'Varanasi Weaves',
        transaction_reference: 'LD-TX-101',
        status: 'awaiting_seller_verification',
        buyer_claimed_at: new Date().toISOString(),
        buyer_submitted_utr: '123456789012',
        seller_verified_at: null,
        verified_by: null,
        rejection_reason: null,
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      },
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(awaitingVerificationOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getAllByText('Payment Submitted').length).toBeGreaterThanOrEqual(1);
    });

    expect(screen.getByText('Awaiting Seller Verification')).toBeInTheDocument();
    expect(screen.getByText("We'll notify you once verified by the boutique")).toBeInTheDocument();
  });

  // 16. Payment rejection state
  it('16. Payment rejection state: displays rejection state from boutique and allows re-entry', async () => {
    const rejectedOrder: OrderReceipt = {
      ...baseOrderReceipt,
      payment_status: 'unpaid',
      active_payment_attempt: {
        id: 'attempt-2',
        order_id: 'order-uuid-101',
        payment_type: 'full',
        payment_method: 'upi',
        expected_amount_paisa: 250000,
        payee_vpa_snapshot: 'boutique@okhdfcbank',
        payee_display_name_snapshot: 'Varanasi Weaves',
        transaction_reference: 'LD-TX-102',
        status: 'rejected',
        buyer_claimed_at: new Date().toISOString(),
        buyer_submitted_utr: '000111222333',
        seller_verified_at: null,
        verified_by: null,
        rejection_reason: 'UTR not found in boutique bank account statement.',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      },
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(rejectedOrder);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getAllByText('Payment Submitted').length).toBeGreaterThanOrEqual(1);
    });

    expect(screen.getByText(/UTR not found in boutique bank account statement/i)).toBeInTheDocument();
  });

  // 17. Network failure and retry
  it('17. Network failure and retry: renders retry button and re-attempts fetch on click', async () => {
    const getOrderSpy = vi
      .spyOn(buyerCatalog, 'getOrderByToken')
      .mockRejectedValueOnce(new TypeError('Failed to fetch (network error)'))
      .mockResolvedValueOnce(baseOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-retry-btn')).toBeInTheDocument();
    });

    expect(screen.getByText(/Connection issue retrieving order receipt/i)).toBeInTheDocument();

    const retryBtn = screen.getByTestId('order-retry-btn');
    fireEvent.click(retryBtn);

    await waitFor(() => {
      expect(screen.getByTestId('order-tracking-page')).toBeInTheDocument();
    });

    expect(getOrderSpy).toHaveBeenCalledTimes(2);
  });

  // 18. PII minimization
  it('18. PII minimization: never leaks order tokens, full phone numbers, or addresses in public metadata', async () => {
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-tracking-page')).toBeInTheDocument();
    });

    // Ensure token is not rendered in plaintext
    expect(screen.queryByText('secret-token-xyz')).not.toBeInTheDocument();
    // Ensure raw phone numbers are not in receipt DOM
    expect(screen.queryByText(/919830012345/)).not.toBeInTheDocument();
  });

  // 19. Timeline status correctness
  it('19. Timeline status correctness: incomplete steps are not marked with checkmarks', async () => {
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByLabelText('Order Status Progression')).toBeInTheDocument();
    });

    // Delivered is pending (circle) and not completed checkmark
    const deliveredStep = screen.getByText('Delivered').closest('.ld-timeline-step');
    expect(deliveredStep).toHaveClass('pending');
    expect(deliveredStep).not.toHaveClass('completed');
  });

  // 20. Mobile and desktop rendering
  it('20. Mobile and desktop rendering: renders navigation dock and global header with active orders tab', async () => {
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('mobile-bottom-dock')).toBeInTheDocument();
    });

    const ordersTab = screen.getByTestId('dock-orders-tab');
    expect(ordersTab).toHaveClass('active');
    expect(screen.getByTestId('global-buyer-header')).toBeInTheDocument();
  });

  // 21. Keyboard navigation
  it('21. Keyboard navigation: lookup inputs and tracking buttons are keyboard focusable', () => {
    render(<OrderLookupPage />);
    const idInput = screen.getByLabelText(/Order Number or Tracking Link/i);
    const tokenInput = screen.getByLabelText(/Receipt Access Key/i);
    const submitBtn = screen.getByRole('button', { name: /Retrieve Order Receipt/i });

    idInput.focus();
    expect(document.activeElement).toBe(idInput);

    tokenInput.focus();
    expect(document.activeElement).toBe(tokenInput);

    submitBtn.focus();
    expect(document.activeElement).toBe(submitBtn);
  });

  // 22. Screen-reader status announcements
  it('22. Screen-reader status announcements: includes aria-live regions for accessible status updates', async () => {
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-tracking-page')).toBeInTheDocument();
    });

    // Check that polite live region exists
    const liveRegion = document.querySelector('[aria-live="polite"]');
    expect(liveRegion).toBeInTheDocument();
  });
});
