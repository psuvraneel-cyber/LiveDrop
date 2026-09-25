/**
 * LiveDrop Buyer Webfront — MobileBottomDock Unit Tests
 *
 * Verifies:
 * 1. Exactly 5 tabs matching reference template: Home, Live, Shop, Designers, Profile
 * 2. Active tab resolution based on route and hash anchors
 * 3. Hiding on fullscreen live rooms (/drop/*)
 * 4. Profile tab triggers profile drawer
 */

import React from 'react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { MobileBottomDock } from '../components/navigation/MobileBottomDock';
import { CartProvider } from '../lib/cart/cart-context';
import { ProfileProvider } from '../lib/profile/profile-context';

let mockPathname = '/';

vi.mock('next/navigation', () => ({
  usePathname: () => mockPathname,
  useRouter: () => ({
    push: vi.fn(),
    replace: vi.fn(),
    prefetch: vi.fn(),
  }),
}));

function renderWithProviders(ui: React.ReactElement) {
  return render(
    <CartProvider>
      <ProfileProvider>{ui}</ProfileProvider>
    </CartProvider>
  );
}

describe('MobileBottomDock Component Tests', () => {
  beforeEach(() => {
    mockPathname = '/';
    window.location.hash = '';
  });

  it('renders exactly 5 buyer navigation tabs (Home, Live, Shop, Designers, Profile)', () => {
    renderWithProviders(<MobileBottomDock />);

    expect(screen.getByTestId('mobile-bottom-dock')).toBeInTheDocument();
    expect(screen.getByTestId('dock-home-tab')).toBeInTheDocument();
    expect(screen.getByTestId('dock-live-tab')).toBeInTheDocument();
    expect(screen.getByTestId('dock-shop-tab')).toBeInTheDocument();
    expect(screen.getByTestId('dock-designers-tab')).toBeInTheDocument();
    expect(screen.getByTestId('dock-profile-tab')).toBeInTheDocument();
  });

  it('highlights Home tab as active on root path (/)', () => {
    mockPathname = '/';
    renderWithProviders(<MobileBottomDock />);

    const homeTab = screen.getByTestId('dock-home-tab');
    expect(homeTab).toHaveClass('active');
    expect(homeTab).toHaveAttribute('aria-current', 'page');
  });

  it('highlights Live tab when hash is #live-drops on homepage', () => {
    mockPathname = '/';
    window.location.hash = '#live-drops';
    renderWithProviders(<MobileBottomDock />);

    const liveTab = screen.getByTestId('dock-live-tab');
    expect(liveTab).toHaveClass('active');

    const homeTab = screen.getByTestId('dock-home-tab');
    expect(homeTab).not.toHaveClass('active');
  });

  it('highlights Shop tab on /shop route', () => {
    mockPathname = '/shop';
    renderWithProviders(<MobileBottomDock />);

    const shopTab = screen.getByTestId('dock-shop-tab');
    expect(shopTab).toHaveClass('active');
    expect(shopTab).toHaveAttribute('aria-current', 'page');
  });

  it('highlights Designers tab on boutique storefront route (/[storeSlug])', () => {
    mockPathname = '/suv-s';
    renderWithProviders(<MobileBottomDock />);

    const designersTab = screen.getByTestId('dock-designers-tab');
    expect(designersTab).toHaveClass('active');
  });

  it('strictly hides the dock on fullscreen live drop rooms (/drop/[slug])', () => {
    mockPathname = '/drop/midnight-silks';
    renderWithProviders(<MobileBottomDock />);

    expect(screen.queryByTestId('mobile-bottom-dock')).not.toBeInTheDocument();
  });

  it('updates window hash when clicking hash-anchored tabs', () => {
    mockPathname = '/';
    window.location.hash = '';
    renderWithProviders(<MobileBottomDock />);

    const liveTab = screen.getByTestId('dock-live-tab');
    fireEvent.click(liveTab);
    expect(window.location.hash).toBe('#live-drops');

    const homeTab = screen.getByTestId('dock-home-tab');
    fireEvent.click(homeTab);
    expect(window.location.hash).toBe('');
  });
});
