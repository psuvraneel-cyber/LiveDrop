/**
 * LiveDrop Buyer Webfront — MobileBottomDock Unit Tests
 *
 * Verifies:
 * 1. Safe rendering across mock and browser environments
 * 2. Exactly 4 tabs: Home, Live, Shop, Orders (with Bag cleanly in header)
 * 3. Active tab resolution based on route and hash anchors
 * 4. Hiding on fullscreen live rooms (/drop/*)
 */

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MobileBottomDock } from '../components/navigation/MobileBottomDock';
import { CartProvider } from '../lib/cart/cart-context';

let mockPathname = '/';

vi.mock('next/navigation', () => ({
  usePathname: () => mockPathname,
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
  }),
}));

describe('MobileBottomDock Component Tests', () => {
  beforeEach(() => {
    mockPathname = '/';
    window.location.hash = '';
  });

  it('renders exactly 4 buyer navigation tabs (Home, Live, Shop, Orders)', () => {
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    expect(screen.getByTestId('mobile-bottom-dock')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Home/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Live Drops/i })).toBeInTheDocument();
    expect(screen.getByTestId('dock-shop-tab')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Orders/i })).toBeInTheDocument();
    // Bag is strictly in the header, not duplicate 5th tab in bottom dock
    expect(screen.queryByTestId('dock-bag-tab')).not.toBeInTheDocument();
  });

  it('highlights Home tab as active on root path (/)', () => {
    mockPathname = '/';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const homeTab = screen.getByRole('link', { name: /^Home/i });
    expect(homeTab).toHaveClass('active');
    expect(homeTab).toHaveAttribute('aria-current', 'page');
  });

  it('highlights Live tab when hash is #live-drops on homepage', () => {
    mockPathname = '/';
    window.location.hash = '#live-drops';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const liveTab = screen.getByRole('link', { name: /^Live Drops/i });
    expect(liveTab).toHaveClass('active');

    const homeTab = screen.getByRole('link', { name: /^Home/i });
    expect(homeTab).not.toHaveClass('active');
  });

  it('highlights Shop tab on /shop route', () => {
    mockPathname = '/shop';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const shopTab = screen.getByTestId('dock-shop-tab');
    expect(shopTab).toHaveClass('active');
    expect(shopTab).toHaveAttribute('aria-current', 'page');
  });

  it('highlights Shop tab on boutique storefront route (/[storeSlug])', () => {
    mockPathname = '/suv-s';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const shopTab = screen.getByTestId('dock-shop-tab');
    expect(shopTab).toHaveClass('active');
  });

  it('highlights Orders tab on /order route', () => {
    mockPathname = '/order';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const ordersTab = screen.getByRole('link', { name: /^Orders/i });
    expect(ordersTab).toHaveClass('active');
    expect(ordersTab).toHaveAttribute('aria-current', 'page');
  });

  it('strictly hides the dock on fullscreen live drop rooms (/drop/[slug])', () => {
    mockPathname = '/drop/midnight-silks';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    expect(screen.queryByTestId('mobile-bottom-dock')).not.toBeInTheDocument();
  });

  it('updates window hash when clicking hash-anchored tabs', () => {
    mockPathname = '/';
    window.location.hash = '';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const liveTab = screen.getByRole('link', { name: /^Live Drops/i });
    fireEvent.click(liveTab);
    expect(window.location.hash).toBe('#live-drops');

    const homeTab = screen.getByRole('link', { name: /^Home/i });
    fireEvent.click(homeTab);
    expect(window.location.hash).toBe('');
  });
});
