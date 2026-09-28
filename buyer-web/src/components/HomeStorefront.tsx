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
import { LuxuryTopHeader } from './navigation/LuxuryTopHeader';
import { MobileBottomDock } from './navigation/MobileBottomDock';
import { Hero } from './Hero';
import { CategoryRail } from './CategoryRail';
import { ProductCard } from './ProductCard';
import { BoutiqueCard } from './BoutiqueCard';
import { SectionTitle } from './SectionTitle';
import { TrustStrip } from './TrustStrip';
import { Footer } from './Footer';

export interface HomeStorefrontProps {
  activeDrops?: PublicDropCatalog[];
  storefronts?: PublicSellerStorefront[];
  featuredProducts?: PublicProductView[];
  initialLiveDrop?: PublicDropCatalog | null;
  initialProducts?: PublicProductView[];
  recentDrops?: PublicDropCatalog[];
}

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

      {/* 2. Inset Haute-Couture Live Drop Spotlight Hero */}
      <Hero
        activeDrop={primaryLiveDrop}
        hasActiveLiveDrop={hasActiveLiveDrop}
      />

      {/* 3. Category Discovery Rail */}
      <CategoryRail
        selectedCategory={selectedCategory}
        onSelectCategory={setSelectedCategory}
      />

      {/* Main Content Area */}
      <main className="ld-home-main max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-10 space-y-10 sm:space-y-14">
        {/* 4. Featured Products Section (2-col mobile, 4-col desktop) */}
        <section
          id="featured-products"
          className="space-y-4"
          aria-label="Featured Products"
          data-testid="featured-products-section"
        >
          <SectionTitle
            title={
              selectedCategory === 'all'
                ? 'Featured Pieces'
                : `${selectedCategory.charAt(0).toUpperCase() + selectedCategory.slice(1)}`
            }
            subtitle={`${displayedProducts.length} pieces available`}
            actionHref="/shop"
            actionLabel="View All →"
            actionTestId="featured-view-all-btn"
          />

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

        {/* 5. Live & Verified Boutiques Discovery Rail */}
        <section
          id="boutiques"
          className="space-y-4 scroll-mt-24"
          aria-label="Live Boutiques"
          data-testid="boutiques-directory-section"
        >
          <SectionTitle
            title="Live Boutiques"
            subtitle={`${filteredStorefronts.length} independent ateliers`}
            actionHref="/shop"
            actionLabel="View All →"
            actionTestId="boutiques-view-all-btn"
          />

          {filteredStorefronts.length > 0 ? (
            <div className="flex sm:grid sm:grid-cols-2 lg:grid-cols-3 gap-3.5 sm:gap-4 lg:gap-5 overflow-x-auto sm:overflow-visible pb-2 sm:pb-0 scrollbar-none snap-x snap-mandatory">
              {filteredStorefronts.map((boutique) => {
                const isLive = resolvedActiveDrops.some(
                  (d) =>
                    d.seller_id === boutique.id ||
                    (d.profiles?.store_name &&
                      d.profiles.store_name.toLowerCase() === boutique.store_name.toLowerCase())
                );

                return (
                  <BoutiqueCard
                    key={boutique.id}
                    boutique={boutique}
                    isLive={isLive}
                  />
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
        <TrustStrip />
      </main>

      {/* 8. Restrained Luxury Footer */}
      <Footer />

      {/* 9. 5-Tab Navigation Dock */}
      <MobileBottomDock />
    </div>
  );
}
