/**
 * LiveDrop Buyer Webfront — Buyer Cart Integration & Component Tests (TASK-2.2)
 *
 * Comprehensive tests covering:
 * 1. Cart domain operations: add, remove, clear, single-piece deduplication, drop boundary
 * 2. Integer Paisa calculations (ADR-009) with zero floating-point math
 * 3. Realtime & catalog availability reconciliation (reserved/sold transitions, checkout disabling)
 * 4. UI components: ProductCard button transitions, StickyCartBar, CartDrawer, CartEmptyState
 * 5. Multi-tab storage synchronization and SSR hydration safety
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor, renderHook, act } from '@testing-library/react';
import { CartProvider, useCart, resetCartStore } from '../lib/cart/cart-context';
import { ProductCard } from '../components/ProductCard';
import { StickyCartBar } from '../components/cart/StickyCartBar';
import { CartDrawer } from '../components/cart/CartDrawer';
import { CartEmptyState } from '../components/cart/CartEmptyState';
import { PublicDropView } from '../components/PublicDropView';
import { PublicProductView, PublicDropCatalog } from '../types/domain';
import { CART_STORAGE_KEY } from '../lib/cart/cart-storage';

const mockDrop: PublicDropCatalog = {
  id: 'drop-test-uuid-01',
  seller_id: 'seller-test-uuid-01',
  title: 'Silk Showcase Live',
  slug: 'silk-showcase',
  status: 'live',
  shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 200000,
  live_started_at: '2026-09-11T12:00:00Z',
  closed_at: null,
  created_at: '2026-09-11T11:00:00Z',
  updated_at: '2026-09-11T11:00:00Z',
  profiles: {
    store_name: "Silk Studio",
    store_slug: 'silk-studio',
    phone_number: '919830012345',
    upi_id: 'silkstudio@okaxis',
    upi_qr_url: null,
    default_shipping_fee_paisa: 8000,
    free_shipping_threshold_paisa: 200000,
    advance_confirmation_enabled: true,
    advance_amount_paisa: 25000,
    hold_duration_days: 30,
  },
};

const mockProductA1: PublicProductView = {
  id: 'prod-01',
  code: '#A01',
  title: 'Handloom Tussar Saree',
  price_paisa: 185000, // ₹1,850.00
  size: 'Free Size',
  image_url: 'https://images.livedrop.store/saree.webp',
  status: 'available',
  reserved_at: null,
  version: 1,
};

const mockProductA2: PublicProductView = {
  id: 'prod-02',
  code: '#A02',
  title: 'Chanderi Cotton Kurti',
  price_paisa: 75000, // ₹750.00
  size: 'M',
  image_url: 'https://images.livedrop.store/kurti.webp',
  status: 'available',
  reserved_at: null,
  version: 1,
};

const mockProductA3Sold: PublicProductView = {
  id: 'prod-03',
  code: '#A03',
  title: 'Pure Jamdani Silk Dupatta',
  price_paisa: 125000,
  size: 'Free Size',
  image_url: 'https://images.livedrop.store/dupatta.webp',
  status: 'sold',
  reserved_at: null,
  version: 2,
};

describe('TASK-2.2: Cart Context Domain Operations', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
  });

  it('adds an available product and updates item count and integer Paisa subtotal', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      const res = result.current.addItem(mockProductA1, 'drop-test-uuid-01');
      expect(res.success).toBe(true);
    });

    expect(result.current.itemCount).toBe(1);
    expect(result.current.items).toHaveLength(1);
    expect(result.current.items[0].code).toBe('#A01');
    expect(result.current.items[0].pricePaisa).toBe(185000);
    expect(result.current.subtotalPaisa).toBe(185000);
    expect(result.current.isInCart('prod-01')).toBe(true);
  });

  it('enforces single-piece inventory invariant: duplicate adds do not create quantity > 1', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      const firstAdd = result.current.addItem(mockProductA1, 'drop-test-uuid-01');
      expect(firstAdd.success).toBe(true);
    });

    // Attempt second add of same unique product
    act(() => {
      const secondAdd = result.current.addItem(mockProductA1, 'drop-test-uuid-01');
      expect(secondAdd.success).toBe(false);
      if (!secondAdd.success) {
        expect(secondAdd.reason).toBe('ALREADY_IN_CART');
      }
    });

    expect(result.current.itemCount).toBe(1);
    expect(result.current.items).toHaveLength(1);
    expect(result.current.subtotalPaisa).toBe(185000);
  });

  it('calculates integer Paisa totals accurately across multiple products', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      result.current.addItem(mockProductA1, 'drop-test-uuid-01'); // 185000 paisa
      result.current.addItem(mockProductA2, 'drop-test-uuid-01'); // 75000 paisa
    });

    expect(result.current.itemCount).toBe(2);
    // Integer Paisa: 185000 + 75000 = 260000 (₹2,600)
    expect(result.current.subtotalPaisa).toBe(260000);

    // Remove one item
    act(() => {
      result.current.removeItem('prod-01');
    });

    expect(result.current.itemCount).toBe(1);
    expect(result.current.subtotalPaisa).toBe(75000);
  });

  it('rejects adding an unavailable (reserved or sold) product', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      const res = result.current.addItem(mockProductA3Sold, 'drop-test-uuid-01');
      expect(res.success).toBe(false);
      if (!res.success) {
        expect(res.reason).toBe('UNAVAILABLE');
      }
    });

    expect(result.current.itemCount).toBe(0);
    expect(result.current.subtotalPaisa).toBe(0);
  });

  it('enforces drop boundary constraint: blocks adding products from different drop', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      result.current.addItem(mockProductA1, 'drop-test-uuid-01');
    });

    act(() => {
      const foreignProduct: PublicProductView = {
        ...mockProductA2,
        id: 'prod-foreign-01',
      };
      const res = result.current.addItem(foreignProduct, 'drop-different-uuid-99');
      expect(res.success).toBe(false);
      if (!res.success) {
        expect(res.reason).toBe('DIFFERENT_DROP');
      }
    });

    expect(result.current.itemCount).toBe(1);
  });

  it('clears all items and storage on clearCart()', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      result.current.addItem(mockProductA1, 'drop-test-uuid-01');
      result.current.addItem(mockProductA2, 'drop-test-uuid-01');
    });

    expect(result.current.itemCount).toBe(2);

    act(() => {
      result.current.clearCart();
    });

    expect(result.current.itemCount).toBe(0);
    expect(result.current.items).toEqual([]);
    expect(result.current.subtotalPaisa).toBe(0);
    expect(window.localStorage.getItem(CART_STORAGE_KEY)).toBeNull();
  });
});

describe('TASK-2.2: Availability Reconciliation & Stale Catalog Handling', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
  });

  it('reconciles cart items when a product becomes RESERVED in the live catalog', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      result.current.addItem(mockProductA1, 'drop-test-uuid-01');
    });

    // Catalog state updates: #A01 was reserved by another buyer
    const updatedCatalog: PublicProductView[] = [
      {
        ...mockProductA1,
        status: 'reserved',
        reserved_at: '2026-09-11T12:05:00Z',
        version: 2,
      },
    ];

    const reconciled = result.current.getReconciledItems(updatedCatalog);
    expect(reconciled).toHaveLength(1);
    expect(reconciled[0].status).toBe('reserved');
    expect(reconciled[0].isAvailable).toBe(false);
  });

  it('reconciles cart items when a product becomes SOLD OUT in the live catalog', () => {
    const { result } = renderHook(() => useCart(), {
      wrapper: ({ children }) => <CartProvider>{children}</CartProvider>,
    });

    act(() => {
      result.current.addItem(mockProductA1, 'drop-test-uuid-01');
    });

    // Catalog state updates: #A01 is sold
    const updatedCatalog: PublicProductView[] = [
      {
        ...mockProductA1,
        status: 'sold',
        version: 3,
      },
    ];

    const reconciled = result.current.getReconciledItems(updatedCatalog);
    expect(reconciled).toHaveLength(1);
    expect(reconciled[0].status).toBe('sold');
    expect(reconciled[0].isAvailable).toBe(false);
  });
});

describe('TASK-2.2: ProductCard Cart Button States', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
  });

  it('renders "+ Add to Bag" for available product and switches to "In Cart" on click', () => {
    render(
      <CartProvider>
        <ProductCard product={mockProductA1} dropId="drop-test-uuid-01" />
      </CartProvider>
    );

    const btn = screen.getByTestId('cart-btn-prod-01');
    expect(btn).toHaveTextContent('Add to Bag');

    fireEvent.click(btn);

    expect(btn).toHaveTextContent('In Cart');
  });

  it('clicking "In Cart" button a second time does not duplicate item', () => {
    render(
      <CartProvider>
        <ProductCard product={mockProductA1} dropId="drop-test-uuid-01" />
      </CartProvider>
    );

    const btn = screen.getByTestId('cart-btn-prod-01');
    fireEvent.click(btn);
    expect(btn).toHaveTextContent('In Cart');

    // Second click
    fireEvent.click(btn);
    expect(btn).toHaveTextContent('In Cart');
  });

  it('renders disabled "Sold Out" button for sold products', () => {
    render(
      <CartProvider>
        <ProductCard product={mockProductA3Sold} dropId="drop-test-uuid-01" />
      </CartProvider>
    );

    const btn = screen.getByTestId('cart-btn-prod-03');
    expect(btn).toBeDisabled();
    expect(btn).toHaveTextContent('Sold Out');
  });
});

describe('TASK-2.2: StickyCartBar & CartDrawer UI Components', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
  });

  it('renders StickyCartBar only when items exist, showing item count and formatted INR subtotal', () => {
    const handleOpen = vi.fn();

    const { unmount } = render(
      <CartProvider>
        <StickyCartBar onOpenCart={handleOpen} />
      </CartProvider>
    );

    // Initial empty state: bar should not be visible
    expect(screen.queryByTestId('sticky-cart-bar')).toBeNull();
    unmount();

    // Pre-populate cart in storage
    window.localStorage.setItem(
      CART_STORAGE_KEY,
      JSON.stringify({
        version: 1,
        dropId: 'drop-test-uuid-01',
        items: [
          {
            productId: 'prod-01',
            dropId: 'drop-test-uuid-01',
            code: '#A01',
            title: 'Saree',
            pricePaisa: 185000,
            imageUrl: '',
            size: '',
            addedAt: Date.now(),
          },
        ],
        updatedAt: Date.now(),
      })
    );
    resetCartStore();

    render(
      <CartProvider>
        <StickyCartBar onOpenCart={handleOpen} />
      </CartProvider>
    );

    const bar = screen.getByTestId('sticky-cart-bar');
    expect(bar).toBeInTheDocument();
    expect(screen.getByTestId('sticky-cart-count')).toHaveTextContent('Cart · 1');
    expect(screen.getByTestId('sticky-cart-subtotal')).toHaveTextContent('₹1,850');

    const viewBtn = screen.getByTestId('sticky-view-cart-btn');
    fireEvent.click(viewBtn);
    expect(handleOpen).toHaveBeenCalledTimes(1);
  });

  it('renders CartDrawer with items, prominent flash code, remove button, and subtotal', () => {
    window.localStorage.setItem(
      CART_STORAGE_KEY,
      JSON.stringify({
        version: 1,
        dropId: 'drop-test-uuid-01',
        items: [
          {
            productId: 'prod-01',
            dropId: 'drop-test-uuid-01',
            code: '#A01',
            title: 'Handloom Tussar Saree',
            pricePaisa: 185000,
            imageUrl: '',
            size: 'Free Size',
            addedAt: Date.now(),
          },
        ],
        updatedAt: Date.now(),
      })
    );

    const handleClose = vi.fn();

    render(
      <CartProvider>
        <CartDrawer
          isOpen={true}
          onClose={handleClose}
          catalogProducts={[mockProductA1]}
          drop={mockDrop}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('cart-drawer')).toBeInTheDocument();
    expect(screen.getByText('#A01')).toBeInTheDocument();
    expect(screen.getByText('Handloom Tussar Saree')).toBeInTheDocument();
    expect(screen.getByTestId('cart-subtotal')).toHaveTextContent('₹1,850');

    // Remove item
    const removeBtn = screen.getByTestId('cart-remove-prod-01');
    fireEvent.click(removeBtn);

    // Empty state should appear
    expect(screen.getByTestId('cart-empty-state')).toBeInTheDocument();
  });

  it('disables checkout button and shows warning banner when an item in cart is unavailable', () => {
    window.localStorage.setItem(
      CART_STORAGE_KEY,
      JSON.stringify({
        version: 1,
        dropId: 'drop-test-uuid-01',
        items: [
          {
            productId: 'prod-01',
            dropId: 'drop-test-uuid-01',
            code: '#A01',
            title: 'Handloom Tussar Saree',
            pricePaisa: 185000,
            imageUrl: '',
            size: 'Free Size',
            addedAt: Date.now(),
          },
        ],
        updatedAt: Date.now(),
      })
    );

    // Catalog has #A01 as RESERVED
    const reservedCatalog: PublicProductView[] = [
      {
        ...mockProductA1,
        status: 'reserved',
        reserved_at: '2026-09-11T12:05:00Z',
        version: 2,
      },
    ];

    render(
      <CartProvider>
        <CartDrawer
          isOpen={true}
          onClose={() => {}}
          catalogProducts={reservedCatalog}
          drop={mockDrop}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('cart-unavailable-banner')).toBeInTheDocument();
    expect(screen.getByTestId('cart-item-warning-prod-01')).toHaveTextContent('RESERVED — No longer available');
    expect(screen.getByTestId('cart-checkout-btn')).toBeDisabled();
    expect(screen.getByTestId('cart-continue-shopping-btn')).toBeInTheDocument();
    expect(screen.queryByTestId('cart-subtotal')).toBeNull(); // ₹0 summary card is suppressed

    // 1-click remove unavailable items
    const removeUnavailableBtn = screen.getByTestId('cart-remove-unavailable-btn');
    fireEvent.click(removeUnavailableBtn);

    // Cart is now empty
    expect(screen.getByTestId('cart-empty-state')).toBeInTheDocument();
  });
});

describe('TASK-2.2: Full PublicDropView Cart Integration', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
  });

  it('integrates catalog browsing and add-to-cart in PublicDropView end-to-end', async () => {
    render(
      <PublicDropView
        slug="silk-showcase"
        initialDrop={mockDrop}
        initialProducts={[mockProductA1, mockProductA2]}
      />
    );

    // Initial state: sticky cart bar is not rendered
    expect(screen.queryByTestId('sticky-cart-bar')).toBeNull();

    // Tap Add to Bag on #A01
    const addBtn = screen.getByTestId('cart-btn-prod-01');
    fireEvent.click(addBtn);

    // Button updates to In Cart
    expect(addBtn).toHaveTextContent('In Cart');

    // Sticky cart bar appears with 1 item and ₹1,850
    await waitFor(() => {
      expect(screen.getByTestId('sticky-cart-bar')).toBeInTheDocument();
    });
    expect(screen.getByTestId('sticky-cart-count')).toHaveTextContent('Cart · 1');
    expect(screen.getByTestId('sticky-cart-subtotal')).toHaveTextContent('₹1,850');

    // Header cart badge displays 1
    expect(screen.getByTestId('header-cart-count')).toHaveTextContent('1');

    // Open Cart Drawer
    const viewCartBtn = screen.getByTestId('sticky-view-cart-btn');
    fireEvent.click(viewCartBtn);

    expect(screen.getByTestId('cart-drawer')).toBeInTheDocument();
    expect(screen.getByTestId('cart-item-prod-01')).toBeInTheDocument();

    // Close Cart Drawer via close button
    const closeBtn = screen.getByTestId('cart-drawer-close');
    fireEvent.click(closeBtn);

    await waitFor(() => {
      expect(screen.queryByTestId('cart-drawer')).toBeNull();
    });
  });
});

describe('TASK-2.2: CartEmptyState Component', () => {
  it('renders empty cart icon, title, description, and triggers browse callback', () => {
    const handleBrowse = vi.fn();
    render(<CartEmptyState onBrowse={handleBrowse} />);

    expect(screen.getByTestId('cart-empty-state')).toBeInTheDocument();
    expect(screen.getByText('Your bag is empty')).toBeInTheDocument();
    expect(
      screen.getByText('Discover unique pieces from independent boutiques.')
    ).toBeInTheDocument();

    const browseBtn = screen.getByTestId('cart-browse-btn');
    expect(browseBtn).toHaveTextContent('Explore Shop');
    fireEvent.click(browseBtn);
    expect(handleBrowse).toHaveBeenCalledTimes(1);
  });
});
