'use client';

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
    imageUrl: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=1000&q=80',
    actionText: 'Explore Sarees',
  },
  {
    id: 'lehengas',
    tag: 'HAUTE BRIDAL',
    title: 'Lehengas',
    tagline: 'For every grand celebration',
    imageUrl: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?auto=format&fit=crop&w=1000&q=80',
    actionText: 'Explore Lehengas',
  },
  {
    id: 'jewelry',
    tag: 'ROYAL HEIRLOOMS',
    title: 'Jewelry',
    tagline: 'Heirlooms reimagined for the modern patron',
    imageUrl: 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=1000&q=80',
    actionText: 'Explore Jewelry',
  },
  {
    id: 'mens-couture',
    tag: 'CONTEMPORARY ROYALTY',
    title: "Men's Couture",
    tagline: 'Tradition with a sharp, modern edge',
    imageUrl: 'https://images.unsplash.com/photo-1594938298603-c8148c4dae35?auto=format&fit=crop&w=1000&q=80',
    actionText: "Explore Men's Couture",
  },
  {
    id: 'accessories',
    tag: 'COUTURE ACCENTS',
    title: 'Accessories',
    tagline: 'The definitive finishing touch',
    imageUrl: 'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=1000&q=80',
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
      className="min-h-screen bg-[#08080A] text-[#FBFBFB] pb-24 font-sans select-none"
      data-testid="shop-category-directory"
    >
      {/* 1. Header */}
      <LuxuryTopHeader
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      <main className="max-w-4xl mx-auto px-4 pt-4 sm:pt-6 space-y-6">
        {/* Page Title & Subtitle */}
        <div className="text-center space-y-2 pt-2">
          <span className="text-[#D4AF37] text-xs font-semibold tracking-widest uppercase">
            ✦ Curated Collections ✦
          </span>
          <h1 className="text-2xl sm:text-3xl font-serif text-[#FBFBFB] tracking-wide">
            Couture by Category
          </h1>
          <p className="text-xs sm:text-sm text-white/60 max-w-md mx-auto leading-relaxed">
            Discover singular handcrafted Indian couture direct from independent master designers and ateliers.
          </p>
        </div>

        {/* Category Horizontal Filter Tabs */}
        <div
          className="flex gap-2 overflow-x-auto pb-2 scrollbar-none justify-start sm:justify-center"
          role="tablist"
        >
          {TABS.map((tab) => (
            <button
              key={tab.id}
              type="button"
              role="tab"
              aria-selected={activeTab === tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`px-4 py-1.5 rounded-full text-xs font-medium tracking-wide transition-all whitespace-nowrap cursor-pointer ${
                activeTab === tab.id
                  ? 'bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] font-bold shadow-md shadow-[rgba(212,175,55,0.25)]'
                  : 'bg-white/5 text-white/70 hover:bg-white/10 hover:text-white border border-white/5'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* 2. Full-Width Editorial Category Cards (Screen 2 Mockup) */}
        <section className="space-y-4" aria-label="Featured Categories">
          {filteredCategories.map((cat) => (
            <div
              key={cat.id}
              className="relative w-full h-56 sm:h-72 rounded-2xl overflow-hidden border border-[rgba(212,175,55,0.25)] shadow-xl group cursor-pointer"
            >
              <Image
                src={cat.imageUrl}
                alt={cat.title}
                fill
                className="object-cover group-hover:scale-105 transition-transform duration-700 brightness-75"
                sizes="(max-width: 768px) 100vw, 800px"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40 to-transparent" />

              <div className="absolute inset-0 p-5 sm:p-7 flex flex-col justify-end">
                <span className="text-[#D4AF37] text-[10px] sm:text-xs font-mono font-bold tracking-widest uppercase mb-1">
                  {cat.tag}
                </span>
                <h3 className="text-xl sm:text-3xl font-serif text-[#FBFBFB] tracking-wide mb-1">
                  {cat.title}
                </h3>
                <p className="text-xs sm:text-sm text-white/70 font-sans mb-3 max-w-sm">
                  {cat.tagline}
                </p>

                <div>
                  <Link
                    href={`/#boutiques`}
                    className="inline-flex items-center gap-1.5 px-4 py-2 rounded-full bg-black/60 backdrop-blur-md border border-[rgba(212,175,55,0.4)] text-[#FBFBFB] hover:text-[#D4AF37] text-xs font-semibold tracking-wider uppercase transition-colors"
                  >
                    <span>{cat.actionText}</span>
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                      <line x1="5" y1="12" x2="19" y2="12" />
                      <polyline points="12 5 19 12 12 19" />
                    </svg>
                  </Link>
                </div>
              </div>
            </div>
          ))}
        </section>

        {/* 3. Verified Independent Boutiques Directory */}
        {filteredBoutiques.length > 0 && (
          <section className="pt-6 space-y-4" aria-label="Verified Designer Boutiques">
            <div className="flex items-center justify-between border-b border-white/5 pb-2">
              <h2 className="text-lg font-serif text-[#FBFBFB] tracking-wide">
                Verified Ateliers
              </h2>
              <span className="text-xs text-[#D4AF37] font-mono">
                {filteredBoutiques.length} Boutiques
              </span>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
              {filteredBoutiques.map((sf) => (
                <Link
                  key={sf.id}
                  href={`/${sf.store_slug}`}
                  className="p-4 rounded-xl bg-[#0E0E12] border border-white/10 hover:border-[rgba(212,175,55,0.4)] flex items-center justify-between transition-all group"
                >
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-[rgba(212,175,55,0.15)] text-[#D4AF37] border border-[rgba(212,175,55,0.3)] flex items-center justify-center font-serif font-bold text-sm">
                      {sf.store_name.charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-sm font-medium text-white group-hover:text-[#D4AF37] transition-colors">
                          {sf.store_name}
                        </span>
                        <span className="text-[#D4AF37] text-xs">✓</span>
                      </div>
                      <span className="text-xs text-white/50 font-mono">
                        /{sf.store_slug}
                      </span>
                    </div>
                  </div>

                  <span className="text-xs text-[#D4AF37] font-semibold group-hover:translate-x-1 transition-transform">
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
