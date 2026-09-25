'use client';

import React, { useSyncExternalStore } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useOptionalProfile } from '../../lib/profile/profile-context';

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
  const profileContext = useOptionalProfile();
  const isProfileOpen = profileContext?.isProfileOpen ?? false;
  const openProfile = profileContext?.openProfile;

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
  const isHomeBase = pathname === '/' || pathname === '';
  const isShopRoute = pathname === '/shop';
  const isBoutiqueRoute = Boolean(
    pathname &&
    pathname !== '/' &&
    !isCart &&
    !pathname.startsWith('/order') &&
    !pathname.startsWith('/drop/') &&
    !isShopRoute
  );

  const isLiveActive = isHomeBase && currentHash === '#live-drops';
  const isDesignersActive = isBoutiqueRoute || (isHomeBase && currentHash === '#boutiques');
  const isShopActive = isShopRoute;
  const isProfileActive = isProfileOpen;
  const isHomeActive = isHomeBase && !isLiveActive && !isDesignersActive && !isShopActive && !isCart && !isProfileActive;

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

        {/* 4. Designers */}
        <Link
          href="/#boutiques"
          className={`ld-dock-tab ${isDesignersActive ? 'active' : ''}`}
          aria-label="Designers"
          data-testid="dock-designers-tab"
          onClick={() => setHashLocation('#boutiques')}
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z" />
            </svg>
          </div>
          <span className="ld-dock-label">Designers</span>
          {isDesignersActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </Link>

        {/* 5. Profile */}
        <button
          type="button"
          className={`ld-dock-tab ${isProfileActive ? 'active' : ''}`}
          aria-label="Profile"
          data-testid="dock-profile-tab"
          onClick={() => {
            if (openProfile) {
              openProfile();
            }
          }}
        >
          <div className="ld-dock-icon-wrap">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="8" r="4" />
              <path d="M20 21a8 8 0 1 0-16 0" />
            </svg>
          </div>
          <span className="ld-dock-label">Profile</span>
          {isProfileActive && <span className="ld-dock-active-line" aria-hidden="true" />}
        </button>
      </div>
    </nav>
  );
}
