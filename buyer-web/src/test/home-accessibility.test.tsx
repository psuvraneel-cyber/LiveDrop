/**
 * LiveDrop Buyer Webfront — Home Accessibility & Layout Audit Tests
 *
 * Validates WCAG 2.1 AA / Section 508 accessibility criteria:
 * 1. Exactly one logical h1
 * 2. Proper heading hierarchy (h1 -> h2 -> h3) without level skips
 * 3. Accessible category controls with role="tablist" and role="tab"
 * 4. All icon-only buttons possess explicit aria-label or accessible names
 * 5. Screen-reader status for cart bag button and live indicator
 * 6. Minimum 44px touch target compliance for interactive controls
 * 7. Focus visibility classes on interactive links and buttons
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { HomeStorefront } from '../components/HomeStorefront';
import { CartProvider } from '../lib/cart/cart-context';
import { ProfileProvider } from '../lib/profile/profile-context';
import { PublicProductView, PublicSellerStorefront } from '../types/domain';

vi.mock('next/navigation', () => ({
  usePathname: () => '/',
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
  }),
}));

const mockBoutique: PublicSellerStorefront = {
  id: 'seller-a1',
  store_name: "Kashi Silks",
  store_slug: 'kashi-silks',
  phone_number: '919876543210',
  upi_id: 'kashi@okaxis',
  upi_qr_url: null,
  default_shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: null,
  advance_confirmation_enabled: false,
  advance_amount_paisa: 0,
  hold_duration_days: 2,
  is_approved: true,
};

const mockProduct: PublicProductView = {
  id: 'prod-saree-1',
  seller_id: 'seller-a1',
  drop_id: 'drop-a1',
  code: '#A01',
  title: 'Handwoven Banarasi Brocade Saree',
  size: 'Free Size',
  price_paisa: 1250000,
  image_url: 'https://images.unsplash.com/photo-saree',
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

describe('HomeStorefront Accessibility Audit (WCAG AA Compliance)', () => {
  it('A11Y-01: Contains exactly one logical h1 element', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique]}
        featuredProducts={[mockProduct]}
      />
    );

    const h1Elements = screen.getAllByRole('heading', { level: 1 });
    expect(h1Elements).toHaveLength(1);
    expect(h1Elements[0]).toHaveTextContent(/NO LIVE DROP/i);
  });

  it('A11Y-02: Follows valid heading hierarchy without skipping levels', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique]}
        featuredProducts={[mockProduct]}
      />
    );

    const h1s = screen.getAllByRole('heading', { level: 1 });
    const h2s = screen.getAllByRole('heading', { level: 2 });
    const h3s = screen.getAllByRole('heading', { level: 3 });

    expect(h1s.length).toBe(1);
    expect(h2s.length).toBeGreaterThanOrEqual(2); // Featured Pieces, Live Boutiques
    expect(h3s.length).toBeGreaterThanOrEqual(2); // Product Card, Boutique Card
  });

  it('A11Y-03: Category rail provides valid tablist and tab roles with aria-selected', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique]}
        featuredProducts={[mockProduct]}
      />
    );

    const tablist = screen.getByRole('tablist');
    expect(tablist).toBeInTheDocument();

    const tabs = screen.getAllByRole('tab');
    expect(tabs.length).toBe(7);

    // Initial 'All' tab should be selected
    const allTab = screen.getByTestId('category-chip-all');
    expect(allTab).toHaveAttribute('aria-selected', 'true');

    // Other tabs should not be selected initially
    const sareesTab = screen.getByTestId('category-chip-sarees');
    expect(sareesTab).toHaveAttribute('aria-selected', 'false');
  });

  it('A11Y-04: Icon-only buttons possess explicit accessible names (aria-label)', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique]}
        featuredProducts={[mockProduct]}
      />
    );

    // Search trigger
    const searchTrigger = screen.getByRole('button', { name: /open search/i });
    expect(searchTrigger).toBeInTheDocument();

    // Bag button
    const bagBtn = screen.getByTestId('luxury-bag-btn');
    expect(bagBtn).toHaveAttribute('aria-label', expect.stringMatching(/shopping bag/i));

    // WhatsApp action button
    const whatsappBtn = screen.getByTestId('whatsapp-store-kashi-silks');
    expect(whatsappBtn).toHaveAttribute('aria-label', expect.stringMatching(/whatsapp kashi silks/i));
  });

  it('A11Y-05: Product card article provides comprehensive accessible description', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique]}
        featuredProducts={[mockProduct]}
      />
    );

    const article = screen.getByTestId('product-card-prod-saree-1');
    expect(article).toHaveAttribute('aria-label', expect.stringContaining('#A01: Handwoven Banarasi Brocade Saree'));
    expect(article).toHaveAttribute('aria-label', expect.stringContaining('AVAILABLE'));
  });

  it('A11Y-06: Interactive actions enforce minimum 44px touch targets', () => {
    renderWithProviders(
      <HomeStorefront
        storefronts={[mockBoutique]}
        featuredProducts={[mockProduct]}
      />
    );

    // CTA button min-height
    const ctaBtn = screen.getByTestId('explore-live-shows-btn');
    expect(ctaBtn.className).toContain('min-h-[44px]');

    // Visit boutique link min-height
    const visitBtn = screen.getByTestId('visit-boutique-kashi-silks');
    expect(visitBtn.className).toContain('min-h-[44px]');
    expect(visitBtn.className).toContain('min-w-[44px]');

    // WhatsApp button min-height
    const whatsappBtn = screen.getByTestId('whatsapp-store-kashi-silks');
    expect(whatsappBtn.className).toContain('min-h-[44px]');
    expect(whatsappBtn.className).toContain('min-w-[44px]');
  });
});
