/**
 * LiveDrop Buyer Webfront — Phase 1A Stabilization & Behavior Preservation Audit Tests
 *
 * Verifies all 15 production-shaped cases:
 * 1. No active live drop
 * 2. One active live drop
 * 3. Multiple active live drops
 * 4. Empty featured-products response
 * 5. Empty storefront response
 * 6. Reserved product
 * 7. Sold product
 * 8. Missing product image
 * 9. Search query
 * 10. Category selection
 * 11. Product-card navigation
 * 12. Boutique-card navigation
 * 13. Cart add/open behavior
 * 14. Mobile navigation
 * 15. Desktop navigation
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';
import { HomeStorefront } from '../components/HomeStorefront';
import { CartProvider, resetCartStore } from '../lib/cart/cart-context';
import { ProfileProvider } from '../lib/profile/profile-context';
import { PublicDropCatalog, PublicSellerStorefront, PublicProductView } from '../types/domain';

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
  }),
}));

const mockBoutiqueA: PublicSellerStorefront = {
  id: 'seller-a',
  store_name: "Aadya's Heritage",
  store_slug: 'aadyas-heritage',
  phone_number: '919876543210',
  upi_id: 'aadya@okhdfc',
  upi_qr_url: null,
  default_shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  advance_confirmation_enabled: false,
  advance_amount_paisa: 0,
  hold_duration_days: 2,
  is_approved: true,
};

const mockBoutiqueB: PublicSellerStorefront = {
  id: 'seller-b',
  store_name: "Banaras Weaves",
  store_slug: 'banaras-weaves',
  phone_number: '919876543211',
  upi_id: 'banaras@okaxis',
  upi_qr_url: null,
  default_shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  advance_confirmation_enabled: false,
  advance_amount_paisa: 0,
  hold_duration_days: 2,
  is_approved: true,
};

const mockDrop1: PublicDropCatalog = {
  id: 'drop-1',
  seller_id: 'seller-a',
  title: 'Royal Banarasi Silk Drop',
  slug: 'royal-banarasi-silk-drop',
  status: 'live',
  shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  live_started_at: '2026-09-28T10:00:00Z',
  closed_at: null,
  created_at: '2026-09-28T09:00:00Z',
  updated_at: '2026-09-28T09:00:00Z',
  profiles: {
    store_name: "Aadya's Heritage",
    store_slug: 'aadyas-heritage',
    phone_number: '919876543210',
    upi_id: 'aadya@okhdfc',
    upi_qr_url: null,
    default_shipping_fee_paisa: 0,
    free_shipping_threshold_paisa: null,
    advance_confirmation_enabled: false,
    advance_amount_paisa: 0,
    hold_duration_days: 2,
  },
};

const mockDrop2: PublicDropCatalog = {
  id: 'drop-2',
  seller_id: 'seller-b',
  title: 'Chanderi Festival Showcase',
  slug: 'chanderi-festival-showcase',
  status: 'live',
  shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  live_started_at: '2026-09-28T11:00:00Z',
  closed_at: null,
  created_at: '2026-09-28T09:30:00Z',
  updated_at: '2026-09-28T09:30:00Z',
  profiles: {
    store_name: "Banaras Weaves",
    store_slug: 'banaras-weaves',
    phone_number: '919876543211',
    upi_id: 'banaras@okaxis',
    upi_qr_url: null,
    default_shipping_fee_paisa: 0,
    free_shipping_threshold_paisa: null,
    advance_confirmation_enabled: false,
    advance_amount_paisa: 0,
    hold_duration_days: 2,
  },
};

const mockAvailableProduct: PublicProductView = {
  id: 'prod-avail',
  seller_id: 'seller-a',
  drop_id: 'drop-1',
  code: '#S01',
  title: 'Pure Katan Silk Saree',
  size: 'Free Size',
  price_paisa: 1850000,
  image_url: 'https://images.unsplash.com/photo-saree',
  status: 'available',
  reserved_at: null,
  version: 1,
};

const mockReservedProduct: PublicProductView = {
  id: 'prod-res',
  seller_id: 'seller-a',
  drop_id: 'drop-1',
  code: '#L01',
  title: 'Crimson Velvet Bridal Lehenga',
  size: 'M',
  price_paisa: 3500000,
  image_url: 'https://images.unsplash.com/photo-lehenga',
  status: 'reserved',
  reserved_at: '2026-09-28T12:00:00Z',
  version: 2,
};

const mockSoldProduct: PublicProductView = {
  id: 'prod-sold',
  seller_id: 'seller-a',
  drop_id: 'drop-1',
  code: '#K01',
  title: 'Handloom Chanderi Anarkali Kurti',
  size: 'L',
  price_paisa: 850000,
  image_url: 'https://images.unsplash.com/photo-kurti',
  status: 'sold',
  reserved_at: null,
  version: 3,
};

const mockMissingImageProduct: PublicProductView = {
  id: 'prod-no-img',
  seller_id: 'seller-a',
  drop_id: 'drop-1',
  code: '#J01',
  title: 'Polki Diamond Kundan Necklace',
  size: 'Adjustable',
  price_paisa: 4200000,
  image_url: '',
  status: 'available',
  reserved_at: null,
  version: 1,
};

function renderWithProviders(ui: React.ReactElement) {
  return render(
    <CartProvider>
      <ProfileProvider>{ui}</ProfileProvider>
    </CartProvider>
  );
}

describe('Phase 1A Homepage Stabilization & 15 Production Cases', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    vi.clearAllMocks();
  });

  // Case 1: No active live drop
  it('Case 1: Renders graceful NO LIVE DROP state when no broadcast is active', () => {
    renderWithProviders(<HomeStorefront activeDrops={[]} storefronts={[mockBoutiqueA]} />);

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('NO LIVE DROP');
    expect(screen.getByText('Explore pieces from independent boutiques.')).toBeInTheDocument();
    const cta = screen.getByTestId('explore-live-shows-btn');
    expect(cta).toHaveAttribute('href', '/shop');
  });

  // Case 2: One active live drop
  it('Case 2: Renders LIVE NOW hero when exactly one drop is streaming', () => {
    renderWithProviders(
      <HomeStorefront activeDrops={[mockDrop1]} storefronts={[mockBoutiqueA]} />
    );

    const hero = screen.getByTestId('live-drop-hero');
    expect(hero).toHaveTextContent(/LIVE NOW/i);
    expect(hero).toHaveTextContent('Royal Banarasi Silk Drop');
    expect(hero).toHaveTextContent("Aadya's Heritage");

    const shopBtn = screen.getByTestId('shop-live-hero-btn');
    expect(shopBtn).toHaveAttribute('href', '/drop/royal-banarasi-silk-drop');
  });

  // Case 3: Multiple active live drops
  it('Case 3: Handles multiple active live drops by prioritizing the primary drop', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockDrop1, mockDrop2]}
        storefronts={[mockBoutiqueA, mockBoutiqueB]}
      />
    );

    const hero = screen.getByTestId('live-drop-hero');
    expect(hero).toBeInTheDocument();
    expect(hero).toHaveTextContent('Royal Banarasi Silk Drop');
  });

  // Case 4: Empty featured-products response
  it('Case 4: Renders compact clean empty state when featured products array is empty', () => {
    renderWithProviders(
      <HomeStorefront storefronts={[mockBoutiqueA]} featuredProducts={[]} />
    );

    expect(screen.getByText('0 pieces available')).toBeInTheDocument();
    expect(screen.getByText(/New collection pieces dropping soon/i)).toBeInTheDocument();
    expect(screen.getByText(/Browse all categories in shop →/i)).toBeInTheDocument();
  });

  // Case 5: Empty storefront response
  it('Case 5: Renders compact empty state when storefront directory is empty', () => {
    renderWithProviders(
      <HomeStorefront activeDrops={[]} storefronts={[]} featuredProducts={[]} />
    );

    expect(screen.getByTestId('boutiques-empty-state')).toBeInTheDocument();
    expect(screen.getByText(/Independent boutiques will be featured here soon/i)).toBeInTheDocument();
  });

  // Case 6: Reserved product
  it('Case 6: Correctly marks reserved piece with badge and disabled button', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[mockReservedProduct]}
      />
    );

    expect(screen.getByText('RESERVED')).toBeInTheDocument();
    const btn = screen.getByTestId('cart-btn-prod-res');
    expect(btn).toBeDisabled();
    expect(btn).toHaveTextContent('Reserved');
  });

  // Case 7: Sold product
  it('Case 7: Correctly marks sold piece with badge and disabled Sold Out button', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[mockSoldProduct]}
      />
    );

    expect(screen.getByText('SOLD OUT')).toBeInTheDocument();
    const btn = screen.getByTestId('cart-btn-prod-sold');
    expect(btn).toBeDisabled();
    expect(btn).toHaveTextContent('Sold Out');
  });

  // Case 8: Missing product image
  it('Case 8: Renders branded fallback placeholder when image_url is missing', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[mockMissingImageProduct]}
      />
    );

    const fallback = screen.getByTestId('fallback-image-prod-no-img');
    expect(fallback).toBeInTheDocument();
    expect(fallback).toHaveTextContent('LiveDrop');
    expect(fallback).toHaveTextContent('Image unavailable');
  });

  // Case 9: Search query filtering
  it('Case 9: Filters both products and boutiques dynamically via search input', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA, mockBoutiqueB]}
        featuredProducts={[mockAvailableProduct, mockReservedProduct]}
      />
    );

    const searchInput = screen.getByTestId('platform-search-input');
    fireEvent.change(searchInput, { target: { value: 'Saree' } });

    // Product filtered
    expect(screen.getByText('Pure Katan Silk Saree')).toBeInTheDocument();
    expect(screen.queryByText('Crimson Velvet Bridal Lehenga')).toBeNull();

    // Boutiques filtered
    fireEvent.change(searchInput, { target: { value: 'Banaras' } });
    expect(screen.getByTestId('boutique-card-banaras-weaves')).toBeInTheDocument();
    expect(screen.queryByTestId('boutique-card-aadyas-heritage')).toBeNull();
  });

  // Case 10: Category selection
  it('Case 10: Filters displayed products when category chips are selected', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[mockAvailableProduct, mockReservedProduct]}
      />
    );

    // Select Sarees
    fireEvent.click(screen.getByTestId('category-chip-sarees'));
    expect(screen.getByText('Pure Katan Silk Saree')).toBeInTheDocument();
    expect(screen.queryByText('Crimson Velvet Bridal Lehenga')).toBeNull();

    // Select Lehengas
    fireEvent.click(screen.getByTestId('category-chip-lehengas'));
    expect(screen.getByText('Crimson Velvet Bridal Lehenga')).toBeInTheDocument();
    expect(screen.queryByText('Pure Katan Silk Saree')).toBeNull();
  });

  // Case 11: Product-card navigation & modal
  it('Case 11: Clicking product card opens detail modal with full specifications', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[mockAvailableProduct]}
      />
    );

    const card = screen.getByTestId('product-card-prod-avail');
    fireEvent.click(card);

    expect(screen.getByTestId('product-detail-sheet-prod-avail')).toBeInTheDocument();
    expect(screen.getByText(/Pure Handloom Silk/i)).toBeInTheDocument();
  });

  // Case 12: Boutique-card navigation
  it('Case 12: Boutique card links directly to boutique storefront URL', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[]}
      />
    );

    const visitLink = screen.getByTestId('visit-boutique-aadyas-heritage');
    expect(visitLink).toHaveAttribute('href', '/aadyas-heritage');
  });

  // Case 13: Cart add/open behavior
  it('Case 13: Clicking Add to Bag adds available product to cart and updates state', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockDrop1]}
        storefronts={[mockBoutiqueA]}
        featuredProducts={[mockAvailableProduct]}
      />
    );

    const addBtn = screen.getByTestId('cart-btn-prod-avail');
    expect(addBtn).toHaveTextContent('Add to Bag');

    fireEvent.click(addBtn);

    expect(screen.getByTestId('cart-btn-prod-avail')).toHaveTextContent('In Cart');
  });

  // Case 14: Mobile navigation dock
  it('Case 14: Renders mobile bottom dock with Home tab marked active', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[]}
      />
    );

    const dock = screen.getByTestId('mobile-bottom-dock');
    expect(dock).toBeInTheDocument();

    const homeTab = screen.getByTestId('dock-home-tab');
    expect(homeTab).toHaveAttribute('aria-current', 'page');
  });

  // Case 15: Desktop navigation header
  it('Case 15: Renders luxury desktop header with brand mark and primary links', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutiqueA]}
        featuredProducts={[]}
      />
    );

    const header = screen.getByTestId('global-buyer-header');
    expect(header).toBeInTheDocument();
    expect(screen.getAllByText('LiveDrop').length).toBeGreaterThan(0);
    expect(within(header).getByRole('link', { name: 'Shop' })).toHaveAttribute('href', '/shop');
  });
});
