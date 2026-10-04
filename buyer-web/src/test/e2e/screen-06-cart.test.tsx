/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 06 (Cart With Items)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 18 & ORIGINAL_REQUEST.md R7
 *
 * Test Inventory (>=5 tests):
 * 1. Renders minimal header with title, item count, and gold Clear link
 * 2. Displays 10-minute reservation policy warning banner with limited edition notice
 * 3. Renders item row with 3:4 thumbnail, code (#A01), title, size, and formatted price
 * 4. Enforces single-piece edition constraint on quantity stepper (+ disabled)
 * 5. Expands customer gift note field, inputs special request, and saves note
 * 6. Calculates order summary with integer Paisa arithmetic (subtotal, shipping, total)
 * 7. Removes item from cart via trash action button
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent, waitFor } from '@testing-library/react';
import CartPage from '../../app/cart/page';
import * as buyerCatalog from '../../lib/data/buyer-catalog';
import {
  mockLiveDrop,
  mockProducts,
} from './fixtures/mock-catalog-data';
import { renderWithProviders, seedCartStorage } from './fixtures/test-providers';
import { resetCartStore } from '../../lib/cart/cart-context';

describe('Tier 1: Screen 06 — Cart With Items', () => {
  const itemA01 = mockProducts[0]; // ₹1,850 (185000 Paisa)

  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    vi.clearAllMocks();

    vi.spyOn(buyerCatalog, 'getPublicProductsForDrop').mockResolvedValue(mockProducts);
    // The cart loads its drop's shipping rules (drop fee Rs 80, drop threshold Rs 2,000).
    vi.spyOn(buyerCatalog, 'getLiveDropById').mockResolvedValue({
      ...mockLiveDrop,
      shipping_fee_paisa: 8000,
      free_shipping_threshold_paisa: 200000,
    });

    // Pre-populate cart with item #A01
    seedCartStorage([
      {
        id: itemA01.id,
        code: itemA01.code,
        title: itemA01.title,
        pricePaisa: itemA01.price_paisa,
        size: itemA01.size,
        dropId: 'drop-live-festival-01',
      },
    ]);
  });

  it('renders minimal header with title, item count, and gold Clear link', async () => {
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByText(/Your Cart \(1\)/i)).toBeInTheDocument();
    });

    const clearBtn = screen.getByTestId('cart-page-clear-btn');
    expect(clearBtn).toBeInTheDocument();
    expect(clearBtn).toHaveTextContent(/Clear/i);
  });

  it('displays 10-minute reservation policy warning banner', async () => {
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(
        screen.getByText(/Items are not reserved until checkout/i)
      ).toBeInTheDocument();
    });
    expect(
      screen.getByText(/Live drops are single-piece limited editions/i)
    ).toBeInTheDocument();
  });

  it('renders item row with product code, title, size, and formatted price in Paisa', async () => {
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByTestId(`cart-item-${itemA01.id}`)).toBeInTheDocument();
    });

    const itemRow = screen.getByTestId(`cart-item-${itemA01.id}`);
    expect(itemRow).toHaveTextContent('#A01');
    expect(itemRow).toHaveTextContent('Handloom Tussar Silk Saree');
    expect(itemRow).toHaveTextContent('Free Size');
    expect(itemRow).toHaveTextContent('₹1,850');
  });

  it('enforces single-piece edition constraint disabling quantity increment', async () => {
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByText(/Single Piece/i)).toBeInTheDocument();
    });

    // Increment button is disabled
    const plusBtn = screen.getByTitle(/Single piece edition/i);
    expect(plusBtn).toBeDisabled();
  });

  it('expands customer gift note accordion, enters request, and saves note', async () => {
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByRole('button', { name: /Add a note/i })).toBeInTheDocument();
    });

    // Click to expand note accordion
    const toggleNoteBtn = screen.getByRole('button', { name: /Add a note/i });
    fireEvent.click(toggleNoteBtn);

    // Enter note text
    const noteInput = screen.getByTestId('cart-page-note-input');
    expect(noteInput).toBeInTheDocument();
    fireEvent.change(noteInput, {
      target: { value: 'Please pack in luxury festive gift wrap with handwritten card.' },
    });

    // Save note
    const saveBtn = screen.getByTestId('cart-page-save-note-btn');
    fireEvent.click(saveBtn);
  });

  it('calculates order summary breakdown with integer Paisa arithmetic', async () => {
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByTestId('cart-page-subtotal')).toBeInTheDocument();
    });

    // Subtotal: ₹1,850
    const subtotalEl = screen.getByTestId('cart-page-subtotal');
    expect(subtotalEl).toHaveTextContent('₹1,850');

    // Total: ₹1,930 (₹1,850 + ₹80 drop shipping fee since below the drop's ₹2,000 threshold)
    await waitFor(() => {
      expect(screen.getByTestId('cart-page-total')).toHaveTextContent('₹1,930');
    });
    expect(screen.getByTestId('cart-page-shipping')).toHaveTextContent('₹80');

    // Checkout button
    const checkoutBtn = screen.getByTestId('cart-page-checkout-btn');
    expect(checkoutBtn).toBeInTheDocument();
    expect(checkoutBtn).not.toBeDisabled();
    expect(checkoutBtn).toHaveTextContent(/Proceed to Checkout/i);
  });

  it('removes item from cart when clicking trash action button', async () => {
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByTestId(`cart-remove-${itemA01.id}`)).toBeInTheDocument();
    });

    const removeBtn = screen.getByTestId(`cart-remove-${itemA01.id}`);
    fireEvent.click(removeBtn);

    // Cart is now empty, rendering empty state
    await waitFor(() => {
      expect(screen.getByTestId('cart-empty-state')).toBeInTheDocument();
    });
  });

  it('uses the drop threshold over the shop threshold (SA-PAY-008)', async () => {
    vi.spyOn(buyerCatalog, 'getLiveDropById').mockResolvedValue({
      ...mockLiveDrop,
      shipping_fee_paisa: 8000,
      free_shipping_threshold_paisa: 150000,
      profiles: { ...mockLiveDrop.profiles, default_shipping_fee_paisa: 8000, free_shipping_threshold_paisa: 300000 },
    });
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByTestId('cart-page-shipping')).toHaveTextContent('FREE');
    });
    expect(screen.getByTestId('cart-page-total')).toHaveTextContent('₹1,850');
  });

  it('charges shipping when neither the drop nor the shop sets a threshold (no hidden ₹2,000 default)', async () => {
    vi.spyOn(buyerCatalog, 'getLiveDropById').mockResolvedValue({
      ...mockLiveDrop,
      shipping_fee_paisa: 8000,
      free_shipping_threshold_paisa: null,
      profiles: { ...mockLiveDrop.profiles, default_shipping_fee_paisa: 8000, free_shipping_threshold_paisa: null },
    });
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByTestId('cart-page-shipping')).toHaveTextContent('₹80');
    });
    expect(screen.getByTestId('cart-page-total')).toHaveTextContent('₹1,930');
  });

  it('shows shipping as calculated at checkout while the drop rules are unknown', async () => {
    vi.spyOn(buyerCatalog, 'getLiveDropById').mockResolvedValue(null);
    renderWithProviders(<CartPage />);

    await waitFor(() => {
      expect(screen.getByTestId('cart-page-shipping')).toHaveTextContent(/Calculated at checkout/i);
    });
    expect(screen.getByTestId('cart-page-total')).toHaveTextContent('₹1,850');
  });
});
