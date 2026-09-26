/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 10 (Orders Directory & Lookup)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 22 & ORIGINAL_REQUEST.md R9
 *
 * Test Inventory (>=5 tests):
 * 1. Renders minimal header with LiveDrop brand and ORDERS title
 * 2. Displays luxury segmented tabs ("Recent Orders" and "Saved Pieces")
 * 3. Renders saved order cards with thumbnail icon, order code, boutique name, and formatted price
 * 4. Displays formatted order status badge
 * 5. Provides manual order number / tracking link lookup form
 * 6. Renders mobile bottom dock with Orders tab marked active
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import OrderLookupPage from '../../app/order/page';
import { renderWithProviders } from './fixtures/test-providers';
import { saveRecentOrderSummary } from '../../lib/cart/cart-storage';

describe('Tier 1: Screen 10 — Orders Directory & Lookup', () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.clearAllMocks();
  });

  it('renders minimal header with LiveDrop brand and ORDERS title', () => {
    renderWithProviders(<OrderLookupPage />);

    expect(screen.getByText(/LiveDrop ORDERS/i)).toBeInTheDocument();
    expect(screen.getByText(/Track Your Order/i)).toBeInTheDocument();
  });

  it('displays luxury segmented tabs for Recent Orders and Saved Pieces', () => {
    renderWithProviders(<OrderLookupPage />);

    expect(screen.getByRole('tab', { name: /Recent Orders/i })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: /Saved Pieces/i })).toBeInTheDocument();
  });

  it('renders cached order cards with thumbnail icon, code, boutique, and formatted price', () => {
    saveRecentOrderSummary({
      id: 'order-uuid-101',
      token: 'token-abc-123',
      orderCode: 'LD-9X4M2P',
      storeName: "Sonali's Boutique",
      totalPaisa: 185000,
      paymentStatus: 'verified',
      fulfilmentStatus: 'not_ready',
    });

    renderWithProviders(<OrderLookupPage />);

    expect(screen.getByTestId('recent-order-item-order-uuid-101')).toBeInTheDocument();
    expect(screen.getByText(/LD-9X4M2P/i)).toBeInTheDocument();
    expect(screen.getByText("Sonali's Boutique")).toBeInTheDocument();
    expect(screen.getByText('₹1,850')).toBeInTheDocument();
    expect(screen.getByText('Payment Verified')).toBeInTheDocument();
  });

  it('switches between Recent Orders and Saved Pieces tabs', () => {
    renderWithProviders(<OrderLookupPage />);

    const savedTab = screen.getByRole('tab', { name: /Saved Pieces/i });
    fireEvent.click(savedTab);

    expect(savedTab).toHaveClass('text-[#D4AF37]');
  });

  it('renders manual lookup form for searching by order number or link', () => {
    renderWithProviders(<OrderLookupPage />);

    expect(screen.getByLabelText(/Order Number or Tracking Link/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Receipt Access Key/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Retrieve Order Receipt/i })).toBeInTheDocument();
  });

  it('renders mobile bottom navigation dock with Orders tab marked active', () => {
    renderWithProviders(<OrderLookupPage />);

    const ordersTab = screen.getByTestId('dock-orders-tab');
    expect(ordersTab).toBeInTheDocument();
    expect(ordersTab).toHaveClass('active');
  });
});
