/**
 * LiveDrop E2E Test Suite — Tier 1: Screen 05 (Filter Sheet Modal)
 *
 * Authoritative Spec: docs/BUYER-REFERENCE-DESIGN-SPEC.md Section 17 & PROJECT.md M2 Contract
 *
 * Test Inventory (>=5 tests):
 * 1. Renders bottom drawer modal with drag handle, serif "Filters" title, and close button
 * 2. Selects category filter chips (All, Sarees, Kurtis, Lehengas) with active styling
 * 3. Adjusts price range slider in integer Paisa and updates formatted INR ceiling
 * 4. Selects availability filter chips (All, Available, Reserved)
 * 5. Toggles size filter chips (Free Size, XS, S, M, L, XL, XXL) supporting multi-selection
 * 6. Resets all filters back to initial defaults on "Clear All" click
 * 7. Submits applied filters via "Show [X] Pieces →" CTA and closes sheet
 * 8. Dismisses modal when clicking the close button
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { screen, fireEvent, render } from '@testing-library/react';
import {
  ReferenceFilterSheet,
  FilterState,
} from './fixtures/ReferenceFilterSheet';

describe('Tier 1: Screen 05 — Multi-Dimensional Filter Sheet', () => {
  const initialFilters: FilterState = {
    category: null,
    priceRange: [0, 5000000], // 0 to ₹50,000 in Paisa
    availability: 'all',
    sizes: [],
  };

  it('renders bottom drawer modal with drag handle, title, and close button', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={initialFilters}
        onApplyFilters={handleApply}
      />
    );

    expect(screen.getByRole('dialog', { name: 'Filter Sheet' })).toBeInTheDocument();
    expect(screen.getByTestId('filter-sheet-handle')).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 2, name: 'Filters' })).toBeInTheDocument();
    expect(screen.getByTestId('filter-sheet-close-btn')).toBeInTheDocument();
    expect(screen.getByTestId('filter-sheet-clear-all-btn')).toBeInTheDocument();
  });

  it('selects category filter chips and updates active selection', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={initialFilters}
        onApplyFilters={handleApply}
      />
    );

    // Initial state: "All" is selected
    const allChip = screen.getByTestId('filter-category-all');
    expect(allChip).toHaveClass('bg-[#D4AF37]');

    // Click Sarees
    const sareesChip = screen.getByTestId('filter-category-sarees');
    fireEvent.click(sareesChip);
    expect(sareesChip).toHaveClass('bg-[#D4AF37]');
  });

  it('adjusts price range slider in integer Paisa and updates formatted INR ceiling', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={initialFilters}
        onApplyFilters={handleApply}
      />
    );

    const priceSlider = screen.getByTestId('filter-price-slider');
    const priceDisplay = screen.getByTestId('filter-price-display');

    expect(priceDisplay).toHaveTextContent('Up to ₹50,000');

    // Change slider to ₹25,000 (2500000 Paisa)
    fireEvent.change(priceSlider, { target: { value: '2500000' } });
    expect(priceDisplay).toHaveTextContent('Up to ₹25,000');
  });

  it('selects availability filter chips (All, Available, Reserved)', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={initialFilters}
        onApplyFilters={handleApply}
      />
    );

    const availInStock = screen.getByTestId('filter-avail-in_stock');
    fireEvent.click(availInStock);
    expect(availInStock).toHaveClass('bg-[#D4AF37]');

    const availReserved = screen.getByTestId('filter-avail-reserved');
    fireEvent.click(availReserved);
    expect(availReserved).toHaveClass('bg-[#D4AF37]');
  });

  it('toggles size filter chips supporting multi-selection', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={initialFilters}
        onApplyFilters={handleApply}
      />
    );

    const sizeM = screen.getByTestId('filter-size-m');
    const sizeL = screen.getByTestId('filter-size-l');

    // Select M
    fireEvent.click(sizeM);
    expect(sizeM).toHaveClass('bg-[#D4AF37]');

    // Select L
    fireEvent.click(sizeL);
    expect(sizeL).toHaveClass('bg-[#D4AF37]');
    expect(sizeM).toHaveClass('bg-[#D4AF37]');

    // Unselect M
    fireEvent.click(sizeM);
    expect(sizeM).not.toHaveClass('bg-[#D4AF37]');
    expect(sizeL).toHaveClass('bg-[#D4AF37]');
  });

  it('resets all filters back to initial defaults when clicking "Clear All"', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    const modifiedFilters: FilterState = {
      category: 'sarees',
      priceRange: [0, 2000000],
      availability: 'in_stock',
      sizes: ['M', 'L'],
    };

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={modifiedFilters}
        onApplyFilters={handleApply}
      />
    );

    const clearAllBtn = screen.getByTestId('filter-sheet-clear-all-btn');
    fireEvent.click(clearAllBtn);

    // "All" category becomes active again
    expect(screen.getByTestId('filter-category-all')).toHaveClass('bg-[#D4AF37]');
    // Price ceiling resets
    expect(screen.getByTestId('filter-price-display')).toHaveTextContent('Up to ₹50,000');
  });

  it('submits applied filters via "Show [X] Pieces →" CTA and closes sheet', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={initialFilters}
        onApplyFilters={handleApply}
        totalMatchingPieces={8}
      />
    );

    // Select Kurtis
    fireEvent.click(screen.getByTestId('filter-category-kurtis'));

    // Submit
    const applyBtn = screen.getByTestId('filter-sheet-apply-btn');
    expect(applyBtn).toHaveTextContent('Show 8 Pieces →');

    fireEvent.click(applyBtn);

    expect(handleApply).toHaveBeenCalledWith(
      expect.objectContaining({
        category: 'kurtis',
      })
    );
    expect(handleClose).toHaveBeenCalledTimes(1);
  });

  it('dismisses modal when clicking the close "✕" button', () => {
    const handleClose = vi.fn();
    const handleApply = vi.fn();

    render(
      <ReferenceFilterSheet
        isOpen={true}
        onClose={handleClose}
        filters={initialFilters}
        onApplyFilters={handleApply}
      />
    );

    const closeBtn = screen.getByTestId('filter-sheet-close-btn');
    fireEvent.click(closeBtn);
    expect(handleClose).toHaveBeenCalledTimes(1);
  });
});
