import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import OrderTrackingPage from '../app/order/[id]/page';
import * as buyerCatalog from '../lib/data/buyer-catalog';
import { cacheOrderToken, getCachedOrderToken } from '../lib/cart/cart-storage';
import { OrderReceipt } from '../types/domain';
import { InvalidOrderTokenError } from '../lib/errors';

let mockParams: { id?: string } = { id: 'order-uuid-123' };
let mockSearchParams = new URLSearchParams();

vi.mock('next/navigation', () => ({
  useParams: () => mockParams,
  useSearchParams: () => mockSearchParams,
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
  }),
}));

describe('Dedicated Order Tracking Route (/order/[id])', () => {
  const mockOrderReceipt: OrderReceipt = {
    id: 'order-uuid-123',
    order_code: 'LD-9X4M2P',
    buyer_name: 'Priya Sharma',
    subtotal_paisa: 150000,
    shipping_paisa: 0,
    total_paisa: 150000,
    confirmation_mode: 'full_payment',
    advance_required_paisa: 150000,
    advance_paid_paisa: 0,
    total_paid_paisa: 0,
    balance_due_paisa: 150000,
    payment_status: 'unpaid',
    fulfilment_status: 'not_ready',
    status: 'pending',
    hold_expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    store_name: "Mother's Boutique",
    store_slug: 'mothers-boutique',
    upi_id: 'boutique@okaxis',
    upi_qr_url: null,
    items: [
      {
        product_id: 'prod-01',
        code: '#A01',
        title: 'Silk Kurti',
        image_url: 'https://example.com/a01.jpg',
        price_at_purchase_paisa: 150000,
      },
    ],
  };

  beforeEach(() => {
    window.localStorage.clear();
    mockParams = { id: 'order-uuid-123' };
    mockSearchParams = new URLSearchParams();
    vi.clearAllMocks();
  });

  it('renders order receipt successfully when valid ?token= is provided in URL', async () => {
    mockSearchParams = new URLSearchParams('token=valid-token-abc');
    const getOrderSpy = vi
      .spyOn(buyerCatalog, 'getOrderByToken')
      .mockResolvedValue(mockOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-tracking-page')).toBeInTheDocument();
    });

    expect(getOrderSpy).toHaveBeenCalledWith(
      expect.anything(),
      'order-uuid-123',
      'valid-token-abc'
    );
    expect(screen.getByText('LD-9X4M2P')).toBeInTheDocument();
    expect(screen.getByText('Silk Kurti')).toBeInTheDocument();
  });

  it('falls back to strictly matching cached token in localStorage when ?token= is missing', async () => {
    mockSearchParams = new URLSearchParams();
    cacheOrderToken('order-uuid-123', 'cached-token-xyz');

    const getOrderSpy = vi
      .spyOn(buyerCatalog, 'getOrderByToken')
      .mockResolvedValue(mockOrderReceipt);

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-tracking-page')).toBeInTheDocument();
    });

    expect(getOrderSpy).toHaveBeenCalledWith(
      expect.anything(),
      'order-uuid-123',
      'cached-token-xyz'
    );
    expect(screen.getByText('LD-9X4M2P')).toBeInTheDocument();
  });

  it('shows privacy protection error screen when token is missing from URL and localStorage', async () => {
    mockSearchParams = new URLSearchParams(); // No token

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-access-restricted')).toBeInTheDocument();
    });

    expect(screen.getByText('Order Access Restricted')).toBeInTheDocument();
    expect(screen.queryByText('Silk Kurti')).not.toBeInTheDocument();
  });

  it('purges cached token from localStorage when backend validation fails', async () => {
    cacheOrderToken('order-uuid-123', 'stale-token');
    mockSearchParams = new URLSearchParams();

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockRejectedValue(
      new InvalidOrderTokenError('Invalid or expired access token.')
    );

    render(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-access-restricted')).toBeInTheDocument();
    });

    // Verify token was erased from localStorage upon invalidation
    expect(getCachedOrderToken('order-uuid-123')).toBeNull();
  });
});
