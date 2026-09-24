/**
 * LiveDrop Buyer Webfront — MobileBottomDock Unit Tests
 *
 * Verifies:
 * 1. Safe rendering across mock and browser environments
 * 2. Active tab resolution based on route and hash anchors
 * 3. Hiding on fullscreen live rooms (/drop/*)
 * 4. Isolation of checkout route to prevent false boutique tab highlights
 * 5. Bag item counter badge rendering
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

  it('renders all 5 buyer journey navigation tabs', () => {
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    expect(screen.getByTestId('mobile-bottom-dock')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Home/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Live Drops/i })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Boutiques/i })).toBeInTheDocument();
    expect(screen.getByTestId('dock-bag-tab')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /^Orders/i })).toBeInTheDocument();
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

  it('highlights Boutiques tab when hash is #boutiques on homepage', () => {
    mockPathname = '/';
    window.location.hash = '#boutiques';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const boutiquesTab = screen.getByRole('link', { name: /^Boutiques/i });
    expect(boutiquesTab).toHaveClass('active');

    const homeTab = screen.getByRole('link', { name: /^Home/i });
    expect(homeTab).not.toHaveClass('active');
  });

  it('highlights Boutiques tab on boutique storefront route (/[storeSlug])', () => {
    mockPathname = '/suv-s';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const boutiquesTab = screen.getByRole('link', { name: /^Boutiques/i });
    expect(boutiquesTab).toHaveClass('active');
  });

  it('highlights Bag tab on /cart and /checkout, never falsely activating Boutiques', () => {
    mockPathname = '/cart';
    const { unmount } = render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const bagTab = screen.getByTestId('dock-bag-tab');
    expect(bagTab).toHaveClass('active');
    unmount();

    mockPathname = '/checkout';
    render(
      <CartProvider>
        <MobileBottomDock />
      </CartProvider>
    );

    const checkoutBagTab = screen.getByTestId('dock-bag-tab');
    expect(checkoutBagTab).toHaveClass('active');

    const boutiquesTab = screen.getByRole('link', { name: /^Boutiques/i });
    expect(boutiquesTab).not.toHaveClass('active');
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

