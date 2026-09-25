/**
 * LiveDrop Buyer Webfront — Screen 6 Cart UI Unit Tests
 *
 * Verifies:
 * 1. CartItemRow renders square thumbnail, formatted INR price, size pill, and stepper
 * 2. CartDrawer renders Screen 6 layout: header, item rows, gift note, order summary, checkout button, 3 trust badges
 * 3. Adding and saving order notes in CartDrawer
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CartProvider, useCart, resetCartStore } from '../lib/cart/cart-context';
import { CartDrawer } from '../components/cart/CartDrawer';
import { CartItemRow } from '../components/cart/CartItemRow';
import { CartItem } from '../types/cart';
import { PublicProductView } from '../types/domain';

const mockItem: CartItem = {
  productId: 'prod-lehenga-1',
  dropId: 'drop-bridal-1',
  code: '#A01',
  title: 'Zardozi Bridal Lehenga',
  pricePaisa: 18900000, // ₹1,89,000.00
  imageUrl: 'https://example.com/lehenga.jpg',
  size: 'M',
  addedAt: Date.now(),
};

const mockProduct: PublicProductView = {
  id: 'prod-lehenga-1',
  drop_id: 'drop-bridal-1',
  title: 'Zardozi Bridal Lehenga',
  price_paisa: 18900000,
  code: '#A01',
  status: 'available',
  size: 'M',
  image_url: 'https://example.com/lehenga.jpg',
  reserved_at: null,
  version: 1,
};

describe('CartItemRow Component Tests', () => {
  it('renders product details with formatted INR price and variant pills', () => {
    const handleRemove = vi.fn();
    render(<CartItemRow item={mockItem} onRemove={handleRemove} isAvailable={true} />);

    expect(screen.getByText('Zardozi Bridal Lehenga')).toBeInTheDocument();
    expect(screen.getByText('₹1,89,000')).toBeInTheDocument();
    expect(screen.getByText('M')).toBeInTheDocument();
    expect(screen.getByText('Single Piece')).toBeInTheDocument();

    const removeBtn = screen.getByTestId('cart-remove-prod-lehenga-1');
    fireEvent.click(removeBtn);
    expect(handleRemove).toHaveBeenCalledWith('prod-lehenga-1');
  });
});

describe('CartDrawer Screen 6 Tests', () => {
  beforeEach(() => {
    resetCartStore();
  });

  function CartTestRig() {
    const { addItem, openDrawer, isDrawerOpen, closeDrawer } = useCart();
    return (
      <div>
        <button
          onClick={() => {
            addItem(mockProduct, 'drop-bridal-1');
            openDrawer();
          }}
          data-testid="add-and-open"
        >
          Add and Open
        </button>
        <CartDrawer isOpen={isDrawerOpen} onClose={closeDrawer} catalogProducts={[mockProduct]} />
      </div>
    );
  }

  it('renders Screen 6 layout: header, item list, gift note row, order summary, trust badges', () => {
    render(
      <CartProvider>
        <CartTestRig />
      </CartProvider>
    );

    fireEvent.click(screen.getByTestId('add-and-open'));

    // Drawer header
    expect(screen.getByTestId('cart-drawer')).toBeInTheDocument();
    expect(screen.getByText('Your Cart (1)')).toBeInTheDocument();
    expect(screen.getByTestId('cart-back-btn')).toBeInTheDocument();

    // Item row
    expect(screen.getByTestId('cart-item-prod-lehenga-1')).toBeInTheDocument();
    expect(screen.getByText('Zardozi Bridal Lehenga')).toBeInTheDocument();

    // Gift note toggle
    expect(screen.getByTestId('cart-note-toggle')).toBeInTheDocument();

    // Order summary
    expect(screen.getByText('Order Summary')).toBeInTheDocument();
    expect(screen.getByTestId('cart-subtotal')).toHaveTextContent('₹1,89,000');
    expect(screen.getByTestId('cart-total')).toHaveTextContent('₹1,89,000');

    // Checkout CTA button
    expect(screen.getByTestId('cart-checkout-btn')).toBeInTheDocument();

    // 3 Assurance Badges
    expect(screen.getByText('100% Authentic')).toBeInTheDocument();
    expect(screen.getByText('Insured Delivery')).toBeInTheDocument();
    expect(screen.getByText('Easy Returns')).toBeInTheDocument();
  });

  it('supports typing and saving a personalized gift note', () => {
    render(
      <CartProvider>
        <CartTestRig />
      </CartProvider>
    );

    fireEvent.click(screen.getByTestId('add-and-open'));

    // Open note input
    fireEvent.click(screen.getByTestId('cart-note-toggle'));
    expect(screen.getByTestId('cart-note-input')).toBeInTheDocument();

    fireEvent.change(screen.getByTestId('cart-note-input'), {
      target: { value: 'Please gift wrap with gold silk ribbon' },
    });
    fireEvent.click(screen.getByTestId('cart-save-note-btn'));

    // Verify saved note
    expect(screen.getByText(/Please gift wrap/i)).toBeInTheDocument();
  });
});
