'use client';

/**
 * LiveDrop — Dedicated Buyer Cart Page (/cart) (TASK-2.2)
 *
 * Provides a dedicated standalone route for reviewing cart items,
 * surviving browser refreshes and bookmarking.
 */

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCart, CartProvider, useOptionalCart } from '../../lib/cart/cart-context';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { CartEmptyState } from '../../components/cart/CartEmptyState';
import { getBuyerClient } from '../../lib/supabase/client';
import { getPublicProductsForDrop } from '../../lib/data/buyer-catalog';
import { PublicProductView } from '../../types/domain';

function CartPageContent() {
  const router = useRouter();
  const { items, itemCount, subtotalPaisa, dropId, isHydrated, removeItem, clearCart, getReconciledItems } = useCart();
  const [catalogProducts, setCatalogProducts] = useState<PublicProductView[]>([]);

  // If dropId exists, fetch latest catalog snapshot for availability reconciliation
  useEffect(() => {
    let active = true;

    if (dropId) {
      const fetchCatalog = async () => {
        try {
          const client = getBuyerClient();
          const products = await getPublicProductsForDrop(client, dropId);
          if (active) {
            setCatalogProducts(products);
          }
        } catch {
          // Keep local cart display if network fetch fails
        }
      };
      void fetchCatalog();
    }

    return () => {
      active = false;
    };
  }, [dropId]);

  if (!isHydrated) {
    return (
      <div className="ld-cart-page-loading" data-testid="cart-page-loading">
        <div className="ld-spinner" />
      </div>
    );
  }

  const reconciledItems = getReconciledItems(catalogProducts);
  const hasUnavailableItems = reconciledItems.some((item) => !item.isAvailable);

  return (
    <div className="ld-cart-page" data-testid="cart-page">
      {/* Top Navigation */}
      <header className="ld-cart-page-header">
        <div className="ld-cart-page-nav">
          <Link href="/" className="ld-back-link" data-testid="cart-back-btn">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <line x1="19" y1="12" x2="5" y2="12" />
              <polyline points="12 19 5 12 12 5" />
            </svg>
            <span>Back</span>
          </Link>
          <span className="ld-cart-page-brand">LiveDrop</span>
        </div>
      </header>

      <main className="ld-container ld-cart-page-main" role="main">
        <div className="ld-cart-page-title-row">
          <h1 className="ld-cart-page-title">Your Cart</h1>
          {itemCount > 0 && (
            <span className="ld-cart-count-badge" data-testid="page-cart-count">
              {itemCount} {itemCount === 1 ? 'item' : 'items'}
            </span>
          )}
        </div>

        {/* Informational Stock Notice */}
        {items.length > 0 && (
          <div className="ld-cart-disclaimer" data-testid="page-cart-disclaimer">
            <span className="ld-cart-disclaimer-icon" aria-hidden="true">⚡</span>
            <span>Items are not reserved until checkout. Flash sale stock remains live.</span>
          </div>
        )}

        {/* Unavailable items alert banner */}
        {hasUnavailableItems && (
          <div className="ld-cart-alert-banner" data-testid="page-cart-unavailable-banner">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            <span>Some items in your cart were claimed by another buyer. Please remove them to proceed.</span>
          </div>
        )}

        {items.length === 0 ? (
          <CartEmptyState />
        ) : (
          <div className="ld-cart-page-grid">
            {/* Items List */}
            <div className="ld-cart-list" role="list" aria-label="Cart items">
              {reconciledItems.map((item) => {
                const isItemUnavailable = !item.isAvailable;

                return (
                  <div
                    key={item.productId}
                    className={`ld-cart-item ${isItemUnavailable ? 'unavailable' : ''}`}
                    data-testid={`cart-page-item-${item.productId}`}
                    role="listitem"
                  >
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

                      {isItemUnavailable && (
                        <div
                          className="ld-cart-item-status-warning"
                          data-testid={`cart-page-warning-${item.productId}`}
                        >
                          <span className="ld-cart-warning-dot" aria-hidden="true" />
                          {item.status === 'reserved' ? 'RESERVED — No longer available' : 'SOLD OUT'}
                        </div>
                      )}
                    </div>

                    <div className="ld-cart-item-actions">
                      <button
                        type="button"
                        className="ld-cart-remove-btn"
                        onClick={() => removeItem(item.productId)}
                        aria-label={`Remove ${item.code}: ${item.title} from cart`}
                        data-testid={`cart-page-remove-${item.productId}`}
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

            {/* Subtotal Card */}
            <div className="ld-cart-page-summary">
              <div className="ld-summary-row">
                <span className="ld-summary-label">Subtotal</span>
                <span className="ld-summary-value" data-testid="cart-page-subtotal">
                  {formatPaisaToINR(subtotalPaisa)}
                </span>
              </div>

              <div className="ld-summary-shipping-note">
                <span>Shipping calculated at checkout</span>
              </div>

              <button
                type="button"
                className="ld-btn-checkout"
                disabled={hasUnavailableItems}
                onClick={() => {
                  if (!hasUnavailableItems) {
                    router.push('/checkout');
                  }
                }}
                data-testid="cart-page-checkout-btn"
              >
                {hasUnavailableItems ? 'Remove Unavailable Items' : 'Proceed to Checkout'}
              </button>

              <button
                type="button"
                className="ld-btn-clear-cart"
                onClick={clearCart}
                data-testid="cart-page-clear-btn"
              >
                Clear Cart
              </button>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

export default function CartPage() {
  const existingCart = useOptionalCart();
  if (existingCart) {
    return <CartPageContent />;
  }

  return (
    <CartProvider>
      <CartPageContent />
    </CartProvider>
  );
}
