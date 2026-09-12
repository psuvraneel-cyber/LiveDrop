import React from 'react';
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import CheckoutPage from '../app/checkout/page';
import { CartProvider, resetCartStore } from '../lib/cart/cart-context';
import { CART_STORAGE_KEY } from '../lib/cart/cart-storage';
import * as buyerCatalog from '../lib/data/buyer-catalog';
import { CreateOrderSuccessResponse, OrderReceipt, PublicProductView } from '../types/domain';
import { StockUnavailableError, NetworkError } from '../lib/errors';

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

describe('TASK-2.3: Buyer Checkout & Atomic Reservation (/checkout)', () => {
  const dropId = 'drop-test-uuid-01';

  const mockProduct1: PublicProductView = {
    id: 'prod-01',
    code: '#A01',
    title: 'Handloom Tussar Saree',
    price_paisa: 185000,
    size: 'Free Size',
    image_url: 'https://images.example.com/a01.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  };

  const mockProduct2: PublicProductView = {
    id: 'prod-02',
    code: '#A02',
    title: 'Chanderi Cotton Kurti',
    price_paisa: 75000,
    size: 'M',
    image_url: 'https://images.example.com/a02.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  };

  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    mockSearchParams = new URLSearchParams();
    vi.clearAllMocks();

    // Default mock for getPublicProductsForDrop
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
        dropId,
        items: items.map((item) => ({
          productId: item.id,
          dropId,
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

  describe('Direct Access & Cart Entry Conditions', () => {
    it('renders empty checkout state when navigating directly with empty bag', async () => {
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
    });

    it('renders pre-checkout review and buyer form when cart contains items', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
        { id: 'prod-02', code: '#A02', title: 'Chanderi Cotton Kurti', pricePaisa: 75000 },
      ]);

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('checkout-page')).toBeInTheDocument();
      });

      // Products in review
      expect(screen.getByTestId('checkout-code-prod-01')).toHaveTextContent('#A01');
      expect(screen.getByTestId('checkout-code-prod-02')).toHaveTextContent('#A02');
      expect(screen.getByTestId('checkout-subtotal')).toHaveTextContent('₹2,600');

      // Hold explanation
      expect(screen.getByTestId('checkout-hold-notice')).toBeInTheDocument();

      // Form inputs
      expect(screen.getByTestId('input-buyer-name')).toBeInTheDocument();
      expect(screen.getByTestId('input-buyer-phone')).toBeInTheDocument();
      expect(screen.getByTestId('input-pincode')).toBeInTheDocument();
      expect(screen.getByTestId('input-shipping-address')).toBeInTheDocument();
      expect(screen.getByTestId('checkout-submit-btn')).toBeInTheDocument();
    });

    it('blocks checkout submission and displays alert when an item is unavailable', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
      ]);

      // Mock catalog returning #A01 as reserved
      vi.spyOn(buyerCatalog, 'getPublicProductsForDrop').mockResolvedValue([
        { ...mockProduct1, status: 'reserved', reserved_at: '2026-09-11T14:00:00Z' },
      ]);

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('checkout-unavailable-banner')).toBeInTheDocument();
      });

      expect(screen.getByTestId('checkout-warning-prod-01')).toHaveTextContent('RESERVED — Claimed by another buyer');
      expect(screen.getByTestId('checkout-submit-btn')).toBeDisabled();
      expect(screen.getByTestId('checkout-remove-prod-01')).toBeInTheDocument();

      // Clicking remove cleans the item from cart
      fireEvent.click(screen.getByTestId('checkout-remove-prod-01'));

      await waitFor(() => {
        expect(screen.getByTestId('checkout-empty-state')).toBeInTheDocument();
      });
    });
  });

  describe('Form Validation UX', () => {
    it('validates required fields on submit attempt and highlights errors', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
      ]);

      const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation');

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('checkout-submit-btn')).toBeInTheDocument();
      });

      // Submit empty form
      fireEvent.click(screen.getByTestId('checkout-submit-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('error-buyer-name')).toHaveTextContent(/Full name is required/);
        expect(screen.getByTestId('error-buyer-phone')).toHaveTextContent(/Mobile number is required/);
        expect(screen.getByTestId('error-pincode')).toHaveTextContent(/Delivery pincode is required/);
        expect(screen.getByTestId('error-shipping-address')).toHaveTextContent(/Delivery address is required/);
      });

      expect(createOrderSpy).not.toHaveBeenCalled();
    });

    it('rejects invalid mobile numbers and non-6-digit pincodes', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
      ]);

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('input-buyer-phone')).toBeInTheDocument();
      });

      // Type invalid phone and pincode
      fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '12345' } });
      fireEvent.blur(screen.getByTestId('input-buyer-phone'));

      fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '7000' } });
      fireEvent.blur(screen.getByTestId('input-pincode'));

      await waitFor(() => {
        expect(screen.getByTestId('error-buyer-phone')).toHaveTextContent(/Valid 10-digit Indian mobile number/);
        expect(screen.getByTestId('error-pincode')).toHaveTextContent(/Valid 6-digit pincode/);
      });
    });
  });

  describe('RPC Integration, Price Authority & Single Flight', () => {
    it('submits checkout request with product IDs only and displays authoritative server pricing', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
      ]);

      const mockResponse: CreateOrderSuccessResponse = {
        success: true,
        order_id: 'ord-uuid-999',
        order_code: 'LD-9A8B7C',
        order_token: 'tok-uuid-888',
        subtotal_paisa: 185000,
        shipping_paisa: 8000,
        total_paisa: 193000, // Authoritative: ₹1,930.00
        confirmation_mode: 'advance',
        advance_required_paisa: 25000,
        advance_paid_paisa: 0,
        total_paid_paisa: 0,
        balance_due_paisa: 193000,
        payment_status: 'unpaid',
        fulfilment_status: 'not_ready',
        hold_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
      };

      const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockResolvedValue(mockResponse);

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('input-buyer-name')).toBeInTheDocument();
      });

      // Fill valid buyer details
      fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Debasmita Roy' } });
      fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830112345' } });
      fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700029' } });
      fireEvent.change(screen.getByTestId('input-shipping-address'), {
        target: { value: 'Flat 3C, 14 Lake Road, Southern Avenue, Kolkata' },
      });

      // Submit checkout
      fireEvent.click(screen.getByTestId('checkout-submit-btn'));

      await waitFor(() => {
        expect(createOrderSpy).toHaveBeenCalledTimes(1);
      });

      // Assert untrusted boundary: Client cart totals and prices were NOT sent
      expect(createOrderSpy).toHaveBeenCalledWith(
        expect.anything(),
        {
          p_drop_id: dropId,
          p_product_ids: ['prod-01'],
          p_buyer_name: 'Debasmita Roy',
          p_buyer_phone: '9830112345',
          p_shipping_address: 'Flat 3C, 14 Lake Road, Southern Avenue, Kolkata',
          p_pincode: '700029',
        }
      );

      // Verify success confirmation view
      await waitFor(() => {
        expect(screen.getByTestId('checkout-success-view')).toBeInTheDocument();
      });

      expect(screen.getByTestId('success-order-code')).toHaveTextContent('LD-9A8B7C');
      expect(screen.getByTestId('success-total')).toHaveTextContent('₹1,930');
      expect(screen.getByTestId('success-subtotal')).toHaveTextContent('₹1,850');
      expect(screen.getByTestId('success-shipping')).toHaveTextContent('₹80');
      expect(screen.getByTestId('hold-countdown')).toBeInTheDocument();
      expect(screen.getByTestId('task-handoff-box')).toBeInTheDocument();

      // Verify cart was cleared after successful reservation
      const stored = JSON.parse(window.localStorage.getItem(CART_STORAGE_KEY) || '{}');
      expect(stored.items || []).toHaveLength(0);
    });

    it('prevents duplicate submissions when clicking submit button multiple times in-flight', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
      ]);

      let resolvePromise: (val: CreateOrderSuccessResponse) => void;
      const delayedPromise = new Promise<CreateOrderSuccessResponse>((resolve) => {
        resolvePromise = resolve;
      });

      const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockReturnValue(delayedPromise);

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('input-buyer-name')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Debasmita Roy' } });
      fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830112345' } });
      fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700029' } });
      fireEvent.change(screen.getByTestId('input-shipping-address'), {
        target: { value: 'Flat 3C, 14 Lake Road, Southern Avenue, Kolkata' },
      });

      const submitBtn = screen.getByTestId('checkout-submit-btn');

      // Click once
      fireEvent.click(submitBtn);

      // Button enters disabled in-flight state
      expect(submitBtn).toBeDisabled();
      expect(screen.getByText(/Reserving Items with Database/)).toBeInTheDocument();

      // Click second time while in flight
      fireEvent.click(submitBtn);

      // Only 1 RPC invocation was triggered
      expect(createOrderSpy).toHaveBeenCalledTimes(1);

      // Resolve delayed promise
      resolvePromise!({
        success: true,
        order_id: 'ord-1',
        order_code: 'LD-111111',
        order_token: 'tok-1',
        subtotal_paisa: 185000,
        shipping_paisa: 8000,
        total_paisa: 193000,
        confirmation_mode: 'advance',
        advance_required_paisa: 25000,
        advance_paid_paisa: 0,
        total_paid_paisa: 0,
        balance_due_paisa: 193000,
        payment_status: 'unpaid',
        fulfilment_status: 'not_ready',
        hold_expires_at: new Date().toISOString(),
      });

      await waitFor(() => {
        expect(screen.getByTestId('checkout-success-view')).toBeInTheDocument();
      });
    });
  });

  describe('Failure Scenarios: Stock Collision & Ambiguous Network Outlay', () => {
    it('handles STOCK_UNAVAILABLE collision by showing conflict alert and preserving buyer form data', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
      ]);

      vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockRejectedValue(
        new StockUnavailableError(['prod-01'], 'One or more items in your cart have already been reserved.')
      );

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('input-buyer-name')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Pooja Sen' } });
      fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830099999' } });
      fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700019' } });
      fireEvent.change(screen.getByTestId('input-shipping-address'), {
        target: { value: '12 Ballygunge Circular Road, Kolkata' },
      });

      fireEvent.click(screen.getByTestId('checkout-submit-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('checkout-collision-error-banner')).toBeInTheDocument();
      });

      expect(screen.getByText(/Inventory Conflict Detected/)).toBeInTheDocument();

      // Crucial UX invariant: Form values are NOT erased on failure
      expect(screen.getByTestId('input-buyer-name')).toHaveValue('Pooja Sen');
      expect(screen.getByTestId('input-buyer-phone')).toHaveValue('9830099999');
      expect(screen.getByTestId('input-pincode')).toHaveValue('700019');
      expect(screen.getByTestId('input-shipping-address')).toHaveValue('12 Ballygunge Circular Road, Kolkata');

      // Cart is NOT cleared on collision failure
      const stored = JSON.parse(window.localStorage.getItem(CART_STORAGE_KEY) || '{}');
      expect(stored.items).toHaveLength(1);
    });

    it('handles network failure without blind automatic resubmission', async () => {
      populateCart([
        { id: 'prod-01', code: '#A01', title: 'Handloom Tussar Saree', pricePaisa: 185000 },
      ]);

      const createOrderSpy = vi.spyOn(buyerCatalog, 'createOrderWithReservation').mockRejectedValue(
        new NetworkError('Network request timed out.')
      );

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('input-buyer-name')).toBeInTheDocument();
      });

      fireEvent.change(screen.getByTestId('input-buyer-name'), { target: { value: 'Pooja Sen' } });
      fireEvent.change(screen.getByTestId('input-buyer-phone'), { target: { value: '9830099999' } });
      fireEvent.change(screen.getByTestId('input-pincode'), { target: { value: '700019' } });
      fireEvent.change(screen.getByTestId('input-shipping-address'), {
        target: { value: '12 Ballygunge Circular Road, Kolkata' },
      });

      fireEvent.click(screen.getByTestId('checkout-submit-btn'));

      await waitFor(() => {
        expect(screen.getByTestId('checkout-network-error-banner')).toBeInTheDocument();
      });

      expect(screen.getByText(/Connection Warning/)).toBeInTheDocument();
      expect(screen.getByText(/do not click submit repeatedly/)).toBeInTheDocument();

      // Assert it did not re-invoke the RPC automatically
      expect(createOrderSpy).toHaveBeenCalledTimes(1);
    });
  });

  describe('Token-Gated Order Receipt Lookup Mode', () => {
    it('fetches and displays authoritative receipt when order_id and token are in URL', async () => {
      mockSearchParams = new URLSearchParams({
        order_id: 'ord-uuid-123',
        token: 'token-uuid-456',
      });

      const mockReceipt: OrderReceipt = {
        id: 'ord-uuid-123',
        order_code: 'LD-42A9B1',
        buyer_name: 'Ananya Guha',
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
        hold_expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
        store_name: "Mother's Boutique",
        upi_id: 'mothersboutique@okaxis',
        upi_qr_url: null,
        items: [
          {
            product_id: 'prod-01',
            code: '#A01',
            title: 'Handloom Tussar Saree',
            image_url: '',
            price_at_purchase_paisa: 185000,
          },
        ],
      };

      const getOrderSpy = vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(mockReceipt);

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('checkout-page-receipt')).toBeInTheDocument();
      });

      expect(getOrderSpy).toHaveBeenCalledWith(expect.anything(), 'ord-uuid-123', 'token-uuid-456');
      expect(screen.getByTestId('success-order-code')).toHaveTextContent('LD-42A9B1');
      expect(screen.getByTestId('success-total')).toHaveTextContent('₹1,850');
      expect(screen.getByTestId('success-shipping')).toHaveTextContent('FREE');
    });

    it('displays receipt error state when order receipt cannot be retrieved', async () => {
      mockSearchParams = new URLSearchParams({
        order_id: 'ord-invalid',
        token: 'token-invalid',
      });

      vi.spyOn(buyerCatalog, 'getOrderByToken').mockRejectedValue(
        new Error('Order receipt not found or access denied.')
      );

      render(
        <CartProvider>
          <CheckoutPage />
        </CartProvider>
      );

      await waitFor(() => {
        expect(screen.getByTestId('checkout-receipt-error')).toBeInTheDocument();
      });

      expect(screen.getByText('Order Receipt Not Found')).toBeInTheDocument();
      expect(screen.getByText('Order receipt not found or access denied.')).toBeInTheDocument();
    });
  });
});
