import React from 'react';

export function CatalogEmptyState() {
  return (
    <div className="ld-state-screen" data-testid="catalog-empty-state" role="status">
      <div className="ld-state-icon empty" aria-hidden="true">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
          <path d="M3 6h18" />
          <path d="M16 10a4 4 0 0 1-8 0" />
        </svg>
      </div>
      <h2 className="ld-state-title">No Products Available Yet</h2>
      <p className="ld-state-message">
        The boutique seller has not added any pieces to this drop yet. Products will appear here as soon as they are showcased!
      </p>
    </div>
  );
}
