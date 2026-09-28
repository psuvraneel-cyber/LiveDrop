'use client';

import React from 'react';

export interface CategoryItem {
  id: string;
  label: string;
  image?: string;
}

export const DEFAULT_CATEGORY_CHIPS: CategoryItem[] = [
  { id: 'all', label: 'All' },
  { id: 'sarees', label: 'Sarees' },
  { id: 'kurtis', label: 'Kurtis' },
  { id: 'lehengas', label: 'Lehengas' },
  { id: 'dupattas', label: 'Dupattas' },
  { id: 'jewellery', label: 'Jewellery' },
  { id: 'accessories', label: 'Accessories' },
];

function CategoryGlyph({ id }: { id: string }) {
  switch (id) {
    case 'sarees':
      return (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M4 19c2-4 4-8 8-10s8-2 8-2" />
          <path d="M4 15c2-3 4-6 8-8s8-1 8-1" />
          <path d="M4 22c3-4 6-9 10-12s6-3 6-3" />
          <circle cx="6" cy="6" r="2" />
        </svg>
      );
    case 'kurtis':
      return (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M6 3h12l3 6-4 2v10H7V11L3 9l3-6z" />
          <path d="M10 3a2 2 0 0 0 4 0" />
        </svg>
      );
    case 'lehengas':
      return (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M9 4h6l6 15a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1L9 4z" />
          <path d="M8 12c2 1 6 1 8 0" />
          <path d="M6 16c3 1 9 1 12 0" />
        </svg>
      );
    case 'dupattas':
      return (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M3 8c4-2 7 2 11 0s5-4 7-2v8c-3-2-6 2-10 0s-6-4-8-2V8z" />
        </svg>
      );
    case 'jewellery':
      return (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M6 3h12l4 6-10 12L2 9l4-6z" />
          <path d="M2 9h20" />
          <path d="m10 3 2 6-2 12" />
          <path d="m14 3-2 6 2 12" />
        </svg>
      );
    case 'accessories':
      return (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M12 2v20M2 12h20" />
          <circle cx="12" cy="12" r="4" />
          <path d="m4.93 4.93 14.14 14.14M19.07 4.93 4.93 19.07" />
        </svg>
      );
    default:
      return (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <rect width="7" height="7" x="3" y="3" rx="1" />
          <rect width="7" height="7" x="14" y="3" rx="1" />
          <rect width="7" height="7" x="14" y="14" rx="1" />
          <rect width="7" height="7" x="3" y="14" rx="1" />
        </svg>
      );
  }
}

export interface CategoryRailProps {
  categories?: CategoryItem[];
  selectedCategory?: string;
  onSelectCategory?: (id: string) => void;
}

export function CategoryRail({
  categories = DEFAULT_CATEGORY_CHIPS,
  selectedCategory = 'all',
  onSelectCategory,
}: CategoryRailProps) {
  return (
    <section
      className="w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4 border-b border-white/5"
      aria-label="Product Categories"
    >
      <div
        className="flex items-center gap-3.5 overflow-x-auto pb-1 scrollbar-none"
        role="tablist"
        data-testid="category-chips-rail"
      >
        {categories.map((cat) => {
          const isAll = cat.id === 'all';
          const isSelected = selectedCategory === cat.id;

          return (
            <button
              key={cat.id}
              type="button"
              role="tab"
              aria-selected={isSelected}
              onClick={() => onSelectCategory?.(cat.id)}
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
                  <svg
                    width="22"
                    height="22"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    aria-hidden="true"
                  >
                    <rect width="7" height="7" x="3" y="3" rx="1" />
                    <rect width="7" height="7" x="14" y="3" rx="1" />
                    <rect width="7" height="7" x="14" y="14" rx="1" />
                    <rect width="7" height="7" x="3" y="14" rx="1" />
                  </svg>
                </div>
              ) : (
                <div
                  className={`relative w-12 h-12 rounded-full overflow-hidden border-2 transition-all flex items-center justify-center ${
                    isSelected
                      ? 'border-[#D4AF37] bg-[#1a1712] text-[#D4AF37] ring-2 ring-[#D4AF37]/40 scale-105'
                      : 'border-white/15 bg-[#121214] text-[#AAA49A] hover:border-white/40 hover:text-white'
                  }`}
                >
                  {cat.image ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={cat.image}
                      alt={cat.label}
                      className="w-full h-full object-cover"
                      loading="lazy"
                    />
                  ) : (
                    <CategoryGlyph id={cat.id} />
                  )}
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
  );
}
