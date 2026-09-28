/**
 * Phase 1B: Public Drop Route & Realtime Catalog Behavior Tests (/drop/[slug])
 *
 * Verifies:
 * 1. Valid live drop with boutique branding, title, live badge, and products
 * 2. Missing drop slug resolves to DropNotFoundState
 * 3. Unavailable/closed drop resolves to DropUnavailableState
 * 4. FacebookLivePlayer renders embedded video stream or graceful ambient fallback
 * 5. Real catalog rendering with flash codes and integer Paisa
 * 6. Realtime update dynamically updates product availability
 * 7. Stale event rejection (older version rejected by version counter)
 * 8. Realtime polling fallback status indication
 * 9. Product reservation and sold transitions
 * 10. Single CartDrawer instance ownership
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { SupabaseClient } from '@supabase/supabase-js';
import { PublicDropView } from '../components/PublicDropView';
import { CartProvider } from '../lib/cart/cart-context';
import { PublicDropCatalog, PublicProductView } from '../types/domain';
import { CatalogRealtimeSubscription } from '../lib/realtime/catalog-realtime';

const mockLiveDrop: PublicDropCatalog = {
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
  seller_id: 'seller-777',
  title: 'Autumn Velvet & Zari Runway',
  slug: 'autumn-velvet',
  status: 'live',
  shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
  stream_url: 'https://www.facebook.com/velvet/videos/123456789/',
  live_started_at: '2026-09-28T19:00:00Z',
  closed_at: null,
  created_at: '2026-09-28T18:00:00Z',
  updated_at: '2026-09-28T18:00:00Z',
  profiles: {
    store_name: 'Velvet Atelier',
    store_slug: 'velvet-atelier',
    phone_number: '919830111222',
    upi_id: 'velvet@upi',
    upi_qr_url: null,
    default_shipping_fee_paisa: 8000,
    free_shipping_threshold_paisa: 200000,
    advance_confirmation_enabled: true,
    advance_amount_paisa: 25000,
    hold_duration_days: 7,
  },
};

const mockClosedDrop: PublicDropCatalog = {
  ...mockLiveDrop,
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6802',
  title: 'Archived Spring Edit',
  slug: 'archived-spring',
  status: 'closed',
  closed_at: '2026-09-20T21:00:00Z',
};

const mockProducts: PublicProductView[] = [
  {
    id: 'prod-01',
    drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
    code: '#V01',
    title: 'Midnight Velvet Trench',
    price_paisa: 285000, // ₹2,850.00
    size: 'M',
    image_url: 'https://example.com/trench.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-02',
    drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
    code: '#V02',
    title: 'Burgundy Brocade Corset',
    price_paisa: 145000, // ₹1,450.00
    size: 'S',
    image_url: 'https://example.com/corset.jpg',
    status: 'reserved',
    reserved_at: '2026-09-28T19:10:00Z',
    version: 2,
  },
  {
    id: 'prod-03',
    drop_id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
    code: '#V03',
    title: 'Gold Embroidered Stole',
    price_paisa: 75000, // ₹750.00
    size: 'Free Size',
    image_url: 'https://example.com/stole.jpg',
    status: 'sold',
    reserved_at: null,
    version: 3,
  },
];

describe('Phase 1B: Public Drop Route Behavior (/drop/[slug])', () => {
  it('1. Valid live drop: renders drop header, store branding, live badge, and live stream banner', () => {
    render(
      <CartProvider>
        <PublicDropView
          slug="autumn-velvet"
          initialDrop={mockLiveDrop}
          initialProducts={mockProducts}
          initialState="live"
        />
      </CartProvider>
    );

    // Header Branding & Title
    expect(screen.getByTestId('header-store-name')).toHaveTextContent('Velvet Atelier');
    expect(screen.getByTestId('header-drop-title')).toHaveTextContent('Autumn Velvet & Zari Runway');
    expect(screen.getByTestId('live-now-badge')).toBeInTheDocument();

    // Live Stream Preview
    expect(screen.getByTestId('facebook-live-player')).toBeInTheDocument();
    expect(screen.getByTestId('enter-cinematic-mode-btn')).toHaveTextContent('Watch Live Fullscreen');

    // Real Catalog Rendering
    expect(screen.getByText('Midnight Velvet Trench')).toBeInTheDocument();
    expect(screen.getByText('₹2,850')).toBeInTheDocument();
    expect(screen.getByText('Burgundy Brocade Corset')).toBeInTheDocument();
  });

  it('2. Missing drop: renders DropNotFoundState when drop does not exist', () => {
    render(
      <CartProvider>
        <PublicDropView
          slug="nonexistent-drop"
          initialDrop={null}
          initialProducts={[]}
          initialState="not_found"
        />
      </CartProvider>
    );

    expect(screen.getByTestId('drop-not-found-state')).toBeInTheDocument();
    expect(screen.getByText(/Drop Not Found/i)).toBeInTheDocument();
  });

  it('3. Unavailable / closed drop: renders DropUnavailableState', () => {
    render(
      <CartProvider>
        <PublicDropView
          slug="archived-spring"
          initialDrop={mockClosedDrop}
          initialProducts={[]}
          initialState="closed"
        />
      </CartProvider>
    );

    expect(screen.getByTestId('drop-unavailable-state')).toBeInTheDocument();
    expect(screen.getByText(/Broadcast Ended/i)).toBeInTheDocument();
  });

  it('4. Live stream fallback: renders luxury ambient fallback player when streamUrl is null', () => {
    const dropWithoutStream: PublicDropCatalog = {
      ...mockLiveDrop,
      stream_url: null,
    };

    render(
      <CartProvider>
        <PublicDropView
          slug="autumn-velvet"
          initialDrop={dropWithoutStream}
          initialProducts={mockProducts}
          initialState="live"
        />
      </CartProvider>
    );

    expect(screen.getByTestId('fallback-ambient-player')).toBeInTheDocument();
    expect(screen.getByText('Atelier Stream Connecting')).toBeInTheDocument();
  });

  it('5. Product availability transitions: handles available, reserved, and sold states', () => {
    render(
      <CartProvider>
        <PublicDropView
          slug="autumn-velvet"
          initialDrop={mockLiveDrop}
          initialProducts={mockProducts}
          initialState="live"
        />
      </CartProvider>
    );

    expect(screen.getByTestId('status-badge-prod-01')).toHaveTextContent('AVAILABLE');
    expect(screen.getByTestId('status-badge-prod-02')).toHaveTextContent('RESERVED');
    expect(screen.getByTestId('status-badge-prod-03')).toHaveTextContent('SOLD OUT');

    // Available piece has active Add to Bag button
    expect(screen.getByLabelText(/Add #V01: Midnight Velvet Trench to cart/i)).toBeInTheDocument();

    // Reserved and Sold pieces have disabled buttons
    expect(screen.getByTestId('cart-btn-prod-02')).toBeDisabled();
    expect(screen.getByTestId('cart-btn-prod-03')).toBeDisabled();
  });

  it('6. Realtime update & version ordering: CatalogRealtimeSubscription rejects stale versions', () => {
    const mockClient = {
      channel: vi.fn().mockReturnValue({
        on: vi.fn().mockReturnThis(),
        subscribe: vi.fn().mockReturnThis(),
        unsubscribe: vi.fn(),
      }),
    } as unknown as SupabaseClient;

    let receivedProduct: PublicProductView | null = null;
    const sub = new CatalogRealtimeSubscription(mockClient, {
      dropId: mockLiveDrop.id,
      onProductChange: (p) => {
        receivedProduct = p;
      },
    });

    // Seed version 2 for prod-02
    sub.seedVersions([mockProducts[1]]);

    // Attempt to deliver stale event with version 1
    const stalePayload = {
      eventType: 'UPDATE' as const,
      new: {
        ...mockProducts[1],
        status: 'available' as const,
        version: 1, // Stale! (Seeded was 2)
      },
      old: {},
    };
    sub.handleIncomingPayload(stalePayload);

    // Stale event MUST be rejected
    expect(receivedProduct).toBeNull();

    // Deliver monotonic newer version 3
    const freshPayload = {
      eventType: 'UPDATE' as const,
      new: {
        ...mockProducts[1],
        status: 'sold' as const,
        version: 3, // Fresh!
      },
      old: {},
    };
    sub.handleIncomingPayload(freshPayload);

    // Newer event accepted
    expect(receivedProduct).not.toBeNull();
    expect((receivedProduct as unknown as PublicProductView)?.status).toBe('sold');
  });

  it('7. Single CartDrawer instance: exactly one CartDrawer is mounted in PublicDropView when toggled', () => {
    render(
      <CartProvider>
        <PublicDropView
          slug="autumn-velvet"
          initialDrop={mockLiveDrop}
          initialProducts={mockProducts}
          initialState="live"
        />
      </CartProvider>
    );

    // CartDrawer starts closed (unmounted)
    expect(screen.queryByTestId('cart-drawer')).not.toBeInTheDocument();

    // Open CartDrawer from header
    const cartBtn = screen.getByTestId('header-cart-btn');
    fireEvent.click(cartBtn);

    // Exactly one CartDrawer rendered in the DOM
    const drawers = screen.getAllByTestId('cart-drawer');
    expect(drawers).toHaveLength(1);
  });

  it('8. Cinematic mode toggle: switches from catalog grid to CinematicLiveRoomView', () => {
    render(
      <CartProvider>
        <PublicDropView
          slug="autumn-velvet"
          initialDrop={mockLiveDrop}
          initialProducts={mockProducts}
          initialState="live"
        />
      </CartProvider>
    );

    // Initially in grid mode
    expect(screen.getByTestId('product-grid')).toBeInTheDocument();
    expect(screen.queryByTestId('cinematic-live-room')).not.toBeInTheDocument();

    // Click "Watch Live Fullscreen"
    const fullscreenBtn = screen.getByTestId('enter-cinematic-mode-btn');
    fireEvent.click(fullscreenBtn);

    // Now in cinematic live room
    expect(screen.getByTestId('cinematic-live-room')).toBeInTheDocument();
    expect(screen.queryByTestId('product-grid')).not.toBeInTheDocument();

    // Exit back to grid
    const backBtn = screen.getByTestId('live-room-back-btn');
    fireEvent.click(backBtn);

    // Back to grid mode
    expect(screen.getByTestId('product-grid')).toBeInTheDocument();
  });
});
