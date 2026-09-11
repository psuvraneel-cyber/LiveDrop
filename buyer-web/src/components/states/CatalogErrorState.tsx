import React from 'react';

export interface CatalogErrorStateProps {
  message?: string;
  onRetry: () => void;
}

export function CatalogErrorState({ message, onRetry }: CatalogErrorStateProps) {
  return (
    <div className="ld-container">
      <div className="ld-state-screen" data-testid="catalog-error-state" role="alert">
        <div className="ld-state-icon error" aria-hidden="true">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3Z" />
            <line x1="12" y1="9" x2="12" y2="13" />
            <line x1="12" y1="17" x2="12.01" y2="17" />
          </svg>
        </div>
        <h1 className="ld-state-title">Unable to Load Catalog</h1>
        <p className="ld-state-message">
          {message || 'A network error occurred while connecting to the live drop. Please check your connection and try again.'}
        </p>
        <button
          type="button"
          className="ld-btn ld-btn-primary"
          onClick={onRetry}
          aria-label="Retry loading the live drop catalog"
          style={{ marginTop: '8px' }}
        >
          Try Again
        </button>
      </div>
    </div>
  );
}
