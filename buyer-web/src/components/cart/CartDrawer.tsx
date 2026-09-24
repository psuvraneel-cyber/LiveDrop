'use client';

import React, { useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { useCart } from '../../lib/cart/cart-context';
import { PublicDropCatalog, PublicProductView } from '../../types/domain';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { CartEmptyState } from './CartEmptyState';

export interface CartDrawerProps {
  isOpen: boolean;
  onClose: () => void;
  catalogProducts?: PublicProductView[];
  drop?: PublicDropCatalog | null;
}

export function CartDrawer({
  isOpen,
  onClose,
  catalogProducts = [],
  drop = null,
}: CartDrawerProps) {
  const { items, itemCount, subtotalPaisa, removeItem, clearCart, getReconciledItems } = useCart();
  const drawerRef = useRef<HTMLDivElement>(null);
  const router = useRouter();

  // Close on Escape key
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  // Lock body scroll when drawer is open
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [isOpen]);

  if (!isOpen) {
    return null;
  }

  const reconciledItems = getReconciledItems(catalogProducts);
  const hasUnavailableItems = reconciledItems.some((item) => !item.isAvailable);

  return (
    <div
      className="ld-drawer-backdrop"
      onClick={onClose}
      data-testid="cart-drawer-backdrop"
      role="presentation"
    >
      <div
        className="ld-drawer-panel"
        ref={drawerRef}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="cart-drawer-title"
        data-testid="cart-drawer"
      >
        {/* Drawer Header */}
        <div className="ld-drawer-header">
          <div className="ld-drawer-title-group">
            <h2 id="cart-drawer-title" className="ld-drawer-title">
              Your Cart
            </h2>
            <span className="ld-cart-count-badge" data-testid="drawer-cart-count">
              {itemCount} {itemCount === 1 ? 'item' : 'items'}
            </span>
          </div>

          <button
            type="button"
            className="ld-drawer-close-btn"
            onClick={onClose}
            aria-label="Close cart"
            data-testid="cart-drawer-close"
          >
            <svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>

        {/* Informational Stock Notice */}
        {items.length > 0 && (
          <div className="ld-cart-disclaimer" data-testid="cart-disclaimer">
            <span className="ld-cart-disclaimer-icon" aria-hidden="true">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z" />
              </svg>
            </span>
            <span>Items are not reserved until checkout. Inventory remains live for other buyers.</span>
          </div>
        )}

        {/* Unavailable items alert banner if applicable */}
        {hasUnavailableItems && (
          <div className="ld-cart-alert-banner" data-testid="cart-unavailable-banner">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            <span>Some items in your cart were claimed by another buyer. Please remove them to proceed.</span>
          </div>
        )}

        {/* Cart Content Body */}
        <div className="ld-drawer-body">
          {items.length === 0 ? (
            <CartEmptyState onBrowse={onClose} />
          ) : (
            <div className="ld-cart-list" role="list" aria-label="Cart items">
              {reconciledItems.map((item) => {
                const isItemUnavailable = !item.isAvailable;

                return (
                  <div
                    key={item.productId}
                    className={`ld-cart-item ${isItemUnavailable ? 'unavailable' : ''}`}
                    data-testid={`cart-item-${item.productId}`}
                    role="listitem"
                  >
                    {/* Item Thumbnail */}
                    <div className="ld-cart-item-media">
                      {item.imageUrl ? (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img
                          src={item.imageUrl}
                          alt={`${item.code} - ${item.title}`}
                          className="ld-cart-item-img"
                        />
                      ) : (
                        <div className="ld-cart-item-placeholder" aria-hidden="true">
                          <span>{item.code}</span>
                        </div>
                      )}
                    </div>

                    {/* Item Info */}
                    <div className="ld-cart-item-details">
                      <div className="ld-cart-item-header">
                        <span className="ld-cart-item-code">{item.code}</span>
                        <span className="ld-cart-item-price">
                          {formatPaisaToINR(item.pricePaisa)}
                        </span>
                      </div>

                      <h4 className="ld-cart-item-title" title={item.title}>
                        {item.title}
                      </h4>

                      {item.size && (
                        <span className="ld-cart-item-size">Size: {item.size}</span>
                      )}

                      {/* Availability status badge */}
                      {isItemUnavailable && (
                        <div
                          className="ld-cart-item-status-warning"
                          data-testid={`cart-item-warning-${item.productId}`}
                        >
                          <span className="ld-cart-warning-dot" aria-hidden="true" />
                          {item.status === 'reserved' ? 'RESERVED — No longer available' : 'SOLD OUT'}
                        </div>
                      )}
                    </div>

                    {/* Remove Action */}
                    <div className="ld-cart-item-actions">
                      <button
                        type="button"
                        className="ld-cart-remove-btn"
                        onClick={() => removeItem(item.productId)}
                        aria-label={`Remove ${item.code}: ${item.title} from cart`}
                        data-testid={`cart-remove-${item.productId}`}
                      >
                        <svg
                          width="16"
                          height="16"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden="true"
                        >
                          <path d="M3 6h18" />
                          <path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6" />
                          <path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2" />
                        </svg>
                        <span className="ld-cart-remove-text">Remove</span>
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Drawer Footer / Subtotal */}
        {items.length > 0 && (
          <div className="ld-drawer-footer">
            <div className="ld-cart-summary">
              <div className="ld-summary-row">
                <span className="ld-summary-label">Subtotal</span>
                <span className="ld-summary-value" data-testid="cart-subtotal">
                  {formatPaisaToINR(subtotalPaisa)}
                </span>
              </div>

              {drop?.shipping_fee_paisa !== undefined && (
                <div className="ld-summary-shipping-note">
                  {drop.free_shipping_threshold_paisa && subtotalPaisa >= drop.free_shipping_threshold_paisa ? (
                    <span className="ld-free-shipping-qualify">✓ You qualify for Free Shipping!</span>
                  ) : drop.free_shipping_threshold_paisa ? (
                    <span>Add {formatPaisaToINR(drop.free_shipping_threshold_paisa - subtotalPaisa)} more for Free Shipping</span>
                  ) : drop.shipping_fee_paisa === 0 ? (
                    <span>Free Shipping on all orders</span>
                  ) : (
                    <span>Shipping calculated at checkout</span>
                  )}
                </div>
              )}
            </div>

            {/* Checkout Action CTA (Prepared boundary for TASK-2.3) */}
            <button
              type="button"
              className="ld-btn-checkout"
              disabled={hasUnavailableItems}
              data-testid="cart-checkout-btn"
              onClick={() => {
                if (!hasUnavailableItems) {
                  onClose();
                  router.push('/checkout');
                }
              }}
              title={
                hasUnavailableItems
                  ? 'Please remove unavailable items before proceeding'
                  : 'Proceed to Checkout'
              }
            >
              {hasUnavailableItems ? 'Remove Unavailable Items' : 'Proceed to Checkout'}
            </button>

            {/* Clear Cart Button */}
            <button
              type="button"
              className="ld-btn-clear-cart"
              onClick={clearCart}
              data-testid="clear-cart-btn"
            >
              Clear Cart
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
