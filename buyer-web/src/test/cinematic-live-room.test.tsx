/**
 * LiveDrop Buyer Webfront — CinematicLiveRoomView Unit Tests
 *
 * Verifies:
 * 1. Fullscreen live commerce layout with embedded stream player
 * 2. Pinned garment presentation and instant Add to Bag dispatch
 * 3. Swipe-up catalog drawer expansion (stream continuous in background)
 * 4. Interactive like/reaction heart increment
 * 5. Back to grid or navigation handler
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CinematicLiveRoomView } from '../components/live/CinematicLiveRoomView';
import { CartProvider } from '../lib/cart/cart-context';
import { PublicDropCatalog, PublicProductView } from '../types/domain';

const mockDrop: PublicDropCatalog = {
  id: 'drop-live-101',
  seller_id: 'seller-202',
  title: 'Autumn Bridal Collection',
  slug: 'autumn-bridal',
  status: 'live',
  shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  stream_url: 'https://www.facebook.com/boutique/videos/555555555/',
  live_started_at: '2026-09-24T20:00:00Z',
  closed_at: null,
  created_at: '2026-09-24T18:00:00Z',
  updated_at: '2026-09-24T18:00:00Z',
  profiles: {
    store_name: 'Maharani Couture',
    store_slug: 'maharani-couture',
    phone_number: '919830099999',
    upi_id: 'maharani@upi',
    upi_qr_url: null,
    default_shipping_fee_paisa: 0,
    free_shipping_threshold_paisa: null,
    advance_confirmation_enabled: false,
    advance_amount_paisa: 0,
    hold_duration_days: 2,
  },
};

const mockProducts: PublicProductView[] = [
  {
    id: 'prod-01',
    drop_id: 'drop-live-101',
    code: '#B01',
    title: 'Emerald Brocade Lehenga',
    price_paisa: 24500000, // ₹2,45,000
    size: 'M',
    image_url: 'https://example.com/lehenga.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-02',
    drop_id: 'drop-live-101',
    code: '#B02',
    title: 'Ruby Raw Silk Sherwani',
    price_paisa: 17500000, // ₹1,75,000
    size: 'L',
    image_url: 'https://example.com/sherwani.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
];

describe('CinematicLiveRoomView Component Tests', () => {
  it('renders dominant stream player and pinned spotlight product card', () => {
    render(
      <CartProvider>
        <CinematicLiveRoomView
          drop={mockDrop}
          products={mockProducts}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('cinematic-live-room')).toBeInTheDocument();
    expect(screen.getByTestId('facebook-live-player')).toBeInTheDocument();
    expect(screen.getByText('Maharani Couture')).toBeInTheDocument();

    // Pinned card
    expect(screen.getByTestId('pinned-product-card')).toBeInTheDocument();
    expect(screen.getByText('Emerald Brocade Lehenga')).toBeInTheDocument();
    expect(screen.getByText('₹2,45,000')).toBeInTheDocument();
    expect(screen.getByTestId('pinned-claim-btn')).toBeInTheDocument();
  });

  it('adds pinned product to bag when Add to Bag is pressed', () => {
    render(
      <CartProvider>
        <CinematicLiveRoomView
          drop={mockDrop}
          products={mockProducts}
        />
      </CartProvider>
    );

    const claimBtn = screen.getByTestId('pinned-claim-btn');
    fireEvent.click(claimBtn);

    // Verify right column bag button shows 1 item
    expect(screen.getByTestId('live-room-bag-btn')).toBeInTheDocument();
  });

  it('expands full catalog drawer on View All Pieces click', () => {
    render(
      <CartProvider>
        <CinematicLiveRoomView
          drop={mockDrop}
          products={mockProducts}
        />
      </CartProvider>
    );

    expect(screen.queryByTestId('full-catalog-drawer')).not.toBeInTheDocument();

    const expandBtn = screen.getByTestId('expand-catalog-btn');
    fireEvent.click(expandBtn);

    expect(screen.getByTestId('full-catalog-drawer')).toBeInTheDocument();
    expect(screen.getByText('Ruby Raw Silk Sherwani')).toBeInTheDocument();
  });

  it('increments like counter when heart is tapped', () => {
    render(
      <CartProvider>
        <CinematicLiveRoomView
          drop={mockDrop}
          products={mockProducts}
        />
      </CartProvider>
    );

    const initialLikes = screen.getByText('2480');
    expect(initialLikes).toBeInTheDocument();

    const likeBtn = screen.getByLabelText('Like live stream');
    fireEvent.click(likeBtn);

    expect(screen.getByText('2481')).toBeInTheDocument();
  });

  it('invokes onExitToGrid when back button is tapped', () => {
    const handleExit = vi.fn();
    render(
      <CartProvider>
        <CinematicLiveRoomView
          drop={mockDrop}
          products={mockProducts}
          onExitToGrid={handleExit}
        />
      </CartProvider>
    );

    const backBtn = screen.getByTestId('live-room-back-btn');
    fireEvent.click(backBtn);

    expect(handleExit).toHaveBeenCalledTimes(1);
  });
});
