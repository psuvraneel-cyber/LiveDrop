'use client';

import React, { useEffect } from 'react';
import Link from 'next/link';

export default function ErrorBoundary({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Log unexpected errors for client observability
    console.error('Unhandled route error in buyer-web:', error);
  }, [error]);

  return (
    <div className="ld-container" style={{ paddingTop: '60px' }}>
      <div className="ld-state-screen" data-testid="buyer-web-error-boundary" role="alert">
        <div className="ld-state-icon error" aria-hidden="true">
          <svg
            width="32"
            height="32"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <circle cx="12" cy="12" r="10" />
            <line x1="12" y1="8" x2="12" y2="12" />
            <line x1="12" y1="16" x2="12.01" y2="16" />
          </svg>
        </div>
        <h1 className="ld-state-title">Something went wrong</h1>
        <p className="ld-state-message">
          {error?.message ||
            'We encountered an unexpected error while loading this page. Your reserved bag and saved details remain safe.'}
        </p>
        <div style={{ display: 'flex', gap: '12px', marginTop: '16px', flexWrap: 'wrap', justifyContent: 'center' }}>
          <button
            type="button"
            className="ld-btn ld-btn-primary"
            onClick={() => reset()}
            data-testid="error-boundary-retry-btn"
          >
            Try Again
          </button>
          <Link
            href="/"
            className="ld-btn"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              justifyContent: 'center',
              padding: '12px 20px',
              borderRadius: 'var(--radius-pill)',
              background: '#F1F5F9',
              color: '#334155',
              textDecoration: 'none',
              fontWeight: 600,
              fontSize: '14px',
            }}
            data-testid="error-boundary-home-btn"
          >
            Return Home
          </Link>
        </div>
      </div>
    </div>
  );
}
