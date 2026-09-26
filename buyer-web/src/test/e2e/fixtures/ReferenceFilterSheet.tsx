'use client';

/**
 * ReferenceFilterSheet — Canonical Implementation of Screen 05 (Filter Sheet)
 *
 * Implements M2 interface contract from PROJECT.md and visual design specifications
 * from docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 17.
 */

import React, { useState } from 'react';
import { formatPaisaToINR } from '../../../lib/utils/currency';

export interface FilterState {
  category: string | null;
  priceRange: [number, number]; // in Paisa
  availability: 'all' | 'in_stock' | 'reserved';
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

export function ReferenceFilterSheet({
  isOpen,
  onClose,
  filters,
  onApplyFilters,
  availableCategories = DEFAULT_CATEGORIES,
  availableSizes = DEFAULT_SIZES,
  maxPricePaisa = 5000000, // ₹50,000 default max
  totalMatchingPieces = 4,
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

  const handleAvailabilitySelect = (status: 'all' | 'in_stock' | 'reserved') => {
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

  const handlePriceChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = Number(e.target.value);
    setLocalFilters((prev) => ({
      ...prev,
      priceRange: [0, val],
    }));
  };

  const handleClearAll = () => {
    setLocalFilters({
      category: null,
      priceRange: [0, maxPricePaisa],
      availability: 'all',
      sizes: [],
    });
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onApplyFilters(localFilters);
    onClose();
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Filter Sheet"
      data-testid="filter-sheet-modal"
      className="fixed inset-0 z-50 flex flex-col justify-end bg-black/60 backdrop-blur-sm"
    >
      <div
        className="w-full max-h-[90vh] bg-[#0E0E12] border-t border-[rgba(212,175,55,0.25)] rounded-t-2xl flex flex-col overflow-hidden text-[#FBFBFB] font-sans"
        data-testid="filter-sheet-container"
      >
        {/* Top center drag handle */}
        <div className="w-12 h-1 bg-white/20 rounded-full mx-auto mt-3" data-testid="filter-sheet-handle" />

        {/* Header */}
        <header className="flex items-center justify-between px-5 py-4 border-b border-white/5">
          <button
            type="button"
            onClick={onClose}
            aria-label="Close filters"
            data-testid="filter-sheet-close-btn"
            className="text-lg text-[#AAA49A] hover:text-white p-1"
          >
            ✕
          </button>
          <h2 className="text-lg font-serif tracking-wide text-[#FBFBFB]">Filters</h2>
          <button
            type="button"
            onClick={handleClearAll}
            data-testid="filter-sheet-clear-all-btn"
            className="text-xs text-[#D4AF37] hover:underline font-medium"
          >
            Clear All
          </button>
        </header>

        {/* Scrollable Filter Body */}
        <form onSubmit={handleSubmit} className="flex-1 overflow-y-auto px-5 py-4 space-y-6">
          {/* Category Section */}
          <div className="space-y-2.5">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-[#AAA49A]">Category</h3>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Filter by Category">
              {availableCategories.map((cat) => {
                const isSelected =
                  cat === 'All' ? localFilters.category === null : localFilters.category === cat.toLowerCase();
                return (
                  <button
                    key={cat}
                    type="button"
                    data-testid={`filter-category-${cat.toLowerCase()}`}
                    onClick={() => handleCategorySelect(cat)}
                    className={`px-3.5 py-1.5 rounded-full text-xs font-medium transition-all ${
                      isSelected
                        ? 'bg-[#D4AF37] text-black font-semibold'
                        : 'bg-[#16161C] border border-white/10 text-[#AAA49A]'
                    }`}
                  >
                    {cat}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Price Range Section */}
          <div className="space-y-2.5">
            <div className="flex justify-between items-center text-xs">
              <span className="font-semibold uppercase tracking-wider text-[#AAA49A]">Price Range</span>
              <span className="font-mono text-[#D4AF37]" data-testid="filter-price-display">
                Up to {formatPaisaToINR(localFilters.priceRange[1])}
              </span>
            </div>
            <input
              type="range"
              min="0"
              max={maxPricePaisa}
              step="10000" // ₹100 step
              value={localFilters.priceRange[1]}
              onChange={handlePriceChange}
              data-testid="filter-price-slider"
              aria-label="Maximum price in Paisa"
              className="w-full accent-[#D4AF37] bg-[#16161C] cursor-pointer"
            />
            <div className="flex justify-between text-[11px] text-[#AAA49A]">
              <span>₹0</span>
              <span>{formatPaisaToINR(maxPricePaisa)}</span>
            </div>
          </div>

          {/* Availability Section */}
          <div className="space-y-2.5">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-[#AAA49A]">Availability</h3>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Filter by Availability">
              {[
                { id: 'all', label: 'All' },
                { id: 'in_stock', label: 'Available' },
                { id: 'reserved', label: 'Reserved' },
              ].map((item) => {
                const isSelected = localFilters.availability === item.id;
                return (
                  <button
                    key={item.id}
                    type="button"
                    data-testid={`filter-avail-${item.id}`}
                    onClick={() => handleAvailabilitySelect(item.id as 'all' | 'in_stock' | 'reserved')}
                    className={`px-3.5 py-1.5 rounded-full text-xs font-medium transition-all ${
                      isSelected
                        ? 'bg-[#D4AF37] text-black font-semibold'
                        : 'bg-[#16161C] border border-white/10 text-[#AAA49A]'
                    }`}
                  >
                    {item.label}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Size Section */}
          <div className="space-y-2.5">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-[#AAA49A]">Size</h3>
            <div className="flex flex-wrap gap-2" role="group" aria-label="Filter by Size">
              {availableSizes.map((size) => {
                const isSelected = localFilters.sizes.includes(size);
                return (
                  <button
                    key={size}
                    type="button"
                    data-testid={`filter-size-${size.toLowerCase().replace(/\s+/g, '-')}`}
                    onClick={() => handleSizeToggle(size)}
                    className={`px-3.5 py-1.5 rounded-full text-xs font-medium transition-all ${
                      isSelected
                        ? 'bg-[#D4AF37] text-black font-semibold'
                        : 'bg-[#16161C] border border-white/10 text-[#AAA49A]'
                    }`}
                  >
                    {size}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Sticky CTA Submit Button */}
          <div className="pt-4 border-t border-white/5">
            <button
              type="submit"
              data-testid="filter-sheet-apply-btn"
              className="w-full py-3.5 rounded-xl bg-[#D4AF37] text-[#08080A] font-semibold text-sm tracking-wide shadow-lg hover:brightness-105 active:brightness-95 transition-all flex items-center justify-center gap-2"
            >
              <span>Show {totalMatchingPieces} Pieces →</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
