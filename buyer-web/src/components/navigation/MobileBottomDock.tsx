'use client';

import React, { useSyncExternalStore } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useOptionalCart } from '../../lib/cart/cart-context';

function useSafePathname(): string {
  try {
    return usePathname() || '';
  } catch {
    if (typeof window !== 'undefined') {
      return window.location.pathname || '';
    }
    return '';
  }
}

function subscribeHash(callback: () => void): () => void {
  if (typeof window === 'undefined') return () => {};
  window.addEventListener('hashchange', callback);
  window.addEventListener('popstate', callback);
  return () => {
    window.removeEventListener('hashchange', callback);
    window.removeEventListener('popstate', callback);
  };
}

function getHashSnapshot(): string {
  return typeof window !== 'undefined' ? window.location.hash : '';
}

function getHashServerSnapshot(): string {
  return '';
}

function setHashLocation(hash: string) {
  if (typeof window === 'undefined') return;
  if (!hash) {
    if (window.location.hash) {
      window.history.replaceState(null, '', window.location.pathname + window.location.search);
      window.dispatchEvent(new Event('hashchange'));
    }
  } else {
    if (window.location.hash !== hash) {
      window.location.hash = hash;
    }
  }
}

export function MobileBottomDock() {
  const pathname = useSafePathname();
  const cart = useOptionalCart();
  const itemCount = cart?.itemCount ?? 0;
  const isHydrated = cart?.isHydrated ?? false;
  const openDrawer = cart?.openDrawer;
  const isDrawerOpen = cart?.isDrawerOpen ?? false;

  const currentHash = useSyncExternalStore(
    subscribeHash,
    getHashSnapshot,
    getHashServerSnapshot
  );

  // Don't render on live drop fullscreen room if it conflicts with real-time controls
  if (pathname?.startsWith('/drop/')) {
    return null;
  }

  // Determine active tab based on route and hash
  const isHomeBase = pathname === '/' || pathname === '';
  const isLiveActive = isHomeBase && (currentHash === '#live-drops' || currentHash === '#live-now');
  const isShopActive = pathname === '/shop';
  const isOrdersActive = pathname?.startsWith('/order');
  const isBagActive = pathname === '/cart' || pathname === '/checkout' || isDrawerOpen;
  const isHomeActive = isHomeBase && !isLiveActive && !isShopActive && !isOrdersActive && !isBagActive;

  return (
    <nav
      className="ld-bottom-dock"
      aria-label="Buyer Navigation Dock"
      data-testid="mobile-bottom-dock"
    >
      <div className="ld-bottom-dock-inner">
        {/* 1. Home */}
        <Link
          href="/"
          className={`ld-dock-tab ${isHomeActive ? 'active' : ''}`}
          aria-label="Home"
          aria-current={isHomeActive ? 'page' : undefined}
          data-testid="dock-home-tab"
          onClick={() => setHashLocation('')}
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="m3 9 9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" />
              <polyline points="9 22 9 12 15 12 15 22" />
            </svg>
          </div>
          <span className="ld-dock-label">Home</span>
          {isHomeActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 2. Live */}
        <Link
          href="/#live-drops"
          className={`ld-dock-tab ${isLiveActive ? 'active' : ''}`}
          aria-label="Live Drops"
          data-testid="dock-live-tab"
          onClick={() => setHashLocation('#live-drops')}
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="2" />
              <path d="M16.24 7.76a6 6 0 0 1 0 8.49m-8.48-.01a6 6 0 0 1 0-8.49m11.31-2.82a10 10 0 0 1 0 14.14m-14.14 0a10 10 0 0 1 0-14.14" />
            </svg>
            <span className="ld-dock-live-dot" aria-hidden="true" />
          </div>
          <span className="ld-dock-label">Live</span>
          {isLiveActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 3. Shop */}
        <Link
          href="/shop"
          className={`ld-dock-tab ${isShopActive ? 'active' : ''}`}
          aria-label="Shop"
          aria-current={isShopActive ? 'page' : undefined}
          data-testid="dock-shop-tab"
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
              <path d="M3 6h18" />
              <path d="M16 10a4 4 0 0 1-8 0" />
            </svg>
          </div>
          <span className="ld-dock-label">Shop</span>
          {isShopActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 4. Orders */}
        <Link
          href="/order"
          className={`ld-dock-tab ${isOrdersActive ? 'active' : ''}`}
          aria-label="Orders"
          aria-current={isOrdersActive ? 'page' : undefined}
          data-testid="dock-orders-tab"
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <rect width="16" height="20" x="4" y="2" rx="2" />
              <line x1="8" x2="16" y1="6" y2="6" />
              <line x1="8" x2="16" y1="10" y2="10" />
              <line x1="8" x2="12" y1="14" y2="14" />
            </svg>
          </div>
          <span className="ld-dock-label">Orders</span>
          {isOrdersActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 5. Bag */}
        {openDrawer ? (
          <button
            type="button"
            className={`ld-dock-tab ${isBagActive ? 'active' : ''}`}
            aria-label="Shopping Bag"
            data-testid="dock-bag-tab"
            onClick={openDrawer}
          >
            <div className="ld-dock-icon-wrap">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                <path d="M16 11V7a4 4 0 0 0-8 0v4M5 9h14l1 12H4L5 9z" />
              </svg>
              {isHydrated && itemCount > 0 && (
                <span className="ld-header-bag-badge" style={{ position: 'absolute', top: -4, right: -8, width: 16, height: 16, fontSize: 10 }}>
                  {itemCount}
                </span>
              )}
            </div>
            <span className="ld-dock-label">Bag</span>
            {isBagActive && <span className="ld-dock-active-line" aria-hidden="true" />}
          </button>
        ) : (
          <Link
            href="/cart"
            className={`ld-dock-tab ${isBagActive ? 'active' : ''}`}
            aria-label="Shopping Bag"
            data-testid="dock-bag-tab"
          >
            <div className="ld-dock-icon-wrap">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                <path d="M16 11V7a4 4 0 0 0-8 0v4M5 9h14l1 12H4L5 9z" />
              </svg>
              {isHydrated && itemCount > 0 && (
                <span className="ld-header-bag-badge" style={{ position: 'absolute', top: -4, right: -8, width: 16, height: 16, fontSize: 10 }}>
                  {itemCount}
                </span>
              )}
            </div>
            <span className="ld-dock-label">Bag</span>
            {isBagActive && <span className="ld-dock-active-line" aria-hidden="true" />}
          </Link>
        )}
      </div>
    </nav>
  );
}
