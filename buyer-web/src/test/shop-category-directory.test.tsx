/**
 * LiveDrop Buyer Webfront — ShopCategoryDirectory Phase 4 Acceptance Tests
 *
 * Verifies:
 * 1. Category tabs & breadcrumb presentation
 * 2. Dedicated Control Bar (pieces count, search input, sort dropdown)
 * 3. Sorting (Price: Low to High, Price: High to Low)
 * 4. Singular/plural apparel category filtering
 * 5. Section 31 empty state & explore live drops CTA
 * 6. Secondary verified boutique directory
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, within } from '@testing-library/react';
import { ShopCategoryDirectory } from '../components/shop/ShopCategoryDirectory';
import { CartProvider } from '../lib/cart/cart-context';
import { PublicProductView, PublicSellerStorefront } from '../types/domain';

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
    is_approved: true,
  },
];

const mockProducts: PublicProductView[] = [
  {
    id: 'prod-saree',
    code: '#S01',
    title: 'Banarasi Katan Silk Saree',
    price_paisa: 350000,
    size: 'Free Size',
    image_url: 'https://images.unsplash.com/photo-saree',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-kurti',
    code: '#K01',
    title: 'Chanderi Embroidered Kurti',
    price_paisa: 120000,
    size: 'M',
    image_url: 'https://images.unsplash.com/photo-kurti',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-lehenga',
    code: '#L01',
    title: 'Zardozi Bridal Lehenga',
    price_paisa: 850000,
    size: 'Free Size',
    image_url: 'https://images.unsplash.com/photo-lehenga',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
];

describe('ShopCategoryDirectory Phase 4 Tests', () => {
  it('renders boutique collections header, breadcrumb, and category tabs', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} initialProducts={mockProducts} />
      </CartProvider>
    );

    expect(screen.getByTestId('shop-category-directory')).toBeInTheDocument();
    expect(screen.getByText('Boutique Collections')).toBeInTheDocument();
    expect(within(screen.getByRole('main')).getByText('Home')).toBeInTheDocument();
    expect(screen.getByText('Shop Catalog')).toBeInTheDocument();

    expect(screen.getByTestId('shop-category-all')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-sarees')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-kurtis')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-lehengas')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-jewelry')).toBeInTheDocument();
    expect(screen.getByTestId('shop-category-accessories')).toBeInTheDocument();
  });

  it('renders dedicated control bar with search input, count, and sort dropdown', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} initialProducts={mockProducts} />
      </CartProvider>
    );

    expect(screen.getByTestId('shop-search-input')).toBeInTheDocument();
    expect(screen.getByTestId('shop-pieces-count')).toHaveTextContent('3 pieces');
    expect(screen.getByTestId('shop-sort-select')).toBeInTheDocument();
  });

  it('filters active category tab on click and updates displayed products', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} initialProducts={mockProducts} />
      </CartProvider>
    );

    const lehengasTab = screen.getByTestId('shop-category-lehengas');
    fireEvent.click(lehengasTab);

    expect(lehengasTab).toHaveClass('active');
    expect(screen.getByText('Zardozi Bridal Lehenga')).toBeInTheDocument();
    expect(screen.queryByText('Chanderi Embroidered Kurti')).toBeNull();
  });

  it('sorts products by price low-to-high and high-to-low', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} initialProducts={mockProducts} />
      </CartProvider>
    );

    const sortSelect = screen.getByTestId('shop-sort-select');

    // Sort Low to High
    fireEvent.change(sortSelect, { target: { value: 'price-asc' } });
    const productCards = screen.getAllByTestId(/^product-card-/);
    expect(productCards[0]).toHaveAttribute('data-testid', 'product-card-prod-kurti'); // ₹1,200

    // Sort High to Low
    fireEvent.change(sortSelect, { target: { value: 'price-desc' } });
    const productCardsDesc = screen.getAllByTestId(/^product-card-/);
    expect(productCardsDesc[0]).toHaveAttribute('data-testid', 'product-card-prod-lehenga'); // ₹8,500
  });

  it('filters products by search input in dedicated control bar', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} initialProducts={mockProducts} />
      </CartProvider>
    );

    const searchInput = screen.getByTestId('shop-search-input');
    fireEvent.change(searchInput, { target: { value: '#S01' } });

    expect(screen.getByText('Banarasi Katan Silk Saree')).toBeInTheDocument();
    expect(screen.queryByText('Zardozi Bridal Lehenga')).toBeNull();

    // Clear search
    const clearBtn = screen.getByTestId('shop-search-clear-btn');
    fireEvent.click(clearBtn);
    expect(screen.getByText('Zardozi Bridal Lehenga')).toBeInTheDocument();
  });

  it('renders Section 31 empty state when no products match', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} initialProducts={[]} />
      </CartProvider>
    );

    expect(screen.getByTestId('shop-empty-state')).toBeInTheDocument();
    expect(screen.getByText('No pieces available')).toBeInTheDocument();
    expect(screen.getByText('Explore another category or check back during live drops.')).toBeInTheDocument();
    expect(screen.getByTestId('shop-explore-live-drops-btn')).toHaveAttribute('href', '/#live-drops');
  });

  it('renders verified boutiques list and preserve backward-compatible test contract', () => {
    render(
      <CartProvider>
        <ShopCategoryDirectory storefronts={mockStorefronts} initialProducts={mockProducts} />
      </CartProvider>
    );

    expect(screen.getByText('Suv Studio')).toBeInTheDocument();
    expect(screen.getByText('/suv-s')).toBeInTheDocument();
    expect(screen.getByTestId('shop-boutique-card-suv-s')).toBeInTheDocument();
  });
});
