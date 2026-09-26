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
import { filterProductionStorefronts, filterProductionProducts } from '../lib/data/buyer-catalog';
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
  { id: 'all', label: 'All' },
  { id: 'sarees', label: 'Sarees' },
  { id: 'kurtis', label: 'Kurtis' },
  { id: 'lehengas', label: 'Lehengas' },
  { id: 'dupattas', label: 'Dupattas' },
  { id: 'jewellery', label: 'Jewellery' },
  { id: 'accessories', label: 'Accessories' },
];

const CATEGORY_IMAGES: Record<string, string> = {
  all: '',
  sarees: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?w=120&auto=format&fit=crop&q=80',
  kurtis: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?w=120&auto=format&fit=crop&q=80',
  lehengas: 'https://images.unsplash.com/photo-1595777457583-95e059d581b8?w=120&auto=format&fit=crop&q=80',
  dupattas: 'https://images.unsplash.com/photo-1609357605129-26f69add5d6e?w=120&auto=format&fit=crop&q=80',
  jewellery: 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?w=120&auto=format&fit=crop&q=80',
  accessories: 'https://images.unsplash.com/photo-1611591475852-5a48d88e0a81?w=120&auto=format&fit=crop&q=80',
};

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

  // Combined product feed from prop or initialProducts, filtered for production hygiene
  const allAvailableProducts = useMemo(() => {
    let list = [...featuredProducts];
    if (list.length === 0 && initialProducts.length > 0) {
      list = initialProducts.filter((p) => p.status === 'available');
    }
    return filterProductionProducts(list);
  }, [featuredProducts, initialProducts]);

  // Filtered products by category chip & search query
  const displayedProducts = useMemo(() => {
    let list = allAvailableProducts;

    if (selectedCategory !== 'all') {
      const cat = selectedCategory.toLowerCase();
      list = list.filter((p) => {
        const text = `${p.title || ''} ${p.code || ''} ${p.description || ''}`.toLowerCase();
        if (cat === 'sarees') return text.includes('saree');
        if (cat === 'kurtis') return text.includes('kurti');
        if (cat === 'lehengas') return text.includes('lehenga');
        if (cat === 'dupattas') return text.includes('dupatta');
        if (cat === 'jewellery' || cat === 'jewelry') return text.includes('jewel');
        if (cat === 'accessories') return text.includes('access');
        return text.includes(cat);
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
  const heroBackground =
    primaryLiveDrop?.hero_image_url ||
    (allAvailableProducts.length > 0 ? allAvailableProducts[0].image_url : null);

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

      {/* 2. Inset Haute-Couture Live Drop Spotlight Hero (Screen 01 Reference) */}
      <div className="w-full max-w-6xl mx-auto px-4 pt-3 pb-2">
        <section
          id="live-drops"
          className="relative w-full h-[320px] sm:h-[360px] md:h-[400px] flex items-end overflow-hidden rounded-2xl border border-white/10 bg-[#121211] scroll-mt-16 shadow-2xl"
          aria-label="LiveDrop Spotlight Hero"
          data-testid={hasActiveLiveDrop ? "live-drop-hero" : "spotlight-hero"}
        >
          <div className="absolute inset-0 pointer-events-none">
            {heroBackground ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={heroBackground}
                alt={hasActiveLiveDrop && primaryLiveDrop ? primaryLiveDrop.title : 'LiveDrop Spotlight'}
                className="w-full h-full object-cover object-top sm:object-center brightness-60 transition-transform duration-700"
              />
            ) : (
              <div className="w-full h-full bg-gradient-to-br from-[#1b1613] via-[#121211] to-[#090909]" />
            )}
            <div className="absolute inset-0 bg-gradient-to-t from-[#08080A] via-[#08080A]/60 to-transparent" />
            <div className="absolute inset-0 bg-gradient-to-r from-[#08080A]/85 via-transparent to-transparent" />
          </div>

          <div className="relative w-full p-4 sm:p-6 flex flex-col justify-end">
            <div className="max-w-xl space-y-2">
              {/* Live Indicator or Eyebrow */}
              {hasActiveLiveDrop && primaryLiveDrop ? (
                <div className="inline-flex items-center gap-2">
                  <span className="inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full bg-[#EF4444] text-white font-mono font-bold text-[10px] tracking-wider uppercase shadow-md">
                    <span className="w-1.5 h-1.5 rounded-full bg-white animate-pulse" />
                    LIVE NOW
                  </span>
                </div>
              ) : null}

              {/* Headline */}
              <h1 className="text-2xl sm:text-3xl md:text-4xl font-serif text-[#FBFBFB] tracking-wide leading-tight">
                {hasActiveLiveDrop && primaryLiveDrop
                  ? primaryLiveDrop.title
                  : 'NO LIVE DROP'}
              </h1>

              {/* Subtitle / Boutique Attribution */}
              <p className="text-xs sm:text-sm text-[#F4F1EA]/80 font-sans max-w-md leading-snug">
                {hasActiveLiveDrop && primaryLiveDrop
                  ? `${primaryLiveDrop.profiles?.store_name || 'Independent Boutique'}`
                  : 'Explore pieces from independent boutiques.'}
              </p>

              {/* Luxury Feature Tags (Screen 01) */}
              <div className="flex flex-wrap items-center gap-1.5 pt-0.5 pb-1">
                <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-black/50 backdrop-blur-md border border-white/10 text-[10px] text-white/90">
                  <span className="text-[#D4AF37]">✦</span> Live shopping
                </span>
                <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-black/50 backdrop-blur-md border border-white/10 text-[10px] text-white/90">
                  <span className="text-[#D4AF37]">✦</span> Exclusive pieces
                </span>
                <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-black/50 backdrop-blur-md border border-white/10 text-[10px] text-white/90">
                  <span className="text-[#D4AF37]">✦</span> Handpicked
                </span>
              </div>

              {/* Action CTA & Pagination Dots Row */}
              <div className="pt-1 flex items-center justify-between">
                {hasActiveLiveDrop && primaryLiveDrop ? (
                  <Link
                    href={`/drop/${primaryLiveDrop.slug}`}
                    className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] text-xs sm:text-sm font-bold tracking-wide transition-all shadow-lg hover:scale-[1.02] active:scale-[0.98]"
                    data-testid="shop-live-hero-btn"
                  >
                    <span>Shop Live Drop</span>
                    <span aria-hidden="true">→</span>
                  </Link>
                ) : (
                  <Link
                    href="/shop"
                    className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] text-xs sm:text-sm font-bold tracking-wide transition-all shadow-lg hover:scale-[1.02] active:scale-[0.98]"
                    data-testid="explore-live-shows-btn"
                  >
                    <span>Shop Collections</span>
                    <span aria-hidden="true">→</span>
                  </Link>
                )}

                {/* Slider pagination indicators (Screen 01) */}
                <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-black/40 backdrop-blur-sm border border-white/10 text-[10px] text-white/70">
                  <span className="w-1.5 h-1.5 rounded-full bg-[#D4AF37]" />
                  <span className="w-1.5 h-1.5 rounded-full bg-white/40" />
                  <span className="w-1.5 h-1.5 rounded-full bg-white/40" />
                  <span className="ml-1 font-mono text-[9px]">1/4</span>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>

      {/* 3. Category Discovery Rail (Screen 01: Square 'All' card + circular photo avatars) */}
      <section
        className="w-full max-w-6xl mx-auto px-4 sm:px-8 py-4 border-b border-white/5"
        aria-label="Product Categories"
      >
        <div
          className="flex items-center gap-3.5 overflow-x-auto pb-1 scrollbar-none"
          role="tablist"
          data-testid="category-chips-rail"
        >
          {CATEGORY_CHIPS.map((cat) => {
            const isAll = cat.id === 'all';
            const isSelected = selectedCategory === cat.id;
            const categoryImage = CATEGORY_IMAGES[cat.id];

            return (
              <button
                key={cat.id}
                type="button"
                role="tab"
                aria-selected={isSelected}
                onClick={() => setSelectedCategory(cat.id)}
                className={`flex flex-col items-center gap-1.5 transition-transform flex-shrink-0 cursor-pointer ${
                  isSelected ? 'scale-105 active' : 'opacity-85 hover:opacity-100'
                }`}
                data-testid={`category-chip-${cat.id}`}
              >
                {isAll ? (
                  <div
                    className={`w-12 h-12 rounded-xl flex items-center justify-center shadow-md transition-all ${
                      isSelected
                        ? 'bg-[#D4AF37] text-[#08080A] ring-2 ring-[#D4AF37]/50'
                        : 'bg-[#16161C] text-[#D4AF37] border border-white/10'
                    }`}
                  >
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <rect width="7" height="7" x="3" y="3" rx="1" />
                      <rect width="7" height="7" x="14" y="3" rx="1" />
                      <rect width="7" height="7" x="14" y="14" rx="1" />
                      <rect width="7" height="7" x="3" y="14" rx="1" />
                    </svg>
                  </div>
                ) : (
                  <div
                    className={`relative w-12 h-12 rounded-full overflow-hidden border-2 transition-all ${
                      isSelected
                        ? 'border-[#D4AF37] ring-2 ring-[#D4AF37]/40 scale-105'
                        : 'border-white/15 hover:border-white/40'
                    }`}
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={categoryImage}
                      alt={cat.label}
                      className="w-full h-full object-cover"
                      loading="lazy"
                    />
                  </div>
                )}
                <span
                  className={`text-[11px] font-sans tracking-wide whitespace-nowrap ${
                    isSelected ? 'text-[#D4AF37] font-semibold' : 'text-[#AAA49A]'
                  }`}
                >
                  {cat.label}
                </span>
              </button>
            );
          })}
        </div>
      </section>

      {/* Main Content Area */}
      <main className="max-w-6xl mx-auto px-4 sm:px-8 py-6 sm:py-10 space-y-10 sm:space-y-14">
        {/* 4. Featured Products Section (2-col mobile, 4-col desktop) */}
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
              data-testid="featured-view-all-btn"
            >
              View All →
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

        {/* 5. Live & Verified Boutiques Discovery Rail (Horizontal scroll-snap on mobile) */}
        <section id="boutiques" className="space-y-3 scroll-mt-24" aria-label="Live Boutiques" data-testid="boutiques-directory-section">
          <div className="flex items-center justify-between border-b border-white/10 pb-2.5">
            <div>
              <h2 className="text-lg sm:text-xl font-serif text-[#F4F1EA] tracking-wide">
                Live Boutiques
              </h2>
              <span className="text-xs text-[#AAA49A]">
                {filteredStorefronts.length} independent ateliers
              </span>
            </div>
            <Link
              href="/shop"
              className="text-xs sm:text-sm text-[#C79A45] hover:text-[#E2C27A] font-sans font-medium transition-colors"
              data-testid="boutiques-view-all-btn"
            >
              View All →
            </Link>
          </div>

          {filteredStorefronts.length > 0 ? (
            <div className="flex sm:grid sm:grid-cols-2 lg:grid-cols-3 gap-3 overflow-x-auto pb-2 scrollbar-none snap-x snap-mandatory">
              {filteredStorefronts.map((boutique) => {
                const isLive = resolvedActiveDrops.some(
                  (d) =>
                    d.seller_id === boutique.id ||
                    (d.profiles?.store_name &&
                      d.profiles.store_name.toLowerCase() === boutique.store_name.toLowerCase())
                );

                return (
                  <div
                    key={boutique.id}
                    className="flex-shrink-0 w-64 sm:w-auto p-3.5 rounded-xl bg-[#121211] border border-white/5 hover:border-[rgba(199,154,69,0.3)] transition-all flex flex-col justify-between gap-3 shadow-sm snap-start"
                    data-testid={`boutique-card-${boutique.store_slug}`}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex items-center gap-2.5 min-w-0">
                        <div className="w-9 h-9 rounded-full bg-[#181715] border border-[#C79A45]/30 flex items-center justify-center text-[#C79A45] font-serif font-bold text-sm flex-shrink-0">
                          {boutique.store_name[0]?.toUpperCase() || 'B'}
                        </div>
                        <div className="min-w-0">
                          <div className="flex items-center gap-1">
                            <h3 className="text-xs sm:text-sm font-semibold text-white truncate">
                              {boutique.store_name}
                            </h3>
                            <span className="text-[#C79A45] text-xs flex-shrink-0" title="Verified">✓</span>
                          </div>
                          <span className="text-[11px] text-[#AAA49A] block truncate">
                            Independent Boutique
                          </span>
                        </div>
                      </div>

                      {isLive && (
                        <span
                          className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-[#E5484D]/15 border border-[#E5484D]/40 text-[#E5484D] text-[10px] font-mono font-bold uppercase tracking-wider flex-shrink-0"
                          data-testid={`boutique-live-badge-${boutique.store_slug}`}
                        >
                          <span className="w-1.5 h-1.5 rounded-full bg-[#E5484D] animate-pulse" />
                          LIVE
                        </span>
                      )}
                    </div>

                    <div className="flex items-center justify-between pt-2 border-t border-white/5">
                      <Link
                        href={`/${boutique.store_slug}`}
                        className="text-xs text-[#C79A45] hover:text-[#E2C27A] font-semibold transition-colors flex items-center gap-1 group"
                        data-testid={`visit-boutique-${boutique.store_slug}`}
                      >
                        <span>Visit</span>
                        <span aria-hidden="true" className="group-hover:translate-x-0.5 transition-transform">→</span>
                      </Link>
                      <a
                        href={getBoutiqueWhatsAppUrl(boutique.phone_number, boutique.store_name)}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-xs text-[#25D366] hover:text-[#2fe671] p-1 transition-colors"
                        title="WhatsApp Boutique"
                        aria-label={`WhatsApp ${boutique.store_name}`}
                        data-testid={`whatsapp-store-${boutique.store_slug}`}
                      >
                        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                          <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
                        </svg>
                      </a>
                    </div>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="py-6 px-4 text-center rounded-xl bg-[#121211] border border-white/5" data-testid="boutiques-empty-state">
              <p className="text-xs text-[#AAA49A]">
                {searchQuery ? `No boutiques matching "${searchQuery}".` : 'Independent boutiques will be featured here soon.'}
              </p>
            </div>
          )}
        </section>

        {/* 7. Compact Restrained Trust Strip */}
        <section
          className="py-4 px-4 rounded-xl bg-[#121211] border border-white/5 text-center"
          aria-label="Buyer Trust Assurances"
        >
          <div className="flex flex-wrap items-center justify-center gap-x-4 gap-y-1.5 text-xs text-[#AAA49A]">
            <span className="text-[#C79A45] font-medium tracking-wide">Direct UPI</span>
            <span className="text-white/20">•</span>
            <span className="text-[#C79A45] font-medium tracking-wide">Instant Reservation</span>
            <span className="text-white/20">•</span>
            <span className="text-[#C79A45] font-medium tracking-wide">Independent Boutiques</span>
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
