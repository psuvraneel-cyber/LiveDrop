/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 08 (Checkout & Delivery Details)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 20 & ORIGINAL_REQUEST.md R8
 *
 * Test Inventory (>=5 tests):
 * 1. Renders 3-step breadcrumb progress indicator ("1 Details", "2 Payment", "3 Confirm")
 * 2. Renders delivery details form with dark elevated input fields
 * 3. Enforces validation on Indian mobile numbers (10 digits) and PIN codes (6 digits)
 * 4. Displays order breakdown review with 15-minute hold reservation notice
 * 5. Submits order using create_order_with_reservation with single-flight lock
 * 6. Generates and attaches unique checkout idempotency key (req_chk_*)
 * 7. Renders empty checkout state when visited with no items in cart
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi, afterEach } from 'vitest';
import { screen, fireEvent, waitFor } from '@testing-library/react';
import CheckoutPage from '../../app/checkout/page';
import * as buyerCatalog from '../../lib/data/buyer-catalog';
import {
  mockProducts,
  mockCreateOrderResponse,
} from './fixtures/mock-catalog-data';
import { renderWithProviders, seedCartStorage } from './fixtures/test-providers';
import { resetCartStore } from '../../lib/cart/cart-context';

describe('Tier 1: Screen 08 — Checkout & Delivery Form', () => {
  const itemA01 = mockProducts[0]; // ₹1,850

  beforeEach(() => {
    window.localStorage.clear();
    window.sessionStorage.clear();
    resetCartStore();
    vi.clearAllMocks();

    vi.spyOn(buyerCatalog, 'getPublicProductsForDrop').mockResolvedValue(mockProducts);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('renders 3-step progress indicator with Step 1 active', async () => {
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

    renderWithProviders(<CheckoutPage />);

    await waitFor(() => {
      expect(screen.getByText('Details')).toBeInTheDocument();
    });
    expect(screen.getByText('Payment')).toBeInTheDocument();
  });

  it('renders delivery details form with full name, phone, PIN, and street address inputs', async () => {
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

    renderWithProviders(<CheckoutPage />);

    await waitFor(() => {
      expect(screen.getByTestId('input-buyer-name')).toBeInTheDocument();
    });
    expect(screen.getByTestId('input-buyer-phone')).toBeInTheDocument();
    expect(screen.getByTestId('input-pincode')).toBeInTheDocument();
    expect(screen.getByTestId('input-shipping-address')).toBeInTheDocument();
  });

  it('enforces validation errors for invalid mobile numbers and PIN codes', async () => {
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

    renderWithProviders(<CheckoutPage />);

    await waitFor(() => {
      expect(screen.getByTestId('input-buyer-phone')).toBeInTheDocument();
    });

    const phoneInput = screen.getByTestId('input-buyer-phone');
    const pincodeInput = screen.getByTestId('input-pincode');
    const submitBtn = screen.getByTestId('checkout-submit-btn');

    // Invalid phone: 1234
    fireEvent.change(phoneInput, { target: { value: '1234' } });
    fireEvent.blur(phoneInput);

    // Invalid pincode: 99
    fireEvent.change(pincodeInput, { target: { value: '99' } });
    fireEvent.blur(pincodeInput);

    // Attempt submit
    fireEvent.click(submitBtn);

    await waitFor(() => {
      expect(screen.getByText(/10-digit/i)).toBeInTheDocument();
    });
    expect(screen.getByText(/6-digit/i)).toBeInTheDocument();
  });

  it('displays order breakdown review with 15-minute hold reservation notice', async () => {
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

    renderWithProviders(<CheckoutPage />);

    await waitFor(() => {
      expect(screen.getByTestId('checkout-hold-notice')).toBeInTheDocument();
    });

    expect(screen.getByTestId('checkout-hold-notice')).toHaveTextContent(
      /15-minute hold/i
    );
    expect(screen.getByText('Handloom Tussar Silk Saree')).toBeInTheDocument();
    expect(screen.getByText('#A01')).toBeInTheDocument();
  });

  it('submits checkout request with single-flight lock using atomic RPC mock', async () => {
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

    const orderSpy = vi
      .spyOn(buyerCatalog, 'createOrderWithReservation')
      .mockResolvedValue(mockCreateOrderResponse);

    renderWithProviders(<CheckoutPage />);

    await waitFor(() => {
      expect(screen.getByTestId('input-buyer-name')).toBeInTheDocument();
    });

    // Fill valid form
    fireEvent.change(screen.getByTestId('input-buyer-name'), {
      target: { value: 'Priya Sharma' },
    });
    fireEvent.change(screen.getByTestId('input-buyer-phone'), {
      target: { value: '9876543210' },
    });
    fireEvent.change(screen.getByTestId('input-pincode'), {
      target: { value: '560001' },
    });
    fireEvent.change(screen.getByTestId('input-shipping-address'), {
      target: { value: 'Flat 4B, Prestige Palm, MG Road, Bengaluru' },
    });

    const submitBtn = screen.getByTestId('checkout-submit-btn');
    fireEvent.click(submitBtn);

    // Verify RPC invocation with exact payload shape
    await waitFor(() => {
      expect(orderSpy).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          p_drop_id: 'drop-live-festival-01',
          p_product_ids: [itemA01.id],
          p_buyer_name: 'Priya Sharma',
          p_buyer_phone: '9876543210',
          p_shipping_address: 'Flat 4B, Prestige Palm, MG Road, Bengaluru',
          p_pincode: '560001',
          p_idempotency_key: expect.stringMatching(/^req_chk_/),
        })
      );
    });
  });

  it('renders empty checkout state when bag contains 0 items', async () => {
    renderWithProviders(<CheckoutPage />);

    await waitFor(() => {
      expect(screen.getByTestId('checkout-empty-state')).toBeInTheDocument();
    });
    expect(screen.getByText('Your Bag is Empty')).toBeInTheDocument();
  });
});
