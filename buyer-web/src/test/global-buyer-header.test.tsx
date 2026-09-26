import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { GlobalBuyerHeader } from '../components/navigation/GlobalBuyerHeader';
import { BuyerShell } from '../components/layout/BuyerShell';
import { CartProvider } from '../lib/cart/cart-context';

describe('GlobalBuyerHeader Component Tests', () => {
  it('renders storefront variant by default with brand and search', () => {
    const handleSearchChange = vi.fn();
    render(
      <CartProvider>
        <GlobalBuyerHeader
          variant="storefront"
          searchQuery=""
          onSearchChange={handleSearchChange}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('global-buyer-header')).toBeInTheDocument();
    expect(screen.getByTestId('platform-search-input')).toBeInTheDocument();
    expect(screen.getByTestId('luxury-bag-btn')).toBeInTheDocument();
  });

  it('renders boutique variant with store badge and share action', () => {
    const handleShare = vi.fn();
    render(
      <CartProvider>
        <GlobalBuyerHeader
          variant="boutique"
          storeName="Sabyasachi Heritage"
          onShare={handleShare}
          isCopied={false}
          hasLiveDrop={true}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('global-buyer-header')).toBeInTheDocument();
    expect(screen.getByTestId('storefront-name-badge')).toHaveTextContent('Sabyasachi Heritage');

    const shareBtn = screen.getByTestId('copy-storefront-link-btn');
    expect(shareBtn).toBeInTheDocument();
    fireEvent.click(shareBtn);
    expect(handleShare).toHaveBeenCalledTimes(1);

    expect(screen.getByTestId('storefront-cart-btn')).toBeInTheDocument();
  });

  it('renders minimal variant with back navigation link and title', () => {
    render(
      <CartProvider>
        <GlobalBuyerHeader
          variant="minimal"
          backHref="/"
          backLabel="Return Home"
          backTestId="test-back-btn"
          title="Checkout Review"
          rightAction={<span data-testid="test-right-action">Step 1</span>}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('global-buyer-header')).toBeInTheDocument();
    expect(screen.getByTestId('test-back-btn')).toBeInTheDocument();
    expect(screen.getByText('Checkout Review')).toBeInTheDocument();
    expect(screen.getByTestId('test-right-action')).toBeInTheDocument();
  });

  it('does not register scroll listeners on window (guaranteed flicker immunity)', () => {
    const addEventListenerSpy = vi.spyOn(window, 'addEventListener');

    render(
      <CartProvider>
        <GlobalBuyerHeader variant="storefront" />
      </CartProvider>
    );

    const scrollListeners = addEventListenerSpy.mock.calls.filter(
      ([event]) => event === 'scroll'
    );
    expect(scrollListeners.length).toBe(0);

    addEventListenerSpy.mockRestore();
  });
});

describe('BuyerShell Unified Layout Component', () => {
  it('renders header, content container, and bottom dock by default', () => {
    render(
      <CartProvider>
        <BuyerShell
          headerProps={{ variant: 'storefront' }}
        >
          <div data-testid="main-test-content">Buyer Page Body</div>
        </BuyerShell>
      </CartProvider>
    );

    expect(screen.getByTestId('global-buyer-header')).toBeInTheDocument();
    expect(screen.getByTestId('main-test-content')).toBeInTheDocument();
    expect(screen.getByTestId('mobile-bottom-dock')).toBeInTheDocument();
  });

  it('allows hiding dock or header via props when in modal or fullscreen flow', () => {
    render(
      <CartProvider>
        <BuyerShell showHeader={false} showBottomDock={false}>
          <div data-testid="modal-content">Fullscreen Body</div>
        </BuyerShell>
      </CartProvider>
    );

    expect(screen.queryByTestId('global-buyer-header')).not.toBeInTheDocument();
    expect(screen.queryByTestId('mobile-bottom-dock')).not.toBeInTheDocument();
    expect(screen.getByTestId('modal-content')).toBeInTheDocument();
  });
});
