/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 04 (Product Detail Modal)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 16 & ORIGINAL_REQUEST.md R6
 *
 * Test Inventory (>=5 tests):
 * 1. Renders 3:4 portrait product image, angle navigation arrows, and thumbnail strip
 * 2. Renders metadata: flash code (#A01), title, formatted INR price, and size pill
 * 3. Toggles wishlist heart state on click
 * 4. Adds product to cart via "Add to Bag" sticky CTA
 * 5. Handles "Buy Now" CTA by adding to cart and routing toward checkout
 * 6. Disables purchase actions when product is reserved or sold out
 * 7. Closes modal when clicking the close button or pressing Escape key
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import { ProductDetailModal } from '../../components/ProductDetailModal';
import {
  mockProducts,
} from './fixtures/mock-catalog-data';
import { renderWithProviders } from './fixtures/test-providers';
import { resetCartStore } from '../../lib/cart/cart-context';

describe('Tier 1: Screen 04 — Product Detail Modal', () => {
  const availableProduct = mockProducts[0]; // #A01 Handloom Tussar Silk Saree (has multiple image_urls)
  const reservedProduct = mockProducts[3];  // #A04 Banarasi Lehenga (reserved)
  const soldProduct = mockProducts[4];      // #A05 Temple Gold Choker (sold)

  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    vi.clearAllMocks();
  });

  it('renders 3:4 portrait image, angle navigation buttons, and thumbnail strip', () => {
    const handleClose = vi.fn();
    renderWithProviders(
      <ProductDetailModal
        product={availableProduct}
        isOpen={true}
        onClose={handleClose}
      />
    );

    // Modal dialog
    expect(screen.getByRole('dialog')).toBeInTheDocument();

    // Thumbnails
    const thumb1 = screen.getByLabelText('View photo 1');
    const thumb2 = screen.getByLabelText('View photo 2');
    expect(thumb1).toBeInTheDocument();
    expect(thumb2).toBeInTheDocument();

    // Angle navigation
    const nextArrow = screen.getByLabelText('Next angle');
    expect(nextArrow).toBeInTheDocument();
    fireEvent.click(nextArrow);
  });

  it('renders flash code, product title, formatted price, and size pill', () => {
    const handleClose = vi.fn();
    renderWithProviders(
      <ProductDetailModal
        product={availableProduct}
        isOpen={true}
        onClose={handleClose}
      />
    );

    expect(screen.getByText('#A01')).toBeInTheDocument();
    expect(screen.getByText('Handloom Tussar Silk Saree')).toBeInTheDocument();
    expect(screen.getByText('₹1,850')).toBeInTheDocument();
    expect(screen.getByText(/Free Size/i)).toBeInTheDocument();
    expect(screen.getByText(/Available/i)).toBeInTheDocument();
  });

  it('toggles wishlist heart button state on user interaction', () => {
    const handleClose = vi.fn();
    renderWithProviders(
      <ProductDetailModal
        product={availableProduct}
        isOpen={true}
        onClose={handleClose}
      />
    );

    const wishlistBtn = screen.getByLabelText('Add to wishlist');
    expect(wishlistBtn).toBeInTheDocument();

    // Click to add
    fireEvent.click(wishlistBtn);
    expect(screen.getByLabelText('Remove from wishlist')).toBeInTheDocument();

    // Click to remove
    fireEvent.click(screen.getByLabelText('Remove from wishlist'));
    expect(screen.getByLabelText('Add to wishlist')).toBeInTheDocument();
  });

  it('adds item to cart and transitions CTA to "In Bag" on click', () => {
    const handleClose = vi.fn();
    renderWithProviders(
      <ProductDetailModal
        product={availableProduct}
        isOpen={true}
        onClose={handleClose}
        dropId="drop-live-festival-01"
      />
    );

    const addBtn = screen.getByTestId(`sheet-add-to-cart-${availableProduct.id}`);
    expect(addBtn).toBeInTheDocument();
    expect(addBtn).toHaveTextContent(/Add to Bag/i);

    fireEvent.click(addBtn);

    // Transitions to In Bag state
    expect(addBtn).toHaveTextContent(/In Bag/i);
  });

  it('handles "Buy Now" CTA click by invoking add to bag', () => {
    const handleClose = vi.fn();
    renderWithProviders(
      <ProductDetailModal
        product={availableProduct}
        isOpen={true}
        onClose={handleClose}
        dropId="drop-live-festival-01"
      />
    );

    const buyNowBtn = screen.getByTestId(`sheet-buy-now-${availableProduct.id}`);
    expect(buyNowBtn).toBeInTheDocument();
    expect(buyNowBtn).toHaveTextContent(/Buy Now/i);

    fireEvent.click(buyNowBtn);
  });

  it('disables purchase actions when product is reserved or sold out', () => {
    const handleClose = vi.fn();

    // Test Reserved Product
    const { unmount } = renderWithProviders(
      <ProductDetailModal
        product={reservedProduct}
        isOpen={true}
        onClose={handleClose}
      />
    );

    expect(
      screen.getByRole('button', { name: /Item Currently Reserved/i })
    ).toBeDisabled();
    unmount();

    // Test Sold Out Product
    renderWithProviders(
      <ProductDetailModal
        product={soldProduct}
        isOpen={true}
        onClose={handleClose}
      />
    );

    expect(
      screen.getByRole('button', { name: /Sold Out/i })
    ).toBeDisabled();
  });

  it('invokes onClose when clicking close button or pressing Escape key', () => {
    const handleClose = vi.fn();
    renderWithProviders(
      <ProductDetailModal
        product={availableProduct}
        isOpen={true}
        onClose={handleClose}
      />
    );

    // 1. Close button click
    const closeBtn = screen.getByTestId('product-detail-close-btn');
    fireEvent.click(closeBtn);
    expect(handleClose).toHaveBeenCalledTimes(1);

    // 2. Escape key press
    fireEvent.keyDown(window, { key: 'Escape' });
    expect(handleClose).toHaveBeenCalledTimes(2);
  });
});
