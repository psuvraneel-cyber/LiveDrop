import React, { useState } from 'react';
import { PublicProductView } from '../types/domain';
import { formatPaisaToINR } from '../lib/utils/currency';

export interface ProductCardProps {
  product: PublicProductView;
}

export function ProductCard({ product }: ProductCardProps) {
  const [imageError, setImageError] = useState(false);
  const isAvailable = product.status === 'available';
  const isReserved = product.status === 'reserved';
  const isSold = product.status === 'sold';

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
      </div>
    </article>
  );
}
