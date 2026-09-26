/**
 * LiveDrop Buyer Webfront — Screen 1 HomeStorefront Unit Tests
 *
 * Verifies:
 * 1. Screen 1 Hero section: HERITAGE MEETS NOW badge, Cormorant Garamond title, Explore CTA
 * 2. 5 Circular story reels: Sarees, Lehengas, Jewelry, Men's Couture, Accessories
 * 3. 3-State Live Commerce Section:
 *    - State 1: LIVE NOW when active drop is streaming
 *    - State 2: UP NEXT with Notify Me when no drop is live
 * 4. Verified Ateliers directory
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { HomeStorefront } from '../components/HomeStorefront';
import { CartProvider } from '../lib/cart/cart-context';
import { ProfileProvider } from '../lib/profile/profile-context';
import { PublicDropCatalog, PublicSellerStorefront } from '../types/domain';

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
  }),
}));

const mockBoutique: PublicSellerStorefront = {
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

function renderWithProviders(ui: React.ReactElement) {
  return render(
    <CartProvider>
      <ProfileProvider>{ui}</ProfileProvider>
    </CartProvider>
  );
}

describe('HomeStorefront Component Tests', () => {
  it('renders compact hero section with clean headline and CTA', () => {
    renderWithProviders(<HomeStorefront storefronts={[mockBoutique]} />);

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(/No Live Drop Right Now/i);
    expect(screen.getByTestId('explore-live-shows-btn')).toBeInTheDocument();
  });

  it('renders the compact category chips rail', () => {
    renderWithProviders(<HomeStorefront storefronts={[mockBoutique]} />);

    expect(screen.getByTestId('category-chips-rail')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-all')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-sarees')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-kurtis')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-lehengas')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-jewelry')).toBeInTheDocument();
  });

  it('STATE 1: renders LIVE NOW broadcast hero when an active drop is streaming', () => {
    renderWithProviders(
      <HomeStorefront activeDrops={[mockLiveDrop]} storefronts={[mockBoutique]} />
    );

    expect(screen.getByTestId('live-drop-hero')).toBeInTheDocument();
    expect(screen.getAllByText('Bridal Lehengas with Anaya').length).toBeGreaterThan(0);
    expect(screen.getAllByText(/LIVE/i).length).toBeGreaterThan(0);
    expect(screen.getByTestId('shop-live-hero-btn')).toBeInTheDocument();
  });

  it('STATE 2: renders calm no-live state when no drop is streaming', () => {
    renderWithProviders(<HomeStorefront activeDrops={[]} storefronts={[mockBoutique]} />);

    expect(screen.getByText('No Live Drop Right Now')).toBeInTheDocument();
    expect(screen.getByText(/Explore the latest pieces from independent boutiques/i)).toBeInTheDocument();
    expect(screen.getByTestId('explore-live-shows-btn')).toBeInTheDocument();
  });

  it('renders verified boutiques rail with boutique card and WhatsApp link', () => {
    renderWithProviders(<HomeStorefront storefronts={[mockBoutique]} />);

    expect(screen.getByText('Live Boutiques')).toBeInTheDocument();
    expect(screen.getByTestId('boutique-card-suvs-atelier')).toBeInTheDocument();
    expect(screen.getByTestId('visit-boutique-suvs-atelier')).toBeInTheDocument();
    expect(screen.getByTestId('whatsapp-store-suvs-atelier')).toBeInTheDocument();
    expect(screen.queryByTestId('boutique-live-badge-suvs-atelier')).toBeNull();
  });

  it('renders LIVE badge on boutique card only when boutique has an active drop', () => {
    renderWithProviders(
      <HomeStorefront activeDrops={[mockLiveDrop]} storefronts={[mockBoutique]} />
    );

    expect(screen.getByTestId('boutique-live-badge-suvs-atelier')).toBeInTheDocument();
  });
});

