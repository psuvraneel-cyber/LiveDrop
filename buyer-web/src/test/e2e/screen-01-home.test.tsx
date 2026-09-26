/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 01 (Home Storefront)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 13 & ORIGINAL_REQUEST.md R3
 *
 * Test Inventory (>=5 tests):
 * 1. Renders cinematic live hero with LIVE NOW badge, title, boutique name, and CTA
 * 2. Renders category discovery rail with square "All" card and category chips
 * 3. Renders 2-column featured product grid with 3:4 portrait cards and flash codes
 * 4. Interacts with compact 36x36px gold bag button to add garment to cart
 * 5. Handles NO LIVE DROP state when no broadcast is currently active
 * 6. Renders mobile bottom navigation dock with Home tab marked active
 */

import React from 'react';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { screen, fireEvent } from '@testing-library/react';
import { HomeStorefront } from '../../components/HomeStorefront';
import {
  mockLiveDrop,
  mockProducts,
  mockBoutiqueSonali,
  mockBoutiqueSuv,
} from './fixtures/mock-catalog-data';
import { renderWithProviders } from './fixtures/test-providers';
import { resetCartStore } from '../../lib/cart/cart-context';

describe('Tier 1: Screen 01 — Home Storefront', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
    vi.clearAllMocks();
  });

  it('renders cinematic live hero with LIVE NOW badge, collection title, and boutique name', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockLiveDrop]}
        featuredProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    // Hero live container
    const hero = screen.getByTestId('live-drop-hero');
    expect(hero).toBeInTheDocument();
    expect(hero).toHaveTextContent(/LIVE NOW/i);

    // Collection title & boutique name
    expect(hero).toHaveTextContent('Festive Silk & Handloom Collection');
    expect(hero).toHaveTextContent("Sonali's Boutique");

    // Primary gold CTA
    const shopCta = screen.getByTestId('shop-live-hero-btn');
    expect(shopCta).toBeInTheDocument();
    expect(shopCta).toHaveTextContent(/Shop Live Drop/i);
    expect(shopCta).toHaveAttribute('href', '/drop/festive-silk-handloom');
  });

  it('renders category discovery rail with "All" card and category chips', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockLiveDrop]}
        featuredProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    // Category rail container
    const categoryRail = screen.getByTestId('category-chips-rail');
    expect(categoryRail).toBeInTheDocument();

    // "All" card
    const allChip = screen.getByTestId('category-chip-all');
    expect(allChip).toBeInTheDocument();
    expect(allChip).toHaveTextContent(/All/i);

    // Specific category chips
    expect(screen.getByTestId('category-chip-sarees')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-kurtis')).toBeInTheDocument();
    expect(screen.getByTestId('category-chip-lehengas')).toBeInTheDocument();
  });

  it('renders 2-column featured product grid with 3:4 portrait cards and flash codes', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockLiveDrop]}
        featuredProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    // Featured section header
    expect(screen.getByText(/Featured Pieces/i)).toBeInTheDocument();

    // Flash codes for available products
    expect(screen.getByText('#A01')).toBeInTheDocument();
    expect(screen.getByText('Handloom Tussar Silk Saree')).toBeInTheDocument();
    expect(screen.getByText('₹1,850')).toBeInTheDocument();

    expect(screen.getByText('#A02')).toBeInTheDocument();
    expect(screen.getByText('Chanderi Cotton Kurti')).toBeInTheDocument();
    expect(screen.getByText('₹750')).toBeInTheDocument();
  });

  it('adds item to bag when clicking compact gold bag button on product card', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockLiveDrop]}
        featuredProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    // Find bag button for product #A01
    const bagBtn = screen.getByTestId('cart-btn-prod-saree-a01');
    expect(bagBtn).toBeInTheDocument();
    expect(bagBtn).toHaveAttribute('aria-label', expect.stringContaining('#A01'));

    // Click to add to bag
    fireEvent.click(bagBtn);

    // Verify button transitions to In Bag / In Cart state
    expect(screen.getByTestId('cart-btn-prod-saree-a01')).toHaveAttribute(
      'aria-label',
      expect.stringMatching(/in your cart|in bag/i)
    );
  });

  it('renders NO LIVE DROP fallback state with boutique discovery when drop is inactive', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[]}
        featuredProducts={[]}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    // Hero shows no live drop state
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('NO LIVE DROP');
    expect(
      screen.getByText('Explore pieces from independent boutiques.')
    ).toBeInTheDocument();

    // Secondary boutique directory exists
    expect(screen.getByTestId('boutiques-directory-section')).toBeInTheDocument();
    expect(screen.getByText("Sonali's Boutique")).toBeInTheDocument();
    expect(screen.getByText("Suv's Atelier")).toBeInTheDocument();
  });

  it('renders mobile bottom dock with Home tab marked active', () => {
    renderWithProviders(
      <HomeStorefront
        activeDrops={[mockLiveDrop]}
        featuredProducts={mockProducts}
        storefronts={[mockBoutiqueSonali, mockBoutiqueSuv]}
      />
    );

    const dock = screen.getByTestId('mobile-bottom-dock');
    expect(dock).toBeInTheDocument();

    const homeTab = screen.getByTestId('dock-home-tab');
    expect(homeTab).toBeInTheDocument();
    expect(homeTab).toHaveAttribute('aria-current', 'page');
  });
});
