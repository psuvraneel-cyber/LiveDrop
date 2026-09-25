'use client';

/**
 * LiveDrop — Commerce-First Shop Page
 *
 * Full-fidelity implementation matching product-first principles:
 * - Product-oriented search & category filters (All, Sarees, Kurtis, Lehengas, Dupattas, Jewelry, Accessories)
 * - Immediate 2-column mobile / 4-column desktop Product Grid
 * - Zero giant full-screen category banner artwork
 * - Secondary Verified Ateliers discovery rail at bottom
 * - Zero bottom dock overlap
 */

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import { PublicProductView, PublicSellerStorefront } from '../../types/domain';
import { filterProductionProducts, filterProductionStorefronts } from '../../lib/data/buyer-catalog';
import { LuxuryTopHeader } from '../navigation/LuxuryTopHeader';
import { MobileBottomDock } from '../navigation/MobileBottomDock';
import { ProductCard } from '../ProductCard';

export interface ShopCategoryDirectoryProps {
  storefronts?: PublicSellerStorefront[];
  initialProducts?: PublicProductView[];
}

const CATEGORY_TABS = [
  { id: 'all', label: 'All' },
  { id: 'sarees', label: 'Sarees' },
  { id: 'kurtis', label: 'Kurtis' },
  { id: 'lehengas', label: 'Lehengas' },
  { id: 'dupattas', label: 'Dupattas' },
  { id: 'jewelry', label: 'Jewelry' },
  { id: 'accessories', label: 'Accessories' },
];

export function ShopCategoryDirectory({
  storefronts = [],
  initialProducts = [],
}: ShopCategoryDirectoryProps) {
  const [activeTab, setActiveTab] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'featured' | 'price-asc' | 'price-desc'>('featured');

  // Filter products by category tab and search query with production hygiene
  const filteredProducts = useMemo(() => {
    let list = filterProductionProducts(initialProducts);

    if (activeTab !== 'all') {
      const tabKeyword = activeTab.toLowerCase();
      list = list.filter((p) => {
        const title = (p.title || '').toLowerCase();
        const code = (p.code || '').toLowerCase();
        return title.includes(tabKeyword) || code.includes(tabKeyword);
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

    if (sortBy === 'price-asc') {
      list.sort((a, b) => a.price_paisa - b.price_paisa);
    } else if (sortBy === 'price-desc') {
      list.sort((a, b) => b.price_paisa - a.price_paisa);
    }

    return list;
  }, [initialProducts, activeTab, searchQuery, sortBy]);

  const filteredBoutiques = useMemo(() => {
    const valid = filterProductionStorefronts(storefronts);
    if (!searchQuery.trim()) return valid;
    const q = searchQuery.toLowerCase().trim();
    return valid.filter(
      (s) =>
        s.store_name.toLowerCase().includes(q) ||
        s.store_slug.toLowerCase().includes(q)
    );
  }, [storefronts, searchQuery]);

  return (
    <div
      className="ld-has-bottom-dock min-h-screen bg-[#090909] text-[#F4F1EA] font-sans"
      data-testid="shop-category-directory"
    >
      {/* 1. Header */}
      <LuxuryTopHeader
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      <main className="max-w-6xl mx-auto px-4 sm:px-8 pt-4 sm:pt-6 space-y-6 sm:space-y-8">
        {/* Page Title & Breadcrumb */}
        <div className="space-y-1">
          <div className="flex items-center gap-2 text-xs text-[#AAA49A]">
            <Link href="/" className="hover:text-white transition-colors">Home</Link>
            <span>/</span>
            <span className="text-[#F4F1EA]">Shop Catalog</span>
          </div>
          <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3 pt-1">
            <div>
              <h1 className="text-2xl sm:text-4xl font-serif text-[#F4F1EA] tracking-wide">
                Boutique Collections
              </h1>
              <p className="text-xs sm:text-sm text-[#AAA49A]">
                {filteredProducts.length} pieces available from verified ateliers
              </p>
            </div>

            {/* Sort Dropdown */}
            <div className="flex items-center gap-2">
              <label htmlFor="shop-sort" className="text-xs text-[#AAA49A] whitespace-nowrap">
                Sort by:
              </label>
              <select
                id="shop-sort"
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as 'featured' | 'price-asc' | 'price-desc')}
                className="bg-[#121211] border border-white/10 rounded-lg px-3 py-1.5 text-xs text-[#F4F1EA] focus:outline-none focus:border-[#C79A45] cursor-pointer"
              >
                <option value="featured">Featured / Latest</option>
                <option value="price-asc">Price: Low to High</option>
                <option value="price-desc">Price: High to Low</option>
              </select>
            </div>
          </div>
        </div>

        {/* 2. Category Horizontal Filter Tabs */}
        <div
          className="flex gap-2 overflow-x-auto pb-2 scrollbar-none"
          role="tablist"
        >
          {CATEGORY_TABS.map((tab) => (
            <button
              key={tab.id}
              type="button"
              role="tab"
              data-testid={`shop-category-${tab.id}`}
              aria-selected={activeTab === tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-1.5 rounded-full text-xs font-medium tracking-wide transition-all whitespace-nowrap cursor-pointer ${
                activeTab === tab.id
                  ? 'active bg-[#C79A45] text-[#090909] font-bold shadow-md'
                  : 'bg-white/5 text-[#AAA49A] hover:bg-white/10 hover:text-white border border-white/5'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* 3. Product-First Grid (2-column mobile, 4-column desktop) */}
        <section aria-label="Available Garments Catalog">
          {filteredProducts.length > 0 ? (
            <div className="ld-product-grid" data-testid="shop-product-grid">
              {filteredProducts.map((product) => (
                <ProductCard
                  key={product.id}
                  product={product}
                  dropId={product.drop_id}
                />
              ))}
            </div>
          ) : (
            <div className="py-16 px-4 text-center rounded-2xl bg-[#121211] border border-white/5 space-y-3">
              <p className="text-base text-[#F4F1EA] font-medium">
                No pieces found
              </p>
              <p className="text-xs text-[#AAA49A] max-w-sm mx-auto">
                {searchQuery
                  ? `No garments matched your search for "${searchQuery}". Try searching for sarees, kurtis, or specific flash codes like #A01.`
                  : `No pieces currently listed under ${activeTab}. Explore other categories or check back during live drops.`}
              </p>
              {(activeTab !== 'all' || searchQuery) && (
                <button
                  type="button"
                  onClick={() => {
                    setActiveTab('all');
                    setSearchQuery('');
                  }}
                  className="px-4 py-2 rounded-full bg-white/10 hover:bg-white/15 text-xs text-white font-medium transition-all"
                >
                  Clear Filters
                </button>
              )}
            </div>
          )}
        </section>

        {/* 4. Secondary Verified Independent Boutiques Directory Rail */}
        {filteredBoutiques.length > 0 && (
          <section className="pt-8 sm:pt-12 space-y-4 border-t border-white/5" aria-label="Verified Designer Boutiques">
            <div className="flex items-center justify-between pb-2">
              <h2 className="text-lg sm:text-xl font-serif text-[#F4F1EA] tracking-wide">
                Verified Ateliers
              </h2>
              <span className="text-xs text-[#AAA49A]">
                {filteredBoutiques.length} Boutiques
              </span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 sm:gap-4">
              {filteredBoutiques.map((sf) => (
                <Link
                  key={sf.id}
                  href={`/${sf.store_slug}`}
                  className="p-4 rounded-xl bg-[#121211] border border-white/5 hover:border-[rgba(199,154,69,0.35)] flex items-center justify-between transition-all group shadow-sm"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-[#181715] border border-[#C79A45]/30 flex items-center justify-center font-serif font-bold text-sm text-[#C79A45] shadow-sm group-hover:scale-105 transition-transform">
                      {sf.store_name.charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-sm font-semibold text-white group-hover:text-[#E2C27A] transition-colors">
                          {sf.store_name}
                        </span>
                        <span className="text-[#C79A45] text-xs">✓</span>
                      </div>
                      <span className="text-[11px] text-[#AAA49A]">
                        Independent Atelier
                        <span className="sr-only">/{sf.store_slug}</span>
                      </span>
                    </div>
                  </div>

                  <span className="text-xs text-[#C79A45] font-semibold group-hover:translate-x-1 transition-transform">
                    Visit →
                  </span>
                </Link>
              ))}
            </div>
          </section>
        )}
      </main>

      {/* 5. Bottom Navigation Dock */}
      <MobileBottomDock />
    </div>
  );
}
