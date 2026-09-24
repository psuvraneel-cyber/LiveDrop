/**
 * LiveDrop Buyer Webfront — ShopCategoryDirectory Unit Tests
 *
 * Verifies:
 * 1. Category tabs and editorial cards presentation
 * 2. Tab switching logic
 * 3. Verified boutique directory rendering
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { ShopCategoryDirectory } from '../components/shop/ShopCategoryDirectory';
import { CartProvider } from '../lib/cart/cart-context';
import { PublicSellerStorefront } from '../types/domain';

vi.mock('next/navigation', () => ({
  usePathname: () => '/shop',
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
  }),
}));

const mockStorefronts: PublicSellerStorefront[] = [
  {
    id: 'sf-1',
    store_name: 'Suv Studio',
    store_slug: 'suv-s',
    default_shipping_fee_paisa: 0,
    free_shipping_threshold_paisa: null,
    advance_confirmation_enabled: false,
    advance_amount_paisa: 0,
    hold_duration_days: 2,
    upi_qr_url: null,
  },
];

describe('ShopCategoryDirectory Component Tests', () => {
  it('renders all luxury category cards by default', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} />
      </CartProvider>
    );

    expect(screen.getByTestId('shop-category-directory')).toBeInTheDocument();
    expect(screen.getByText('Couture by Category')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Sarees', level: 3 })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Lehengas', level: 3 })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Jewelry', level: 3 })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: "Men's Couture", level: 3 })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Accessories', level: 3 })).toBeInTheDocument();
  });

  it('filters categories when tab is selected', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} />
      </CartProvider>
    );

    const lehengasTab = screen.getByRole('tab', { name: /^Lehengas/i });
    fireEvent.click(lehengasTab);

    expect(screen.getByText('For every grand celebration')).toBeInTheDocument();
    // Non-lehenga taglines should be hidden
    expect(screen.queryByText('Timeless drapes for every era')).not.toBeInTheDocument();
  });

  it('renders verified boutiques list', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} />
      </CartProvider>
    );

    expect(screen.getByText('Suv Studio')).toBeInTheDocument();
    expect(screen.getByText('/suv-s')).toBeInTheDocument();
  });
});
