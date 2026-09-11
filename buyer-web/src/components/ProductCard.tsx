import React, { useState } from 'react';
import { PublicProductView } from '../types/domain';
import { formatPaisaToINR } from '../lib/utils/currency';
import { useOptionalCart } from '../lib/cart/cart-context';

export interface ProductCardProps {
  product: PublicProductView;
  dropId?: string;
  onAddToCart?: (product: PublicProductView) => void;
}

export function ProductCard({ product, dropId, onAddToCart }: ProductCardProps) {
  const [imageError, setImageError] = useState(false);
  const cart = useOptionalCart();

  const isAvailable = product.status === 'available';
  const isReserved = product.status === 'reserved';
  const isSold = product.status === 'sold';

  const inCart = cart ? cart.isInCart(product.id) : false;

  // Status badge label and class
  let statusText = 'AVAILABLE';
  let statusClass = 'available';

  if (isReserved) {
    statusText = 'RESERVED';
    statusClass = 'reserved';
  } else if (isSold) {
    statusText = 'SOLD OUT';
    statusClass = 'sold';
  }

  const handleAddToCart = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onAddToCart) {
      onAddToCart(product);
      return;
    }
    if (cart && isAvailable) {
      const targetDropId = dropId || (product as unknown as { drop_id?: string }).drop_id || cart.dropId || '';
      cart.addItem(product, targetDropId);
    }
  };

  return (
    <article
      className={`ld-product-card ${!isAvailable ? 'unavailable' : ''}`}
      data-testid={`product-card-${product.id}`}
      aria-label={`${product.code}: ${product.title} - ${formatPaisaToINR(product.price_paisa)} - ${statusText}`}
    >
      {/* Media Thumbnail Container (1:1 aspect ratio) */}
      <div className="ld-card-media">
        {/* Flash Code Badge (Top-Left, High Contrast Monospace) */}
        <span
          className="ld-flash-badge"
          data-testid={`flash-badge-${product.id}`}
          aria-label={`Flash code ${product.code}`}
        >
          {product.code}
        </span>

        {/* Availability Badge (Top-Right) */}
        <span
          className={`ld-status-badge ${statusClass}`}
          data-testid={`status-badge-${product.id}`}
        >
          {statusText}
        </span>

        {/* Product Image or Fallback */}
        {product.image_url && !imageError ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={product.image_url}
            alt={`${product.code} - ${product.title}`}
            className="ld-product-image"
            loading="lazy"
            decoding="async"
            onError={() => setImageError(true)}
          />
        ) : (
          <div className="ld-image-fallback" data-testid={`fallback-image-${product.id}`}>
            <svg
              className="ld-image-fallback-icon"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
              aria-hidden="true"
            >
              <rect width="18" height="18" x="3" y="3" rx="2" ry="2" />
              <circle cx="9" cy="9" r="2" />
              <path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21" />
            </svg>
            <span className="ld-image-fallback-text">{product.code}</span>
          </div>
        )}
      </div>

      {/* Product Details */}
      <div className="ld-card-body">
        <h3 className="ld-product-title" title={product.title}>
          {product.title}
        </h3>

        <div className="ld-card-meta">
          <span className="ld-product-price">
            {formatPaisaToINR(product.price_paisa)}
          </span>

          {product.size && (
            <span className="ld-product-size" title={`Size: ${product.size}`}>
              {product.size}
            </span>
          )}
        </div>

        {/* Add to Cart / In Cart / Status Button */}
        <div className="ld-card-action">
          {isAvailable ? (
            inCart ? (
              <button
                type="button"
                className="ld-btn-in-cart"
                onClick={handleAddToCart}
                data-testid={`cart-btn-${product.id}`}
                aria-label={`${product.code} is in your cart`}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <polyline points="20 6 9 17 4 12" />
                </svg>
                <span>In Cart</span>
              </button>
            ) : (
              <button
                type="button"
                className="ld-btn-add-cart"
                onClick={handleAddToCart}
                data-testid={`cart-btn-${product.id}`}
                aria-label={`Add ${product.code}: ${product.title} to cart`}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                  <line x1="12" y1="5" x2="12" y2="19" />
                  <line x1="5" y1="12" x2="19" y2="12" />
                </svg>
                <span>Add to Bag</span>
              </button>
            )
          ) : (
            <button
              type="button"
              className="ld-btn-disabled-status"
              disabled
              data-testid={`cart-btn-${product.id}`}
              aria-label={`${product.code} is ${statusText}`}
            >
              <span>{isReserved ? 'Reserved' : 'Sold Out'}</span>
            </button>
          )}
        </div>
      </div>
    </article>
  );
}
