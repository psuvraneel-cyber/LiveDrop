'use client';

/**
 * LiveDrop — Screen 2: Haute Couture Shop by Category
 *
 * Full-fidelity implementation of the category directory:
 * - Curated luxury photography for Indian Couture categories
 * - Responsive 1-column mobile / 2-column desktop editorial cards
 * - Verified Ateliers directory
 * - Zero bottom dock clipping
 */

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { PublicSellerStorefront } from '../../types/domain';
import { LuxuryTopHeader } from '../navigation/LuxuryTopHeader';
import { MobileBottomDock } from '../navigation/MobileBottomDock';

export interface ShopCategoryDirectoryProps {
  storefronts?: PublicSellerStorefront[];
}

interface EditorialCategory {
  id: string;
  tag: string;
  title: string;
  tagline: string;
  imageUrl: string;
  actionText: string;
}

const EDITORIAL_CATEGORIES: EditorialCategory[] = [
  {
    id: 'sarees',
    tag: 'HANDLOOM & HERITAGE',
    title: 'Sarees',
    tagline: 'Timeless drapes for every era',
    imageUrl: 'https://images.unsplash.com/photo-1617627143750-d86bc21e42bb?auto=format&fit=crop&w=1000&q=80',
    actionText: 'Explore Sarees',
  },
  {
    id: 'lehengas',
    tag: 'HAUTE BRIDAL',
    title: 'Lehengas',
    tagline: 'For every grand celebration',
    imageUrl: 'https://images.unsplash.com/photo-1595777457583-95e059d581b8?auto=format&fit=crop&w=1000&q=80',
    actionText: 'Explore Lehengas',
  },
  {
    id: 'jewelry',
    tag: 'ROYAL HEIRLOOMS',
    title: 'Jewelry',
    tagline: 'Heirlooms reimagined for the modern patron',
    imageUrl: 'https://images.unsplash.com/photo-1599643478518-a784e5dc4c8f?auto=format&fit=crop&w=1000&q=80',
    actionText: 'Explore Jewelry',
  },
  {
    id: 'mens-couture',
    tag: 'CONTEMPORARY ROYALTY',
    title: "Men's Couture",
    tagline: 'Tradition with a sharp, modern edge',
    imageUrl: 'https://images.unsplash.com/photo-1621609764095-b32bbe35cf3a?auto=format&fit=crop&w=1000&q=80',
    actionText: "Explore Men's Couture",
  },
  {
    id: 'accessories',
    tag: 'COUTURE ACCENTS',
    title: 'Accessories',
    tagline: 'The definitive finishing touch',
    imageUrl: 'https://images.unsplash.com/photo-1584917865442-de89df76afd3?auto=format&fit=crop&w=1000&q=80',
    actionText: 'Explore Accessories',
  },
];

const TABS = [
  { id: 'all', label: 'All' },
  { id: 'sarees', label: 'Sarees' },
  { id: 'lehengas', label: 'Lehengas' },
  { id: 'jewelry', label: 'Jewelry' },
  { id: 'mens-couture', label: "Men's Couture" },
  { id: 'accessories', label: 'Accessories' },
];

export function ShopCategoryDirectory({
  storefronts = [],
}: ShopCategoryDirectoryProps) {
  const [activeTab, setActiveTab] = useState('all');
  const [searchQuery, setSearchQuery] = useState('');

  const filteredCategories = useMemo(() => {
    let list = EDITORIAL_CATEGORIES;
    if (activeTab !== 'all') {
      list = list.filter((c) => c.id === activeTab);
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      list = list.filter(
        (c) =>
          c.title.toLowerCase().includes(q) ||
          c.tagline.toLowerCase().includes(q) ||
          c.tag.toLowerCase().includes(q)
      );
    }
    return list;
  }, [activeTab, searchQuery]);

  const filteredBoutiques = useMemo(() => {
    if (!searchQuery.trim()) return storefronts;
    const q = searchQuery.toLowerCase().trim();
    return storefronts.filter(
      (s) =>
        s.store_name.toLowerCase().includes(q) ||
        s.store_slug.toLowerCase().includes(q)
    );
  }, [storefronts, searchQuery]);

  return (
    <div
      className="ld-has-bottom-dock min-h-screen bg-[#08080A] text-[#FBFBFB] pb-36 sm:pb-24 font-sans select-none"
      data-testid="shop-category-directory"
    >
      {/* 1. Header */}
      <LuxuryTopHeader
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      <main className="max-w-6xl mx-auto px-4 sm:px-8 pt-6 sm:pt-8 space-y-8 sm:space-y-12">
        {/* Page Title & Subtitle */}
        <div className="text-center space-y-2 pt-2">
          <span className="text-[#D4AF37] text-xs font-mono font-bold tracking-[0.25em] uppercase">
            ✦ CURATED COLLECTIONS ✦
          </span>
          <h1 className="text-3xl sm:text-5xl font-serif text-[#FBFBFB] tracking-wide">
            Couture by Category
          </h1>
          <p className="text-xs sm:text-base text-white/60 max-w-lg mx-auto leading-relaxed">
            Discover singular handcrafted Indian couture direct from independent master designers and ateliers.
          </p>
        </div>

        {/* Category Horizontal Filter Tabs */}
        <div
          className="flex gap-2.5 overflow-x-auto pb-2 scrollbar-none justify-start sm:justify-center"
          role="tablist"
        >
          {TABS.map((tab) => (
            <button
              key={tab.id}
              type="button"
              role="tab"
              aria-selected={activeTab === tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-5 py-2 rounded-full text-xs font-medium tracking-wide transition-all whitespace-nowrap cursor-pointer ${
                activeTab === tab.id
                  ? 'bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] font-bold shadow-lg shadow-[rgba(212,175,55,0.25)]'
                  : 'bg-white/5 text-white/70 hover:bg-white/10 hover:text-white border border-white/5'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* 2. Full-Width Editorial Category Cards (Screen 2 Mockup) */}
        <section className="grid grid-cols-1 md:grid-cols-2 gap-5 sm:gap-6" aria-label="Featured Categories">
          {filteredCategories.map((cat) => (
            <div
              key={cat.id}
              className="relative w-full h-64 sm:h-80 rounded-3xl overflow-hidden border border-[rgba(212,175,55,0.2)] shadow-xl group"
            >
              <Image
                src={cat.imageUrl}
                alt={cat.title}
                fill
                className="object-cover group-hover:scale-105 transition-transform duration-700 brightness-75"
                sizes="(max-width: 768px) 100vw, 800px"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40 to-transparent" />

              <div className="absolute inset-0 p-6 sm:p-8 flex flex-col justify-end">
                <span className="text-[#D4AF37] text-[10px] sm:text-xs font-mono font-bold tracking-widest uppercase mb-1.5">
                  {cat.tag}
                </span>
                <h3 className="text-2xl sm:text-3xl font-serif text-[#FBFBFB] tracking-wide mb-1">
                  {cat.title}
                </h3>
                <p className="text-xs sm:text-sm text-white/70 font-sans mb-4 max-w-sm">
                  {cat.tagline}
                </p>

                <div>
                  <Link
                    href="/#boutiques"
                    className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-black/60 backdrop-blur-md border border-[rgba(212,175,55,0.4)] text-[#FBFBFB] hover:text-[#D4AF37] hover:border-[#D4AF37] text-xs font-semibold tracking-wide transition-all shadow-md group/btn"
                  >
                    <span>{cat.actionText}</span>
                    <span aria-hidden="true" className="group-hover/btn:translate-x-1 transition-transform">→</span>
                  </Link>
                </div>
              </div>
            </div>
          ))}
        </section>

        {/* 3. Verified Independent Boutiques Directory */}
        {filteredBoutiques.length > 0 && (
          <section className="pt-6 sm:pt-10 space-y-4 sm:space-y-6" aria-label="Verified Designer Boutiques">
            <div className="flex items-center justify-between border-b border-white/10 pb-3">
              <h2 className="text-xl sm:text-2xl font-serif text-[#FBFBFB] tracking-wide">
                Verified Ateliers
              </h2>
              <span className="text-xs sm:text-sm text-[#D4AF37] font-mono font-medium">
                {filteredBoutiques.length} Boutiques
              </span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
              {filteredBoutiques.map((sf) => (
                <Link
                  key={sf.id}
                  href={`/${sf.store_slug}`}
                  className="p-5 rounded-2xl bg-[#0E0E12] border border-white/10 hover:border-[rgba(212,175,55,0.35)] flex items-center justify-between transition-all group shadow-md"
                >
                  <div className="flex items-center gap-3.5">
                    <div className="w-11 h-11 rounded-full bg-gradient-to-br from-[#2A0811] to-[#15151B] border border-[#D4AF37]/40 flex items-center justify-center font-serif font-bold text-base text-[#D4AF37] shadow-sm group-hover:scale-105 transition-transform">
                      {sf.store_name.charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-base font-serif font-medium text-white group-hover:text-[#D4AF37] transition-colors">
                          {sf.store_name}
                        </span>
                        <span className="text-[#D4AF37] text-xs">✓</span>
                      </div>
                      <span className="text-xs text-white/50 font-mono">
                        /{sf.store_slug}
                      </span>
                    </div>
                  </div>

                  <span className="text-xs sm:text-sm text-[#D4AF37] font-semibold group-hover:translate-x-1 transition-transform">
                    Visit →
                  </span>
                </Link>
              ))}
            </div>
          </section>
        )}
      </main>

      {/* 4. Bottom Navigation Dock */}
      <MobileBottomDock />
    </div>
  );
}
