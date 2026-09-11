import React from 'react';

export type AvailabilityFilter = 'all' | 'available' | 'unavailable';

export interface CatalogToolbarProps {
  searchQuery: string;
  onSearchChange: (query: string) => void;
  activeFilter: AvailabilityFilter;
  onFilterChange: (filter: AvailabilityFilter) => void;
  totalCount: number;
  filteredCount: number;
}

export function CatalogToolbar({
  searchQuery,
  onSearchChange,
  activeFilter,
  onFilterChange,
  totalCount,
  filteredCount,
}: CatalogToolbarProps) {
  return (
    <div className="ld-toolbar" role="search" aria-label="Search and filter drop catalog">
      {/* Search Bar */}
      <div className="ld-search-wrapper">
        <svg
          className="ld-search-icon"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <circle cx="11" cy="11" r="8" />
          <path d="m21 21-4.3-4.3" />
        </svg>

        <input
          type="text"
          className="ld-search-input"
          placeholder="Search flash code (e.g. #A01) or title..."
          value={searchQuery}
          onChange={(e) => onSearchChange(e.target.value)}
          aria-label="Search products by flash code or title"
          data-testid="catalog-search-input"
        />

        {searchQuery.trim() !== '' && (
          <button
            type="button"
            className="ld-search-clear"
            onClick={() => onSearchChange('')}
            aria-label="Clear search input"
            data-testid="search-clear-button"
          >
            ×
          </button>
        )}
      </div>

      {/* Filter Row: Pills + Item Count */}
      <div className="ld-filter-row">
        <div className="ld-filter-pills" role="tablist" aria-label="Filter products by status">
          <button
            type="button"
            role="tab"
            aria-selected={activeFilter === 'all'}
            className={`ld-filter-pill ${activeFilter === 'all' ? 'active' : ''}`}
            onClick={() => onFilterChange('all')}
            data-testid="filter-pill-all"
          >
            All Items
          </button>

          <button
            type="button"
            role="tab"
            aria-selected={activeFilter === 'available'}
            className={`ld-filter-pill ${activeFilter === 'available' ? 'active' : ''}`}
            onClick={() => onFilterChange('available')}
            data-testid="filter-pill-available"
          >
            Available
          </button>

          <button
            type="button"
            role="tab"
            aria-selected={activeFilter === 'unavailable'}
            className={`ld-filter-pill ${activeFilter === 'unavailable' ? 'active' : ''}`}
            onClick={() => onFilterChange('unavailable')}
            data-testid="filter-pill-unavailable"
          >
            Reserved / Sold
          </button>
        </div>

        <span className="ld-item-count" data-testid="item-count-display">
          {searchQuery.trim() !== '' || activeFilter !== 'all'
            ? `${filteredCount} of ${totalCount}`
            : `${totalCount} item${totalCount === 1 ? '' : 's'}`}
        </span>
      </div>
    </div>
  );
}
