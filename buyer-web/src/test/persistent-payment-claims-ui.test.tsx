import React from 'react';
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DirectUpiPaymentView } from '../components/checkout/DirectUpiPaymentView';
import { OrderReceipt, PaymentAttempt } from '../types/domain';
import * as buyerCatalog from '../lib/data/buyer-catalog';
import * as supabaseClient from '../lib/supabase/client';

// Mock QRCode
vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,mockqr'),
  },
}));

describe('TASK-2.4C: Persistent Payment Claims & Resume-Safe Buyer UX', () => {
  const mockOrderToken = '4b56c377-a036-4b66-42ff-8b39406df589';
  const mockOrderId = '9a279045-2366-464a-f866-ba7f546fa067';

  const baseOrder: OrderReceipt = {
    id: mockOrderId,
    order_code: 'LD-1001',
    buyer_name: 'Priya Sen',
    subtotal_paisa: 185000,
    shipping_paisa: 0,
    total_paisa: 185000,
    confirmation_mode: 'advance',
    advance_required_paisa: 25000,
    advance_paid_paisa: 0,
    total_paid_paisa: 0,
    balance_due_paisa: 185000,
    payment_status: 'unpaid',
    fulfilment_status: 'not_ready',
    status: 'pending',
    hold_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    store_name: 'Priya Trends',
    store_slug: 'priya-trends',
    upi_id: 'priya@okaxis',
    upi_enabled: true,
    upi_qr_url: null,
    items: [
      {
        product_id: 'prod-01',
        code: '#A01',
        title: 'Handloom Silk Saree',
        price_at_purchase_paisa: 185000,
        image_url: 'https://images.example.com/a01.jpg',
      },
    ],
  };

  const activeAttempt: PaymentAttempt = {
    id: 'att-uuid-001',
    order_id: mockOrderId,
    payment_type: 'advance',
    payment_method: 'upi',
    expected_amount_paisa: 25000,
    payee_vpa_snapshot: 'priya@okaxis',
    payee_display_name_snapshot: 'Priya Trends',
    transaction_reference: 'LD1001-ADV',
    status: 'awaiting_payment',
    buyer_submitted_utr: null,
    buyer_claimed_at: null,
    seller_verified_at: null,
    verified_by: null,
    rejection_reason: null,
    verification_expires_at: null,
    expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };

  interface MockRealtimeChannel {
    on: ReturnType<typeof vi.fn>;
    subscribe: ReturnType<typeof vi.fn>;
  }

  let mockChannel: MockRealtimeChannel;

  beforeEach(() => {
    vi.clearAllMocks();

    mockChannel = {
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn((cb?: (status: string) => void) => {
        if (cb) cb('SUBSCRIBED');
        return mockChannel;
      }),
    };

    vi.spyOn(supabaseClient, 'getBuyerClient').mockReturnValue({
      channel: vi.fn().mockReturnValue(mockChannel),
      removeChannel: vi.fn(),
    } as unknown as ReturnType<typeof supabaseClient.getBuyerClient>);

    vi.spyOn(buyerCatalog, 'initiatePaymentAttempt').mockResolvedValue({
      success: true,
      payment_attempt_id: activeAttempt.id,
      order_id: mockOrderId,
      payment_type: 'advance',
      expected_amount_paisa: 25000,
      payee_vpa: 'priya@okaxis',
      payee_display_name: 'Priya Trends',
      transaction_reference: 'LD1001-ADV',
      status: 'awaiting_payment',
      upi_uri: 'upi://pay?pa=priya@okaxis&pn=Priya%20Trends&am=250.00&tr=LD1001-ADV',
      verification_expires_at: null,
      expires_at: activeAttempt.expires_at,
    });

    vi.spyOn(buyerCatalog, 'submitBuyerPaymentClaim').mockResolvedValue({
      success: true,
      payment_attempt_id: activeAttempt.id,
      order_id: mockOrderId,
      status: 'awaiting_seller_verification',
      buyer_submitted_utr: '428739182799',
      buyer_claimed_at: new Date().toISOString(),
      verification_expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      message: 'Claim registered',
    });

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrder);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('UI-01: buyer opens pending payment -> renders UPI details & UTR submission form', async () => {
    render(<DirectUpiPaymentView order={baseOrder} orderToken={mockOrderToken} />);

    await waitFor(() => {
      expect(screen.getByTestId('payee-vpa')).toHaveTextContent('priya@okaxis');
      expect(screen.getByTestId('payment-expected-amount')).toHaveTextContent('₹250');
      expect(screen.getByTestId('utr-submission-form')).toBeInTheDocument();
      expect(screen.getByTestId('utr-input-field')).toBeInTheDocument();
      expect(screen.getByTestId('submit-payment-claim-btn')).toBeInTheDocument();
    });
  });

  it('UI-02: buyer submits UTR -> shows safe-to-close notice, masked UTR, 24h deadline, and do-not-pay-again warning', async () => {
    render(<DirectUpiPaymentView order={baseOrder} orderToken={mockOrderToken} />);

    await waitFor(() => {
      expect(screen.getByTestId('utr-input-field')).toBeInTheDocument();
    });

    const utrInput = screen.getByTestId('utr-input-field');
    fireEvent.change(utrInput, { target: { value: '428739182799' } });

    const submitBtn = screen.getByTestId('submit-payment-claim-btn');
    fireEvent.click(submitBtn);

    await waitFor(() => {
      expect(screen.getByTestId('payment-claimed-card')).toBeInTheDocument();
      expect(screen.getByTestId('safe-to-close-notice')).toHaveTextContent(/safely close this page/i);
      expect(screen.getByTestId('submitted-utr-val')).toHaveTextContent('••••••••2799');
      expect(screen.getByTestId('verification-deadline')).toBeInTheDocument();
      expect(screen.getByTestId('do-not-pay-again-warning')).toHaveTextContent(/do not pay again/i);
    });
  });

  it('UI-03: buyer closes/reopens browser -> loads pending claim from server state without new attempt', async () => {
    const orderWithPendingClaim: OrderReceipt = {
      ...baseOrder,
      payment_attempt: {
        ...activeAttempt,
        status: 'awaiting_seller_verification',
        buyer_submitted_utr: '428739182799',
        buyer_claimed_at: new Date().toISOString(),
        verification_expires_at: new Date(Date.now() + 23 * 60 * 60 * 1000).toISOString(),
      },
    };

    render(<DirectUpiPaymentView order={orderWithPendingClaim} orderToken={mockOrderToken} />);

    // Renders claimed card immediately from authoritative order props
    expect(screen.getByTestId('payment-claimed-card')).toBeInTheDocument();
    expect(screen.getByTestId('safe-to-close-notice')).toBeInTheDocument();
    expect(screen.getByTestId('submitted-utr-val')).toHaveTextContent('••••••••2799');

    // Does NOT initiate a new attempt
    expect(buyerCatalog.initiatePaymentAttempt).not.toHaveBeenCalled();
    // Does NOT show fresh UTR submission form
    expect(screen.queryByTestId('utr-submission-form')).not.toBeInTheDocument();
  });

  it('UI-04: buyer receives realtime verified update -> transitions to advance verified banner without page refresh', async () => {
    let realtimeCallback: ((payload: unknown) => void) | null = null;

    mockChannel.on = vi.fn((_event: string, filter: { table?: string }, cb: (payload: unknown) => void) => {
      if (filter?.table === 'orders') {
        realtimeCallback = cb;
      }
      return mockChannel;
    });

    const onRefresh = vi.fn();
    render(<DirectUpiPaymentView order={baseOrder} orderToken={mockOrderToken} onOrderRefresh={onRefresh} />);

    await waitFor(() => {
      expect(realtimeCallback).toBeTruthy();
    });

    const verifiedOrder: OrderReceipt = {
      ...baseOrder,
      status: 'confirmed',
      payment_status: 'advance_paid',
      advance_paid_paisa: 25000,
      total_paid_paisa: 25000,
      balance_due_paisa: 160000,
      hold_expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    };

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(verifiedOrder);

    // Simulate seller verifying payment on server -> triggers Realtime event to buyer channel
    realtimeCallback!({
      eventType: 'UPDATE',
      new: {
        id: mockOrderId,
        status: 'confirmed',
        payment_status: 'advance_paid',
        advance_paid_paisa: 25000,
        total_paid_paisa: 25000,
        balance_due_paisa: 160000,
      },
    });

    await waitFor(() => {
      expect(buyerCatalog.getOrderByToken).toHaveBeenCalledWith(
        expect.anything(),
        mockOrderId,
        mockOrderToken
      );
      expect(onRefresh).toHaveBeenCalledWith(verifiedOrder);
    });
  });

  it('UI-05: buyer reloads after verification -> renders verified advance banner, ₹250 paid, ₹1,600 balance', async () => {
    const verifiedOrder: OrderReceipt = {
      ...baseOrder,
      status: 'confirmed',
      payment_status: 'advance_paid',
      advance_paid_paisa: 25000,
      total_paid_paisa: 25000,
      balance_due_paisa: 160000,
      hold_expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
    };

    render(<DirectUpiPaymentView order={verifiedOrder} orderToken={mockOrderToken} />);

    expect(screen.getByTestId('advance-verified-banner')).toBeInTheDocument();
    expect(screen.getByText('✓ Advance Payment Verified')).toBeInTheDocument();
    expect(screen.getByText(/Your order is confirmed/i)).toBeInTheDocument();
    expect(screen.getByText(/The ₹250 advance is part of your purchase price/)).toBeInTheDocument();
    expect(screen.getByText(/₹250\s+Paid/i)).toBeInTheDocument();
    expect(screen.getByText('₹1,600')).toBeInTheDocument();
  });

  it('UI-06: buyer reloads after verification expired -> shows verification expired banner', async () => {
    const expiredOrder: OrderReceipt = {
      ...baseOrder,
      status: 'cancelled',
      payment_status: 'unpaid',
      payment_attempt: {
        ...activeAttempt,
        status: 'expired',
      },
    };

    render(<DirectUpiPaymentView order={expiredOrder} orderToken={mockOrderToken} />);

    expect(screen.getByTestId('verification-expired-banner')).toBeInTheDocument();
    expect(screen.getByText(/Payment Verification Expired/i)).toBeInTheDocument();
    expect(screen.getByText(/This order could not be confirmed because the payment was not verified/)).toBeInTheDocument();
  });

  it('UI-07: buyer sees network retry state -> retry button triggers authoritative state refresh', async () => {
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockRejectedValueOnce(new Error('Network disconnected'));

    render(<DirectUpiPaymentView order={baseOrder} orderToken={mockOrderToken} />);

    // Simulate tab resumption triggering visibilitychange while network failed
    fireEvent(document, new Event('visibilitychange'));

    await waitFor(() => {
      expect(screen.getByTestId('network-refresh-error')).toBeInTheDocument();
      expect(screen.getByText(/Unable to refresh order status/)).toBeInTheDocument();
    });

    // Network recovers, buyer clicks retry
    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrder);
    const retryBtn = screen.getByTestId('retry-refresh-btn');
    fireEvent.click(retryBtn);

    await waitFor(() => {
      expect(screen.queryByTestId('network-refresh-error')).not.toBeInTheDocument();
    });
  });

  it('UI-08: buyer cannot accidentally initiate duplicate payment attempt when attempt is already active', async () => {
    const orderWithActiveAttempt: OrderReceipt = {
      ...baseOrder,
      payment_attempt: activeAttempt,
    };

    render(<DirectUpiPaymentView order={orderWithActiveAttempt} orderToken={mockOrderToken} />);

    await waitFor(() => {
      expect(screen.getByTestId('payee-vpa')).toHaveTextContent('priya@okaxis');
      expect(screen.getByTestId('payment-reference')).toHaveTextContent('LD1001-ADV');
    });

    // initiatePaymentAttempt must NOT have been called because active attempt already exists
    expect(buyerCatalog.initiatePaymentAttempt).not.toHaveBeenCalled();
  });
});
