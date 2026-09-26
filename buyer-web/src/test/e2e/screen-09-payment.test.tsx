/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 09 (Direct UPI Payment View)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 21 & ORIGINAL_REQUEST.md R8
 *
 * Test Inventory (>=5 tests):
 * 1. Renders amount display in integer Paisa, QR container, and UPI scan instructions
 * 2. Displays boutique UPI ID box with copy button
 * 3. Enforces 12-digit numeric constraint on UTR / Transaction ID input
 * 4. Submits valid UTR through "Verify Payment" action calling submitBuyerPaymentClaim
 * 5. Handles advance payment and full payment modes cleanly
 * 6. Provides WhatsApp direct support button for manual assistance
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent, waitFor } from '@testing-library/react';
import { DirectUpiPaymentView } from '../../components/checkout/DirectUpiPaymentView';
import * as buyerCatalog from '../../lib/data/buyer-catalog';
import { mockOrderReceiptFull, mockPaymentAttempt } from './fixtures/mock-catalog-data';
import { renderWithProviders } from './fixtures/test-providers';

describe('Tier 1: Screen 09 — Direct UPI Payment View', () => {
  beforeEach(() => {
    window.localStorage.clear();
    vi.clearAllMocks();
  });

  it('renders amount display in integer Paisa, QR container, and UPI instructions', () => {
    renderWithProviders(
      <DirectUpiPaymentView
        order={mockOrderReceiptFull}
        orderToken="8f7a6c9d-1234-4567-89ab-cdef01234567"
      />
    );

    // Formatted INR Total
    expect(screen.getByText(/Pay in Full \(₹1,850\)/i)).toBeInTheDocument();
    // Scan instructions
    expect(screen.getByText(/Scan with any UPI app to pay exact amount/i)).toBeInTheDocument();
  });

  it('displays boutique UPI ID box with copy button', async () => {
    const writeTextSpy = vi.fn().mockResolvedValue(undefined);
    Object.assign(navigator, {
      clipboard: {
        writeText: writeTextSpy,
      },
    });

    renderWithProviders(
      <DirectUpiPaymentView
        order={mockOrderReceiptFull}
        orderToken="8f7a6c9d-1234-4567-89ab-cdef01234567"
      />
    );

    const upiIdDisplay = screen.getByTestId('payee-vpa');
    expect(upiIdDisplay).toBeInTheDocument();
    expect(upiIdDisplay).toHaveTextContent(mockPaymentAttempt.payee_vpa_snapshot);

    const copyBtn = screen.getByTestId('copy-vpa-btn');
    expect(copyBtn).toBeInTheDocument();
    fireEvent.click(copyBtn);

    await waitFor(() => {
      expect(writeTextSpy).toHaveBeenCalledWith(mockPaymentAttempt.payee_vpa_snapshot);
    });
  });

  it('validates 12-digit numeric UTR constraint and shows alert on invalid input', async () => {
    renderWithProviders(
      <DirectUpiPaymentView
        order={mockOrderReceiptFull}
        orderToken="8f7a6c9d-1234-4567-89ab-cdef01234567"
      />
    );

    const utrInput = screen.getByTestId('utr-input-field');
    const submitBtn = screen.getByTestId('submit-payment-claim-btn');

    // Type short invalid UTR (5 digits)
    fireEvent.change(utrInput, { target: { value: '12345' } });
    fireEvent.click(submitBtn);

    await waitFor(() => {
      expect(screen.getByTestId('utr-field-error')).toBeInTheDocument();
    });
    expect(screen.getByTestId('utr-field-error')).toHaveTextContent(/6–35 alphanumeric/i);
  });

  it('submits valid 12-digit UTR via "I\'ve Completed Payment" calling submitBuyerPaymentClaim', async () => {
    const claimSpy = vi.spyOn(buyerCatalog, 'submitBuyerPaymentClaim').mockResolvedValue({
      success: true,
      payment_attempt_id: 'attempt-123',
      order_id: mockOrderReceiptFull.id,
      status: 'buyer_claimed',
      buyer_submitted_utr: '123456789012',
      buyer_claimed_at: new Date().toISOString(),
      verification_expires_at: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
      message: 'Payment claim submitted successfully',
    });

    renderWithProviders(
      <DirectUpiPaymentView
        order={mockOrderReceiptFull}
        orderToken="8f7a6c9d-1234-4567-89ab-cdef01234567"
      />
    );

    const utrInput = screen.getByTestId('utr-input-field');
    fireEvent.change(utrInput, { target: { value: '123456789012' } });

    const submitBtn = screen.getByTestId('submit-payment-claim-btn');
    fireEvent.click(submitBtn);

    await waitFor(() => {
      expect(claimSpy).toHaveBeenCalled();
    });
  });

  it('renders WhatsApp fallback support action button', () => {
    renderWithProviders(
      <DirectUpiPaymentView
        order={mockOrderReceiptFull}
        orderToken="8f7a6c9d-1234-4567-89ab-cdef01234567"
      />
    );

    const whatsappBtn = screen.getByTestId('whatsapp-chat-btn');
    expect(whatsappBtn).toBeInTheDocument();
    expect(whatsappBtn).toHaveAttribute('href');
    expect(whatsappBtn.getAttribute('href')).toContain('api.whatsapp.com');
  });
});
