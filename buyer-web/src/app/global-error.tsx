'use client';

import React from 'react';

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="en">
      <body style={{ margin: 0, padding: 0, fontFamily: 'system-ui, -apple-system, sans-serif', backgroundColor: '#F8FAFC' }}>
        <div style={{ maxWidth: '640px', margin: '60px auto', padding: '0 16px', textAlign: 'center' }}>
          <div
            style={{
              background: '#FFFFFF',
              borderRadius: '12px',
              padding: '32px 24px',
              boxShadow: '0 4px 6px -1px rgba(0,0,0,0.1)',
            }}
          >
            <div style={{ display: 'flex', justifyContent: 'center', marginBottom: '16px', color: '#D4AF37' }}>
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
            </div>
            <h1 style={{ fontSize: '20px', fontWeight: 700, color: '#0F172A', marginBottom: '8px' }}>
              Application Error
            </h1>
            <p style={{ color: '#64748B', fontSize: '14px', marginBottom: '24px', lineHeight: 1.5 }}>
              {error?.message || 'A critical error occurred while loading LiveDrop.'}
            </p>
            <button
              type="button"
              onClick={() => reset()}
              style={{
                backgroundColor: '#16A34A',
                color: '#FFFFFF',
                border: 'none',
                borderRadius: '24px',
                padding: '12px 24px',
                fontSize: '14px',
                fontWeight: 600,
                cursor: 'pointer',
              }}
            >
              Reload Page
            </button>
          </div>
        </div>
      </body>
    </html>
  );
}
