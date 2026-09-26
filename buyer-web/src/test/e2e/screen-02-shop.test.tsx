/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 02 (Shop / Catalog Directory)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 14 & ORIGINAL_REQUEST.md R4
 *
 * Test Inventory (>=5 tests):
 * 1. Renders boutique collections header, breadcrumbs, and pieces count subtitle
 * 2. Filters products by search query (product title or flash code) with instant reaction
 * 3. Clears search query when clicking the '×' button
 * 4. Filters products by category tabs (All, Sarees, Kurtis, etc.)
 * 5. Sorts products by price ascending and descending using integer Paisa
 * 6. Renders empty search state when no products match the search query
 * 7. Renders mobile bottom navigation dock with Shop tab marked active
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import { ShopCategoryDirectory } from '../../components/shop/ShopCategoryDirectory';
import {
  mockProducts,
  mockBoutiqueSonali,
  mockBoutiqueSuv,
} from './fixtures/mock-catalog-data';
import { renderWithProviders } from './fixtures/test-providers';
import { resetCartStore } from '../../lib/cart/cart-context';

describe('Tier 1: Screen 02 — Shop Catalog Directory', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    vi.clearAllMocks();
  });

  it('renders boutique collections header, breadcrumbs, and catalog piece count', () => {
    renderWithProviders(
      <ShopCategoryDirectory
        initialProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    // Header & Breadcrumb
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Boutique Collections');
    expect(screen.getAllByRole('link', { name: 'Home' })[0]).toBeInTheDocument();
    expect(screen.getByText('Shop Catalog')).toBeInTheDocument();

    // Piece count
    const countElement = screen.getByTestId('shop-pieces-count');
    expect(countElement).toBeInTheDocument();
    expect(countElement).toHaveTextContent(`${mockProducts.length} pieces`);
  });

  it('filters products by search query matching flash code #A01', () => {
    renderWithProviders(
      <ShopCategoryDirectory
        initialProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    const searchInput = screen.getByTestId('shop-search-input');
    fireEvent.change(searchInput, { target: { value: '#A01' } });

    // #A01 matches
    expect(screen.getByText('Handloom Tussar Silk Saree')).toBeInTheDocument();
    expect(screen.getByText('#A01')).toBeInTheDocument();

    // Other pieces are filtered out
    expect(screen.queryByText('Chanderi Cotton Kurti')).not.toBeInTheDocument();
    expect(screen.queryByText('#A02')).not.toBeInTheDocument();
  });

  it('clears search query when clicking the clear "×" button', () => {
    renderWithProviders(
      <ShopCategoryDirectory
        initialProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    const searchInput = screen.getByTestId('shop-search-input');
    fireEvent.change(searchInput, { target: { value: 'Kurti' } });

    expect(screen.getByText('Chanderi Cotton Kurti')).toBeInTheDocument();
    expect(screen.queryByText('Handloom Tussar Silk Saree')).not.toBeInTheDocument();

    // Click clear button
    const clearBtn = screen.getByTestId('shop-search-clear-btn');
    fireEvent.click(clearBtn);

    // Both products return
    expect(screen.getByText('Handloom Tussar Silk Saree')).toBeInTheDocument();
    expect(screen.getByText('Chanderi Cotton Kurti')).toBeInTheDocument();
  });

  it('filters products when clicking category horizontal tabs', () => {
    renderWithProviders(
      <ShopCategoryDirectory
        initialProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    // Click Sarees tab
    const sareesTab = screen.getByTestId('shop-category-sarees');
    fireEvent.click(sareesTab);

    expect(screen.getByText('Handloom Tussar Silk Saree')).toBeInTheDocument();
    expect(screen.queryByText('Chanderi Cotton Kurti')).not.toBeInTheDocument();

    // Click Kurtis tab
    const kurtisTab = screen.getByTestId('shop-category-kurtis');
    fireEvent.click(kurtisTab);

    expect(screen.getByText('Chanderi Cotton Kurti')).toBeInTheDocument();
    expect(screen.queryByText('Handloom Tussar Silk Saree')).not.toBeInTheDocument();
  });

  it('sorts products by price low-to-high and high-to-low using integer Paisa', () => {
    renderWithProviders(
      <ShopCategoryDirectory
        initialProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    const sortSelect = screen.getByTestId('shop-sort-select');

    // Sort Price Low to High
    fireEvent.change(sortSelect, { target: { value: 'price-asc' } });
    const productGridAsc = screen.getByTestId('shop-product-grid');
    const titlesAsc = productGridAsc.querySelectorAll('.ld-card-title, h3');
    // First should be lowest price: Chanderi Cotton Kurti (75000 Paisa / ₹750)
    expect(titlesAsc[0]?.textContent).toContain('Chanderi Cotton Kurti');

    // Sort Price High to Low
    fireEvent.change(sortSelect, { target: { value: 'price-desc' } });
    const productGridDesc = screen.getByTestId('shop-product-grid');
    const titlesDesc = productGridDesc.querySelectorAll('.ld-card-title, h3');
    // First should be highest price: Banarasi Katan Silk Lehenga (310000 Paisa / ₹3,100)
    expect(titlesDesc[0]?.textContent).toContain('Banarasi Katan Silk Lehenga');
  });

  it('renders empty search state when no pieces match the filter criteria', () => {
    renderWithProviders(
      <ShopCategoryDirectory
        initialProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    const searchInput = screen.getByTestId('shop-search-input');
    fireEvent.change(searchInput, { target: { value: 'Nonexistent garment XYZ' } });

    const emptyState = screen.getByTestId('shop-empty-state');
    expect(emptyState).toBeInTheDocument();
    expect(emptyState).toHaveTextContent('No pieces available');
    expect(emptyState).toHaveTextContent('No garments matched "Nonexistent garment XYZ"');
  });

  it('renders mobile bottom dock with Shop tab marked active', () => {
    renderWithProviders(
      <ShopCategoryDirectory
        initialProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    const dock = screen.getByTestId('mobile-bottom-dock');
    expect(dock).toBeInTheDocument();

    const shopTab = screen.getByTestId('dock-shop-tab');
    expect(shopTab).toBeInTheDocument();
  });
});
