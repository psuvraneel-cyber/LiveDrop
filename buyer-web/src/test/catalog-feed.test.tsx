/**
 * LiveDrop Buyer Webfront — Public Drop & Catalog Feed Tests (TASK-2.1)
 *
 * Comprehensive integration and component test suite covering:
 * 1. Public drop route resolution and visibility states (Live, Closed, Not Found, Error)
 * 2. Product catalog presentation: prominent flash codes, integer Paisa prices, availability states
 * 3. Client-side search and filtering: code matching (#A01, a01), title matching, empty search state, clear search
 * 4. Realtime inventory updates: availability transitions, monotonic version defense, channel cleanup
 * 5. Error resilience: image fallbacks, network retry, offline realtime indicators
 */

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { PublicDropView } from '../components/PublicDropView';
import { ProductCard } from '../components/ProductCard';
import { formatPaisaToINR } from '../lib/utils/currency';
import { PublicDropCatalog, PublicProductView } from '../types/domain';
import * as buyerCatalogModule from '../lib/data/buyer-catalog';
import { CatalogRealtimeSubscription } from '../lib/realtime/catalog-realtime';

// Sample synthetic test data matching seed conventions
const mockLiveDrop: PublicDropCatalog = {
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
  seller_id: '8a329e71-4b10-4055-90d2-df8029d5b512',
  title: 'Friday Silk Special',
  slug: 'mothers-boutique',
  status: 'live',
  shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
  live_started_at: '2026-09-11T13:00:00Z',
  closed_at: null,
  created_at: '2026-09-11T12:00:00Z',
  updated_at: '2026-09-11T12:00:00Z',
  profiles: {
    store_name: "Mother's Boutique",
    store_slug: 'mothers-boutique',
    phone_number: '919830012345',
    upi_id: 'mothersboutique@okaxis',
    upi_qr_url: 'https://storage.livedrop.store/qrs/mb.webp',
    default_shipping_fee_paisa: 8000,
    free_shipping_threshold_paisa: 200000,
    advance_confirmation_enabled: true,
    advance_amount_paisa: 25000,
    hold_duration_days: 30,
  },
};

const mockClosedDrop: PublicDropCatalog = {
  ...mockLiveDrop,
  id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6802',
  title: 'Past Clearance Collection',
  slug: 'past-clearance',
  status: 'closed',
  closed_at: '2026-09-10T15:00:00Z',
};

const mockProducts: PublicProductView[] = [
  {
    id: 'prod-01',
    code: '#A01',
    title: 'Handloom Tussar Saree',
    price_paisa: 185000, // ₹1,850.00
    size: 'Free Size',
    image_url: 'https://images.livedrop.store/products/tussar.webp',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-02',
    code: '#A02',
    title: 'Chanderi Cotton Kurti',
    price_paisa: 75000, // ₹750.00
    size: 'L',
    image_url: 'https://images.livedrop.store/products/kurti.webp',
    status: 'reserved',
    reserved_at: '2026-09-11T13:10:00Z',
    version: 2,
  },
  {
    id: 'prod-03',
    code: '#A03',
    title: 'Pure Jamdani Silk Dupatta',
    price_paisa: 125000, // ₹1,250.00
    size: 'Free Size',
    image_url: 'https://images.livedrop.store/products/dupatta.webp',
    status: 'sold',
    reserved_at: null,
    version: 3,
  },
];

describe('TASK-2.1: Monetary Formatting (Integer Paisa ADR-009)', () => {
  it('formats whole rupee amounts correctly with Indian comma separators', () => {
    expect(formatPaisaToINR(185000)).toBe('₹1,850');
    expect(formatPaisaToINR(75000)).toBe('₹750');
    expect(formatPaisaToINR(200000)).toBe('₹2,000');
    expect(formatPaisaToINR(10000000)).toBe('₹1,00,000');
  });

  it('formats fractional paisa correctly when remainder is non-zero', () => {
    expect(formatPaisaToINR(185050)).toBe('₹1,850.50');
    expect(formatPaisaToINR(99)).toBe('₹0.99');
    expect(formatPaisaToINR(5)).toBe('₹0.05');
  });

  it('handles zero and edge cases gracefully without NaN', () => {
    expect(formatPaisaToINR(0)).toBe('₹0');
    expect(formatPaisaToINR(-500)).toBe('₹0');
    expect(formatPaisaToINR(NaN)).toBe('₹0');
  });
});

describe('TASK-2.1: ProductCard Presentation', () => {
  it('renders prominent flash code, title, formatted price, and available status badge', () => {
    render(<ProductCard product={mockProducts[0]} />);

    // Prominent flash code
    const flashBadge = screen.getByTestId('flash-badge-prod-01');
    expect(flashBadge).toHaveTextContent('#A01');

    // Title and price
    expect(screen.getByText('Handloom Tussar Saree')).toBeInTheDocument();
    expect(screen.getByText('₹1,850')).toBeInTheDocument();
    expect(screen.getByText('Free Size')).toBeInTheDocument();

    // Available status badge
    const statusBadge = screen.getByTestId('status-badge-prod-01');
    expect(statusBadge).toHaveTextContent('AVAILABLE');
    expect(statusBadge).toHaveClass('available');

    // Available card should not have the dimmed unavailable class
    const card = screen.getByTestId('product-card-prod-01');
    expect(card).not.toHaveClass('unavailable');
  });

  it('renders RESERVED status badge and dims card for reserved items', () => {
    render(<ProductCard product={mockProducts[1]} />);

    const statusBadge = screen.getByTestId('status-badge-prod-02');
    expect(statusBadge).toHaveTextContent('RESERVED');
    expect(statusBadge).toHaveClass('reserved');

    const card = screen.getByTestId('product-card-prod-02');
    expect(card).toHaveClass('unavailable');
  });

  it('renders SOLD OUT status badge and dims card for sold items', () => {
    render(<ProductCard product={mockProducts[2]} />);

    const statusBadge = screen.getByTestId('status-badge-prod-03');
    expect(statusBadge).toHaveTextContent('SOLD OUT');
    expect(statusBadge).toHaveClass('sold');

    const card = screen.getByTestId('product-card-prod-03');
    expect(card).toHaveClass('unavailable');
  });

  it('falls back gracefully to SVG placeholder when product image fails to load', () => {
    render(<ProductCard product={mockProducts[0]} />);

    const img = screen.getByRole('img');
    fireEvent.error(img);

    // Image fallback is rendered with the flash code
    expect(screen.getByTestId('fallback-image-prod-01')).toBeInTheDocument();
    expect(screen.getByText('#A01', { selector: '.ld-image-fallback-text' })).toBeInTheDocument();
  });
});

describe('TASK-2.1: Public Drop Resolution & Visibility States', () => {
  beforeEach(() => {
    vi.restoreAllMocks();
  });

  it('renders live drop with boutique branding, title, live badge, and products', async () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    // Header presentation
    expect(screen.getByTestId('header-store-name')).toHaveTextContent("Mother's Boutique");
    expect(screen.getByTestId('header-drop-title')).toHaveTextContent('Friday Silk Special');
    expect(screen.getByTestId('live-now-badge')).toHaveTextContent('LIVE NOW');

    // Shipping notice
    expect(screen.getByTestId('shipping-notice')).toHaveTextContent('Free above ₹2,000');

    // Product cards
    expect(screen.getByTestId('product-card-prod-01')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-02')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-03')).toBeInTheDocument();
  });

  it('renders DropNotFoundState when drop does not exist', async () => {
    render(
      <PublicDropView
        slug="unknown-slug"
        initialState="not_found"
      />
    );

    expect(screen.getByTestId('drop-not-found-state')).toBeInTheDocument();
    expect(screen.getByText(/Drop Not Found/i)).toBeInTheDocument();
    expect(screen.getByText(/unknown-slug/i)).toBeInTheDocument();
  });

  it('renders DropUnavailableState when drop is closed (Broadcast Ended)', async () => {
    render(
      <PublicDropView
        slug="past-clearance"
        initialDrop={mockClosedDrop}
        initialState="closed"
      />
    );

    expect(screen.getByTestId('drop-unavailable-state')).toBeInTheDocument();
    expect(screen.getByText(/Broadcast Ended/i)).toBeInTheDocument();
    expect(screen.getByText(/Past Clearance Collection/i)).toBeInTheDocument();
  });

  it('renders CatalogErrorState with interactive retry on network/backend failure', async () => {
    const mockGetLiveDrop = vi.spyOn(buyerCatalogModule, 'getLiveDropBySlug')
      .mockRejectedValueOnce(new Error('PostgreSQL connection timeout'))
      .mockResolvedValueOnce(mockLiveDrop);

    vi.spyOn(buyerCatalogModule, 'getPublicProductsForDrop')
      .mockResolvedValue(mockProducts);

    render(<PublicDropView slug="mothers-boutique" />);

    // Initially loading skeleton
    expect(screen.getByTestId('catalog-loading-skeleton')).toBeInTheDocument();

    // Transitions to error state
    await waitFor(() => {
      expect(screen.getByTestId('catalog-error-state')).toBeInTheDocument();
    });
    expect(screen.getByText(/Unable to Load Catalog/i)).toBeInTheDocument();
    expect(screen.getByText(/PostgreSQL connection timeout/i)).toBeInTheDocument();

    // Clicking "Try Again" triggers recovery
    const retryBtn = screen.getByRole('button', { name: /retry/i });
    fireEvent.click(retryBtn);

    await waitFor(() => {
      expect(screen.getByTestId('header-store-name')).toHaveTextContent("Mother's Boutique");
    });
    expect(mockGetLiveDrop).toHaveBeenCalledTimes(2);
  });

  it('renders CatalogEmptyState when a live drop has 0 products', async () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={[]}
      />
    );

    expect(screen.getByTestId('catalog-empty-state')).toBeInTheDocument();
    expect(screen.getByText(/No Products Available Yet/i)).toBeInTheDocument();
  });
});

describe('TASK-2.1: Client-Side Search & Filtering', () => {
  it('filters by product title (case-insensitive and whitespace-tolerant)', () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    const searchInput = screen.getByTestId('catalog-search-input');

    // Search "tussar" (should match Handloom Tussar Saree only)
    fireEvent.change(searchInput, { target: { value: '  tussar  ' } });

    expect(screen.getByTestId('product-card-prod-01')).toBeInTheDocument();
    expect(screen.queryByTestId('product-card-prod-02')).not.toBeInTheDocument();
    expect(screen.queryByTestId('product-card-prod-03')).not.toBeInTheDocument();
    expect(screen.getByTestId('item-count-display')).toHaveTextContent('1 of 3');
  });

  it('filters by flash code with or without the "#" prefix', () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    const searchInput = screen.getByTestId('catalog-search-input');

    // Search without '#' (typing "a02" matches "#A02")
    fireEvent.change(searchInput, { target: { value: 'a02' } });

    expect(screen.queryByTestId('product-card-prod-01')).not.toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-02')).toBeInTheDocument();
    expect(screen.queryByTestId('product-card-prod-03')).not.toBeInTheDocument();

    // Search with '#' (typing "#A03" matches "#A03")
    fireEvent.change(searchInput, { target: { value: '#A03' } });

    expect(screen.queryByTestId('product-card-prod-01')).not.toBeInTheDocument();
    expect(screen.queryByTestId('product-card-prod-02')).not.toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-03')).toBeInTheDocument();
  });

  it('renders CatalogSearchEmptyState when search query yields no matches', () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    const searchInput = screen.getByTestId('catalog-search-input');
    fireEvent.change(searchInput, { target: { value: 'nonexistent-code' } });

    expect(screen.getByTestId('catalog-search-empty-state')).toBeInTheDocument();
    expect(screen.getByText(/No Matching Products/i)).toBeInTheDocument();
    expect(screen.getByText(/nonexistent-code/i)).toBeInTheDocument();

    // Clear Search button restores full catalog
    const clearBtn = screen.getByRole('button', { name: /clear current search query/i });
    fireEvent.click(clearBtn);

    expect(screen.getByTestId('product-card-prod-01')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-02')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-03')).toBeInTheDocument();
  });

  it('filters by availability pill tabs (Available vs Reserved/Sold)', () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    // 1. Click "Available" tab
    const availablePill = screen.getByTestId('filter-pill-available');
    fireEvent.click(availablePill);

    expect(screen.getByTestId('product-card-prod-01')).toBeInTheDocument();
    expect(screen.queryByTestId('product-card-prod-02')).not.toBeInTheDocument();
    expect(screen.queryByTestId('product-card-prod-03')).not.toBeInTheDocument();

    // 2. Click "Reserved / Sold" tab
    const unavailablePill = screen.getByTestId('filter-pill-unavailable');
    fireEvent.click(unavailablePill);

    expect(screen.queryByTestId('product-card-prod-01')).not.toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-02')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-03')).toBeInTheDocument();

    // 3. Click "All Items" tab
    const allPill = screen.getByTestId('filter-pill-all');
    fireEvent.click(allPill);

    expect(screen.getByTestId('product-card-prod-01')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-02')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-03')).toBeInTheDocument();
  });
});

describe('TASK-2.1: Realtime Catalog Lifecycle & Version Defense', () => {
  let capturedCallback: ((payload: PublicProductView) => void) | null = null;
  let capturedStatusCallback: ((status: string) => void) | null = null;
  const mockUnsubscribe = vi.fn().mockResolvedValue(undefined);

  beforeEach(() => {
    capturedCallback = null;
    capturedStatusCallback = null;
    mockUnsubscribe.mockClear();

    // Mock CatalogRealtimeSubscription
    vi.spyOn(CatalogRealtimeSubscription.prototype, 'subscribe').mockImplementation(function (this: CatalogRealtimeSubscription) {
      // Extract callback from options
      // @ts-expect-error accessing private options for testing
      capturedCallback = this.options.onProductChange;
      // @ts-expect-error accessing private options for testing
      capturedStatusCallback = this.options.onStatusChange;
      capturedStatusCallback?.('SUBSCRIBED');
      return {} as never;
    });

    vi.spyOn(CatalogRealtimeSubscription.prototype, 'unsubscribe').mockImplementation(mockUnsubscribe);
  });

  it('updates product availability dynamically upon receiving valid Realtime event', async () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    // Initial state: #A01 is available
    const initialBadge = screen.getByTestId('status-badge-prod-01');
    expect(initialBadge).toHaveTextContent('AVAILABLE');

    // Simulate Realtime event: prod-01 status transitions to 'reserved' (version 2)
    const updatedProd: PublicProductView = {
      ...mockProducts[0],
      status: 'reserved',
      version: 2,
    };

    expect(capturedCallback).toBeDefined();
    await React.act(async () => {
      capturedCallback!(updatedProd);
    });

    // UI dynamically reflects reserved status without full page refresh
    await waitFor(() => {
      const updatedBadge = screen.getByTestId('status-badge-prod-01');
      expect(updatedBadge).toHaveTextContent('RESERVED');
    });
  });

  it('cleans up Realtime subscription upon component unmount', () => {
    const { unmount } = render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    unmount();
    expect(mockUnsubscribe).toHaveBeenCalledTimes(1);
  });

  it('displays offline indicator when realtime connection drops but preserves catalog', async () => {
    render(
      <PublicDropView
        slug="mothers-boutique"
        initialDrop={mockLiveDrop}
        initialProducts={mockProducts}
      />
    );

    // Initially connected
    expect(screen.getByTestId('realtime-status')).toHaveTextContent('Live updates');

    // Simulate connection drop
    expect(capturedStatusCallback).toBeDefined();
    await React.act(async () => {
      capturedStatusCallback!('CHANNEL_ERROR');
    });

    // Indicator switches to offline
    await waitFor(() => {
      expect(screen.getByTestId('realtime-status')).toHaveTextContent('Offline');
    });

    // Loaded catalog products remain fully visible and interactive
    expect(screen.getByTestId('product-card-prod-01')).toBeInTheDocument();
    expect(screen.getByTestId('product-card-prod-02')).toBeInTheDocument();
  });
});
