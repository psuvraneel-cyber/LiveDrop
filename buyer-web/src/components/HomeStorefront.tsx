'use client';

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import { PublicDropCatalog, PublicProductView, PublicSellerStorefront } from '../types/domain';
import { normalizeIndianPhoneNumber } from './BoutiqueStorefrontView';

export interface HomeStorefrontProps {
  activeDrops?: PublicDropCatalog[];
  storefronts?: PublicSellerStorefront[];
  initialLiveDrop?: PublicDropCatalog | null;
  initialProducts?: PublicProductView[];
  recentDrops?: PublicDropCatalog[];
}

export function HomeStorefront({
  activeDrops = [],
  storefronts = [],
  initialLiveDrop,
  recentDrops = [],
}: HomeStorefrontProps) {
  const [searchQuery, setSearchQuery] = useState('');

  // Resolved active live drops: either passed in or inferred from initialLiveDrop
  const resolvedActiveDrops = useMemo(() => {
    if (activeDrops && activeDrops.length > 0) return activeDrops;
    if (initialLiveDrop && initialLiveDrop.status === 'live') return [initialLiveDrop];
    return [];
  }, [activeDrops, initialLiveDrop]);

  // Resolved storefronts: either passed in or extracted from recentDrops
  const resolvedStorefronts = useMemo(() => {
    if (storefronts && storefronts.length > 0) return storefronts;
    const extracted: PublicSellerStorefront[] = [];
    const seen = new Set<string>();

    for (const drop of recentDrops) {
      if (drop.profiles && !seen.has(drop.seller_id)) {
        seen.add(drop.seller_id);
        extracted.push({
          id: drop.seller_id,
          store_name: drop.profiles.store_name,
          store_slug: drop.profiles.store_slug || 'boutique',
          phone_number: drop.profiles.phone_number || null,
          upi_id: drop.profiles.upi_id,
          upi_qr_url: drop.profiles.upi_qr_url,
          default_shipping_fee_paisa: drop.profiles.default_shipping_fee_paisa,
          free_shipping_threshold_paisa: drop.profiles.free_shipping_threshold_paisa,
          advance_confirmation_enabled: drop.profiles.advance_confirmation_enabled,
          advance_amount_paisa: drop.profiles.advance_amount_paisa,
          hold_duration_days: drop.profiles.hold_duration_days,
        });
      }
    }
    return extracted;
  }, [storefronts, recentDrops]);

  // Filtered boutiques and drops based on search query
  const filteredStorefronts = useMemo(() => {
    if (!searchQuery.trim()) return resolvedStorefronts;
    const query = searchQuery.toLowerCase().trim();
    return resolvedStorefronts.filter(
      (s) =>
        s.store_name.toLowerCase().includes(query) ||
        s.store_slug.toLowerCase().includes(query)
    );
  }, [resolvedStorefronts, searchQuery]);

  const filteredActiveDrops = useMemo(() => {
    if (!searchQuery.trim()) return resolvedActiveDrops;
    const query = searchQuery.toLowerCase().trim();
    return resolvedActiveDrops.filter(
      (d) =>
        d.title.toLowerCase().includes(query) ||
        (d.profiles?.store_name && d.profiles.store_name.toLowerCase().includes(query)) ||
        d.slug.toLowerCase().includes(query)
    );
  }, [resolvedActiveDrops, searchQuery]);

  const getBoutiqueWhatsAppUrl = (phone: string | null | undefined, name: string) => {
    const targetPhone = normalizeIndianPhoneNumber(phone);
    const text = `Hi ${name}, I discovered your boutique on LiveDrop!`;
    if (targetPhone) {
      return `https://wa.me/${targetPhone}?text=${encodeURIComponent(text)}`;
    }
    return `https://wa.me/?text=${encodeURIComponent(text)}`;
  };

  return (
    <div className="ld-home-storefront" data-testid="platform-home">
      {/* 1. Global Navigation Bar */}
      <header className="ld-navbar" role="banner">
        <div className="ld-navbar-inner">
          <div className="ld-navbar-left">
            <Link href="/" className="ld-brand-emblem" aria-label="LiveDrop Home">
              <span className="ld-brand-sparkle">✦</span>
              <span className="ld-brand-title">LiveDrop</span>
              <span className="ld-brand-sub">LIVE COMMERCE</span>
            </Link>
          </div>

          <nav className="ld-nav-links" aria-label="Main Navigation">
            <a href="#boutiques" className="ld-nav-link active">Boutiques</a>
            {resolvedActiveDrops.length > 0 ? (
              <a href="#live-drops" className="ld-nav-link ld-nav-live-link">
                Live Drops <span className="ld-nav-count-badge">LIVE</span>
              </a>
            ) : (
              <a href="#live-drops" className="ld-nav-link">Live Drops</a>
            )}
            <a href="#how-it-works" className="ld-nav-link">How It Works</a>
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
              placeholder="Search boutique or drop name..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              aria-label="Search boutiques and drops"
              data-testid="platform-search-input"
            />
          </div>
        </div>
      </header>

      {/* 2. Platform Hero Section */}
      <section className="ld-hero-section">
        <div className="ld-hero-glow" aria-hidden="true" />
        <div className="ld-hero-container">
          <div className="ld-hero-content" style={{ maxWidth: '780px', margin: '0 auto', textAlign: 'center' }}>
            <div className="ld-hero-badge-row" style={{ justifyContent: 'center' }}>
              <span className="ld-hero-live-pill active">
                <span className="ld-hero-live-dot" style={{ backgroundColor: 'var(--color-gold, #D4AF37)' }} />
                INDIA&apos;S INDEPENDENT BOUTIQUES
              </span>
              <span className="ld-hero-location">✦ Zero Middlemen Commerce</span>
            </div>

            <h1 className="ld-hero-store-name" style={{ fontSize: 'clamp(32px, 6vw, 56px)' }}>
              India&apos;s Luxury Boutiques, Streaming Live
            </h1>

            <p className="ld-hero-tagline" style={{ maxWidth: '640px', margin: '0 auto 24px' }}>
              Handcrafted sarees, designer wear, and artisanal collections directly from verified independent boutiques across India. Single-piece creations with direct UPI checkout.
            </p>

            <div className="ld-hero-cta-group" style={{ justifyContent: 'center' }}>
              <a href="#boutiques" className="ld-btn-gold-cta" data-testid="explore-boutiques-btn">
                <span>Explore Boutiques</span>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <line x1="5" y1="12" x2="19" y2="12" />
                  <polyline points="12 5 19 12 12 19" />
                </svg>
              </a>

              {resolvedActiveDrops.length > 0 && (
                <a href="#live-drops" className="ld-btn-watch-live">
                  <span className="ld-live-dot-pulse" />
                  <span>{resolvedActiveDrops.length} Live Drop{resolvedActiveDrops.length === 1 ? '' : 's'} Streaming</span>
                </a>
              )}
            </div>
          </div>
        </div>
      </section>

      {/* 3. Section: Live Drops Streaming Now */}
      <section className="ld-platform-section" id="live-drops" data-testid="live-drops-section">
        <div className="ld-platform-section-header">
          <div className="ld-hero-badge-row">
            <span className={`ld-hero-live-pill ${resolvedActiveDrops.length > 0 ? 'live' : 'active'}`}>
              <span className="ld-hero-live-dot" />
              {resolvedActiveDrops.length > 0 ? 'STREAMING NOW' : 'NEXT SESSIONS'}
            </span>
          </div>
          <h2 className="ld-platform-section-title">Active Live Drops</h2>
          <p className="ld-platform-section-subtitle">
            {resolvedActiveDrops.length > 0
              ? 'Join a live stream right now to view real-time garment presentations and claim limited pieces.'
              : 'There are no active live sessions at this exact moment. Browse our boutique studios below or check back during scheduled drop hours.'}
          </p>
        </div>

        {filteredActiveDrops.length > 0 ? (
          <div className="ld-live-drops-grid">
            {filteredActiveDrops.map((drop) => (
              <div key={drop.id} className="ld-live-drop-card" data-testid={`live-drop-card-${drop.slug}`}>
                <div className="ld-live-drop-top">
                  <span className="ld-hero-live-pill live" style={{ padding: '3px 10px', fontSize: '11px' }}>
                    <span className="ld-hero-live-dot" />
                    LIVE
                  </span>
                  <span className="ld-live-drop-store">{drop.profiles?.store_name || 'Boutique'}</span>
                </div>
                <h3 className="ld-live-drop-title">{drop.title}</h3>
                <p style={{ fontSize: '13px', color: 'var(--text-secondary)' }}>
                  Interactive live flash sale with direct atomic reservation locks.
                </p>
                <div className="ld-live-drop-actions">
                  <Link href={`/drop/${drop.slug}`} className="ld-btn-visit-boutique">
                    Enter Live Room & Claim Pieces →
                  </Link>
                  {drop.profiles?.store_slug && (
                    <Link
                      href={`/${drop.profiles.store_slug}`}
                      className="ld-share-btn"
                      title="Visit Storefront"
                    >
                      Boutique
                    </Link>
                  )}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="ld-empty-showcase" style={{ padding: '36px 20px', maxWidth: '600px' }}>
            <span className="ld-empty-sparkle">✦</span>
            <h3>No Active Live Drops Right Now</h3>
            <p>
              Boutiques stream drops live at scheduled times. Explore verified boutique lookbooks below to see past creations and connect with designers!
            </p>
          </div>
        )}
      </section>

      {/* 4. Section: Discover Independent Boutiques */}
      <section className="ld-platform-section" id="boutiques" data-testid="boutiques-directory-section">
        <div className="ld-platform-section-header">
          <h2 className="ld-platform-section-title">Discover Verified Boutiques</h2>
          <p className="ld-platform-section-subtitle">
            Explore dedicated storefronts for each seller. Every boutique has a dedicated URL and curated lookbooks.
          </p>
        </div>

        {filteredStorefronts.length > 0 ? (
          <div className="ld-boutique-grid" data-testid="boutique-grid">
            {filteredStorefronts.map((boutique) => (
              <article key={boutique.id} className="ld-boutique-card" data-testid={`boutique-card-${boutique.store_slug}`}>
                <div className="ld-boutique-card-top">
                  <div className="ld-boutique-card-emblem">
                    {boutique.store_name.slice(0, 1).toUpperCase()}
                  </div>
                  <span className="ld-verified-boutique-tag">✦ Verified</span>
                </div>

                <div className="ld-boutique-card-info">
                  <h3>{boutique.store_name}</h3>
                  <p>livedrop-in.vercel.app/<strong>{boutique.store_slug}</strong></p>
                </div>

                <div className="ld-boutique-card-perks">
                  <span>✓ Handcrafted Single Pieces</span>
                  <span>✓ Direct Studio Dispatch</span>
                  <span>✓ 100% Direct UPI</span>
                </div>

                <div className="ld-boutique-card-actions">
                  <Link
                    href={`/${boutique.store_slug}`}
                    className="ld-btn-visit-boutique"
                    data-testid={`visit-boutique-${boutique.store_slug}`}
                  >
                    Visit Boutique →
                  </Link>

                  {boutique.phone_number && (
                    <a
                      href={getBoutiqueWhatsAppUrl(boutique.phone_number, boutique.store_name)}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="ld-btn-whatsapp-icon"
                      title="Chat on WhatsApp"
                      aria-label={`Chat with ${boutique.store_name} on WhatsApp`}
                    >
                      💬
                    </a>
                  )}
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="ld-empty-showcase">
            <span className="ld-empty-sparkle">✦</span>
            <h3>No Boutiques Found</h3>
            <p>
              {searchQuery.trim()
                ? `No boutiques matched "${searchQuery}". Try a different search term.`
                : 'Our platform is currently welcoming verified boutique sellers. Check back soon!'}
            </p>
          </div>
        )}
      </section>

      {/* 5. How LiveDrop Works */}
      <section className="ld-value-props-bar" id="how-it-works">
        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">🎥</div>
          <div className="ld-prop-text">
            <strong>Live Streaming Drops</strong>
            <span>Real-time boutique video sessions</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">🔒</div>
          <div className="ld-prop-text">
            <strong>Atomic Claim Locks</strong>
            <span>First buyer to tap locks the piece</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">⚡</div>
          <div className="ld-prop-text">
            <strong>100% Direct UPI</strong>
            <span>Zero middleman payment fees</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon">📦</div>
          <div className="ld-prop-text">
            <strong>Verified Dispatch</strong>
            <span>Direct shipping from studio</span>
          </div>
        </div>
      </section>

      {/* 6. Luxury Footer */}
      <footer className="ld-footer">
        <div className="ld-footer-top">
          <span className="ld-footer-brand">LiveDrop</span>
          <span className="ld-footer-bullets">
            INDIAN BOUTIQUES • LIVE COMMERCE • ATOMIC INVENTORY • ZERO TRANSACTION FEES
          </span>
          <div className="ld-footer-socials">
            <span className="ld-social-icon" title="Instagram">📸</span>
            <span className="ld-social-icon" title="YouTube">📺</span>
          </div>
        </div>
        <div className="ld-footer-bottom">
          <span className="ld-script-tagline">Crafted for Indian Boutiques ~</span>
          <span className="ld-copyright">
            © {new Date().getFullYear()} LiveDrop Technologies. Canonical deployment: livedrop-in.vercel.app
          </span>
        </div>
      </footer>
    </div>
  );
}
