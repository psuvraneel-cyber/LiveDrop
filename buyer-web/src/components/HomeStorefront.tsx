'use client';

import React, { useState, useEffect, useMemo } from 'react';
import Link from 'next/link';
import { PublicDropCatalog, PublicProductView } from '../types/domain';
import { useCart } from '../lib/cart/cart-context';
import { ProductCard } from './ProductCard';
import { CartDrawer } from './cart/CartDrawer';
import { StickyCartBar } from './cart/StickyCartBar';

export interface HomeStorefrontProps {
  initialLiveDrop: PublicDropCatalog | null;
  initialProducts: PublicProductView[];
  recentDrops?: PublicDropCatalog[];
}

// Fallback curated boutique pieces for when DB is fresh / developing
const FALLBACK_PRODUCTS: PublicProductView[] = [
  {
    id: 'fb-prod-01',
    code: '#A21',
    title: 'Banarasi Silk Saree',
    price_paisa: 185000,
    status: 'available',
    size: 'Free Size',
    reserved_at: null,
    version: 1,
    image_url: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=800&q=80',
    image_urls: [
      'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=800&q=80',
      'https://images.unsplash.com/photo-1617627143750-d86bc21e42bb?auto=format&fit=crop&w=800&q=80',
    ],
    description: 'Pure Banarasi silk with traditional zari weave. Elegant, festive, and timeless. Handcrafted with love by Varanasi master weavers.',
    quantity_available: 3,
  },
  {
    id: 'fb-prod-02',
    code: '#A22',
    title: 'Kanchipuram Saree',
    price_paisa: 225000,
    status: 'available',
    size: 'Free Size',
    reserved_at: null,
    version: 1,
    image_url: 'https://images.unsplash.com/photo-1617627143750-d86bc21e42bb?auto=format&fit=crop&w=800&q=80',
    description: 'Authentic royal emerald Kanchipuram silk featuring intricate temple border zari weaving.',
    quantity_available: 1,
  },
  {
    id: 'fb-prod-03',
    code: '#A17',
    title: 'Chikankari Kurti',
    price_paisa: 145000,
    status: 'available',
    size: 'M / L',
    reserved_at: null,
    version: 1,
    image_url: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?auto=format&fit=crop&w=800&q=80',
    description: 'Lucknowi hand-embroidered white thread Chikankari kurti on premium breathable georgette.',
    quantity_available: 4,
  },
  {
    id: 'fb-prod-04',
    code: '#A24',
    title: 'Tussar Silk Saree',
    price_paisa: 235000,
    status: 'available',
    size: 'Free Size',
    reserved_at: null,
    version: 1,
    image_url: 'https://images.unsplash.com/photo-1609357605129-26f69add5d6e?auto=format&fit=crop&w=800&q=80',
    description: 'Wild organic Tussar silk in rich purple tones with antique gold foil motifs.',
    quantity_available: 1,
  },
  {
    id: 'fb-prod-05',
    code: '#A25',
    title: 'Designer Anarkali',
    price_paisa: 195000,
    status: 'available',
    size: 'L',
    reserved_at: null,
    version: 1,
    image_url: 'https://images.unsplash.com/photo-1563245372-f21724e3856d?auto=format&fit=crop&w=800&q=80',
    description: 'Flowing crimson designer Anarkali suit with delicate mirror work and dupatta set.',
    quantity_available: 2,
  },
  {
    id: 'fb-prod-06',
    code: '#A30',
    title: 'Soft Silk Saree',
    price_paisa: 175000,
    status: 'available',
    size: 'Free Size',
    reserved_at: null,
    version: 1,
    image_url: 'https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&w=800&q=80',
    description: 'Lightweight contemporary soft silk saree in dark charcoal noir with rose gold borders.',
    quantity_available: 2,
  },
];

const CATEGORIES = [
  'All',
  'Sarees',
  'Kurtis',
  'Dupattas',
  'Lehengas',
  'Jewellery',
  'Accessories',
  'Co-ords',
];

export function HomeStorefront({
  initialLiveDrop,
  initialProducts = [],
  recentDrops = [],
}: HomeStorefrontProps) {
  const { isDrawerOpen, openDrawer, closeDrawer, itemCount, isHydrated } = useCart();

  const [activeCategory, setActiveCategory] = useState('All');
  const [searchQuery, setSearchQuery] = useState('');
  const [isWatchLiveOpen, setIsWatchLiveOpen] = useState(false);

  // Active Drop information
  const activeDrop = initialLiveDrop || (recentDrops.length > 0 ? recentDrops[0] : null);
  const isDropLive = Boolean(initialLiveDrop && initialLiveDrop.status === 'live');
  const storeName = activeDrop?.profiles?.store_name || 'Priya Boutique';
  const dropTitle = activeDrop?.title || 'Festive Silks & Timeless Weaves';
  const dropSlug = activeDrop?.slug || 'festive-silks';

  // Live Drop Countdown Timer (1 hr 24 mins default or calculated from drop)
  const [timeLeft, setTimeLeft] = useState({ hrs: 1, mins: 24, secs: 36 });
  useEffect(() => {
    const timer = setInterval(() => {
      setTimeLeft((prev) => {
        if (prev.secs > 0) return { ...prev, secs: prev.secs - 1 };
        if (prev.mins > 0) return { ...prev, mins: prev.mins - 1, secs: 59 };
        if (prev.hrs > 0) return { ...prev, hrs: prev.hrs - 1, mins: 59, secs: 59 };
        return { hrs: 0, mins: 0, secs: 0 };
      });
    }, 1000);
    return () => clearInterval(timer);
  }, []);

  // Format single digits with leading zero
  const pad = (n: number) => n.toString().padStart(2, '0');

  // Product catalog resolution: real products if available, otherwise curated fallback
  const displayProducts = useMemo(() => {
    const source = initialProducts.length > 0 ? initialProducts : FALLBACK_PRODUCTS;
    return source.filter((p) => {
      // Category matching
      if (activeCategory !== 'All') {
        const titleLower = p.title.toLowerCase();
        const descLower = (p.description || '').toLowerCase();
        const catLower = activeCategory.toLowerCase();
        const matchesCategory =
          titleLower.includes(catLower) ||
          descLower.includes(catLower) ||
          (activeCategory === 'Sarees' && (titleLower.includes('saree') || titleLower.includes('silk')));
        if (!matchesCategory) return false;
      }

      // Search query matching
      if (searchQuery.trim() !== '') {
        const query = searchQuery.trim().toLowerCase();
        const cleanCode = query.startsWith('#') ? query : `#${query}`;
        const matchTitle = p.title.toLowerCase().includes(query);
        const matchCode = p.code.toLowerCase().includes(query) || p.code.toLowerCase().includes(cleanCode);
        if (!matchTitle && !matchCode) return false;
      }

      return true;
    });
  }, [initialProducts, activeCategory, searchQuery]);

  return (
    <div className="ld-home-storefront" data-testid="home-storefront">
      {/* 1. Global Navigation Bar */}
      <header className="ld-navbar" role="banner">
        <div className="ld-navbar-inner">
          <div className="ld-navbar-left">
            <button
              type="button"
              className="ld-nav-menu-btn"
              aria-label="Open navigation menu"
              onClick={() => {}}
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="3" y1="12" x2="21" y2="12" />
                <line x1="3" y1="6" x2="21" y2="6" />
                <line x1="3" y1="18" x2="21" y2="18" />
              </svg>
            </button>

            <Link href="/" className="ld-brand-emblem" aria-label="LiveDrop Home">
              <span className="ld-brand-sparkle">✦</span>
              <span className="ld-brand-title">LiveDrop</span>
              <span className="ld-brand-sub">LIVE COMMERCE</span>
            </Link>
          </div>

          <nav className="ld-nav-links" aria-label="Main Navigation">
            <Link href="/" className="ld-nav-link active">Shop</Link>
            {activeDrop ? (
              <Link href={`/drop/${dropSlug}`} className="ld-nav-link ld-nav-live-link">
                Live Drops <span className="ld-nav-count-badge">LIVE</span>
              </Link>
            ) : (
              <span className="ld-nav-link disabled">Live Drops</span>
            )}
            <a href="#categories" className="ld-nav-link">Collections</a>
            <a href="#about" className="ld-nav-link">About</a>
          </nav>

          {/* Search Input Bar */}
          <div className="ld-nav-search-box">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="ld-nav-search-icon">
              <circle cx="11" cy="11" r="8" />
              <line x1="21" y1="21" x2="16.65" y2="16.65" />
            </svg>
            <input
              type="text"
              className="ld-nav-search-input"
              placeholder="Search sarees, kurtis, dupattas..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              aria-label="Search catalog"
            />
          </div>

          {/* Right Action Icons */}
          <div className="ld-navbar-right">
            {isDropLive && (
              <Link href={`/drop/${dropSlug}`} className="ld-nav-shop-live-btn">
                <span className="ld-live-dot-pulse" />
                <span>Shop Live</span>
              </Link>
            )}

            {/* Cart Button */}
            <button
              type="button"
              className="ld-nav-cart-btn"
              onClick={openDrawer}
              aria-label={`Shopping bag with ${itemCount} items`}
              data-testid="home-nav-cart-btn"
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                <path d="M3 6h18" />
                <path d="M16 10a4 4 0 0 1-8 0" />
              </svg>
              {isHydrated && itemCount > 0 && (
                <span className="ld-nav-cart-badge" data-testid="home-cart-badge">
                  {itemCount}
                </span>
              )}
            </button>
          </div>
        </div>
      </header>

      {/* 2. Main Luxury Hero Drop Showcase */}
      <section className="ld-hero-section">
        {/* Ambient Dark Gold Radial Glow */}
        <div className="ld-hero-glow" aria-hidden="true" />

        <div className="ld-hero-container">
          {/* Left Hero Storyboard */}
          <div className="ld-hero-content">
            <div className="ld-hero-badge-row">
              <span className={`ld-hero-live-pill ${isDropLive ? 'live' : 'active'}`}>
                <span className="ld-hero-live-dot" />
                {isDropLive ? 'LIVE NOW' : 'FEATURED DROP'}
              </span>
              <span className="ld-hero-location">📍 Bengaluru, KA</span>
            </div>

            <h1 className="ld-hero-store-name">{storeName}</h1>
            <p className="ld-hero-tagline">{dropTitle}</p>

            <div className="ld-hero-stats-row">
              <span className="ld-hero-stat">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z" />
                  <circle cx="12" cy="12" r="3" />
                </svg>
                <strong>42</strong> watching
              </span>
              <span className="ld-hero-stat-sep">•</span>
              <span className="ld-hero-stat">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                  <path d="M3 6h18" />
                </svg>
                <strong>126</strong> sold
              </span>
            </div>

            <blockquote className="ld-hero-quote">
              “Tradition meets modern elegance — handcrafted with love.”
            </blockquote>

            <div className="ld-hero-cta-group">
              <Link
                href={activeDrop ? `/drop/${dropSlug}` : '#catalog'}
                className="ld-btn-gold-cta"
                data-testid="hero-shop-drop-btn"
              >
                <span>Shop the Drop</span>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <line x1="5" y1="12" x2="19" y2="12" />
                  <polyline points="12 5 19 12 12 19" />
                </svg>
              </Link>

              <button
                type="button"
                className="ld-btn-watch-live"
                onClick={() => setIsWatchLiveOpen(true)}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                  <polygon points="5 3 19 12 5 21 5 3" />
                </svg>
                <span>Watch Live</span>
              </button>
            </div>
          </div>

          {/* Right Hero: Countdown Timer & Boutique Guarantee Card */}
          <div className="ld-hero-aside">
            <div className="ld-hero-timer-card">
              <span className="ld-timer-title">Drop Ends In</span>
              <div className="ld-timer-clock">
                <div className="ld-timer-unit">
                  <span className="ld-timer-num">{pad(timeLeft.hrs)}</span>
                  <span className="ld-timer-lbl">Hrs</span>
                </div>
                <span className="ld-timer-colon">:</span>
                <div className="ld-timer-unit">
                  <span className="ld-timer-num">{pad(timeLeft.mins)}</span>
                  <span className="ld-timer-lbl">Mins</span>
                </div>
                <span className="ld-timer-colon">:</span>
                <div className="ld-timer-unit">
                  <span className="ld-timer-num">{pad(timeLeft.secs)}</span>
                  <span className="ld-timer-lbl">Secs</span>
                </div>
              </div>

              <div className="ld-timer-divider" />

              <ul className="ld-hero-perks-list">
                <li>
                  <span className="ld-perk-check">✓</span>
                  <span>Authentic Handpicked Pieces</span>
                </li>
                <li>
                  <span className="ld-perk-check">✓</span>
                  <span>Single Pieces, No Restock</span>
                </li>
                <li>
                  <span className="ld-perk-check">✓</span>
                  <span>Direct UPI Payments</span>
                </li>
                <li>
                  <span className="ld-perk-check">✓</span>
                  <span>Support Independent Sellers</span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* 3. Value Proposition Bar */}
      <section className="ld-value-props-bar" id="about">
        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">💎</div>
          <div className="ld-prop-text">
            <strong>Unique Pieces</strong>
            <span>Limited Stock</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">👥</div>
          <div className="ld-prop-text">
            <strong>Independent Sellers</strong>
            <span>From Across India</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">🤝</div>
          <div className="ld-prop-text">
            <strong>No Middlemen</strong>
            <span>No Gateway Fees</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">⚡</div>
          <div className="ld-prop-text">
            <strong>Secure & Direct</strong>
            <span>100% UPI Payments</span>
          </div>
        </div>
      </section>

      {/* 4. Category Tabs Filter */}
      <section className="ld-categories-section" id="categories">
        <div className="ld-category-tabs-row" role="tablist" aria-label="Browse categories">
          {CATEGORIES.map((cat) => (
            <button
              key={cat}
              type="button"
              role="tab"
              aria-selected={activeCategory === cat}
              className={`ld-category-pill ${activeCategory === cat ? 'active' : ''}`}
              onClick={() => setActiveCategory(cat)}
            >
              {cat}
            </button>
          ))}
        </div>
      </section>

      {/* 5. Featured Products Catalog Section */}
      <main className="ld-catalog-section" id="catalog">
        <div className="ld-catalog-header">
          <div className="ld-catalog-header-left">
            <h2 className="ld-catalog-title">
              {activeCategory === 'All' ? 'Featured Pieces' : activeCategory}
            </h2>
            <span className="ld-catalog-subtitle">
              {displayProducts.length} single-piece creation{displayProducts.length === 1 ? '' : 's'} available
            </span>
          </div>

          {activeDrop && (
            <Link href={`/drop/${dropSlug}`} className="ld-view-all-link">
              <span>View Full Drop</span>
              <span>→</span>
            </Link>
          )}
        </div>

        {/* Product Cards Grid */}
        <div className="ld-products-grid">
          {displayProducts.map((prod) => (
            <ProductCard
              key={prod.id}
              product={prod}
              dropId={activeDrop?.id}
              storeName={storeName}
            />
          ))}
        </div>
      </main>

      {/* 6. Luxury Footer */}
      <footer className="ld-footer">
        <div className="ld-footer-top">
          <span className="ld-footer-brand">LiveDrop</span>
          <span className="ld-footer-bullets">
            SHOP LIVE • UNIQUE PIECES • REAL PEOPLE • INDIAN BOUTIQUES
          </span>
          <div className="ld-footer-socials">
            <span className="ld-social-icon" title="Instagram">📸</span>
            <span className="ld-social-icon" title="YouTube">📺</span>
            <span className="ld-social-icon" title="Facebook">🌐</span>
            <span className="ld-social-icon" title="Pinterest">📌</span>
          </div>
        </div>
        <div className="ld-footer-bottom">
          <span className="ld-script-tagline">Fashion Lives Here ~</span>
          <span className="ld-copyright">© {new Date().getFullYear()} LiveDrop Technologies. Handcrafted in India.</span>
        </div>
      </footer>

      {/* 7. Watch Live Broadcast Modal Simulation */}
      {isWatchLiveOpen && (
        <div className="ld-modal-backdrop" onClick={() => setIsWatchLiveOpen(false)}>
          <div className="ld-watch-live-modal" onClick={(e) => e.stopPropagation()}>
            <div className="ld-live-stream-header">
              <div className="ld-live-stream-badge">
                <span className="ld-hero-live-dot" />
                <span>LIVE BROADCAST</span>
              </div>
              <button
                type="button"
                className="ld-sheet-btn-icon"
                onClick={() => setIsWatchLiveOpen(false)}
                aria-label="Close live stream"
              >
                ✕
              </button>
            </div>

            <div className="ld-live-stream-video">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=1200&q=80"
                alt="Live broadcast preview"
                className="ld-live-stream-img"
              />
              <div className="ld-live-stream-overlay">
                <span className="ld-stream-viewer-count">👁 42 people watching right now</span>
                <span className="ld-stream-seller-badge">{storeName} is showcasing Saree #A21</span>
              </div>
            </div>

            <div className="ld-live-stream-footer">
              <Link
                href={`/drop/${dropSlug}`}
                className="ld-btn-gold-cta"
                onClick={() => setIsWatchLiveOpen(false)}
              >
                Enter Live Room & Claim Pieces
              </Link>
            </div>
          </div>
        </div>
      )}

      {/* 8. Sticky Mobile Cart Bar */}
      <StickyCartBar onOpenCart={openDrawer} />

      {/* 9. Slide-over Cart Drawer */}
      <CartDrawer
        isOpen={isDrawerOpen}
        onClose={closeDrawer}
        catalogProducts={displayProducts}
        drop={activeDrop}
      />
    </div>
  );
}
