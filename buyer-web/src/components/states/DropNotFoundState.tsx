import React from 'react';

export interface DropNotFoundStateProps {
  slug?: string;
}

export function DropNotFoundState({ slug }: DropNotFoundStateProps) {
  return (
    <div className="ld-container">
      <div className="ld-state-screen" data-testid="drop-not-found-state" role="alert">
        <div className="ld-state-icon not-found" aria-hidden="true">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10" />
            <path d="m15 9-6 6" />
            <path d="m9 9 6 6" />
          </svg>
        </div>
        <h1 className="ld-state-title">Drop Not Found</h1>
        <p className="ld-state-message">
          {slug ? (
            <>We couldn&apos;t find an active live drop matching <strong style={{ color: 'var(--text-primary)' }}>&ldquo;{slug}&rdquo;</strong>.</>
          ) : (
            'The requested drop link does not exist or may have been typed incorrectly.'
          )}
        </p>
        <p className="ld-state-message" style={{ fontSize: '13px', marginTop: '-4px' }}>
          Please verify the link shared during the Facebook Live or WhatsApp broadcast.
        </p>
      </div>
    </div>
  );
}
