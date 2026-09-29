import React from 'react';
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor, act } from '@testing-library/react';
import CheckoutPage from '../app/checkout/page';
import { HoldCountdown } from '../components/checkout/HoldCountdown';
import { CheckoutSuccessView } from '../components/checkout/CheckoutSuccessView';
import { DirectUpiPaymentView } from '../components/checkout/DirectUpiPaymentView';
import { CartProvider, resetCartStore } from '../lib/cart/cart-context';
import { CART_STORAGE_KEY } from '../lib/cart/cart-storage';
import * as buyerCatalog from '../lib/data/buyer-catalog';
import * as supabaseClient from '../lib/supabase/client';
import {
  CreateOrderSuccessResponse,
  OrderReceipt,
  PaymentAttempt,
  PublicProductView,
} from '../types/domain';
import { StockUnavailableError, NetworkError } from '../lib/errors';

// Mock Canvas getContext for confetti
if (typeof HTMLCanvasElement !== 'undefined') {
  HTMLCanvasElement.prototype.getContext = vi.fn().mockReturnValue({
    clearRect: vi.fn(),
    fillRect: vi.fn(),
    save: vi.fn(),
    restore: vi.fn(),
    translate: vi.fn(),
    rotate: vi.fn(),
  }) as unknown as typeof HTMLCanvasElement.prototype.getContext;
}

// Mock QRCode
vi.mock('qrcode', () => ({
  default: {
    toDataURL: vi.fn().mockResolvedValue('data:image/png;base64,mockqrdata'),
  },
}));

// Mock Next.js navigation
const mockPush = vi.fn();
let mockSearchParams = new URLSearchParams();

vi.mock('next/navigation', () => ({
  useRouter: () => ({
    push: mockPush,
    replace: vi.fn(),
    prefetch: vi.fn(),
    back: vi.fn(),
    forward: vi.fn(),
  }),
  useSearchParams: () => mockSearchParams,
  usePathname: () => '/checkout',
}));

describe('LiveDrop Phase 2: Checkout & Direct UPI Payment Presentation Gate', () => {
  const mockDropId = 'drop-festive-silk-001';
  const mockOrderId = 'order-uuid-999';
  const mockOrderToken = 'token-uuid-abc-123';
  const mockOrderCode = 'LD-FEST99';

  const mockProduct1: PublicProductView = {
    id: 'prod-01',
    code: '#S01',
    title: 'Banarasi Zari Handloom Saree',
    price_paisa: 185000,
    size: 'Free Size',
    image_url: 'https://images.example.com/s01.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  };

  const mockProduct2: PublicProductView = {
    id: 'prod-02',
    code: '#S02',
    title: 'Crimson Chanderi Silk Kurti',
    price_paisa: 75000,
    size: 'M',
    image_url: 'https://images.example.com/s02.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  };

  const baseOrderReceipt: OrderReceipt = {
    id: mockOrderId,
    order_code: mockOrderCode,
    buyer_name: 'Ananya Roy',
    subtotal_paisa: 260000,
    shipping_paisa: 8000,
    total_paisa: 268000,
    confirmation_mode: 'advance',
    advance_required_paisa: 50000,
    advance_paid_paisa: 0,
    total_paid_paisa: 0,
    balance_due_paisa: 268000,
    payment_status: 'unpaid',
    fulfilment_status: 'not_ready',
    status: 'pending',
    hold_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    store_name: 'Heritage Boutiques',
    store_slug: 'heritage-boutiques',
    upi_id: 'heritage@okaxis',
    upi_enabled: true,
    upi_qr_url: null,
    items: [
      {
        product_id: mockProduct1.id,
        code: mockProduct1.code,
        title: mockProduct1.title,
        price_at_purchase_paisa: mockProduct1.price_paisa,
        image_url: mockProduct1.image_url,
      },
      {
        product_id: mockProduct2.id,
        code: mockProduct2.code,
        title: mockProduct2.title,
        price_at_purchase_paisa: mockProduct2.price_paisa,
        image_url: mockProduct2.image_url,
      },
    ],
  };

  const basePaymentAttempt: PaymentAttempt = {
    id: 'attempt-uuid-001',
    order_id: mockOrderId,
    payment_type: 'advance',
    payment_method: 'upi',
    expected_amount_paisa: 50000,
    payee_vpa_snapshot: 'heritage@okaxis',
    payee_display_name_snapshot: 'Heritage Boutiques',
    transaction_reference: 'LD-FEST99-ADV',
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
    upi_uri: 'upi://pay?pa=heritage@okaxis&pn=Heritage%20Boutiques&am=500.00&tr=LD-FEST99-ADV&cu=INR',
  };

  interface MockRealtimeChannel {
    on: ReturnType<typeof vi.fn>;
    subscribe: ReturnType<typeof vi.fn>;
  }
  let mockChannel: MockRealtimeChannel;

  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    mockSearchParams = new URLSearchParams();
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

    vi.spyOn(buyerCatalog, 'getPublicProductsForDrop').mockResolvedValue([mockProduct1, mockProduct2]);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function populateCart(items: Array<{ id: string; code: string; title: string; pricePaisa: number; size?: string }>) {
    window.localStorage.setItem(
      CART_STORAGE_KEY,
      JSON.stringify({
        version: 1,
        dropId: mockDropId,
        items: items.map((item) => ({
          productId: item.id,
          dropId: mockDropId,
          code: item.code,
          title: item.title,
          pricePaisa: item.pricePaisa,
          imageUrl: '',
          size: item.size || 'Free Size',
          addedAt: Date.now(),
        })),
        updatedAt: Date.now(),
      })
    );
  }

  // =========================================================================
  // 1. Empty cart entering checkout
  // =========================================================================
  it('1. Empty cart entering checkout: displays luxury empty state and browse CTA', async () => {
    render(
      <CartProvider>
        <CheckoutPage />
      </CartProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('checkout-empty-state')).toBeInTheDocument();
    });

    expect(screen.getByText('Your Bag is Empty')).toBeInTheDocument();
    expect(screen.getByTestId('checkout-browse-btn')).toHaveAttribute('href', '/');
    expect(screen.queryByTestId('checkout-page')).not.toBeInTheDocument();
  });

  // =========================================================================
  // 2. Valid checkout form
  // =========================================================================
  it('2. Valid checkout form: accepts valid details and passes sanitized payload to createOrderWithReservation', async () => {
    populateCart([
      { id: mockProduct1.id, code: mockProduct1.code, title: mockProduct1.title, pricePaisa: mockProduct1.price_paisa },
    ]);

    const mockCreateResponse: CreateOrderSuccessResponse = {
      success: true,
      order_id: mockOrderId,
      order_code: mockOrderCode,
      order_token: mockOrderToken,
      subtotal_paisa: 185000,
      shipping_paisa: 8000,
      total_paisa: 193000,
      hold_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      confirmation_mode: 'full_payment',
      advance_required_paisa: 0,
      advance_paid_paisa: 0,
      balance_due_paisa: 193000,
      total_paid_paisa: 0,
      payment_status: 'unpaid',
      fulfilment_status: 'not_ready',
    };

    const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockResolvedValue(mockCreateResponse);

    render(
      <CartProvider>
        <CheckoutPage />
      </CartProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('checkout-page')).toBeInTheDocument();
    });

    // Fill valid form fields
    fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Sangeeta Mukherjee' } });
    fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830123456' } });
    fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700032' } });
    fireEvent.change(screen.getByTestId('input-shipping-address'), { target: { value: 'Flat 4B, Greenview Apts, Jadavpur' } });

    fireEvent.click(screen.getByTestId('checkout-submit-btn'));

    await waitFor(() => {
      expect(createOrderSpy).toHaveBeenCalledTimes(1);
    });

    const calledPayload = createOrderSpy.mock.calls[0][1];
    expect(calledPayload.p_drop_id).toBe(mockDropId);
    expect(calledPayload.p_product_ids).toEqual([mockProduct1.id]);
    expect(calledPayload.p_buyer_name).toBe('Sangeeta Mukherjee');
    expect(calledPayload.p_buyer_phone).toBe('9830123456');
    expect(calledPayload.p_pincode).toBe('700032');
    expect(calledPayload.p_shipping_address).toBe('Flat 4B, Greenview Apts, Jadavpur');

    // Transitions to success view
    await waitFor(() => {
      expect(screen.getByTestId('checkout-page-success')).toBeInTheDocument();
      expect(screen.getByTestId('success-order-code')).toHaveTextContent(mockOrderCode);
    });
  });

  // =========================================================================
  // 3. Invalid buyer fields
  // =========================================================================
  it('3. Invalid buyer fields: enforces client-side validation errors and blocks RPC dispatch', async () => {
    populateCart([
      { id: mockProduct1.id, code: mockProduct1.code, title: mockProduct1.title, pricePaisa: mockProduct1.price_paisa },
    ]);

    const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation');

    render(
      <CartProvider>
        <CheckoutPage />
      </CartProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('checkout-page')).toBeInTheDocument();
    });

    // Enter invalid phone and short pincode
    fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'A' } }); // too short
    fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '12345' } }); // invalid phone
    fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '99' } }); // invalid pincode
    fireEvent.change(screen.getByTestId('input-shipping-address'), { target: { value: 'Too short' } });

    fireEvent.click(screen.getByTestId('checkout-submit-btn'));

    await waitFor(() => {
      expect(screen.getByTestId('error-buyer-name')).toBeInTheDocument();
      expect(screen.getByTestId('error-buyer-phone')).toBeInTheDocument();
      expect(screen.getByTestId('error-pincode')).toBeInTheDocument();
      expect(screen.getByTestId('error-shipping-address')).toBeInTheDocument();
    });

    expect(createOrderSpy).not.toHaveBeenCalled();
  });

  // =========================================================================
  // 4. Authoritative subtotal/shipping/total display
  // =========================================================================
  it('4. Authoritative subtotal/shipping/total display: strictly formats integer Paisa without floating point math', () => {
    render(
      <CheckoutSuccessView
        order={{
          ...baseOrderReceipt,
          subtotal_paisa: 260000,
          shipping_paisa: 8000,
          total_paisa: 268000,
        }}
        orderToken={mockOrderToken}
      />
    );

    expect(screen.getByTestId('success-subtotal')).toHaveTextContent('₹2,600');
    expect(screen.getByTestId('success-shipping')).toHaveTextContent('₹80');
    expect(screen.getByTestId('success-total')).toHaveTextContent('₹2,680');
  });

  // =========================================================================
  // 5. Duplicate checkout submission
  // =========================================================================
  it('5. Duplicate checkout submission: single-flight lock disables button and prevents duplicate RPC execution', async () => {
    populateCart([
      { id: mockProduct1.id, code: mockProduct1.code, title: mockProduct1.title, pricePaisa: mockProduct1.price_paisa },
    ]);

    let resolveOrderPromise: (val: CreateOrderSuccessResponse) => void;
    const pendingOrderPromise = new Promise<CreateOrderSuccessResponse>((resolve) => {
      resolveOrderPromise = resolve;
    });

    const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockReturnValue(pendingOrderPromise);

    render(
      <CartProvider>
        <CheckoutPage />
      </CartProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('checkout-page')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Sangeeta Mukherjee' } });
    fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830123456' } });
    fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700032' } });
    fireEvent.change(screen.getByTestId('input-shipping-address'), { target: { value: 'Flat 4B, Greenview Apts, Jadavpur' } });

    const submitBtn = screen.getByTestId('checkout-submit-btn');
    fireEvent.click(submitBtn);

    // Button should now be disabled and show loading state
    expect(submitBtn).toBeDisabled();
    expect(screen.getByText(/Reserving Items with Database.../i)).toBeInTheDocument();

    // Secondary click attempt while in-flight
    fireEvent.click(submitBtn);

    expect(createOrderSpy).toHaveBeenCalledTimes(1);

    // Resolve in-flight request
    act(() => {
      resolveOrderPromise!({
        success: true,
        order_id: mockOrderId,
        order_code: mockOrderCode,
        order_token: mockOrderToken,
        subtotal_paisa: 185000,
        shipping_paisa: 8000,
        total_paisa: 193000,
        hold_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
        confirmation_mode: 'full_payment',
        advance_required_paisa: 0,
        advance_paid_paisa: 0,
        balance_due_paisa: 193000,
        total_paid_paisa: 0,
        payment_status: 'unpaid',
        fulfilment_status: 'not_ready',
      });
    });

    await waitFor(() => {
      expect(screen.getByTestId('checkout-page-success')).toBeInTheDocument();
    });
  });

  // =========================================================================
  // 6. Idempotent retry
  // =========================================================================
  it('6. Idempotent retry: generates and persists idempotency key across network interruption', async () => {
    populateCart([
      { id: mockProduct1.id, code: mockProduct1.code, title: mockProduct1.title, pricePaisa: mockProduct1.price_paisa },
    ]);

    const networkError = new NetworkError('Connection interrupted during checkout');
    const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockRejectedValueOnce(networkError);

    render(
      <CartProvider>
        <CheckoutPage />
      </CartProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('checkout-page')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Sangeeta Mukherjee' } });
    fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830123456' } });
    fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700032' } });
    fireEvent.change(screen.getByTestId('input-shipping-address'), { target: { value: 'Flat 4B, Greenview Apts, Jadavpur' } });

    fireEvent.click(screen.getByTestId('checkout-submit-btn'));

    await waitFor(() => {
      expect(screen.getByTestId('checkout-network-error-banner')).toBeInTheDocument();
    });

    const firstKey = createOrderSpy.mock.calls[0][1].p_idempotency_key;
    expect(firstKey).toBeTruthy();
    expect(screen.getByText(/We were unable to confirm whether your reservation succeeded/i)).toBeInTheDocument();
  });

  // =========================================================================
  // 7. Reservation conflict
  // =========================================================================
  it('7. Reservation conflict: handles StockUnavailableError and marks unavailable items clearly', async () => {
    populateCart([
      { id: mockProduct1.id, code: mockProduct1.code, title: mockProduct1.title, pricePaisa: mockProduct1.price_paisa },
    ]);

    const conflictErr = new StockUnavailableError(
      [mockProduct1.id],
      'One or more items in your cart are no longer available.'
    );
    vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockRejectedValueOnce(conflictErr);

    render(
      <CartProvider>
        <CheckoutPage />
      </CartProvider>
    );

    await waitFor(() => {
      expect(screen.getByTestId('checkout-page')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Sangeeta Mukherjee' } });
    fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830123456' } });
    fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700032' } });
    fireEvent.change(screen.getByTestId('input-shipping-address'), { target: { value: 'Flat 4B, Greenview Apts, Jadavpur' } });

    fireEvent.click(screen.getByTestId('checkout-submit-btn'));

    await waitFor(() => {
      expect(screen.getByTestId('checkout-collision-error-banner')).toBeInTheDocument();
    });

    expect(screen.getByText(/Inventory Conflict Detected/i)).toBeInTheDocument();
  });

  // =========================================================================
  // 8. Expired hold
  // =========================================================================
  it('8. Expired hold: HoldCountdown displays expired status pill when hold time has elapsed', () => {
    const expiredTimestamp = new Date(Date.now() - 5000).toISOString();

    render(<HoldCountdown expiresAt={expiredTimestamp} />);

    expect(screen.getByTestId('hold-countdown-expired')).toBeInTheDocument();
    expect(screen.getByText('Hold period has expired')).toBeInTheDocument();
  });

  // =========================================================================
  // 9. Receipt and order-token retention
  // =========================================================================
  it('9. Receipt and order-token retention: preserves cached token and retrieves authoritative order by token', async () => {
    mockSearchParams = new URLSearchParams(`order_id=${mockOrderId}&token=${mockOrderToken}`);

    const getOrderSpy = vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(baseOrderReceipt);

    render(
      <CartProvider>
        <CheckoutPage />
      </CartProvider>
    );

    await waitFor(() => {
      expect(getOrderSpy).toHaveBeenCalledWith(expect.anything(), mockOrderId, mockOrderToken);
    });

    await waitFor(() => {
      expect(screen.getByTestId('checkout-page-receipt')).toBeInTheDocument();
      expect(screen.getByTestId('success-order-code')).toHaveTextContent(mockOrderCode);
    });
  });

  // =========================================================================
  // 10. UPI attempt creation
  // =========================================================================
  it('10. UPI attempt creation: automatically calls initiate_payment_attempt when unpaid order mounts', async () => {
    const initiateSpy = vi.spyOn(buyerCatalog, 'initiatePaymentAttempt').mockResolvedValue({
      success: true,
      payment_attempt_id: basePaymentAttempt.id,
      order_id: mockOrderId,
      payment_type: 'advance',
      expected_amount_paisa: 50000,
      payee_vpa: 'heritage@okaxis',
      payee_display_name: 'Heritage Boutiques',
      transaction_reference: 'LD-FEST99-ADV',
      upi_uri: basePaymentAttempt.upi_uri!,
      status: 'awaiting_payment',
      expires_at: basePaymentAttempt.expires_at,
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: null,
        }}
        orderToken={mockOrderToken}
      />
    );

    await waitFor(() => {
      expect(initiateSpy).toHaveBeenCalledWith(expect.anything(), mockOrderId, mockOrderToken, 'advance');
    });

    await waitFor(() => {
      expect(screen.getByTestId('payee-vpa')).toHaveTextContent('heritage@okaxis');
      expect(screen.getByTestId('payment-expected-amount')).toHaveTextContent('₹500');
    });
  });

  // =========================================================================
  // 11. Reuse of active payment attempt
  // =========================================================================
  it('11. Reuse of active payment attempt: reuses existing active attempt without triggering duplicate RPC', async () => {
    const initiateSpy = vi.spyOn(buyerCatalog, 'initiatePaymentAttempt');

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: basePaymentAttempt,
        }}
        orderToken={mockOrderToken}
      />
    );

    await waitFor(() => {
      expect(screen.getByTestId('payee-vpa')).toHaveTextContent(basePaymentAttempt.payee_vpa_snapshot);
    });

    // initiatePaymentAttempt should NOT be called since active_payment_attempt was supplied
    expect(initiateSpy).not.toHaveBeenCalled();
  });

  // =========================================================================
  // 12. UTR validation
  // =========================================================================
  it('12. UTR validation: blocks submission for empty, too short, or malformed UTR codes', async () => {
    const claimSpy = vi.spyOn(buyerCatalog, 'submitBuyerPaymentClaim');

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: basePaymentAttempt,
        }}
        orderToken={mockOrderToken}
      />
    );

    await waitFor(() => {
      expect(screen.getByTestId('utr-submission-form')).toBeInTheDocument();
    });

    // Empty submission
    fireEvent.click(screen.getByTestId('submit-payment-claim-btn'));

    await waitFor(() => {
      expect(screen.getByTestId('utr-field-error')).toHaveTextContent('Please enter your 12-digit UPI reference (UTR)');
    });
    expect(claimSpy).not.toHaveBeenCalled();

    // Invalid symbols
    fireEvent.change(screen.getByTestId('utr-input-field'), { target: { value: 'UTR@#$!%' } });
    fireEvent.click(screen.getByTestId('submit-payment-claim-btn'));

    await waitFor(() => {
      expect(screen.getByTestId('utr-field-error')).toHaveTextContent('UTR must be 6–35 alphanumeric characters');
    });
    expect(claimSpy).not.toHaveBeenCalled();
  });

  // =========================================================================
  // 13. Claim submission
  // =========================================================================
  it('13. Claim submission: submits valid UTR and updates active attempt to awaiting_seller_verification', async () => {
    const claimSpy = vi.spyOn(buyerCatalog, 'submitBuyerPaymentClaim').mockResolvedValue({
      success: true,
      payment_attempt_id: basePaymentAttempt.id,
      order_id: mockOrderId,
      buyer_submitted_utr: '428739182734',
      status: 'awaiting_seller_verification',
      buyer_claimed_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      verification_expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
      message: 'Payment claim registered successfully',
    });

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue({
      ...baseOrderReceipt,
      active_payment_attempt: {
        ...basePaymentAttempt,
        status: 'awaiting_seller_verification',
        buyer_submitted_utr: '428739182734',
      },
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: basePaymentAttempt,
        }}
        orderToken={mockOrderToken}
      />
    );

    await waitFor(() => {
      expect(screen.getByTestId('utr-input-field')).toBeInTheDocument();
    });

    fireEvent.change(screen.getByTestId('utr-input-field'), { target: { value: '428739182734' } });
    fireEvent.click(screen.getByTestId('submit-payment-claim-btn'));

    await waitFor(() => {
      expect(claimSpy).toHaveBeenCalledWith(
        expect.anything(),
        mockOrderId,
        mockOrderToken,
        basePaymentAttempt.id,
        '428739182734'
      );
    });

    await waitFor(() => {
      expect(screen.getByTestId('payment-claimed-card')).toBeInTheDocument();
      expect(screen.getByTestId('safe-to-close-notice')).toBeInTheDocument();
      expect(screen.getByTestId('submitted-utr-val')).toHaveTextContent('••••••••2734');
    });
  });

  // =========================================================================
  // 14. Seller verification state
  // =========================================================================
  it('14. Seller verification state: shows pending verification banner with safe-to-close advice', () => {
    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: {
            ...basePaymentAttempt,
            status: 'awaiting_seller_verification',
            buyer_submitted_utr: '998877665544',
            verification_expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          },
        }}
        orderToken={mockOrderToken}
      />
    );

    expect(screen.getByTestId('payment-claimed-card')).toBeInTheDocument();
    expect(screen.getByText('Payment Verification Pending')).toBeInTheDocument();
    expect(screen.getByTestId('safe-to-close-notice')).toBeInTheDocument();
    expect(screen.getByTestId('do-not-pay-again-warning')).toBeInTheDocument();
    expect(screen.getByTestId('verification-deadline')).toBeInTheDocument();
  });

  // =========================================================================
  // 15. Seller rejection state
  // =========================================================================
  it('15. Seller rejection state: renders non-accusatory rejection notice and re-submission form', async () => {
    const claimSpy = vi.spyOn(buyerCatalog, 'submitBuyerPaymentClaim').mockResolvedValue({
      success: true,
      payment_attempt_id: basePaymentAttempt.id,
      order_id: mockOrderId,
      buyer_submitted_utr: '123456789012',
      status: 'awaiting_seller_verification',
      buyer_claimed_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      message: 'Payment claim registered successfully',
    });

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue({
      ...baseOrderReceipt,
      active_payment_attempt: {
        ...basePaymentAttempt,
        status: 'awaiting_seller_verification',
        buyer_submitted_utr: '123456789012',
      },
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: {
            ...basePaymentAttempt,
            status: 'rejected',
            rejection_reason: 'Amount mismatch in bank statement',
          },
        }}
        orderToken={mockOrderToken}
      />
    );

    expect(screen.getByTestId('payment-rejected-card')).toBeInTheDocument();
    expect(screen.getByText(/Amount mismatch in bank statement/i)).toBeInTheDocument();
    expect(screen.getByTestId('utr-retry-input')).toBeInTheDocument();

    // Re-submit corrected UTR
    fireEvent.change(screen.getByTestId('utr-retry-input'), { target: { value: '123456789012' } });
    fireEvent.click(screen.getByTestId('retry-claim-btn'));

    await waitFor(() => {
      expect(claimSpy).toHaveBeenCalledWith(
        expect.anything(),
        mockOrderId,
        mockOrderToken,
        basePaymentAttempt.id,
        '123456789012'
      );
    });
  });

  // =========================================================================
  // 16. Payment expiry
  // =========================================================================
  it('16. Payment expiry: renders terminal expired banner when 24h verification window has elapsed', () => {
    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          status: 'expired',
          active_payment_attempt: {
            ...basePaymentAttempt,
            status: 'expired',
          },
        }}
        orderToken={mockOrderToken}
      />
    );

    expect(screen.getByTestId('verification-expired-banner')).toBeInTheDocument();
    expect(screen.getByText('Verification Window Elapsed')).toBeInTheDocument();
    expect(screen.getByText(/product reservation has been released/i)).toBeInTheDocument();
  });

  // =========================================================================
  // 17. Realtime payment update
  // =========================================================================
  it('17. Realtime payment update: subscribes to order & payment_attempts channel and refreshes on change', async () => {
    let capturedCallback: () => void = () => {};

    mockChannel.on = vi.fn().mockImplementation((_event, _filter, callback) => {
      capturedCallback = callback;
      return mockChannel;
    });

    const getOrderSpy = vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue({
      ...baseOrderReceipt,
      payment_status: 'paid',
      total_paid_paisa: 268000,
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: basePaymentAttempt,
        }}
        orderToken={mockOrderToken}
      />
    );

    expect(mockChannel.subscribe).toHaveBeenCalled();

    // Trigger realtime broadcast
    await act(async () => {
      capturedCallback();
    });

    await waitFor(() => {
      expect(getOrderSpy).toHaveBeenCalled();
    });
  });

  // =========================================================================
  // 18. Polling fallback
  // =========================================================================
  it('18. Polling fallback: triggers adaptive refresh while awaiting verification', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });

    const getOrderSpy = vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue({
      ...baseOrderReceipt,
      active_payment_attempt: {
        ...basePaymentAttempt,
        status: 'awaiting_seller_verification',
        buyer_submitted_utr: '998877665544',
      },
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: {
            ...basePaymentAttempt,
            status: 'awaiting_seller_verification',
            buyer_submitted_utr: '998877665544',
          },
        }}
        orderToken={mockOrderToken}
      />
    );

    // Advance 6.5s to trigger first interval (5s + random jitter up to 1s)
    await act(async () => {
      await vi.advanceTimersByTimeAsync(6500);
    });

    expect(getOrderSpy).toHaveBeenCalled();

    vi.useRealTimers();
  });

  // =========================================================================
  // 19. Refresh while awaiting verification
  // =========================================================================
  it('19. Refresh while awaiting verification: network error displays retry button and successfully refetches', async () => {
    const getOrderSpy = vi
      .spyOn(buyerCatalog, 'getOrderByToken')
      .mockRejectedValueOnce(new Error('Network error on refresh'))
      .mockResolvedValueOnce({
        ...baseOrderReceipt,
        active_payment_attempt: {
          ...basePaymentAttempt,
          status: 'awaiting_seller_verification',
          buyer_submitted_utr: '998877665544',
        },
      });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          active_payment_attempt: {
            ...basePaymentAttempt,
            status: 'awaiting_seller_verification',
            buyer_submitted_utr: '998877665544',
          },
        }}
        orderToken={mockOrderToken}
      />
    );

    // Simulate focus event triggering refresh
    await act(async () => {
      window.dispatchEvent(new Event('focus'));
    });

    await waitFor(() => {
      expect(screen.getByTestId('network-refresh-error')).toBeInTheDocument();
      expect(screen.getByTestId('retry-refresh-btn')).toBeInTheDocument();
    });

    // Tap retry button
    fireEvent.click(screen.getByTestId('retry-refresh-btn'));

    await waitFor(() => {
      expect(getOrderSpy).toHaveBeenCalledTimes(2);
      expect(screen.queryByTestId('network-refresh-error')).not.toBeInTheDocument();
    });
  });

  // =========================================================================
  // 20. Advance payment
  // =========================================================================
  it('20. Advance payment: supports advance confirmation mode and shows Option 1 tab', async () => {
    const initiateSpy = vi.spyOn(buyerCatalog, 'initiatePaymentAttempt').mockResolvedValue({
      success: true,
      payment_attempt_id: 'att-advance-1',
      order_id: mockOrderId,
      payment_type: 'advance',
      expected_amount_paisa: 50000,
      payee_vpa: 'heritage@okaxis',
      payee_display_name: 'Heritage Boutiques',
      transaction_reference: 'LD-FEST99-ADV',
      upi_uri: 'upi://pay?pa=heritage@okaxis&am=500.00',
      status: 'awaiting_payment',
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          confirmation_mode: 'advance',
          advance_required_paisa: 50000,
          payment_status: 'unpaid',
          active_payment_attempt: null,
        }}
        orderToken={mockOrderToken}
      />
    );

    await waitFor(() => {
      expect(screen.getByTestId('tab-pay-advance')).toBeInTheDocument();
      expect(screen.getByTestId('tab-pay-full')).toBeInTheDocument();
    });

    expect(screen.getByRole('heading', { level: 3 })).toHaveTextContent('Pay ₹500 Advance');
    expect(initiateSpy).toHaveBeenCalledWith(expect.anything(), mockOrderId, mockOrderToken, 'advance');
  });

  // =========================================================================
  // 21. Balance payment
  // =========================================================================
  it('21. Balance payment: switches to balance payment mode when advance is verified', async () => {
    const initiateSpy = vi.spyOn(buyerCatalog, 'initiatePaymentAttempt').mockResolvedValue({
      success: true,
      payment_attempt_id: 'att-bal-1',
      order_id: mockOrderId,
      payment_type: 'balance',
      expected_amount_paisa: 218000,
      payee_vpa: 'heritage@okaxis',
      payee_display_name: 'Heritage Boutiques',
      transaction_reference: 'LD-FEST99-BAL',
      upi_uri: 'upi://pay?pa=heritage@okaxis&am=2180.00',
      status: 'awaiting_payment',
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          payment_status: 'advance_paid',
          advance_paid_paisa: 50000,
          total_paid_paisa: 50000,
          balance_due_paisa: 218000,
          active_payment_attempt: null,
        }}
        orderToken={mockOrderToken}
      />
    );

    await waitFor(() => {
      expect(screen.getByTestId('advance-verified-banner')).toBeInTheDocument();
    });

    expect(initiateSpy).toHaveBeenCalledWith(expect.anything(), mockOrderId, mockOrderToken, 'balance');
    expect(screen.getByText(/Remaining Balance:/i)).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 3 })).toHaveTextContent('Pay Remaining Balance (₹2,180)');
  });

  // =========================================================================
  // 22. Full payment
  // =========================================================================
  it('22. Full payment: allows switching to Pay in Full option and generates full payment attempt', async () => {
    const initiateSpy = vi.spyOn(buyerCatalog, 'initiatePaymentAttempt').mockResolvedValue({
      success: true,
      payment_attempt_id: 'att-full-1',
      order_id: mockOrderId,
      payment_type: 'full',
      expected_amount_paisa: 268000,
      payee_vpa: 'heritage@okaxis',
      payee_display_name: 'Heritage Boutiques',
      transaction_reference: 'LD-FEST99-FULL',
      upi_uri: 'upi://pay?pa=heritage@okaxis&am=2680.00',
      status: 'awaiting_payment',
      expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
    });

    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          confirmation_mode: 'advance',
          advance_required_paisa: 50000,
          payment_status: 'unpaid',
          active_payment_attempt: basePaymentAttempt,
        }}
        orderToken={mockOrderToken}
      />
    );

    await waitFor(() => {
      expect(screen.getByTestId('tab-pay-full')).toBeInTheDocument();
    });

    // Click Pay in Full tab
    fireEvent.click(screen.getByTestId('tab-pay-full'));

    await waitFor(() => {
      expect(initiateSpy).toHaveBeenCalledWith(expect.anything(), mockOrderId, mockOrderToken, 'full');
    });

    expect(screen.getByRole('heading', { level: 3 })).toHaveTextContent('Pay in Full (₹2,680)');
  });

  // =========================================================================
  // 23. Shipping blocked while balance remains
  // =========================================================================
  it('23. Shipping blocked while balance remains: displays warning that courier dispatch is held until remaining balance is settled', () => {
    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          payment_status: 'advance_paid',
          advance_paid_paisa: 50000,
          balance_due_paisa: 218000,
          active_payment_attempt: null,
        }}
        orderToken={mockOrderToken}
      />
    );

    expect(screen.getByTestId('shipping-blocked-balance-notice')).toBeInTheDocument();
    expect(screen.getByText(/Shipment and courier dispatch are held until the remaining balance/i)).toBeInTheDocument();
  });

  // =========================================================================
  // 24. No false-positive payment success
  // =========================================================================
  it('24. No false-positive payment success: opening UPI link does NOT show payment verified banner', () => {
    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          payment_status: 'unpaid',
          active_payment_attempt: basePaymentAttempt,
        }}
        orderToken={mockOrderToken}
      />
    );

    const upiButton = screen.getByTestId('pay-with-upi-intent-btn');
    expect(upiButton).toBeInTheDocument();

    // Click UPI app button
    fireEvent.click(upiButton);

    // Shows that UPI app was opened, but emphatically NOT payment verified!
    expect(screen.getByTestId('upi-app-opened-banner')).toBeInTheDocument();
    expect(screen.getByText(/Opening a UPI link does not complete payment/i)).toBeInTheDocument();

    // Verification banner MUST NOT exist
    expect(screen.queryByTestId('payment-verified-banner')).not.toBeInTheDocument();

    // Only authoritative backend payment_status = 'paid' triggers verified banner
    render(
      <DirectUpiPaymentView
        order={{
          ...baseOrderReceipt,
          payment_status: 'paid',
          total_paid_paisa: 268000,
          active_payment_attempt: {
            ...basePaymentAttempt,
            status: 'verified',
          },
        }}
        orderToken={mockOrderToken}
      />
    );

    expect(screen.getByTestId('payment-verified-banner')).toBeInTheDocument();
    expect(screen.getByText('Full Payment Settled')).toBeInTheDocument();
  });
});
