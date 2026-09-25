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
  it('renders boutique collections header and category tabs', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} />
      </CartProvider>
    );

    expect(screen.getByTestId('shop-category-directory')).toBeInTheDocument();
    expect(screen.getByText('Boutique Collections')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-all')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-sarees')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-kurtis')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-lehengas')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-jewelry')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-accessories')).toBeInTheDocument();
  });

  it('filters active category tab on click', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} />
      </CartProvider>
    );

    const lehengasTab = screen.getByTestId('shop-category-lehengas');
    fireEvent.click(lehengasTab);

    expect(lehengasTab).toHaveClass('active');
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

