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
  const isCart = pathname === '/cart' || pathname === '/checkout';
  const isOrder = pathname?.startsWith('/order');
  const isHomeBase = pathname === '/' || pathname === '';
  const isBoutiqueRoute = Boolean(
    pathname &&
    pathname !== '/' &&
    !isCart &&
    !isOrder &&
    !pathname.startsWith('/drop/')
  );

  const isLiveActive = isHomeBase && currentHash === '#live-drops';
  const isBoutiquesActive = isBoutiqueRoute || (isHomeBase && currentHash === '#boutiques');
  const isHomeActive = isHomeBase && !isLiveActive && !isBoutiquesActive;

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
          onClick={() => setHashLocation('#live-drops')}
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <polygon points="23 7 16 12 23 17 23 7" />
              <rect width="15" height="14" x="1" y="5" rx="2" ry="2" />
            </svg>
            <span className="ld-dock-live-dot" aria-hidden="true" />
          </div>
          <span className="ld-dock-label">Live</span>
          {isLiveActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 3. Boutiques */}
        <Link
          href="/#boutiques"
          className={`ld-dock-tab ${isBoutiquesActive ? 'active' : ''}`}
          aria-label="Boutiques"
          onClick={() => {
            if (isHomeBase) setHashLocation('#boutiques');
          }}
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2z" />
              <path d="M9 22V12h6v10" />
            </svg>
          </div>
          <span className="ld-dock-label">Boutiques</span>
          {isBoutiquesActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 4. Bag */}
        <Link
          href="/cart"
          className={`ld-dock-tab ${isCart ? 'active' : ''}`}
          aria-label={`Shopping Bag containing ${itemCount} items`}
          aria-current={isCart ? 'page' : undefined}
          data-testid="dock-bag-tab"
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
              <path d="M3 6h18" />
              <path d="M16 10a4 4 0 0 1-8 0" />
            </svg>
            {isHydrated && itemCount > 0 && (
              <span className="ld-dock-bag-badge" data-testid="dock-bag-count">
                {itemCount}
              </span>
            )}
          </div>
          <span className="ld-dock-label">Bag</span>
          {isCart && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 5. Orders */}
        <Link
          href="/order"
          className={`ld-dock-tab ${isOrder ? 'active' : ''}`}
          aria-label="Orders"
          aria-current={isOrder ? 'page' : undefined}
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
              <polyline points="14 2 14 8 20 8" />
              <line x1="16" y1="13" x2="8" y2="13" />
              <line x1="16" y1="17" x2="8" y2="17" />
              <polyline points="10 9 9 9 8 9" />
            </svg>
          </div>
          <span className="ld-dock-label">Orders</span>
          {isOrder && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>
      </div>
    </nav>
  );
}
