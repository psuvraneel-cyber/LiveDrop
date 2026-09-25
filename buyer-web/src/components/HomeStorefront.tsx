'use client';

/**
 * LiveDrop — Commerce-First Home Storefront
 *
 * Designed to user specification:
 * - Compact ~360-480px Hero (45-60% vh max) with safe padding and concise headline
 * - Truthful Live Drop spotlight (State 1: Real Live Drop, State 2: Clean No-Live state)
 * - Zero hardcoded/fake drops, fake viewer stats, or fake designers
 * - Compact horizontal Category Rail (50-60px height) replacing oversized story circles
 * - Prominent 2-column mobile / 4-column desktop Featured Products grid
 * - Horizontal Live & Verified Boutiques discovery rail
 * - Restrained trust assurance footer
 * - Zero global select-none
 */

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import { PublicDropCatalog, PublicProductView, PublicSellerStorefront } from '../types/domain';
import { filterProductionStorefronts } from '../lib/data/buyer-catalog';
import { normalizeIndianPhoneNumber } from './BoutiqueStorefrontView';
import { LuxuryTopHeader } from './navigation/LuxuryTopHeader';
import { MobileBottomDock } from './navigation/MobileBottomDock';
import { ProductCard } from './ProductCard';

export interface HomeStorefrontProps {
  activeDrops?: PublicDropCatalog[];
  storefronts?: PublicSellerStorefront[];
  featuredProducts?: PublicProductView[];
  initialLiveDrop?: PublicDropCatalog | null;
  initialProducts?: PublicProductView[];
  recentDrops?: PublicDropCatalog[];
}

const CATEGORY_CHIPS = [
  { id: 'all', label: 'All Pieces' },
  { id: 'sarees', label: 'Sarees' },
  { id: 'kurtis', label: 'Kurtis' },
  { id: 'lehengas', label: 'Lehengas' },
  { id: 'dupattas', label: 'Dupattas' },
  { id: 'jewelry', label: 'Jewelry' },
  { id: 'accessories', label: 'Accessories' },
];

export function HomeStorefront({
  activeDrops = [],
  storefronts = [],
  featuredProducts = [],
  initialLiveDrop,
  initialProducts = [],
  recentDrops = [],
}: HomeStorefrontProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('all');

  // 1. Resolved active live drops: either passed in or inferred from initialLiveDrop
  const resolvedActiveDrops = useMemo(() => {
    if (activeDrops && activeDrops.length > 0) return activeDrops;
    if (initialLiveDrop && initialLiveDrop.status === 'live') return [initialLiveDrop];
    return [];
  }, [activeDrops, initialLiveDrop]);

  // 2. Resolved storefronts: extract, then filter production deterministically
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

  // 3. Filtered boutiques based on search query
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

  // Combined product feed from prop or initialProducts
  const allAvailableProducts = useMemo(() => {
    const list = [...featuredProducts];
    if (list.length === 0 && initialProducts.length > 0) {
      return initialProducts.filter((p) => p.status === 'available');
    }
    return list;
  }, [featuredProducts, initialProducts]);

  // Filtered products by category chip & search query
  const displayedProducts = useMemo(() => {
    let list = allAvailableProducts;

    if (selectedCategory !== 'all') {
      const cat = selectedCategory.toLowerCase();
      list = list.filter((p) => {
        const title = (p.title || '').toLowerCase();
        const code = (p.code || '').toLowerCase();
        return title.includes(cat) || code.includes(cat);
      });
    }

    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      list = list.filter((p) => {
        const title = (p.title || '').toLowerCase();
        const code = (p.code || '').toLowerCase();
        return title.includes(q) || code.includes(q);
      });
    }

    return list;
  }, [allAvailableProducts, selectedCategory, searchQuery]);

  const getBoutiqueWhatsAppUrl = (phone: string | null | undefined, name: string) => {
    const targetPhone = normalizeIndianPhoneNumber(phone);
    const text = `Hi ${name}, I discovered your boutique on LiveDrop!`;
    if (targetPhone) {
      return `https://wa.me/${targetPhone}?text=${encodeURIComponent(text)}`;
    }
    return `https://wa.me/?text=${encodeURIComponent(text)}`;
  };

  const hasActiveLiveDrop = filteredActiveDrops.length > 0;
  const primaryLiveDrop = hasActiveLiveDrop ? filteredActiveDrops[0] : null;

  return (
    <div
      className="ld-home-storefront ld-has-bottom-dock min-h-screen bg-[#090909] text-[#F4F1EA] font-sans"
      data-testid="platform-home"
    >
      {/* 1. Header with Search & Bag */}
      <LuxuryTopHeader
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      {/* 2. Compact Live Drop Spotlight Hero (~360–460px mobile, max 50–55vh) */}
      <section
        className="relative w-full h-[360px] sm:h-[420px] md:h-[460px] flex items-center overflow-hidden border-b border-white/10 bg-[#121211]"
        aria-label="LiveDrop Spotlight Hero"
        data-testid={hasActiveLiveDrop ? "live-drop-hero" : "spotlight-hero"}
      >
        <div className="absolute inset-0 pointer-events-none">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={
              primaryLiveDrop?.hero_image_url ||
              'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?auto=format&fit=crop&w=1600&q=80'
            }
            alt="LiveDrop Boutique Spotlight"
            className="w-full h-full object-cover object-top sm:object-center brightness-65 transition-transform duration-700"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-[#090909] via-[#090909]/60 to-transparent" />
          <div className="absolute inset-0 bg-gradient-to-r from-[#090909]/90 via-[#090909]/40 to-transparent" />
        </div>

        <div className="relative max-w-6xl mx-auto px-5 sm:px-8 w-full flex flex-col justify-end pb-8 sm:pb-12">
          <div className="max-w-xl space-y-3 sm:space-y-4">
            {/* Live Indicator or Eyebrow */}
            <div className="inline-flex items-center gap-2">
              {hasActiveLiveDrop && primaryLiveDrop ? (
                <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[#E5484D] text-white font-mono font-bold text-[11px] tracking-wider uppercase shadow-md">
                  <span className="w-2 h-2 rounded-full bg-white animate-pulse" />
                  LIVE NOW
                </span>
              ) : (
                <span className="text-[11px] sm:text-xs font-mono font-bold tracking-[0.2em] text-[#C79A45] uppercase">
                  BOUTIQUE COMMERCE
                </span>
              )}
            </div>

            {/* Concise Headline */}
            <h1 className="text-3xl sm:text-5xl font-serif text-[#F4F1EA] tracking-wide leading-tight">
              {hasActiveLiveDrop && primaryLiveDrop
                ? primaryLiveDrop.title
                : 'No Live Drop Right Now'}
            </h1>

            {/* Subtitle */}
            <p className="text-xs sm:text-sm text-[#AAA49A] font-sans max-w-md leading-relaxed">
              {hasActiveLiveDrop && primaryLiveDrop
                ? `Presented by ${primaryLiveDrop.profiles?.store_name || 'Independent Boutique'}. Single-piece exclusive drops reserve instantly.`
                : 'Explore the latest pieces from independent boutiques.'}
            </p>

            {/* Action CTA */}
            <div className="pt-2">
              {hasActiveLiveDrop && primaryLiveDrop ? (
                <Link
                  href={`/drop/${primaryLiveDrop.slug}`}
                  className="inline-flex items-center gap-2 px-6 py-3 rounded-full bg-gradient-to-r from-[#E2C27A] via-[#C79A45] to-[#B58632] text-[#090909] text-xs sm:text-sm font-bold tracking-wide transition-all shadow-lg hover:scale-[1.02] active:scale-[0.98]"
                  data-testid="shop-live-hero-btn"
                >
                  <span>Shop Live Drop</span>
                  <span aria-hidden="true">→</span>
                </Link>
              ) : (
                <Link
                  href="/shop"
                  className="inline-flex items-center gap-2 px-6 py-3 rounded-full bg-gradient-to-r from-[#E2C27A] via-[#C79A45] to-[#B58632] text-[#090909] text-xs sm:text-sm font-bold tracking-wide transition-all shadow-lg hover:scale-[1.02] active:scale-[0.98]"
                  data-testid="explore-live-shows-btn"
                >
                  <span>Explore Collections</span>
                  <span aria-hidden="true">→</span>
                </Link>
              )}
            </div>
          </div>
        </div>
      </section>

      {/* 3. Compact Horizontal Category Rail (~50–65px height) */}
      <section
        className="px-4 sm:px-8 py-4 border-b border-white/5 bg-[#121211]/60 sticky top-16 z-20 backdrop-blur-md"
        aria-label="Product Categories"
      >
        <div
          className="max-w-6xl mx-auto flex items-center gap-2 overflow-x-auto pb-1 scrollbar-none"
          role="tablist"
          data-testid="category-chips-rail"
        >
          {CATEGORY_CHIPS.map((cat) => (
            <button
              key={cat.id}
              type="button"
              role="tab"
              aria-selected={selectedCategory === cat.id}
              onClick={() => setSelectedCategory(cat.id)}
              className={`px-4 py-1.5 rounded-full text-xs font-medium tracking-wide transition-all whitespace-nowrap cursor-pointer ${
                selectedCategory === cat.id
                  ? 'active bg-[#C79A45] text-[#090909] font-bold shadow-md'
                  : 'bg-white/5 text-[#AAA49A] hover:bg-white/10 hover:text-white border border-white/5'
              }`}
              data-testid={`category-chip-${cat.id}`}
            >
              {cat.label}
            </button>
          ))}
        </div>
      </section>

      {/* Main Content Area */}
      <main className="max-w-6xl mx-auto px-4 sm:px-8 py-8 sm:py-12 space-y-12 sm:space-y-16">
        {/* 4. Live Drops Spotlight Section (When Live) */}
        {hasActiveLiveDrop && primaryLiveDrop && (
          <section id="live-drops" className="space-y-4 scroll-mt-24" aria-label="Active Live Drop" data-testid="live-drops-section">
            <div className="flex items-center justify-between border-b border-white/10 pb-3">
              <div className="flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-[#E5484D] animate-pulse" />
                <h2 className="text-xl sm:text-2xl font-serif text-[#F4F1EA] tracking-wide">
                  Live Drop
                </h2>
              </div>
              <Link
                href={`/drop/${primaryLiveDrop.slug}`}
                className="text-xs sm:text-sm text-[#C79A45] hover:text-[#E2C27A] font-sans font-medium transition-colors"
              >
                Enter Room →
              </Link>
            </div>

            <div
              className="relative w-full h-56 sm:h-72 rounded-2xl overflow-hidden border border-[rgba(199,154,69,0.3)] shadow-lg group bg-[#121211]"
              data-testid={`live-drop-card-${primaryLiveDrop.slug}`}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={
                  primaryLiveDrop.hero_image_url ||
                  'https://images.unsplash.com/photo-1546804784-896d0dca3805?auto=format&fit=crop&w=1200&q=80'
                }
                alt={primaryLiveDrop.title}
                className="w-full h-full object-cover brightness-70 group-hover:scale-102 transition-transform duration-500"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40 to-transparent" />

              <div className="absolute bottom-0 inset-x-0 p-5 sm:p-6 flex items-end justify-between gap-4">
                <div className="space-y-1">
                  <span className="text-[11px] font-mono font-bold text-[#E2C27A] uppercase tracking-wider">
                    {primaryLiveDrop.profiles?.store_name || 'Boutique'}
                  </span>
                  <h3 className="text-lg sm:text-2xl font-serif text-white font-medium leading-tight">
                    {primaryLiveDrop.title}
                  </h3>
                </div>

                <Link
                  href={`/drop/${primaryLiveDrop.slug}`}
                  className="px-5 py-2.5 rounded-full bg-[#C79A45] hover:bg-[#E2C27A] text-[#090909] font-bold text-xs tracking-wide transition-all shadow-md flex-shrink-0"
                >
                  Join Drop →
                </Link>
              </div>
            </div>
          </section>
        )}

        {/* 5. Featured Products Section (2-col mobile, 4-col desktop) */}
        <section id="featured-products" className="space-y-4" aria-label="Featured Products" data-testid="featured-products-section">
          <div className="flex items-center justify-between border-b border-white/10 pb-3">
            <div>
              <h2 className="text-xl sm:text-2xl font-serif text-[#F4F1EA] tracking-wide">
                {selectedCategory === 'all'
                  ? 'Featured Pieces'
                  : `${selectedCategory.charAt(0).toUpperCase() + selectedCategory.slice(1)}`}
              </h2>
              <span className="text-xs text-[#AAA49A]">
                {displayedProducts.length} pieces available
              </span>
            </div>
            <Link
              href="/shop"
              className="text-xs sm:text-sm text-[#C79A45] hover:text-[#E2C27A] font-sans font-medium transition-colors"
            >
              View All Catalog →
            </Link>
          </div>

          {displayedProducts.length > 0 ? (
            <div className="ld-product-grid" data-testid="featured-products-grid">
              {displayedProducts.slice(0, 12).map((product) => (
                <ProductCard
                  key={product.id}
                  product={product}
                  dropId={product.drop_id}
                />
              ))}
            </div>
          ) : (
            <div className="py-12 px-4 text-center rounded-2xl bg-[#121211] border border-white/5 space-y-2">
              <p className="text-sm text-[#AAA49A]">
                {searchQuery
                  ? `No pieces found matching "${searchQuery}".`
                  : 'New collection pieces dropping soon from verified boutiques.'}
              </p>
              <Link
                href="/shop"
                className="inline-block text-xs text-[#C79A45] hover:underline font-medium"
              >
                Browse all categories in shop →
              </Link>
            </div>
          )}
        </section>

        {/* 6. Live & Verified Boutiques Discovery Rail */}
        <section id="boutiques" className="space-y-4 scroll-mt-24" aria-label="Live Boutiques" data-testid="boutiques-directory-section">
          <div className="flex items-center justify-between border-b border-white/10 pb-3">
            <div>
              <h2 className="text-xl sm:text-2xl font-serif text-[#F4F1EA] tracking-wide">
                Live Boutiques
              </h2>
              <span className="text-xs text-[#AAA49A]">
                {filteredStorefronts.length} independent ateliers
              </span>
            </div>
            <Link
              href="/shop"
              className="text-xs sm:text-sm text-[#C79A45] hover:text-[#E2C27A] font-sans font-medium transition-colors"
            >
              Explore All →
            </Link>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4">
            {filteredStorefronts.map((boutique) => (
              <div
                key={boutique.id}
                className="p-4 sm:p-5 rounded-xl bg-[#121211] border border-white/5 hover:border-[rgba(199,154,69,0.3)] transition-all flex flex-col justify-between"
                data-testid={`boutique-card-${boutique.store_slug}`}
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-[#181715] border border-[#C79A45]/30 flex items-center justify-center text-[#C79A45] font-serif font-bold text-sm">
                      {boutique.store_name[0]?.toUpperCase() || 'B'}
                    </div>
                    <div>
                      <div className="flex items-center gap-1">
                        <h3 className="text-sm font-semibold text-white">
                          {boutique.store_name}
                        </h3>
                        <span className="text-[#C79A45] text-xs">✓</span>
                      </div>
                      <span className="text-xs text-[#AAA49A] font-mono">
                        /{boutique.store_slug}
                      </span>
                    </div>
                  </div>

                  <Link
                    href={`/${boutique.store_slug}`}
                    className="text-xs text-[#C79A45] hover:text-[#E2C27A] font-semibold flex items-center gap-1 transition-colors flex-shrink-0"
                    data-testid={`visit-boutique-${boutique.store_slug}`}
                  >
                    <span>Visit →</span>
                  </Link>
                </div>

                <div className="pt-3 border-t border-white/5 flex items-center justify-between mt-3 text-xs text-[#AAA49A]">
                  <span>Single-piece drops</span>
                  <a
                    href={getBoutiqueWhatsAppUrl(boutique.phone_number, boutique.store_name)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-[#25D366] hover:underline flex items-center gap-1 font-medium"
                    data-testid={`whatsapp-store-${boutique.store_slug}`}
                  >
                    <span>WhatsApp</span>
                  </a>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* 7. Restrained Trust & Value Assurances */}
        <section className="p-6 rounded-2xl bg-[#121211] border border-white/5" aria-label="Buyer Assurances">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 text-center sm:text-left">
            <div className="space-y-1">
              <span className="text-[#C79A45] text-base font-bold font-mono">01. Direct UPI</span>
              <h4 className="text-sm font-semibold text-white">Direct Peer-to-Peer</h4>
              <p className="text-xs text-[#AAA49A] leading-relaxed">
                Pay boutique sellers directly to their verified UPI address with zero platform markups.
              </p>
            </div>
            <div className="space-y-1">
              <span className="text-[#C79A45] text-base font-bold font-mono">02. Instant Reserve</span>
              <h4 className="text-sm font-semibold text-white">Single-Piece Hold</h4>
              <p className="text-xs text-[#AAA49A] leading-relaxed">
                Atomic database reservations guarantee that one-of-a-kind sarees are locked to your order.
              </p>
            </div>
            <div className="space-y-1">
              <span className="text-[#C79A45] text-base font-bold font-mono">03. Verified Ateliers</span>
              <h4 className="text-sm font-semibold text-white">Independent Boutiques</h4>
              <p className="text-xs text-[#AAA49A] leading-relaxed">
                Curated independent designers with direct WhatsApp concierge for order support.
              </p>
            </div>
          </div>
        </section>
      </main>

      {/* 8. Restrained Footer */}
      <footer className="border-t border-white/5 py-8 px-4 text-center text-xs text-[#AAA49A] space-y-2">
        <p className="font-serif text-sm text-[#F4F1EA]">LiveDrop</p>
        <p>Live commerce for independent Indian fashion boutiques.</p>
        <p className="font-mono text-[11px] text-white/30">© {new Date().getFullYear()} LiveDrop Technologies</p>
      </footer>

      {/* 9. 5-Tab Navigation Dock */}
      <MobileBottomDock />
    </div>
  );
}
