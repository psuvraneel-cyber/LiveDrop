import React, { useState } from 'react';
import { PublicProductView } from '../types/domain';
import { formatPaisaToINR } from '../lib/utils/currency';
import { useOptionalCart } from '../lib/cart/cart-context';
import { ProductDetailModal } from './ProductDetailModal';

export interface ProductCardProps {
  product: PublicProductView;
  dropId?: string;
  storeName?: string;
  onAddToCart?: (product: PublicProductView) => void;
}

export function ProductCard({ product, dropId, storeName, onAddToCart }: ProductCardProps) {
  const images = (product.image_urls && product.image_urls.length > 0)
    ? product.image_urls
    : (product.image_url ? [product.image_url] : []);

  const [activeImageIndex, setActiveImageIndex] = useState(0);
  const [imageErrors, setImageErrors] = useState<Record<number, boolean>>({});
  const [isDetailOpen, setIsDetailOpen] = useState(false);
  const cart = useOptionalCart();

  const isAvailable = product.status === 'available';
  const isReserved = product.status === 'reserved';
  const isSold = product.status === 'sold';

  const inCart = cart ? cart.isInCart(product.id) : false;
  const hasMultipleImages = images.length > 1;

  const currentImageUrl = images[activeImageIndex] || product.image_url;
  const isCurrentError = imageErrors[activeImageIndex] || (!currentImageUrl);

  const handlePrevImage = (e: React.MouseEvent) => {
    e.stopPropagation();
    setActiveImageIndex((prev) => (prev > 0 ? prev - 1 : images.length - 1));
  };

  const handleNextImage = (e: React.MouseEvent) => {
    e.stopPropagation();
    setActiveImageIndex((prev) => (prev < images.length - 1 ? prev + 1 : 0));
  };

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
    <>
      <article
        className={`ld-product-card ${!isAvailable ? 'unavailable' : ''}`}
        data-testid={`product-card-${product.id}`}
        aria-label={`${product.code}: ${product.title} - ${formatPaisaToINR(product.price_paisa)} - ${statusText}`}
        onClick={() => setIsDetailOpen(true)}
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
        {currentImageUrl && !isCurrentError ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={currentImageUrl}
            alt={`${product.code} - ${product.title}${hasMultipleImages ? ` (Angle ${activeImageIndex + 1})` : ''}`}
            className="ld-product-image"
            loading="lazy"
            decoding="async"
            onError={() => setImageErrors((prev) => ({ ...prev, [activeImageIndex]: true }))}
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

        {/* Multi-angle Navigation Arrows */}
        {hasMultipleImages && (
          <>
            <button
              type="button"
              className="ld-carousel-nav ld-carousel-prev"
              onClick={handlePrevImage}
              aria-label="Previous image"
              data-testid={`carousel-prev-${product.id}`}
            >
              &#8249;
            </button>
            <button
              type="button"
              className="ld-carousel-nav ld-carousel-next"
              onClick={handleNextImage}
              aria-label="Next image"
              data-testid={`carousel-next-${product.id}`}
            >
              &#8250;
            </button>
          </>
        )}

        {/* Multi-angle Dot Indicators */}
        {hasMultipleImages && (
          <div className="ld-carousel-dots" data-testid={`carousel-dots-${product.id}`}>
            {images.map((_, idx) => (
              <button
                key={idx}
                type="button"
                className={`ld-carousel-dot ${idx === activeImageIndex ? 'active' : ''}`}
                onClick={(e) => {
                  e.stopPropagation();
                  setActiveImageIndex(idx);
                }}
                aria-label={`View angle ${idx + 1} of ${images.length}`}
              />
            ))}
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
    <ProductDetailModal
      product={product}
      isOpen={isDetailOpen}
      onClose={() => setIsDetailOpen(false)}
      dropId={dropId}
      storeName={storeName}
      onAddToCart={onAddToCart}
    />
  </>
  );
}
