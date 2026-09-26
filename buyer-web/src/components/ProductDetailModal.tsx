'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { PublicProductView } from '../types/domain';
import { formatPaisaToINR } from '../lib/utils/currency';
import { useOptionalCart } from '../lib/cart/cart-context';

export interface ProductDetailModalProps {
  product: PublicProductView | null;
  isOpen: boolean;
  onClose: () => void;
  dropId?: string;
  storeName?: string;
  storeRating?: string;
  storeReviewsCount?: number;
  onAddToCart?: (product: PublicProductView) => void;
}

export function ProductDetailModal({
  product,
  isOpen,
  onClose,
  dropId,
  storeName = 'Priya Boutique',
  storeRating = '4.9',
  storeReviewsCount = 128,
  onAddToCart,
}: ProductDetailModalProps) {
  const router = useRouter();
  const cart = useOptionalCart();

  const [prevProductId, setPrevProductId] = useState(product?.id);
  const [activeImageIndex, setActiveImageIndex] = useState(0);
  const [imageErrors, setImageErrors] = useState<Record<number, boolean>>({});
  const [isWishlisted, setIsWishlisted] = useState(false);
  const [copiedLink, setCopiedLink] = useState(false);

  // Reset active image when product changes
  if (product?.id !== prevProductId) {
    setPrevProductId(product?.id);
    setActiveImageIndex(0);
    setImageErrors({});
    setCopiedLink(false);
  }

  // Lock body scroll when modal is open
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

  // Escape key listener
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && isOpen) {
        onClose();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, onClose]);

  if (!isOpen || !product) {
    return null;
  }

  const images =
    product.image_urls && product.image_urls.length > 0
      ? product.image_urls
      : product.image_url
      ? [product.image_url]
      : [];

  const isAvailable = product.status === 'available';
  const isReserved = product.status === 'reserved';
  const isSold = product.status === 'sold';
  const inCart = cart ? cart.isInCart(product.id) : false;

  const currentImageUrl = images[activeImageIndex] || product.image_url;
  const isCurrentError = imageErrors[activeImageIndex] || !currentImageUrl;

  const handlePrevImage = (e: React.MouseEvent) => {
    e.stopPropagation();
    setActiveImageIndex((prev) => (prev > 0 ? prev - 1 : images.length - 1));
  };

  const handleNextImage = (e: React.MouseEvent) => {
    e.stopPropagation();
    setActiveImageIndex((prev) => (prev < images.length - 1 ? prev + 1 : 0));
  };

  const handleShare = async () => {
    const shareData = {
      title: `${product.code}: ${product.title}`,
      text: `Check out ${product.title} on LiveDrop for ${formatPaisaToINR(product.price_paisa)}!`,
      url: typeof window !== 'undefined' ? window.location.href : '',
    };
    if (typeof navigator !== 'undefined' && navigator.share) {
      try {
        await navigator.share(shareData);
      } catch {
        // User cancelled or unsupported
      }
    } else if (typeof navigator !== 'undefined' && navigator.clipboard) {
      await navigator.clipboard.writeText(shareData.url);
      setCopiedLink(true);
      setTimeout(() => setCopiedLink(false), 2000);
    }
  };

  const handleAddToCart = () => {
    if (onAddToCart) {
      onAddToCart(product);
      return;
    }
    if (cart && isAvailable) {
      const targetDropId = dropId || (product as unknown as { drop_id?: string }).drop_id || cart.dropId || '';
      cart.addItem(product, targetDropId);
    }
  };

  const handleBuyNow = () => {
    if (isAvailable) {
      if (cart && !inCart) {
        const targetDropId = dropId || (product as unknown as { drop_id?: string }).drop_id || cart.dropId || '';
        cart.addItem(product, targetDropId);
      }
      onClose();
      router.push('/checkout');
    }
  };

  // Derive craftsmanship tags (Screen 04 reference: 4 badges)
  const tags: string[] = [];
  if (product.title.toLowerCase().includes('silk') || product.description?.toLowerCase().includes('silk')) {
    tags.push('✦ Pure Handloom Silk');
  } else {
    tags.push('✦ Handcrafted Artisan Weave');
  }
  if (product.title.toLowerCase().includes('zari') || product.description?.toLowerCase().includes('zari')) {
    tags.push('✦ Zari Woven Border');
  } else {
    tags.push('✦ Hand-Embroidered Detailing');
  }
  tags.push('✦ Blouse Piece Included');
  tags.push('✦ Dry Clean Only');

  // Stock status pill
  let stockBadge = 'Available';
  let stockBadgeClass = 'ld-badge-available';
  if (isReserved) {
    stockBadge = 'Reserved';
    stockBadgeClass = 'ld-badge-reserved';
  } else if (isSold) {
    stockBadge = 'Sold Out';
    stockBadgeClass = 'ld-badge-sold';
  } else if (product.quantity_available && product.quantity_available <= 3) {
    stockBadge = `Only ${product.quantity_available} Left`;
    stockBadgeClass = 'ld-badge-urgent';
  }

  return (
    <div
      className="ld-modal-backdrop"
      onClick={onClose}
      data-testid="product-detail-modal-backdrop"
      role="dialog"
      aria-modal="true"
      aria-labelledby="product-detail-title"
    >
      <div
        className="ld-product-sheet"
        onClick={(e) => e.stopPropagation()}
        data-testid={`product-detail-sheet-${product.id}`}
      >
        {/* Mobile Pull Indicator */}
        <div className="ld-sheet-handle-bar" aria-hidden="true">
          <div className="ld-sheet-handle" />
        </div>

        {/* Top Action Nav Bar */}
        <header className="ld-sheet-header">
          <button
            type="button"
            className="ld-sheet-btn-icon"
            onClick={onClose}
            aria-label="Close product details"
            data-testid="product-detail-close-btn"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="19" y1="12" x2="5" y2="12" />
              <polyline points="12 19 5 12 12 5" />
            </svg>
          </button>

          <div className="ld-sheet-header-actions">
            <button
              type="button"
              className={`ld-sheet-btn-icon ${isWishlisted ? 'active' : ''}`}
              onClick={() => setIsWishlisted(!isWishlisted)}
              aria-label={isWishlisted ? 'Remove from wishlist' : 'Add to wishlist'}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill={isWishlisted ? 'var(--gold-primary)' : 'none'} stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
              </svg>
            </button>

            <button
              type="button"
              className="ld-sheet-btn-icon"
              onClick={handleShare}
              aria-label="Share product"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="18" cy="5" r="3" />
                <circle cx="6" cy="12" r="3" />
                <circle cx="18" cy="19" r="3" />
                <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
                <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
              </svg>
            </button>
          </div>
        </header>

        {copiedLink && (
          <div className="ld-sheet-toast">Link copied to clipboard!</div>
        )}

        {/* Scrollable Sheet Content */}
        <div className="ld-sheet-body">
          {/* Main Product Hero Image Showcase */}
          <div className="ld-sheet-media-box">
            <div className="ld-sheet-media-frame">
              {currentImageUrl && !isCurrentError ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={currentImageUrl}
                  alt={`${product.code} - ${product.title}`}
                  className="ld-sheet-main-img"
                  loading="eager"
                  onError={() => setImageErrors((prev) => ({ ...prev, [activeImageIndex]: true }))}
                />
              ) : (
                <div className="ld-sheet-img-fallback">
                  <span className="ld-sheet-fallback-code">{product.code}</span>
                  <span>{product.title}</span>
                </div>
              )}

              {/* Angle Navigation Arrows if multiple images */}
              {images.length > 1 && (
                <>
                  <button
                    type="button"
                    className="ld-sheet-nav-arrow ld-sheet-nav-prev"
                    onClick={handlePrevImage}
                    aria-label="Previous angle"
                  >
                    &#8249;
                  </button>
                  <button
                    type="button"
                    className="ld-sheet-nav-arrow ld-sheet-nav-next"
                    onClick={handleNextImage}
                    aria-label="Next angle"
                  >
                    &#8250;
                  </button>
                </>
              )}

              {/* Photo Counter Badge (Screen 04) */}
              <div
                className="absolute bottom-3 right-3 px-2 py-0.5 rounded-full bg-black/75 backdrop-blur-md border border-white/10 text-white font-mono text-[10px]"
                data-testid="product-detail-counter"
              >
                {activeImageIndex + 1}/{images.length || 1}
              </div>
            </div>

            {/* Thumbnail Strip */}
            {images.length > 1 && (
              <div className="ld-sheet-thumb-strip">
                {images.map((img, idx) => (
                  <button
                    key={idx}
                    type="button"
                    className={`ld-sheet-thumb-btn ${idx === activeImageIndex ? 'active' : ''}`}
                    onClick={() => setActiveImageIndex(idx)}
                    aria-label={`View photo ${idx + 1}`}
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={img} alt={`Thumb ${idx + 1}`} className="ld-sheet-thumb-img" />
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Product Identification & Pricing */}
          <div className="ld-sheet-info-section">
            <div className="ld-sheet-badge-row">
              <span className="ld-sheet-code">{product.code}</span>
              <span className={`ld-sheet-stock-badge ${stockBadgeClass}`}>
                {stockBadge}
              </span>
            </div>

            <h1 id="product-detail-title" className="ld-sheet-title">
              {product.title}
            </h1>

            <div className="ld-sheet-price-row">
              <span className="ld-sheet-price">
                {formatPaisaToINR(product.price_paisa)}
              </span>
              {product.size && (
                <span className="ld-sheet-size-pill">
                  Size: <strong>{product.size}</strong>
                </span>
              )}
            </div>

            {/* Description */}
            <p className="ld-sheet-desc">
              {product.description ||
                'Pure handcrafted boutique creation with traditional artisan weave. Elegant, festive, and timeless. An exclusive single piece curated for special moments.'}
            </p>

            {/* Feature Tags */}
            <div className="ld-sheet-tags-list">
              {tags.map((tag, i) => (
                <span key={i} className="ld-sheet-tag-chip">
                  <span className="ld-sheet-tag-dot" />
                  {tag}
                </span>
              ))}
            </div>

            {/* Delivery & Authentic Guarantees (Screen 04) */}
            <div className="p-3 rounded-xl bg-white/[0.03] border border-white/5 space-y-1.5 text-xs text-[#AAA49A]">
              <div className="flex items-center gap-2 text-[#F4F1EA] font-semibold text-xs">
                <span>🚚</span>
                <span>Complimentary Insured Delivery</span>
              </div>
              <p className="text-[11px] leading-relaxed text-[#AAA49A]">
                Dispatch within 24–48 hours directly from {storeName}. Includes 48-hour authentic artisanal verification guarantee.
              </p>
            </div>

            {/* Boutique Seller Profile Card */}
            <div className="ld-sheet-boutique-card">
              <div className="ld-sheet-boutique-avatar">
                {storeName.charAt(0)}
              </div>
              <div className="ld-sheet-boutique-meta">
                <span className="ld-sheet-boutique-name">{storeName}</span>
                <span className="ld-sheet-boutique-rating">
                  ★ {storeRating} ({storeReviewsCount} verified reviews)
                </span>
              </div>
              <button
                type="button"
                className="ld-sheet-boutique-btn"
                onClick={onClose}
              >
                View Shop
              </button>
            </div>
          </div>
        </div>

        {/* Sticky Bottom Action Bar */}
        <footer className="ld-sheet-footer">
          {isAvailable ? (
            <div className="ld-sheet-footer-actions">
              <button
                type="button"
                className={`ld-sheet-cart-btn ${inCart ? 'in-cart' : ''}`}
                onClick={handleAddToCart}
                data-testid={`sheet-add-to-cart-${product.id}`}
              >
                {inCart ? (
                  <>
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                    <span>In Bag</span>
                  </>
                ) : (
                  <>
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <circle cx="8" cy="21" r="1" />
                      <circle cx="19" cy="21" r="1" />
                      <path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12" />
                    </svg>
                    <span>Add to Bag</span>
                  </>
                )}
              </button>

              <button
                type="button"
                className="ld-sheet-buy-btn"
                onClick={handleBuyNow}
                data-testid={`sheet-buy-now-${product.id}`}
              >
                <span>Buy Now</span>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <line x1="5" y1="12" x2="19" y2="12" />
                  <polyline points="12 5 19 12 12 19" />
                </svg>
              </button>
            </div>
          ) : (
            <button
              type="button"
              className="ld-sheet-disabled-btn"
              disabled
            >
              {isReserved ? 'Item Currently Reserved' : 'Sold Out'}
            </button>
          )}
        </footer>
      </div>
    </div>
  );
}
