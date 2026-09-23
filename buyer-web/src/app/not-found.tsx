import React from 'react';
import Link from 'next/link';

export default function NotFound(): React.JSX.Element {
  return (
    <div className="ld-container" style={{ paddingTop: '60px' }}>
      <div className="ld-state-screen" data-testid="buyer-web-not-found" role="alert">
        <div className="ld-state-icon not-found" aria-hidden="true">
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
            <path d="m15 9-6 6" />
            <path d="m9 9 6 6" />
          </svg>
        </div>
        <h1 className="ld-state-title">Page Not Found</h1>
        <p className="ld-state-message">
          The requested page or live drop link could not be found. It may have expired or moved.
        </p>
        <div style={{ marginTop: '20px' }}>
          <Link href="/" className="ld-btn ld-btn-primary" data-testid="not-found-home-btn">
            Browse Active Drops
          </Link>
        </div>
      </div>
    </div>
  );
}
