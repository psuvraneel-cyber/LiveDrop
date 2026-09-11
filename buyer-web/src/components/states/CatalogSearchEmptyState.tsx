import React from 'react';

export interface CatalogSearchEmptyStateProps {
  searchQuery: string;
  onClearSearch: () => void;
}

export function CatalogSearchEmptyState({ searchQuery, onClearSearch }: CatalogSearchEmptyStateProps) {
  return (
    <div className="ld-state-screen" data-testid="catalog-search-empty-state" role="status">
      <div className="ld-state-icon empty" aria-hidden="true">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="11" cy="11" r="8" />
          <path d="m21 21-4.3-4.3" />
        </svg>
      </div>
      <h2 className="ld-state-title">No Matching Products</h2>
      <p className="ld-state-message">
        No pieces found matching <strong style={{ color: 'var(--text-primary)' }}>&ldquo;{searchQuery}&rdquo;</strong>.
      </p>
      <button
        type="button"
        className="ld-btn ld-btn-secondary"
        onClick={onClearSearch}
        aria-label="Clear current search query"
        style={{ marginTop: '8px' }}
      >
        Clear Search
      </button>
    </div>
  );
}
