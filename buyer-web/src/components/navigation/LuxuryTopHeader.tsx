'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { useOptionalCart } from '../../lib/cart/cart-context';

export interface LuxuryTopHeaderProps {
  searchQuery?: string;
  onSearchChange?: (query: string) => void;
  showSearch?: boolean;
}

export function LuxuryTopHeader({
  searchQuery = '',
  onSearchChange,
  showSearch = true,
}: LuxuryTopHeaderProps) {
  const [isVisible, setIsVisible] = useState(true);
  const [isScrolled, setIsScrolled] = useState(false);
  const [isSearchOpen, setIsSearchOpen] = useState(false);

  const cart = useOptionalCart();
  const itemCount = cart?.itemCount ?? 0;
  const isHydrated = cart?.isHydrated ?? false;
  const openDrawer = cart?.openDrawer;

  useEffect(() => {
    let lastScrollY = window.scrollY;

    const handleScroll = () => {
      const currentScrollY = window.scrollY;
      setIsScrolled(currentScrollY > 20);

      // Only collapse after scrolling past the hero header threshold
      if (currentScrollY > 90) {
        if (currentScrollY > lastScrollY && currentScrollY - lastScrollY > 8) {
          // Scrolling down
          setIsVisible(false);
        } else if (lastScrollY - currentScrollY > 8) {
          // Scrolling up
          setIsVisible(true);
        }
      } else {
        setIsVisible(true);
      }

      lastScrollY = currentScrollY;
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <header
      className={`ld-luxury-header ${isScrolled ? 'scrolled' : ''} ${!isVisible ? 'hidden' : ''}`}
      role="banner"
    >
      <div className="ld-luxury-header-inner">
        {/* Brand Emblem Monogram */}
        <div className="ld-luxury-header-brand">
          <Link href="/" className="ld-header-monogram-link" aria-label="LiveDrop Haute Couture Home">
            <span className="ld-header-crest-icon" aria-hidden="true">✦</span>
            <div className="ld-header-brand-text">
              <span className="ld-header-title">LiveDrop</span>
              <span className="ld-header-subtitle">HAUTE COUTURE</span>
            </div>
          </Link>
        </div>

        {/* Center / Desktop Links */}
        <nav className="ld-header-nav-links" aria-label="Primary Navigation">
          <Link href="/#boutiques" className="ld-header-nav-link">
            Boutiques
          </Link>
          <Link href="/#live-drops" className="ld-header-nav-link">
            Live Drops
          </Link>
          <Link href="/#atelier-standards" className="ld-header-nav-link">
            Atelier Standards
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
                  placeholder="Search boutiques, drops..."
                  value={searchQuery}
                  onChange={(e) => onSearchChange?.(e.target.value)}
                  aria-label="Search boutiques and drops"
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
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
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
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
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
