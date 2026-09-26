/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 03 (Live Drop Room)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 15 & ORIGINAL_REQUEST.md R5
 *
 * Test Inventory (>=5 tests):
 * 1. Renders top bar with boutique branding and LIVE broadcast badge
 * 2. Renders floating live chat overlay with transparent message bubbles
 * 3. Renders pinned spotlight product card with flash code, title, and formatted price
 * 4. Interacts with floating heart button to register likes
 * 5. Adds spotlight product to cart directly from pinned card ("Add to Bag")
 * 6. Expands full catalog drawer when clicking "View All X Pieces"
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import { CinematicLiveRoomView } from '../../components/live/CinematicLiveRoomView';
import {
  mockLiveDrop,
  mockProducts,
} from './fixtures/mock-catalog-data';
import { renderWithProviders } from './fixtures/test-providers';
import { resetCartStore } from '../../lib/cart/cart-context';

describe('Tier 1: Screen 03 — Live Drop Room', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    vi.clearAllMocks();
  });

  it('renders top bar with boutique branding, verified badge, and LIVE indicator', () => {
    renderWithProviders(
      <CinematicLiveRoomView
        drop={mockLiveDrop}
        products={mockProducts}
      />
    );

    expect(screen.getByTestId('cinematic-live-room')).toBeInTheDocument();
    expect(screen.getByText("Sonali's Boutique")).toBeInTheDocument();
    expect(screen.getByText('LIVE')).toBeInTheDocument();
    expect(screen.getByTestId('live-room-back-btn')).toBeInTheDocument();
  });

  it('renders floating live chat overlay with transparent message bubbles', () => {
    renderWithProviders(
      <CinematicLiveRoomView
        drop={mockLiveDrop}
        products={mockProducts}
      />
    );

    // Initial comments
    expect(screen.getByText(/That zari border is breathtaking!/i)).toBeInTheDocument();
    expect(screen.getByText(/Is this pure handloom silk\?/i)).toBeInTheDocument();
    expect(screen.getByText(/Just claimed #A01!/i)).toBeInTheDocument();
  });

  it('renders pinned spotlight product card with code, title, and price in integer Paisa', () => {
    renderWithProviders(
      <CinematicLiveRoomView
        drop={mockLiveDrop}
        products={mockProducts}
      />
    );

    const pinnedCard = screen.getByTestId('pinned-product-card');
    expect(pinnedCard).toBeInTheDocument();
    expect(pinnedCard).toHaveTextContent(/Spotlight Piece/i);
    expect(pinnedCard).toHaveTextContent('#A01');
    expect(pinnedCard).toHaveTextContent('Handloom Tussar Silk Saree');
    expect(pinnedCard).toHaveTextContent('₹1,850');
  });

  it('increments likes count when clicking floating heart button', () => {
    renderWithProviders(
      <CinematicLiveRoomView
        drop={mockLiveDrop}
        products={mockProducts}
      />
    );

    const likeBtn = screen.getByLabelText('Like live stream');
    expect(likeBtn).toBeInTheDocument();

    const initialLikes = screen.getByText('2480');
    expect(initialLikes).toBeInTheDocument();

    // Click like
    fireEvent.click(likeBtn);
    expect(screen.getByText('2481')).toBeInTheDocument();
  });

  it('adds spotlight product to cart when clicking Add to Bag on pinned card', async () => {
    renderWithProviders(
      <CinematicLiveRoomView
        drop={mockLiveDrop}
        products={mockProducts}
      />
    );

    const claimBtn = screen.getByTestId('pinned-claim-btn');
    expect(claimBtn).toBeInTheDocument();
    expect(claimBtn).toHaveTextContent('Add to Bag');

    fireEvent.click(claimBtn);

    // Bag badge should update to 1
    const bagBtn = screen.getByTestId('live-room-bag-btn');
    expect(bagBtn).toHaveAttribute('aria-label', expect.stringContaining('1 items'));
  });

  it('opens full catalog drawer when clicking View All Pieces button', () => {
    renderWithProviders(
      <CinematicLiveRoomView
        drop={mockLiveDrop}
        products={mockProducts}
      />
    );

    const expandBtn = screen.getByTestId('expand-catalog-btn');
    expect(expandBtn).toBeInTheDocument();
    expect(expandBtn).toHaveTextContent(`View All ${mockProducts.length} Pieces`);

    fireEvent.click(expandBtn);

    // Full catalog drawer opens
    const drawer = screen.getByTestId('full-catalog-drawer');
    expect(drawer).toBeInTheDocument();
    expect(drawer).toHaveTextContent('Festive Silk & Handloom Collection');
    expect(drawer).toHaveTextContent(`${mockProducts.length} exclusive couture pieces`);
  });
});
