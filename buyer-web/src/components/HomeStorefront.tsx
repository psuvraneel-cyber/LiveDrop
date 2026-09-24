'use client';

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import { PublicDropCatalog, PublicProductView, PublicSellerStorefront } from '../types/domain';
import { filterProductionStorefronts } from '../lib/data/buyer-catalog';
import { normalizeIndianPhoneNumber } from './BoutiqueStorefrontView';
import { LuxuryTopHeader } from './navigation/LuxuryTopHeader';
import { MobileBottomDock } from './navigation/MobileBottomDock';

export interface HomeStorefrontProps {
  activeDrops?: PublicDropCatalog[];
  storefronts?: PublicSellerStorefront[];
  initialLiveDrop?: PublicDropCatalog | null;
  initialProducts?: PublicProductView[];
  recentDrops?: PublicDropCatalog[];
}

const CATEGORIES = [
  { id: 'all', label: 'All Collections' },
  { id: 'banarasi', label: 'Banarasi Silks' },
  { id: 'bridal', label: 'Bridal Lehengas' },
  { id: 'handloom', label: 'Handloom Weaves' },
  { id: 'designer', label: 'Designer Kurtis' },
  { id: 'jewellery', label: 'Artisanal Jewellery' },
];

export function HomeStorefront({
  activeDrops = [],
  storefronts = [],
  initialLiveDrop,
  recentDrops = [],
}: HomeStorefrontProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');

  // Resolved active live drops: either passed in or inferred from initialLiveDrop
  const resolvedActiveDrops = useMemo(() => {
    if (activeDrops && activeDrops.length > 0) return activeDrops;
    if (initialLiveDrop && initialLiveDrop.status === 'live') return [initialLiveDrop];
    return [];
  }, [activeDrops, initialLiveDrop]);

  // Resolved storefronts: extract, then filter production deterministically
  const resolvedStorefronts = useMemo(() => {
    let raw: PublicSellerStorefront[] = [];

    if (storefronts && storefronts.length > 0) {
      raw = storefronts;
    } else {
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
      raw = extracted;
    }

    return filterProductionStorefronts(raw);
  }, [storefronts, recentDrops]);

  // Filtered boutiques based on search query and category
  const filteredStorefronts = useMemo(() => {
    let result = resolvedStorefronts;

    if (searchQuery.trim()) {
      const query = searchQuery.toLowerCase().trim();
      result = result.filter(
        (s) =>
          s.store_name.toLowerCase().includes(query) ||
          s.store_slug.toLowerCase().includes(query)
      );
    }

    if (selectedCategory !== 'all') {
      const categoryQuery = selectedCategory.toLowerCase();
      // If store matches category keyword or if search was not already matched
      const categoryMatches = result.filter(
        (s) =>
          s.store_name.toLowerCase().includes(categoryQuery) ||
          s.store_slug.toLowerCase().includes(categoryQuery)
      );
      // Keep category filter graceful if no specific tag is attached
      if (categoryMatches.length > 0) {
        result = categoryMatches;
      }
    }

    return result;
  }, [resolvedStorefronts, searchQuery, selectedCategory]);

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
    <div className="ld-home-storefront ld-has-bottom-dock" data-testid="platform-home">
      {/* 1. Scroll-Aware Luxury Top Header */}
      <LuxuryTopHeader
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      {/* 2. Editorial Hero Section (Restrained Luxury Magazine Aesthetic) */}
      <section className="ld-hero-section">
        <div className="ld-hero-glow" aria-hidden="true" />
        <div className="ld-hero-container">
          <div className="ld-hero-content ld-hero-content-editorial">
            <div className="ld-hero-badge-row ld-hero-badge-row-center">
              <span className="ld-hero-live-pill active">
                <span className="ld-hero-live-dot" />
                INDIA&apos;S INDEPENDENT ATELIERS
              </span>
              <span className="ld-hero-location">✦ Direct Artisan Heritage</span>
            </div>

            <h1 className="ld-hero-store-name">
              India&apos;s Luxury Boutiques, Streaming Live
            </h1>

            <p className="ld-hero-tagline ld-hero-tagline-editorial">
              Handcrafted sarees, designer wear, and artisanal collections directly from verified independent boutiques across India. Single-piece creations with direct studio settlement.
            </p>

            <div className="ld-hero-cta-group ld-hero-cta-group-center">
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

      {/* 3. Horizontal Silk Category Chips */}
      <section className="ld-categories-section" aria-label="Product Categories">
        <div className="ld-category-tabs-row" role="tablist">
          {CATEGORIES.map((cat) => (
            <button
              key={cat.id}
              type="button"
              role="tab"
              aria-selected={selectedCategory === cat.id}
              className={`ld-category-pill ${selectedCategory === cat.id ? 'active' : ''}`}
              onClick={() => setSelectedCategory(cat.id)}
            >
              {cat.label}
            </button>
          ))}
        </div>
      </section>

      {/* 4. Section: Live Drops Streaming Now */}
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
                <p style={{ fontSize: '13px', color: 'var(--ivory-muted, rgba(251, 251, 251, 0.65))' }}>
                  Interactive live atelier presentation with instant single-piece reserve.
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

      {/* 5. Section: Discover Independent Boutiques */}
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
                  {Boolean(boutique.is_verified) && (
                    <span className="ld-verified-boutique-tag">✦ Verified</span>
                  )}
                </div>

                <div className="ld-boutique-card-info">
                  <h3>{boutique.store_name}</h3>
                  <p>livedrop-in.vercel.app/<strong>{boutique.store_slug}</strong></p>
                </div>

                <div className="ld-boutique-card-perks">
                  <span>✓ Handcrafted Single Pieces</span>
                  <span>✓ Direct Studio Dispatch</span>
                  <span>✓ Direct UPI Settlement</span>
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
                      <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M17.472 14.382c-.301-.15-1.78-.878-2.056-.978-.276-.101-.477-.15-.678.15-.2.301-.778.978-.954 1.18-.176.201-.351.226-.652.075-.301-.15-1.272-.469-2.423-1.496-.896-.799-1.5-1.787-1.677-2.088-.176-.301-.019-.464.132-.614.136-.135.301-.351.451-.527.151-.176.201-.301.301-.502.1-.201.05-.376-.025-.527-.075-.15-.678-1.632-.929-2.234-.244-.587-.492-.507-.677-.517l-.578-.01c-.201 0-.527.075-.803.376s-1.054 1.029-1.054 2.509c0 1.48 1.079 2.909 1.23 3.109.15.201 2.124 3.243 5.145 4.549.719.311 1.28.497 1.718.636.722.23 1.379.197 1.9.119.58-.088 1.78-.728 2.03-1.431.251-.703.251-1.305.176-1.431-.076-.126-.277-.201-.578-.352z" />
                        <path d="M12 2C6.48 2 2 6.48 2 12c0 1.94.55 3.75 1.51 5.28L2 22l4.88-1.47C8.36 21.48 10.12 22 12 22c5.52 0 10-4.48 10-10S17.52 2 12 2zm0 18c-1.64 0-3.17-.49-4.46-1.34l-.32-.21-2.89.87.87-2.81-.23-.34C4.1 14.86 3.6 13.48 3.6 12c0-4.63 3.77-8.4 8.4-8.4s8.4 3.77 8.4 8.4-3.77 8.4-8.4 8.4z" />
                      </svg>
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

      {/* 6. Atelier Craft Standards (Bespoke SVG Stroke Icons, No Developer Jargon) */}
      <section className="ld-value-props-bar" id="how-it-works">
        <div className="ld-value-prop-item">
          <div className="ld-prop-icon" aria-hidden="true">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--champagne-gold, #D4AF37)" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <polygon points="23 7 16 12 23 17 23 7" />
              <rect width="15" height="14" x="1" y="5" rx="2" ry="2" />
            </svg>
          </div>
          <div className="ld-prop-text">
            <strong>Live Studio Broadcasts</strong>
            <span>Real-time boutique video sessions</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon" aria-hidden="true">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--champagne-gold, #D4AF37)" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
          </div>
          <div className="ld-prop-text">
            <strong>Single-Piece Claim</strong>
            <span>Instant reserve during live drops</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon" aria-hidden="true">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--champagne-gold, #D4AF37)" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              <path d="m9 12 2 2 4-4" />
            </svg>
          </div>
          <div className="ld-prop-text">
            <strong>Direct UPI Settlement</strong>
            <span>Direct payments to artisan studios</span>
          </div>
        </div>

        <div className="ld-value-prop-item">
          <div className="ld-prop-icon" aria-hidden="true">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var(--champagne-gold, #D4AF37)" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="m7.5 4.27 9 5.15" />
              <path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z" />
              <path d="m3.3 7 8.7 5 8.7-5" />
              <path d="M12 22V12" />
            </svg>
          </div>
          <div className="ld-prop-text">
            <strong>Studio Dispatch</strong>
            <span>Direct shipping from artisan ateliers</span>
          </div>
        </div>
      </section>

      {/* 7. Haute Couture Editorial Footer */}
      <footer className="ld-footer">
        <div className="ld-footer-top">
          <span className="ld-footer-brand">LiveDrop</span>
          <span className="ld-footer-bullets">
            CURATED INDIAN BOUTIQUES • LIVE COMMERCE • ARTISANAL HERITAGE • DIRECT SETTLEMENT
          </span>
          <div className="ld-footer-socials">
            <span className="ld-social-icon" title="Instagram">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                <rect width="20" height="20" x="2" y="2" rx="5" ry="5" />
                <path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z" />
                <line x1="17.5" y1="6.5" x2="17.51" y2="6.5" />
              </svg>
            </span>
            <span className="ld-social-icon" title="YouTube">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                <path d="M2.5 17a24.12 24.12 0 0 1 0-10 2 2 0 0 1 1.4-1.4 49.56 49.56 0 0 1 16.2 0A2 2 0 0 1 21.5 7a24.12 24.12 0 0 1 0 10 2 2 0 0 1-1.4 1.4 49.55 49.55 0 0 1-16.2 0A2 2 0 0 1 2.5 17" />
                <polygon points="10 15 15 12 10 9 10 15" />
              </svg>
            </span>
          </div>
        </div>
        <div className="ld-footer-bottom">
          <span className="ld-script-tagline">Crafted for Indian Boutiques ~</span>
          <span className="ld-copyright">
            © {new Date().getFullYear()} LiveDrop Technologies. All rights reserved.
          </span>
        </div>
      </footer>

      {/* 8. Persistent Mobile Bottom Dock */}
      <MobileBottomDock />
    </div>
  );
}
