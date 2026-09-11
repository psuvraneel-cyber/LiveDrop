import React from 'react';

export interface CartEmptyStateProps {
  onBrowse?: () => void;
}

export function CartEmptyState({ onBrowse }: CartEmptyStateProps) {
  return (
    <div className="ld-cart-empty" data-testid="cart-empty-state">
      <div className="ld-cart-empty-icon" aria-hidden="true">
        <svg
          width="48"
          height="48"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
          <path d="M3 6h18" />
          <path d="M16 10a4 4 0 0 1-8 0" />
        </svg>
      </div>

      <h3 className="ld-cart-empty-title">Your cart is empty</h3>
      <p className="ld-cart-empty-desc">
        Browse the live catalog to add items to your bag.
      </p>

      {onBrowse && (
        <button
          type="button"
          className="ld-btn-browse"
          onClick={onBrowse}
          data-testid="cart-browse-btn"
        >
          Browse Catalog
        </button>
      )}
    </div>
  );
}
