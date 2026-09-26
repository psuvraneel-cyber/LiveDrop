'use client';

/**
 * LiveDrop — Commerce-First Shop Page (Phase 4 Restructure)
 *
 * Full-fidelity implementation matching product-first principles:
 * - Product-oriented search & category filters (All, Sarees, Kurtis, Lehengas, Dupattas, Jewellery, Accessories)
 * - Singular/plural apparel keyword matching (Saree/Sarees, Kurti/Kurtis, etc.)
 * - Dedicated Control Bar: inline search, catalog pieces count, and luxury sort dropdown
 * - Immediate 2-column mobile / 4-5 column desktop Product Grid
 * - Section 31 compact empty state: "No pieces available" + "Explore Live Drops"
 * - Subordinate Secondary Verified Ateliers discovery rail at bottom
 * - Zero bottom dock overlap
 */

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import { PublicProductView, PublicSellerStorefront } from '../../types/domain';
import { filterProductionProducts, filterProductionStorefronts } from '../../lib/data/buyer-catalog';
import { LuxuryTopHeader } from '../navigation/LuxuryTopHeader';
import { MobileBottomDock } from '../navigation/MobileBottomDock';
import { ProductCard } from '../ProductCard';
import { FilterSheet, FilterState } from './FilterSheet';

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
  { id: 'jewellery', label: 'Jewellery' },
  { id: 'accessories', label: 'Accessories' },
];

export function ShopCategoryDirectory({
  storefronts = [],
  initialProducts = [],
}: ShopCategoryDirectoryProps) {
  const [activeTab, setActiveTab] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'featured' | 'price-asc' | 'price-desc'>('featured');
  const [isFilterSheetOpen, setIsFilterSheetOpen] = useState(false);
  const [filterState, setFilterState] = useState<FilterState>({
    category: null,
    priceRange: [0, 5000000],
    availability: 'all',
    sizes: [],
  });

  // Filter products by category tab, search query, price, availability, and sizes
  const filteredProducts = useMemo(() => {
    let list = filterProductionProducts(initialProducts);

    if (activeTab !== 'all') {
      const cat = activeTab.toLowerCase();
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

    // Filter by price range
    list = list.filter(
      (p) => p.price_paisa >= filterState.priceRange[0] && p.price_paisa <= filterState.priceRange[1]
    );

    // Filter by availability
    if (filterState.availability === 'in_stock') {
      list = list.filter((p) => p.status === 'available' || (p.quantity_available ?? 1) > 0);
    } else if (filterState.availability === 'reserved') {
      list = list.filter((p) => p.status === 'reserved');
    } else if (filterState.availability === 'sold') {
      list = list.filter((p) => p.status === 'sold');
    }

    // Filter by sizes
    if (filterState.sizes.length > 0) {
      list = list.filter((p) => {
        const text = `${p.title || ''} ${p.description || ''}`.toLowerCase();
        return filterState.sizes.some((size) => text.includes(size.toLowerCase()));
      });
    }

    if (sortBy === 'price-asc') {
      list.sort((a, b) => a.price_paisa - b.price_paisa);
    } else if (sortBy === 'price-desc') {
      list.sort((a, b) => b.price_paisa - a.price_paisa);
    }

    return list;
  }, [initialProducts, activeTab, searchQuery, sortBy, filterState]);

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
      className="ld-has-bottom-dock min-h-screen bg-[#090909] text-[#F4F1EA] font-sans w-full max-w-full overflow-x-clip"
      data-testid="shop-category-directory"
    >
      {/* 1. Canonical Shared Buyer Header */}
      <LuxuryTopHeader
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      <main className="w-full max-w-6xl mx-auto px-4 sm:px-8 pt-4 sm:pt-6 pb-12 space-y-6 sm:space-y-8 min-w-0">
        {/* 2. Breadcrumb & Page Title */}
        <div className="space-y-1">
          <div className="flex items-center gap-2 text-xs text-[#AAA49A]">
            <Link href="/" className="hover:text-white transition-colors">Home</Link>
            <span>/</span>
            <span className="text-[#F4F1EA]">Shop Catalog</span>
          </div>
          <div className="pt-1">
            <h1 className="text-2xl sm:text-4xl font-serif text-[#F4F1EA] tracking-wide">
              Boutique Collections
            </h1>
            <p className="text-xs sm:text-sm text-[#AAA49A]" data-testid="shop-catalog-subtitle">
              {filteredProducts.length} pieces available from verified boutiques
            </p>
          </div>
        </div>

        {/* 3. Dedicated Control Bar (Search, Count, Sort) */}
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3 p-3 rounded-xl bg-[#121211] border border-white/5 shadow-sm">
          <div className="flex items-center gap-2 flex-1 min-w-0">
            <div className="relative flex-1 max-w-md">
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search collection or flash code (#A01)..."
                aria-label="Filter products by title or flash code"
                data-testid="shop-search-input"
                className="w-full bg-[#181715] border border-white/10 rounded-lg px-3 py-1.5 text-xs text-[#F4F1EA] placeholder-[#AAA49A] focus:outline-none focus:border-[#C79A45] transition-colors"
              />
              {searchQuery && (
                <button
                  type="button"
                  onClick={() => setSearchQuery('')}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-xs text-[#AAA49A] hover:text-white"
                  aria-label="Clear search query"
                  data-testid="shop-search-clear-btn"
                >
                  ×
                </button>
              )}
            </div>
          </div>

          <div className="flex items-center justify-between sm:justify-end gap-3 flex-shrink-0">
            <span className="text-xs text-[#AAA49A]" data-testid="shop-pieces-count">
              <span className="font-semibold text-[#F4F1EA]">{filteredProducts.length}</span> pieces
            </span>

            <div className="flex items-center gap-1.5">
              <label htmlFor="shop-sort" className="text-xs text-[#AAA49A] whitespace-nowrap">
                Sort:
              </label>
              <select
                id="shop-sort"
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as 'featured' | 'price-asc' | 'price-desc')}
                data-testid="shop-sort-select"
                className="bg-[#181715] border border-white/10 rounded-lg px-2.5 py-1.5 text-xs text-[#F4F1EA] focus:outline-none focus:border-[#C79A45] cursor-pointer transition-colors"
              >
                <option value="featured">Featured / Latest</option>
                <option value="price-asc">Price: Low to High</option>
                <option value="price-desc">Price: High to Low</option>
              </select>
            </div>

            <button
              type="button"
              onClick={() => setIsFilterSheetOpen(true)}
              data-testid="shop-filter-btn"
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[#181715] hover:bg-white/10 text-xs text-[#F4F1EA] border border-white/10 transition-colors cursor-pointer"
              aria-label="Open filter sheet"
            >
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-[#C79A45]">
                <line x1="4" y1="21" x2="4" y2="14" />
                <line x1="4" y1="10" x2="4" y2="3" />
                <line x1="12" y1="21" x2="12" y2="12" />
                <line x1="12" y1="8" x2="12" y2="3" />
                <line x1="20" y1="21" x2="20" y2="16" />
                <line x1="20" y1="12" x2="20" y2="3" />
                <line x1="1" y1="14" x2="7" y2="14" />
                <line x1="9" y1="8" x2="15" y2="8" />
                <line x1="17" y1="16" x2="23" y2="16" />
              </svg>
              <span>Filter</span>
              {(filterState.category || filterState.priceRange[1] < 5000000 || filterState.availability !== 'all' || filterState.sizes.length > 0) && (
                <span className="w-1.5 h-1.5 rounded-full bg-[#D4AF37]" />
              )}
            </button>
          </div>
        </div>

        {/* 4. Category Horizontal Filter Tabs (Normal document flow, non-sticky) */}
        <div
          className="w-full max-w-full flex gap-2 overflow-x-auto pb-2 scrollbar-none min-w-0"
          role="tablist"
          data-testid="shop-category-tabs-rail"
        >
          {CATEGORY_TABS.map((tab) => (
            <button
              key={tab.id}
              type="button"
              role="tab"
              data-testid={tab.id === 'jewellery' ? 'shop-category-jewelry' : `shop-category-${tab.id}`}
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

        {/* 5. Product-First Grid (2-column mobile, 4-5 column desktop) */}
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
            <div className="py-12 px-4 text-center rounded-2xl bg-[#121211] border border-white/5 space-y-2.5" data-testid="shop-empty-state">
              <p className="text-base text-[#F4F1EA] font-serif font-medium">
                No pieces available
              </p>
              <p className="text-xs text-[#AAA49A] max-w-sm mx-auto">
                {searchQuery
                  ? `No garments matched "${searchQuery}". Explore another category or check back during live drops.`
                  : 'Explore another category or check back during live drops.'}
              </p>
              <div className="pt-2 flex items-center justify-center gap-3">
                {(activeTab !== 'all' || searchQuery) && (
                  <button
                    type="button"
                    onClick={() => {
                      setActiveTab('all');
                      setSearchQuery('');
                    }}
                    className="px-4 py-2 rounded-full bg-white/10 hover:bg-white/15 text-xs text-white font-medium transition-all"
                    data-testid="shop-clear-filters-btn"
                  >
                    Clear Filters
                  </button>
                )}
                <Link
                  href="/#live-drops"
                  className="px-4 py-2 rounded-full bg-[#C79A45] text-[#090909] text-xs font-bold transition-all hover:bg-[#E2C27A]"
                  data-testid="shop-explore-live-drops-btn"
                >
                  Explore Live Drops →
                </Link>
              </div>
            </div>
          )}
        </section>

        {/* 6. Secondary Verified Independent Boutiques Directory Rail */}
        {filteredBoutiques.length > 0 && (
          <section className="pt-8 sm:pt-10 space-y-3.5 border-t border-white/5" aria-label="Verified Designer Boutiques" data-testid="shop-boutiques-section">
            <div className="flex items-center justify-between pb-1">
              <div>
                <h2 className="text-base sm:text-lg font-serif text-[#F4F1EA] tracking-wide">
                  Verified Ateliers
                </h2>
                <span className="text-[11px] text-[#AAA49A]">
                  Discover independent boutiques featured on LiveDrop
                </span>
              </div>
              <span className="text-xs text-[#C79A45]">
                {filteredBoutiques.length} Boutiques
              </span>
            </div>

            <div className="w-full max-w-full flex sm:grid sm:grid-cols-2 lg:grid-cols-3 gap-3 overflow-x-auto pb-2 scrollbar-none snap-x snap-mandatory min-w-0">
              {filteredBoutiques.map((sf) => (
                <Link
                  key={sf.id}
                  href={`/${sf.store_slug}`}
                  className="relative flex-shrink-0 w-64 sm:w-auto p-3.5 rounded-xl bg-[#121211] border border-white/5 hover:border-[rgba(199,154,69,0.35)] flex items-center justify-between transition-all group shadow-sm snap-start"
                  data-testid={`shop-boutique-card-${sf.store_slug}`}
                >
                  <div className="flex items-center gap-2.5 min-w-0">
                    <div className="w-9 h-9 rounded-full bg-[#181715] border border-[#C79A45]/30 flex items-center justify-center font-serif font-bold text-sm text-[#C79A45] shadow-sm group-hover:scale-105 transition-transform flex-shrink-0">
                      {sf.store_name.charAt(0).toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <div className="flex items-center gap-1">
                        <span className="text-xs sm:text-sm font-semibold text-white group-hover:text-[#E2C27A] transition-colors truncate">
                          {sf.store_name}
                        </span>
                        <span className="text-[#C79A45] text-xs flex-shrink-0">✓</span>
                      </div>
                      <span className="relative text-[11px] text-[#AAA49A] block truncate">
                        Independent Atelier
                        <span className="sr-only">/{sf.store_slug}</span>
                      </span>
                    </div>
                  </div>

                  <span className="text-xs text-[#C79A45] font-semibold group-hover:translate-x-0.5 transition-transform flex-shrink-0 pl-2">
                    Visit →
                  </span>
                </Link>
              ))}
            </div>
          </section>
        )}
      </main>

      {/* 7. Haute Couture Filters Bottom Sheet Modal (Screen 05) */}
      <FilterSheet
        isOpen={isFilterSheetOpen}
        onClose={() => setIsFilterSheetOpen(false)}
        filters={filterState}
        onApplyFilters={(newFilters) => {
          setFilterState(newFilters);
          if (newFilters.category) {
            setActiveTab(newFilters.category);
          } else {
            setActiveTab('all');
          }
        }}
        totalMatchingPieces={filteredProducts.length}
      />

      {/* 8. Bottom Navigation Dock */}
      <MobileBottomDock />
    </div>
  );
}
