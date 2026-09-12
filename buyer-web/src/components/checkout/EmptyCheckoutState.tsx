'use client';

import React from 'react';
import Link from 'next/link';

export function EmptyCheckoutState() {
  return (
    <div className="ld-checkout-empty" data-testid="checkout-empty-state">
      <div className="ld-checkout-empty-icon" aria-hidden="true">
        <svg
          width="36"
          height="36"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z" />
          <line x1="3" y1="6" x2="21" y2="6" />
          <path d="M16 10a4 4 0 0 1-8 0" />
        </svg>
      </div>
      <h2 className="ld-checkout-empty-title">Your Bag is Empty</h2>
      <p className="ld-checkout-empty-desc">
        There are no items to check out. Visit a live drop to select garments before reserving.
      </p>
      <Link href="/" className="ld-btn-browse" data-testid="checkout-browse-btn">
        Browse Live Drops
      </Link>
    </div>
  );
}
