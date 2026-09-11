import React from 'react';

export interface DropUnavailableStateProps {
  title?: string;
  storeName?: string;
}

export function DropUnavailableState({ title, storeName }: DropUnavailableStateProps) {
  return (
    <div className="ld-container">
      <div className="ld-state-screen" data-testid="drop-unavailable-state" role="alert">
        <div className="ld-state-icon unavailable" aria-hidden="true">
          <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <rect width="18" height="18" x="3" y="3" rx="2" />
            <path d="M9 9h6" />
            <path d="M12 9v6" />
          </svg>
        </div>
        <h1 className="ld-state-title">Broadcast Ended</h1>
        <p className="ld-state-message">
          {title && storeName ? (
            <>
              <strong>{title}</strong> by <strong>{storeName}</strong> has concluded.
            </>
          ) : (
            'This live drop is no longer active. The boutique broadcast has concluded.'
          )}
        </p>
        <p className="ld-state-message" style={{ fontSize: '13px', marginTop: '-4px' }}>
          Stay tuned to the seller&apos;s Facebook Live or WhatsApp group for upcoming drops and announcements.
        </p>
      </div>
    </div>
  );
}
