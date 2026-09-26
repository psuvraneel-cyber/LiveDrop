'use client';

/**
 * LiveDrop — Haute Couture Filters Bottom Sheet (Screen 05)
 *
 * Implements full-fidelity mobile filter drawer from docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 17:
 * - Top center pull handle
 * - Header: Close '✕' on left, 'Filters' serif title, 'Clear All' gold link on right
 * - Category chips ('All', 'Sarees', 'Kurtis', 'Lehengas', 'Dupattas', 'Jewellery', 'Accessories')
 * - Price Range slider with dynamic currency labels ('₹0' to '₹50,000')
 * - Availability chips ('All', 'Available', 'Reserved', 'Sold')
 * - Size selector chips ('Free Size', 'XS', 'S', 'M', 'L', 'XL', 'XXL')
 * - Sticky bottom CTA: 'Show X Pieces →'
 */

import React, { useState } from 'react';
import { formatPaisaToINR } from '../../lib/utils/currency';

export interface FilterState {
  category: string | null;
  priceRange: [number, number]; // in Paisa
  availability: 'all' | 'in_stock' | 'reserved' | 'sold';
  sizes: string[];
}

export interface FilterSheetProps {
  isOpen: boolean;
  onClose: () => void;
  filters: FilterState;
  onApplyFilters: (filters: FilterState) => void;
  availableCategories?: string[];
  availableSizes?: string[];
  maxPricePaisa?: number;
  totalMatchingPieces?: number;
}

const DEFAULT_CATEGORIES = [
  'All',
  'Sarees',
  'Kurtis',
  'Lehengas',
  'Dupattas',
  'Jewellery',
  'Accessories',
];

const DEFAULT_SIZES = ['Free Size', 'XS', 'S', 'M', 'L', 'XL', 'XXL'];

export function FilterSheet({
  isOpen,
  onClose,
  filters,
  onApplyFilters,
  availableCategories = DEFAULT_CATEGORIES,
  availableSizes = DEFAULT_SIZES,
  maxPricePaisa = 5000000, // ₹50,000 default max
  totalMatchingPieces = 12,
}: FilterSheetProps) {
  const [localFilters, setLocalFilters] = useState<FilterState>(filters);
  const [prevFilters, setPrevFilters] = useState<FilterState>(filters);

  if (prevFilters !== filters) {
    setPrevFilters(filters);
    setLocalFilters(filters);
  }

  if (!isOpen) return null;

  const handleCategorySelect = (cat: string) => {
    setLocalFilters((prev) => ({
      ...prev,
      category: cat === 'All' ? null : cat.toLowerCase(),
    }));
  };

  const handleAvailabilitySelect = (status: 'all' | 'in_stock' | 'reserved' | 'sold') => {
    setLocalFilters((prev) => ({
      ...prev,
      availability: status,
    }));
  };

  const handleSizeToggle = (size: string) => {
    setLocalFilters((prev) => {
      const exists = prev.sizes.includes(size);
      return {
        ...prev,
        sizes: exists ? prev.sizes.filter((s) => s !== size) : [...prev.sizes, size],
      };
    });
  };

  const handleClearAll = () => {
    setLocalFilters({
      category: null,
      priceRange: [0, maxPricePaisa],
      availability: 'all',
      sizes: [],
    });
  };

  const handleApply = () => {
    onApplyFilters(localFilters);
    onClose();
  };

  const isCategorySelected = (cat: string) => {
    if (cat === 'All') return localFilters.category === null;
    return localFilters.category?.toLowerCase() === cat.toLowerCase();
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/75 backdrop-blur-sm animate-in fade-in duration-200"
      onClick={onClose}
      data-testid="filter-sheet-backdrop"
      role="dialog"
      aria-modal="true"
      aria-labelledby="filter-sheet-title"
    >
      <div
        className="w-full max-w-lg bg-[#0E0E12] border-t sm:border border-[rgba(212,175,55,0.25)] rounded-t-3xl sm:rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh] sm:max-h-[85vh] animate-in slide-in-from-bottom duration-300"
        onClick={(e) => e.stopPropagation()}
        data-testid="filter-sheet"
      >
        {/* Top Drag Handle */}
        <div className="pt-3 pb-1 flex justify-center sm:hidden">
          <div className="w-10 h-1 bg-white/20 rounded-full" />
        </div>

        {/* Header Bar */}
        <div className="px-5 py-3 flex items-center justify-between border-b border-white/10">
          <button
            type="button"
            onClick={onClose}
            className="w-8 h-8 rounded-full bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 hover:text-white transition-colors cursor-pointer text-sm font-sans"
            aria-label="Close filters"
            data-testid="filter-sheet-close-btn"
          >
            ✕
          </button>

          <h2
            id="filter-sheet-title"
            className="text-lg font-serif tracking-wide text-[#FBFBFB] font-medium"
          >
            Filters
          </h2>

          <button
            type="button"
            onClick={handleClearAll}
            className="text-xs font-sans font-semibold text-[#D4AF37] hover:text-[#E5C158] transition-colors cursor-pointer"
            data-testid="filter-clear-all-btn"
          >
            Clear All
          </button>
        </div>

        {/* Scrollable Filter Form Controls */}
        <div className="overflow-y-auto px-5 py-4 space-y-6">
          {/* 1. Category */}
          <div className="space-y-2.5">
            <h3 className="text-xs font-sans font-semibold tracking-wider text-white/90 uppercase">
              Category
            </h3>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Filter by Category">
              {availableCategories.map((cat) => {
                const active = isCategorySelected(cat);
                return (
                  <button
                    key={cat}
                    type="button"
                    onClick={() => handleCategorySelect(cat)}
                    className={`px-3.5 py-1.5 rounded-full text-xs font-medium transition-all cursor-pointer ${
                      active
                        ? 'bg-[#D4AF37] text-[#08080A] font-bold shadow-md'
                        : 'bg-[#16161C] text-[#AAA49A] hover:text-white border border-white/10'
                    }`}
                    aria-pressed={active}
                    data-testid={`filter-cat-${cat.toLowerCase()}`}
                  >
                    {cat}
                  </button>
                );
              })}
            </div>
          </div>

          {/* 2. Price Range */}
          <div className="space-y-2.5">
            <div className="flex items-center justify-between">
              <h3 className="text-xs font-sans font-semibold tracking-wider text-white/90 uppercase">
                Price Range
              </h3>
              <span className="text-xs font-mono text-[#D4AF37] font-semibold">
                {formatPaisaToINR(localFilters.priceRange[0])} — {formatPaisaToINR(localFilters.priceRange[1])}
              </span>
            </div>
            <div className="px-1 pt-1">
              <input
                type="range"
                min={0}
                max={maxPricePaisa}
                step={50000} // ₹500 increments
                value={localFilters.priceRange[1]}
                onChange={(e) => {
                  const val = Number(e.target.value);
                  setLocalFilters((prev) => ({
                    ...prev,
                    priceRange: [prev.priceRange[0], val],
                  }));
                }}
                className="w-full accent-[#D4AF37] bg-white/10 rounded-lg h-1.5 cursor-pointer"
                data-testid="filter-price-slider"
                aria-label="Maximum Price"
              />
              <div className="flex justify-between text-[11px] text-[#AAA49A] pt-1.5 font-mono">
                <span>₹0</span>
                <span>{formatPaisaToINR(maxPricePaisa)}</span>
              </div>
            </div>
          </div>

          {/* 3. Availability */}
          <div className="space-y-2.5">
            <h3 className="text-xs font-sans font-semibold tracking-wider text-white/90 uppercase">
              Availability
            </h3>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Filter by Availability">
              {[
                { id: 'all', label: 'All' },
                { id: 'in_stock', label: 'Available' },
                { id: 'reserved', label: 'Reserved' },
                { id: 'sold', label: 'Sold' },
              ].map((item) => {
                const active = localFilters.availability === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    onClick={() => handleAvailabilitySelect(item.id as FilterState['availability'])}
                    className={`px-3.5 py-1.5 rounded-full text-xs font-medium transition-all cursor-pointer ${
                      active
                        ? 'bg-[#D4AF37] text-[#08080A] font-bold shadow-md'
                        : 'bg-[#16161C] text-[#AAA49A] hover:text-white border border-white/10'
                    }`}
                    aria-pressed={active}
                    data-testid={`filter-avail-${item.id}`}
                  >
                    {item.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* 4. Size */}
          <div className="space-y-2.5">
            <h3 className="text-xs font-sans font-semibold tracking-wider text-white/90 uppercase">
              Size
            </h3>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Filter by Size">
              {availableSizes.map((size) => {
                const active = localFilters.sizes.includes(size);
                return (
                  <button
                    key={size}
                    type="button"
                    onClick={() => handleSizeToggle(size)}
                    className={`px-3 py-1.5 rounded-full text-xs font-medium transition-all cursor-pointer ${
                      active
                        ? 'bg-[#D4AF37] text-[#08080A] font-bold shadow-md'
                        : 'bg-[#16161C] text-[#AAA49A] hover:text-white border border-white/10'
                    }`}
                    aria-pressed={active}
                    data-testid={`filter-size-${size.toLowerCase().replace(/\s+/g, '-')}`}
                  >
                    {size}
                  </button>
                );
              })}
            </div>
          </div>
        </div>

        {/* Sticky Bottom Apply Action Bar */}
        <div className="p-4 border-t border-white/10 bg-[#0E0E12] flex items-center justify-center">
          <button
            type="button"
            onClick={handleApply}
            className="w-full py-3 rounded-xl bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] font-sans font-bold text-sm tracking-wide shadow-lg transition-all hover:scale-[1.01] active:scale-[0.99] flex items-center justify-center gap-2 cursor-pointer"
            data-testid="filter-apply-btn"
          >
            <span>Show {totalMatchingPieces} Pieces</span>
            <span aria-hidden="true">→</span>
          </button>
        </div>
      </div>
    </div>
  );
}
