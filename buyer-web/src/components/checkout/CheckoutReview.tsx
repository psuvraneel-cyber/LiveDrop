'use client';

import React from 'react';
import { ReconciledCartItem } from '../../types/cart';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { PublicDropCatalog } from '../../types/domain';

export interface CheckoutReviewProps {
  items: ReconciledCartItem[];
  subtotalPaisa: number;
  drop: PublicDropCatalog | null;
  isSubmitting: boolean;
  hasUnavailableItems: boolean;
  onRemoveItem: (productId: string) => void;
  onSubmit: (e: React.FormEvent) => void;
}

export function CheckoutReview({
  items,
  subtotalPaisa,
  drop,
  isSubmitting,
  hasUnavailableItems,
  onRemoveItem,
  onSubmit,
}: CheckoutReviewProps) {
  // Estimated shipping based on drop rules (informational only; database computes authoritative value)
  let estimatedShippingPaisa = 0;
  let hasFreeShipping = false;

  if (drop) {
    const threshold = drop.free_shipping_threshold_paisa ?? drop.profiles?.free_shipping_threshold_paisa;
    const fee = drop.shipping_fee_paisa ?? drop.profiles?.default_shipping_fee_paisa ?? 8000;

    if (threshold !== null && threshold !== undefined && subtotalPaisa >= threshold) {
      estimatedShippingPaisa = 0;
      hasFreeShipping = true;
    } else {
      estimatedShippingPaisa = fee;
    }
  }

  const estimatedTotalPaisa = subtotalPaisa + estimatedShippingPaisa;

  return (
    <section className="ld-checkout-section ld-checkout-review" aria-labelledby="order-summary-title">
      <div className="ld-checkout-summary-header">
        <h2 id="order-summary-title" className="ld-checkout-card-title">
          Order Summary ({items.length} {items.length === 1 ? 'item' : 'items'})
        </h2>
      </div>

      {/* Unavailable Items Warning Banner */}
      {hasUnavailableItems && (
        <div className="ld-cart-alert-banner" data-testid="checkout-unavailable-banner">
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            aria-hidden="true"
          >
            <circle cx="12" cy="12" r="10" />
            <line x1="12" y1="8" x2="12" y2="12" />
            <line x1="12" y1="16" x2="12.01" y2="16" />
          </svg>
          <span>Some items in your bag were claimed by another buyer. Remove them to proceed.</span>
        </div>
      )}

      {/* Items List */}
      <div className="ld-checkout-items-list" role="list" aria-label="Items in your bag">
        {items.map((item) => {
          const isItemUnavailable = !item.isAvailable;

          return (
            <div
              key={item.productId}
              className={`ld-checkout-item ${isItemUnavailable ? 'unavailable' : ''}`}
              data-testid={`checkout-item-${item.productId}`}
              role="listitem"
            >
              <div className="ld-checkout-item-media">
                {item.imageUrl ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={item.imageUrl}
                    alt={`${item.code} - ${item.title}`}
                    className="ld-checkout-item-img"
                  />
                ) : (
                  <div className="ld-checkout-item-placeholder" aria-hidden="true">
                    <span>{item.code}</span>
                  </div>
                )}
              </div>

              <div className="ld-checkout-item-info">
                <div className="ld-checkout-item-header">
                  <span className="ld-product-code" data-testid={`checkout-code-${item.productId}`}>
                    {item.code}
                  </span>
                  <span className="ld-checkout-item-price">
                    {formatPaisaToINR(item.pricePaisa)}
                  </span>
                </div>

                <h4 className="ld-checkout-item-title" title={item.title}>
                  {item.title}
                </h4>

                {item.size && (
                  <span className="ld-checkout-item-size">Size: {item.size}</span>
                )}

                {isItemUnavailable && (
                  <div
                    className="ld-cart-item-status-warning"
                    data-testid={`checkout-warning-${item.productId}`}
                  >
                    <span className="ld-cart-warning-dot" aria-hidden="true" />
                    {item.status === 'reserved' ? 'RESERVED — Claimed by another buyer' : 'SOLD OUT'}
                  </div>
                )}
              </div>

              {isItemUnavailable && (
                <div className="ld-checkout-item-actions">
                  <button
                    type="button"
                    className="ld-cart-remove-btn"
                    onClick={() => onRemoveItem(item.productId)}
                    aria-label={`Remove unavailable item ${item.code} from bag`}
                    data-testid={`checkout-remove-${item.productId}`}
                  >
                    Remove
                  </button>
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Pre-checkout Breakdown */}
      <div className="ld-checkout-pricing-card">
        <div className="ld-checkout-estimate-notice">
          <span>Pre-checkout estimate • Final total verified by server</span>
        </div>

        <div className="ld-summary-row">
          <span className="ld-summary-label">Estimated Subtotal</span>
          <span className="ld-summary-value" data-testid="checkout-subtotal">
            {formatPaisaToINR(subtotalPaisa)}
          </span>
        </div>

        <div className="ld-summary-row">
          <span className="ld-summary-label">Estimated Delivery</span>
          <span className="ld-summary-value" data-testid="checkout-shipping">
            {hasFreeShipping ? (
              <span className="ld-free-shipping-tag">FREE</span>
            ) : drop ? (
              formatPaisaToINR(estimatedShippingPaisa)
            ) : (
              'Calculated at confirmation'
            )}
          </span>
        </div>

        <div className="ld-summary-row ld-checkout-total-row">
          <span className="ld-total-label">Estimated Total</span>
          <span className="ld-total-value" data-testid="checkout-total">
            {formatPaisaToINR(estimatedTotalPaisa)}
          </span>
        </div>

        {/* Hold Explanation Notice */}
        <div className="ld-cart-disclaimer ld-checkout-hold-notice" data-testid="checkout-hold-notice">
          <span className="ld-cart-disclaimer-icon" aria-hidden="true">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
          </span>
          <span>
            Placing your order reserves a <strong>15-minute hold</strong> on your selected pieces. Payment is completed in the next step.
          </span>
        </div>

        {/* Submission CTA */}
        <button
          type="button"
          className="ld-btn-submit-order"
          disabled={isSubmitting || hasUnavailableItems || items.length === 0}
          onClick={onSubmit}
          data-testid="checkout-submit-btn"
        >
          {isSubmitting ? (
            <span className="ld-btn-loading-content">
              <span className="ld-spinner-small" aria-hidden="true" />
              <span>Reserving Items with Database...</span>
            </span>
          ) : hasUnavailableItems ? (
            'Remove Unavailable Items to Proceed'
          ) : (
            `Place Order & Hold Items (${formatPaisaToINR(estimatedTotalPaisa)})`
          )}
        </button>
      </div>
    </section>
  );
}
