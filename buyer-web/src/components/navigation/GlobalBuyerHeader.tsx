'use client';

import React, { useState } from 'react';
import Link from 'next/link';
import { useOptionalCart } from '../../lib/cart/cart-context';

export type BuyerHeaderVariant = 'storefront' | 'boutique' | 'minimal';

export interface GlobalBuyerHeaderProps {
  variant?: BuyerHeaderVariant;

  // Storefront variant props
  searchQuery?: string;
  onSearchChange?: (query: string) => void;
  showSearch?: boolean;

  // Boutique variant props
  storeName?: string;
  storeSlug?: string;
  onShare?: () => void;
  isCopied?: boolean;
  hasLiveDrop?: boolean;

  // Minimal / Checkout / Order variant props
  title?: string;
  subtitle?: string;
  backHref?: string;
  onBack?: () => void;
  backLabel?: string;
  backTestId?: string;
  rightAction?: React.ReactNode;
}

export function GlobalBuyerHeader({
  variant = 'storefront',
  searchQuery = '',
  onSearchChange,
  showSearch = true,
  storeName,
  onShare,
  isCopied = false,
  hasLiveDrop = false,
  title,
  subtitle,
  backHref,
  onBack,
  backLabel,
  backTestId,
  rightAction,
}: GlobalBuyerHeaderProps) {
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  const cart = useOptionalCart();
  const itemCount = cart?.itemCount ?? 0;
  const isHydrated = cart?.isHydrated ?? false;
  const openDrawer = cart?.openDrawer;

  // =========================================================================
  // 1. BOUTIQUE VARIANT (/[storeSlug])
  // =========================================================================
  if (variant === 'boutique') {
    return (
      <header className="ld-global-header ld-navbar" role="banner" data-testid="global-buyer-header">
        <div className="ld-global-header-inner ld-navbar-inner">
          <div className="ld-global-header-left ld-navbar-left">
            <Link href="/" className="ld-header-monogram-link ld-brand-emblem" aria-label="LiveDrop Home">
              <span className="ld-header-crest-icon ld-brand-sparkle" aria-hidden="true">✦</span>
              <div className="ld-header-brand-text">
                <span className="ld-header-title ld-brand-title">LiveDrop</span>
                <span className="ld-header-subtitle ld-brand-sub">BOUTIQUE</span>
              </div>
            </Link>
          </div>

          <div className="ld-global-header-center ld-navbar-center">
            {storeName && (
              <span className="ld-storefront-nav-name" data-testid="storefront-name-badge">
                {storeName}
              </span>
            )}
          </div>

          <div className="ld-global-header-right ld-navbar-right flex items-center gap-2">
            {onShare && (
              <button
                type="button"
                className="ld-share-btn"
                onClick={onShare}
                title="Copy boutique link"
                aria-label="Copy boutique link"
                data-testid="copy-storefront-link-btn"
              >
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect width="13" height="13" x="9" y="9" rx="2" ry="2" />
                  <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                </svg>
                <span>{isCopied ? 'Copied!' : 'Share'}</span>
              </button>
            )}

            {hasLiveDrop && (
              <button
                type="button"
                className="ld-header-icon-btn ld-nav-cart-btn"
                onClick={openDrawer}
                aria-label={`Shopping bag with ${itemCount} items`}
                data-testid="storefront-cart-btn"
              >
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
                  <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                  <path d="M3 6h18" />
                  <path d="M16 10a4 4 0 0 1-8 0" />
                </svg>
                {isHydrated && itemCount > 0 && (
                  <span className="ld-header-bag-badge ld-nav-cart-badge" data-testid="storefront-cart-badge">
                    {itemCount}
                  </span>
                )}
              </button>
            )}
          </div>
        </div>
      </header>
    );
  }

  // =========================================================================
  // 2. MINIMAL VARIANT (/cart, /checkout, /order, /order/[id])
  // =========================================================================
  if (variant === 'minimal') {
    return (
      <header className="ld-global-header ld-checkout-header" role="banner" data-testid="global-buyer-header">
        <div className="ld-global-header-inner ld-checkout-nav">
          <div className="ld-global-header-left flex items-center gap-3">
            {backHref ? (
              <Link
                href={backHref}
                className="ld-header-back-btn ld-back-link"
                data-testid={backTestId}
                aria-label={backLabel || 'Return'}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <line x1="19" y1="12" x2="5" y2="12" />
                  <polyline points="12 19 5 12 12 5" />
                </svg>
                {backLabel && <span>{backLabel}</span>}
              </Link>
            ) : onBack ? (
              <button
                type="button"
                onClick={onBack}
                className="ld-header-back-btn ld-back-link"
                data-testid={backTestId}
                aria-label={backLabel || 'Return'}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <line x1="19" y1="12" x2="5" y2="12" />
                  <polyline points="12 19 5 12 12 5" />
                </svg>
                {backLabel && <span>{backLabel}</span>}
              </button>
            ) : (
              <Link href="/" className="ld-header-monogram-link" aria-label="LiveDrop Home">
                <span className="ld-header-crest-icon" aria-hidden="true">✦</span>
                <span className="ld-header-title ld-checkout-brand">LiveDrop</span>
              </Link>
            )}
          </div>

          <div className="ld-global-header-center">
            {title && (backHref || onBack || title !== 'LiveDrop') && (
              <span className="ld-header-minimal-title ld-checkout-brand">
                {title}
              </span>
            )}
            {subtitle && (
              <span className="ld-header-minimal-subtitle block text-center text-[10px] text-white/50 tracking-wider">
                {subtitle}
              </span>
            )}
          </div>

          <div className="ld-global-header-right">
            {rightAction || <div className="w-8" />}
          </div>
        </div>
      </header>
    );
  }

  // =========================================================================
  // 3. STOREFRONT VARIANT (Default: /, /shop)
  // =========================================================================
  return (
    <header
      className="ld-global-header ld-luxury-header"
      role="banner"
      data-testid="global-buyer-header"
    >
      <div className="ld-global-header-inner ld-luxury-header-inner">
        {/* Brand Emblem Monogram */}
        <div className="ld-luxury-header-brand">
          <Link href="/" className="ld-header-monogram-link" aria-label="LiveDrop Haute Couture Home">
            <span className="ld-header-crest-icon" aria-hidden="true">✦</span>
            <div className="ld-header-brand-text">
              <span className="ld-header-title">LiveDrop</span>
              <span className="ld-header-subtitle">INDIAN LUXURY LIVE</span>
            </div>
          </Link>
        </div>

        {/* Center / Desktop Links */}
        <nav className="ld-header-nav-links" aria-label="Primary Navigation">
          <Link href="/shop" className="ld-header-nav-link">
            Shop
          </Link>
          <Link href="/#live-drops" className="ld-header-nav-link">
            Live Drops
          </Link>
          <Link href="/shop" className="ld-header-nav-link">
            Collections
          </Link>
          <Link href="/#boutiques" className="ld-header-nav-link">
            Boutiques
          </Link>
        </nav>

        {/* Right Actions: Search & Shopping Bag */}
        <div className="ld-luxury-header-actions">
          {showSearch && (
            <div className={`ld-header-search-wrap ${isSearchOpen ? 'expanded' : ''}`}>
              <button
                type="button"
                className="ld-header-icon-btn ld-header-search-trigger"
                onClick={() => setIsSearchOpen((prev) => !prev)}
                aria-label={isSearchOpen ? 'Close search' : 'Open search'}
              >
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
                  <circle cx="11" cy="11" r="8" />
                  <line x1="21" y1="21" x2="16.65" y2="16.65" />
                </svg>
              </button>

              <div className="ld-header-search-field">
                <input
                  type="text"
                  className="ld-header-search-input"
                  placeholder="Search sarees, kurtis, dupattas..."
                  value={searchQuery}
                  onChange={(e) => onSearchChange?.(e.target.value)}
                  aria-label="Search products, sarees, kurtis"
                  data-testid="platform-search-input"
                />
                {searchQuery && (
                  <button
                    type="button"
                    className="ld-search-clear-btn"
                    onClick={() => onSearchChange?.('')}
                    aria-label="Clear search query"
                  >
                    ✕
                  </button>
                )}
              </div>
            </div>
          )}

          {/* Shopping Bag Button */}
          {openDrawer ? (
            <button
              type="button"
              className="ld-header-icon-btn ld-header-bag-btn"
              onClick={openDrawer}
              aria-label={`Shopping Bag containing ${itemCount} items`}
              data-testid="luxury-bag-btn"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
                <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                <path d="M3 6h18" />
                <path d="M16 10a4 4 0 0 1-8 0" />
              </svg>
              {isHydrated && itemCount > 0 && (
                <span className="ld-header-bag-badge" data-testid="luxury-bag-badge">
                  {itemCount}
                </span>
              )}
            </button>
          ) : (
            <Link
              href="/cart"
              className="ld-header-icon-btn ld-header-bag-btn"
              aria-label={`Shopping Bag containing ${itemCount} items`}
              data-testid="luxury-bag-link"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
                <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                <path d="M3 6h18" />
                <path d="M16 10a4 4 0 0 1-8 0" />
              </svg>
              {isHydrated && itemCount > 0 && (
                <span className="ld-header-bag-badge" data-testid="luxury-bag-badge">
                  {itemCount}
                </span>
              )}
            </Link>
          )}
        </div>
      </div>
    </header>
  );
}
