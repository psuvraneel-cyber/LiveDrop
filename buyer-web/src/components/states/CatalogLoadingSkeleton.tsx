import React from 'react';

export function CatalogLoadingSkeleton() {
  return (
    <div className="ld-container" data-testid="catalog-loading-skeleton" role="status" aria-label="Loading drop catalog">
      {/* Header Skeleton */}
      <div style={{ padding: '16px 0 20px', display: 'flex', flexDirection: 'column', gap: '12px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div className="ld-skeleton" style={{ width: '40px', height: '40px', borderRadius: '50%' }} />
            <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
              <div className="ld-skeleton" style={{ width: '140px', height: '18px' }} />
              <div className="ld-skeleton" style={{ width: '90px', height: '12px' }} />
            </div>
          </div>
          <div className="ld-skeleton" style={{ width: '70px', height: '24px', borderRadius: '24px' }} />
        </div>
        {/* Search bar skeleton */}
        <div className="ld-skeleton" style={{ width: '100%', height: '48px', borderRadius: '24px' }} />
      </div>

      {/* Grid Skeleton */}
      <div className="ld-product-grid">
        {[1, 2, 3, 4].map((i) => (
          <div key={i} className="ld-skeleton-card">
            <div className="ld-skeleton ld-skeleton-media" />
            <div className="ld-skeleton-body">
              <div className="ld-skeleton" style={{ width: '40px', height: '14px' }} />
              <div className="ld-skeleton" style={{ width: '100%', height: '16px' }} />
              <div className="ld-skeleton" style={{ width: '60%', height: '18px', marginTop: '4px' }} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
