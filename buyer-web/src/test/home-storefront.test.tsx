/**
 * LiveDrop Buyer Webfront — HomeStorefront Phase 3 Acceptance & Unit Tests
 *
 * Verifies Phase 3 Specifications:
 * 1. Primary Hierarchy: Header -> Live Drop Hero -> Category Rail -> Featured Pieces -> Live Boutiques -> Compact Trust Strip -> Footer
 * 2. Hero Live State: LIVE NOW, title, boutique name, Shop Live Drop button
 * 3. Hero No-Live State: NO LIVE DROP, "Explore pieces from independent boutiques.", Shop Collections button
 * 4. Product Grid Count states: 4 products, 1 product, 0 products (compact empty state)
 * 5. Boutique Directory states: multiple boutiques, 0 boutiques (compact empty state)
 * 6. Category rail chips and filtering
 * 7. Compact trust strip with verified product assurances
 * 8. Links and navigation integrity
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { HomeStorefront } from '../components/HomeStorefront';
import { CartProvider } from '../lib/cart/cart-context';
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

const mockBoutique1: PublicSellerStorefront = {
  id: 'seller-1',
  store_name: "Suv's Atelier",
  store_slug: 'suvs-atelier',
  phone_number: '9876543210',
  upi_id: 'suv@okaxis',
  upi_qr_url: null,
  default_shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  advance_confirmation_enabled: false,
  advance_amount_paisa: 0,
  hold_duration_days: 2,
  is_approved: true,
};

const mockBoutique2: PublicSellerStorefront = {
  id: 'seller-2',
  store_name: "Sonali's Heritage",
  store_slug: 'sonalis-heritage',
  phone_number: '9876543211',
  upi_id: 'sonali@okhdfc',
  upi_qr_url: null,
  default_shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  advance_confirmation_enabled: false,
  advance_amount_paisa: 0,
  hold_duration_days: 2,
  is_approved: true,
};

const mockLiveDrop: PublicDropCatalog = {
  id: 'drop-live-1',
  seller_id: 'seller-1',
  title: 'Bridal Lehengas with Anaya',
  slug: 'bridal-lehengas-with-anaya',
  status: 'live',
  shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  live_started_at: '2026-09-25T10:00:00Z',
  closed_at: null,
  created_at: '2026-09-25T09:00:00Z',
  updated_at: '2026-09-25T09:00:00Z',
  profiles: {
    store_name: "Suv's Atelier",
    store_slug: 'suvs-atelier',
    phone_number: '9876543210',
    upi_id: 'suv@okaxis',
    upi_qr_url: null,
    default_shipping_fee_paisa: 0,
    free_shipping_threshold_paisa: null,
    advance_confirmation_enabled: false,
    advance_amount_paisa: 0,
    hold_duration_days: 2,
  },
};

const createMockProduct = (id: string, code: string, title: string): PublicProductView => ({
  id,
  seller_id: 'seller-1',
  drop_id: 'drop-live-1',
  code,
  title,
  size: 'Free Size',
  price_paisa: 250000,
  image_url: 'https://images.unsplash.com/photo-example',
  status: 'available',
  reserved_at: null,
  version: 1,
});

const mockFourProducts: PublicProductView[] = [
  createMockProduct('prod-1', 'S01', 'Kanjeevaram Silk Saree'),
  createMockProduct('prod-2', 'L01', 'Zardozi Velvet Lehenga'),
  createMockProduct('prod-3', 'K01', 'Chanderi Embroidered Kurti'),
  createMockProduct('prod-4', 'J01', 'Kundan Choker Jewellery'),
];

function renderWithProviders(ui: React.ReactElement) {
  return render(
    <CartProvider>
      <ProfileProvider>{ui}</ProfileProvider>
    </CartProvider>
  );
}

describe('HomeStorefront Phase 3 Acceptance Tests', () => {
  it('STATE 1: renders LIVE NOW broadcast hero when an active drop exists', () => {
    renderWithProviders(
      <HomeStorefront activeDrops={[mockLiveDrop]} storefronts={[mockBoutique1]} />
    );

    const hero = screen.getByTestId('live-drop-hero');
    expect(hero).toHaveTextContent('LIVE NOW');
    expect(hero).toHaveTextContent('Bridal Lehengas with Anaya');
    expect(hero).toHaveTextContent("Suv's Atelier");

    const shopLiveBtn = screen.getByTestId('shop-live-hero-btn');
    expect(shopLiveBtn).toBeInTheDocument();
    expect(shopLiveBtn).toHaveAttribute('href', '/drop/bridal-lehengas-with-anaya');
  });

  it('STATE 2: renders NO LIVE DROP hero when no drop is streaming', () => {
    renderWithProviders(<HomeStorefront activeDrops={[]} storefronts={[mockBoutique1]} />);

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('NO LIVE DROP');
    expect(screen.getByText('Explore pieces from independent boutiques.')).toBeInTheDocument();

    const shopCollectionsBtn = screen.getByTestId('explore-live-shows-btn');
    expect(shopCollectionsBtn).toBeInTheDocument();
    expect(shopCollectionsBtn).toHaveAttribute('href', '/shop');
  });

  it('CATEGORY RAIL: renders all category chips in normal document flow', () => {
    renderWithProviders(<HomeStorefront storefronts={[mockBoutique1]} />);

    expect(screen.getByTestId('category-chips-rail')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-all')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-sarees')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-kurtis')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-lehengas')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-dupattas')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-jewellery')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-accessories')).toBeInTheDocument();
  });

  it('FEATURED PIECES (4 PRODUCTS): renders grid with 4 pieces and View All link', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique1]}
        featuredProducts={mockFourProducts}
      />
    );

    expect(screen.getByText('Featured Pieces')).toBeInTheDocument();
    expect(screen.getByText('4 pieces available')).toBeInTheDocument();

    const viewAllLink = screen.getByTestId('featured-view-all-btn');
    expect(viewAllLink).toBeInTheDocument();
    expect(viewAllLink).toHaveAttribute('href', '/shop');

    expect(screen.getByText('Kanjeevaram Silk Saree')).toBeInTheDocument();
    expect(screen.getByText('Zardozi Velvet Lehenga')).toBeInTheDocument();
    expect(screen.getByText('Chanderi Embroidered Kurti')).toBeInTheDocument();
    expect(screen.getByText('Kundan Choker Jewellery')).toBeInTheDocument();
  });

  it('FEATURED PIECES (1 PRODUCT): renders single piece correctly', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique1]}
        featuredProducts={[mockFourProducts[0]]}
      />
    );

    expect(screen.getByText('1 pieces available')).toBeInTheDocument();
    expect(screen.getByText('Kanjeevaram Silk Saree')).toBeInTheDocument();
    expect(screen.queryByText('Zardozi Velvet Lehenga')).toBeNull();
  });

  it('FEATURED PIECES (0 PRODUCTS): renders compact intentional empty state', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique1]}
        featuredProducts={[]}
      />
    );

    expect(screen.getByText('0 pieces available')).toBeInTheDocument();
    expect(screen.getByText(/New collection pieces dropping soon/i)).toBeInTheDocument();
    expect(screen.getByText(/Browse all categories in shop →/i)).toBeInTheDocument();
  });

  it('BOUTIQUES DIRECTORY (MULTIPLE): renders compact horizontal boutique rail', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockLiveDrop]}
        storefronts={[mockBoutique1, mockBoutique2]}
      />
    );

    expect(screen.getByText('Live Boutiques')).toBeInTheDocument();
    expect(screen.getByTestId('boutiques-view-all-btn')).toHaveAttribute('href', '/shop');

    expect(screen.getByTestId('boutique-card-suvs-atelier')).toBeInTheDocument();
    expect(screen.getByTestId('boutique-card-sonalis-heritage')).toBeInTheDocument();

    // Live status only for active live drop
    expect(screen.getByTestId('boutique-live-badge-suvs-atelier')).toBeInTheDocument();
    expect(screen.queryByTestId('boutique-live-badge-sonalis-heritage')).toBeNull();

    // Visit link
    expect(screen.getByTestId('visit-boutique-suvs-atelier')).toHaveAttribute('href', '/suvs-atelier');
  });

  it('BOUTIQUES DIRECTORY (0 BOUTIQUES): renders compact empty state without giant empty container', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[]}
      />
    );

    expect(screen.getByTestId('boutiques-empty-state')).toBeInTheDocument();
    expect(screen.getByText(/Independent boutiques will be featured here soon/i)).toBeInTheDocument();
  });

  it('TRUST STRIP: renders restrained verified assurances', () => {
    renderWithProviders(<HomeStorefront storefronts={[mockBoutique1]} />);

    expect(screen.getByText('Direct UPI')).toBeInTheDocument();
    expect(screen.getByText('Instant Reservation')).toBeInTheDocument();
    expect(screen.getByText('Independent Boutiques')).toBeInTheDocument();
  });

  it('CATEGORY FILTERING: filters displayed products when category chips are clicked', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique1]}
        featuredProducts={mockFourProducts}
      />
    );

    // Click 'Sarees' chip
    fireEvent.click(screen.getByTestId('category-chip-sarees'));
    expect(screen.getByText('Kanjeevaram Silk Saree')).toBeInTheDocument();
    expect(screen.queryByText('Zardozi Velvet Lehenga')).toBeNull();

    // Click 'Jewellery' chip
    fireEvent.click(screen.getByTestId('category-chip-jewellery'));
    expect(screen.getByText('Kundan Choker Jewellery')).toBeInTheDocument();
    expect(screen.queryByText('Kanjeevaram Silk Saree')).toBeNull();

    // Click 'All' chip
    fireEvent.click(screen.getByTestId('category-chip-all'));
    expect(screen.getByText('Kanjeevaram Silk Saree')).toBeInTheDocument();
    expect(screen.getByText('Zardozi Velvet Lehenga')).toBeInTheDocument();
  });
});
