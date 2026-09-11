'use client';

import React from 'react';
import { useCart } from '../../lib/cart/cart-context';
import { formatPaisaToINR } from '../../lib/utils/currency';

export interface StickyCartBarProps {
  onOpenCart: () => void;
}

export function StickyCartBar({ onOpenCart }: StickyCartBarProps) {
  const { itemCount, subtotalPaisa, isHydrated } = useCart();

  // Do not render before client hydration or if cart is empty
  if (!isHydrated || itemCount === 0) {
    return null;
  }

  return (
    <div
      className="ld-sticky-cart-bar"
      data-testid="sticky-cart-bar"
      role="region"
      aria-label="Shopping Cart Bar"
    >
      <div className="ld-sticky-cart-inner">
        {/* Cart Count & Subtotal */}
        <div className="ld-sticky-cart-info">
          <div className="ld-sticky-cart-badge-group">
            <span className="ld-sticky-cart-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                <path d="M3 6h18" />
                <path d="M16 10a4 4 0 0 1-8 0" />
              </svg>
            </span>
            <span className="ld-sticky-cart-count" data-testid="sticky-cart-count">
              Cart · {itemCount}
            </span>
          </div>

          <div className="ld-sticky-cart-subtotal" data-testid="sticky-cart-subtotal">
            {formatPaisaToINR(subtotalPaisa)}
          </div>
        </div>

        {/* View Cart Button */}
        <button
          type="button"
          className="ld-sticky-cart-btn"
          onClick={onOpenCart}
          data-testid="sticky-view-cart-btn"
          aria-label={`View cart with ${itemCount} items totaling ${formatPaisaToINR(subtotalPaisa)}`}
        >
          <span>View Cart</span>
          <svg
            width="18"
            height="18"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <polyline points="9 18 15 12 9 6" />
          </svg>
        </button>
      </div>
    </div>
  );
}
