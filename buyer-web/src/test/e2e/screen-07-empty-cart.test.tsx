/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 07 (Empty Cart State)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 19 & ORIGINAL_REQUEST.md R7
 *
 * Test Inventory (>=5 tests):
 * 1. Renders empty cart container with data-testid="cart-empty-state"
 * 2. Displays display serif heading "Your bag is empty"
 * 3. Displays editorial subtitle "Discover unique pieces from independent boutiques."
 * 4. Renders primary gold CTA "Explore Shop" linking to /shop with data-testid="cart-browse-btn"
 * 5. Verifies empty cart illustration is marked aria-hidden for screen-reader accessibility
 * 6. Renders empty state within CartDrawer variant when bag has 0 pieces
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import CartPage from '../../app/cart/page';
import { CartEmptyState } from '../../components/cart/CartEmptyState';
import { CartDrawer } from '../../components/cart/CartDrawer';
import { mockLiveDrop } from './fixtures/mock-catalog-data';
import { renderWithProviders } from './fixtures/test-providers';
import { resetCartStore } from '../../lib/cart/cart-context';

describe('Tier 1: Screen 07 — Empty Cart State', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    vi.clearAllMocks();
  });

  it('renders cart page in empty state when no items are in cart storage', () => {
    renderWithProviders(<CartPage />);

    expect(screen.getByTestId('cart-empty-state')).toBeInTheDocument();
  });

  it('displays display serif heading "Your bag is empty"', () => {
    renderWithProviders(<CartEmptyState />);

    const heading = screen.getByRole('heading', { level: 3 });
    expect(heading).toHaveTextContent('Your bag is empty');
  });

  it('displays editorial subtitle discovering independent boutiques', () => {
    renderWithProviders(<CartEmptyState />);

    expect(
      screen.getByText('Discover unique pieces from independent boutiques.')
    ).toBeInTheDocument();
  });

  it('renders gold CTA linking to /shop with data-testid="cart-browse-btn"', () => {
    renderWithProviders(<CartEmptyState />);

    const browseBtn = screen.getByTestId('cart-browse-btn');
    expect(browseBtn).toBeInTheDocument();
    expect(browseBtn).toHaveTextContent(/Explore Shop/i);
    expect(browseBtn).toHaveAttribute('href', '/shop');
  });

  it('ensures illustration graphic is marked aria-hidden for screen-reader accessibility', () => {
    const { container } = renderWithProviders(<CartEmptyState />);

    const graphicBox = container.querySelector('[aria-hidden="true"]');
    expect(graphicBox).toBeInTheDocument();
  });

  it('renders empty cart state inside CartDrawer when drawer is opened with 0 items', () => {
    const handleClose = vi.fn();
    renderWithProviders(
      <CartDrawer
        isOpen={true}
        onClose={handleClose}
        drop={mockLiveDrop}
        catalogProducts={[]}
      />
    );

    expect(screen.getByTestId('cart-empty-state')).toBeInTheDocument();
    expect(screen.getByText('Your bag is empty')).toBeInTheDocument();

    const browseBtn = screen.getByTestId('cart-browse-btn');
    expect(browseBtn).toBeInTheDocument();
    fireEvent.click(browseBtn);
    expect(handleClose).toHaveBeenCalled();
  });
});
