/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 11 (Order Tracking & Receipt)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 23 & ORIGINAL_REQUEST.md R9
 *
 * Test Inventory (>=5 tests):
 * 1. Blocks unauthorized access when order access token is missing (DPDP Act compliance)
 * 2. Renders order tracking view with order code, boutique, and formatted price
 * 3. Renders reserved items list with thumbnail, code (#A01), title, and price
 * 4. Renders vertical status progression timeline with gold checkmarks
 * 5. Displays authoritative database financial breakdown (Subtotal, Shipping, Total)
 * 6. Renders mobile bottom navigation dock with Orders tab marked active
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, waitFor } from '@testing-library/react';
import OrderTrackingPage from '../../app/order/[id]/page';
import * as buyerCatalog from '../../lib/data/buyer-catalog';
import { mockOrderReceiptFull } from './fixtures/mock-catalog-data';
import { renderWithProviders } from './fixtures/test-providers';

// Mock useParams and useSearchParams for order/[id]
const mockParams = { id: 'order-uuid-101' };
let mockSearchParamsGet = vi.fn((key: string) => {
  if (key === 'token') return 'valid-token-123';
  return null;
});

vi.mock('next/navigation', async () => {
  const actual = await vi.importActual('next/navigation');
  return {
    ...actual,
    useParams: () => mockParams,
    useSearchParams: () => ({
      get: (key: string) => mockSearchParamsGet(key),
    }),
    useRouter: () => ({
      push: vi.fn(),
      replace: vi.fn(),
    }),
  };
});

describe('Tier 1: Screen 11 — Order Tracking & Receipt View', () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.clearAllMocks();
    mockSearchParamsGet = vi.fn((key: string) => {
      if (key === 'token') return 'valid-token-123';
      return null;
    });

    vi.spyOn(buyerCatalog, 'getOrderByToken').mockResolvedValue(mockOrderReceiptFull);
  });

  it('blocks unauthorized access and displays DPDP notice when token is missing', async () => {
    mockSearchParamsGet = vi.fn(() => null);

    renderWithProviders(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('order-access-restricted')).toBeInTheDocument();
    });
    expect(screen.getByText(/Order Access Restricted/i)).toBeInTheDocument();
    expect(screen.getByText(/DPDP Act/i)).toBeInTheDocument();
  });

  it('renders order tracking view with order code and success header', async () => {
    renderWithProviders(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('checkout-success-view')).toBeInTheDocument();
    });
    expect(screen.getByTestId('success-order-code')).toHaveTextContent(mockOrderReceiptFull.order_code);
    expect(screen.getByText(/Thank You!/i)).toBeInTheDocument();
  });

  it('renders reserved item card with code (#A01), title, and formatted price', async () => {
    renderWithProviders(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('checkout-success-view')).toBeInTheDocument();
    });

    const itemRow = screen.getByTestId('success-item-prod-saree-a01');
    expect(itemRow).toBeInTheDocument();
    expect(itemRow).toHaveTextContent('#A01');
    expect(itemRow).toHaveTextContent('Handloom Tussar Silk Saree');
    expect(itemRow).toHaveTextContent('₹1,850');
  });

  it('renders vertical status progression timeline with active status description', async () => {
    renderWithProviders(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByLabelText('Order Status Progression')).toBeInTheDocument();
    });

    expect(screen.getByText('Payment Submitted')).toBeInTheDocument();
    expect(screen.getByText('Awaiting Seller Verification')).toBeInTheDocument();
    expect(screen.getByText('Delivered')).toBeInTheDocument();
  });

  it('displays authoritative database financial breakdown (Subtotal, Delivery, Total)', async () => {
    renderWithProviders(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('success-subtotal')).toBeInTheDocument();
    });

    expect(screen.getByTestId('success-subtotal')).toHaveTextContent('₹1,850');
    expect(screen.getByTestId('success-shipping')).toHaveTextContent('FREE');
    expect(screen.getByTestId('success-total')).toHaveTextContent('₹1,850');
  });

  it('renders mobile bottom navigation dock with Orders tab marked active', async () => {
    renderWithProviders(<OrderTrackingPage />);

    await waitFor(() => {
      expect(screen.getByTestId('dock-orders-tab')).toBeInTheDocument();
    });

    const ordersTab = screen.getByTestId('dock-orders-tab');
    expect(ordersTab).toHaveClass('active');
  });
});
