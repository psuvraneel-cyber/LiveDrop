'use client';

import React, { useState, useEffect } from 'react';
import Image from 'next/image';
import { PublicProductView } from '../../types/domain';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { useOptionalCart } from '../../lib/cart/cart-context';

export interface ProductQuickViewDrawerProps {
  product: PublicProductView | null;
  dropId: string;
  storeName?: string;
  isOpen: boolean;
  onClose: () => void;
  onOpenCart?: () => void;
}

function ProductQuickViewContent({
  product,
  dropId,
  storeName,
  onClose,
  onOpenCart,
}: {
  product: PublicProductView;
  dropId: string;
  storeName: string;
  onClose: () => void;
  onOpenCart?: () => void;
}) {
  const [selectedImageIndex, setSelectedImageIndex] = useState(0);
  const [selectedSize, setSelectedSize] = useState<string>(product.size || 'Free Size');
  const [addedMessage, setAddedMessage] = useState<string | null>(null);

  const cart = useOptionalCart();

  const allImages = (product.image_urls && product.image_urls.length > 0)
    ? product.image_urls
    : [product.image_url || '/placeholder-garment.jpg'];

  const activeImage = allImages[selectedImageIndex] || allImages[0];
  const isAvailable = product.status === 'available';
  const isInCart = cart?.isInCart(product.id) ?? false;

  const handleAddToBag = () => {
    if (!isAvailable || !cart) return;

    const res = cart.addItem(product, dropId);
    if (res.success) {
      setAddedMessage('Added to Bag');
      setTimeout(() => {
        setAddedMessage(null);
        if (onOpenCart) {
          onOpenCart();
        } else if (cart.openDrawer) {
          cart.openDrawer();
        }
      }, 500);
    } else if (res.reason === 'ALREADY_IN_CART') {
      setAddedMessage('Already in Bag');
    } else {
      setAddedMessage('Unable to add piece');
    }
  };

  const handleShare = async () => {
    if (typeof navigator !== 'undefined' && navigator.share) {
      try {
        await navigator.share({
          title: `${product.code} — ${product.title}`,
          text: `Check out ${product.title} from ${storeName} on LiveDrop.`,
          url: window.location.href,
        });
      } catch {
        // User dismissed share dialog
      }
    }
  };

  return (
    <div
      className="w-full max-w-lg bg-[#0E0E12] border-t sm:border border-[rgba(212,175,55,0.25)] rounded-t-3xl sm:rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh] sm:max-h-[85vh] animate-in slide-in-from-bottom duration-300"
      onClick={(e) => e.stopPropagation()}
    >
      {/* Header Bar with Swipe Pill and Close Button */}
      <div className="relative pt-3 pb-2 px-6 flex items-center justify-between border-b border-white/5 bg-[#121217]">
        {/* Top handle pill for mobile visual affordance */}
        <div className="absolute top-2 left-1/2 -translate-x-1/2 w-10 h-1 bg-white/20 rounded-full" />

        <div className="flex items-center gap-2 pt-2">
          <span className="text-[#D4AF37] text-xs font-semibold tracking-wider font-mono uppercase bg-[rgba(212,175,55,0.12)] px-2.5 py-0.5 rounded-full border border-[rgba(212,175,55,0.3)]">
            {product.code}
          </span>
          <span className="text-white/60 text-xs font-sans">
            {storeName}
          </span>
        </div>

        <button
          type="button"
          onClick={onClose}
          className="w-8 h-8 rounded-full bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 hover:text-white transition-colors cursor-pointer"
          aria-label="Close product quick view"
          data-testid="quick-view-close-btn"
        >
          ✕
        </button>
      </div>

      {/* Scrollable Content */}
      <div className="overflow-y-auto px-6 py-4 space-y-5">
        {/* Hero Garment Image */}
        <div className="relative w-full aspect-[4/5] rounded-xl overflow-hidden bg-black/60 border border-white/5 shadow-inner">
          <Image
            src={activeImage}
            alt={product.title}
            fill
            className="object-cover object-top transition-transform duration-500 hover:scale-105"
            sizes="(max-width: 640px) 100vw, 500px"
            priority
          />

          {/* Status Badge */}
          <div className="absolute top-3 left-3 z-10">
            {isAvailable ? (
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-black/70 backdrop-blur-md border border-[#10B981]/40 text-[#34D399] text-xs font-medium">
                <span className="w-1.5 h-1.5 rounded-full bg-[#10B981]" />
                Available Piece
              </span>
            ) : product.status === 'reserved' ? (
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-black/70 backdrop-blur-md border border-[#F59E0B]/40 text-[#FBBF24] text-xs font-medium">
                <span className="w-1.5 h-1.5 rounded-full bg-[#F59E0B]" />
                Hold Reserved
              </span>
            ) : (
              <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-black/70 backdrop-blur-md border border-white/20 text-white/60 text-xs font-medium">
                Sold Out
              </span>
            )}
          </div>

          {/* Quick Share action button on image */}
          <button
            type="button"
            onClick={handleShare}
            className="absolute top-3 right-3 w-9 h-9 rounded-full bg-black/60 backdrop-blur-md border border-white/10 flex items-center justify-center text-white/80 hover:text-white transition-colors cursor-pointer"
            aria-label="Share this garment"
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="18" cy="5" r="3" />
              <circle cx="6" cy="12" r="3" />
              <circle cx="18" cy="19" r="3" />
              <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
              <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
            </svg>
          </button>
        </div>

        {/* Alternate Thumbnail Row if multiple images */}
        {allImages.length > 1 && (
          <div className="flex gap-2.5 overflow-x-auto pb-1">
            {allImages.map((img, idx) => (
              <button
                key={`thumb-${idx}`}
                type="button"
                onClick={() => setSelectedImageIndex(idx)}
                className={`relative w-16 h-20 rounded-lg overflow-hidden border-2 transition-all flex-shrink-0 cursor-pointer ${
                  selectedImageIndex === idx
                    ? 'border-[#D4AF37] ring-2 ring-[rgba(212,175,55,0.3)]'
                    : 'border-white/10 opacity-70 hover:opacity-100'
                }`}
                aria-label={`View photo angle ${idx + 1}`}
              >
                <Image
                  src={img}
                  alt={`${product.title} angle ${idx + 1}`}
                  fill
                  className="object-cover"
                  sizes="64px"
                />
              </button>
            ))}
          </div>
        )}

        {/* Product Details Section */}
        <div className="space-y-3">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h3
                id="product-quick-view-title"
                className="text-xl font-serif text-[#FBFBFB] tracking-wide"
              >
                {product.title}
              </h3>
              <p className="text-xs text-[#D4AF37] font-medium tracking-wide mt-0.5">
                Exclusive Atelier Creation
              </p>
            </div>

            {/* Formatted Integer Paisa Price */}
            <div className="text-right">
              <span className="text-xl font-serif font-bold text-[#FBFBFB] tracking-tight block">
                {formatPaisaToINR(product.price_paisa)}
              </span>
              <span className="text-[11px] text-white/50 block">Direct Studio Price</span>
            </div>
          </div>

          {/* Description if present */}
          {product.description && (
            <p className="text-xs text-[#FBFBFB]/75 leading-relaxed font-sans border-t border-white/5 pt-2">
              {product.description}
            </p>
          )}

          {/* Size Options */}
          <div className="space-y-1.5 pt-1">
            <div className="flex justify-between items-center text-xs">
              <span className="text-white/70 font-medium">Size</span>
              <span className="text-[#D4AF37] font-mono text-[11px]">{selectedSize || product.size}</span>
            </div>

            <div className="flex flex-wrap gap-2">
              {['XS', 'S', 'M', 'L', 'XL', 'Free Size'].map((sz) => {
                const isCurrent = (product.size || '').toLowerCase() === sz.toLowerCase();
                const isSelected = selectedSize === sz;

                return (
                  <button
                    key={sz}
                    type="button"
                    onClick={() => setSelectedSize(sz)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-medium font-mono transition-all cursor-pointer ${
                      isSelected
                        ? 'bg-[#D4AF37] text-black font-bold shadow-md shadow-[rgba(212,175,55,0.25)]'
                        : isCurrent
                        ? 'bg-white/10 text-white border border-[rgba(212,175,55,0.4)]'
                        : 'bg-white/5 text-white/60 hover:bg-white/10 border border-white/5'
                    }`}
                  >
                    {sz}
                  </button>
                );
              })}
            </div>
          </div>

          {/* Trust Assurances Row */}
          <div className="grid grid-cols-3 gap-2 pt-2 border-t border-white/5 text-center">
            <div className="py-2 px-1 rounded-lg bg-white/[0.02] border border-white/5">
              <span className="block text-xs font-serif text-[#D4AF37]">✦ 100%</span>
              <span className="text-[10px] text-white/60">Authentic</span>
            </div>
            <div className="py-2 px-1 rounded-lg bg-white/[0.02] border border-white/5">
              <span className="block text-xs font-serif text-[#D4AF37]">15 Min</span>
              <span className="text-[10px] text-white/60">Reserve Hold</span>
            </div>
            <div className="py-2 px-1 rounded-lg bg-white/[0.02] border border-white/5">
              <span className="block text-xs font-serif text-[#D4AF37]">Direct UPI</span>
              <span className="text-[10px] text-white/60">Safe Settlement</span>
            </div>
          </div>
        </div>
      </div>

      {/* Bottom Sticky Action Bar */}
      <div className="p-4 bg-[#121217] border-t border-white/10 flex items-center gap-3">
        <button
          type="button"
          onClick={handleAddToBag}
          disabled={!isAvailable}
          className={`flex-1 py-3.5 px-6 rounded-full font-sans text-sm font-bold tracking-wide transition-all shadow-lg flex items-center justify-center gap-2 cursor-pointer ${
            !isAvailable
              ? 'bg-white/10 text-white/40 cursor-not-allowed border border-white/5'
              : 'bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] hover:brightness-110 shadow-[0_4px_16px_rgba(212,175,55,0.25)] active:scale-[0.98]'
          }`}
          data-testid="quick-view-add-to-bag-btn"
        >
          {addedMessage ? (
            <span>✓ {addedMessage}</span>
          ) : isInCart ? (
            <span>In Your Bag • Add Another</span>
          ) : isAvailable ? (
            <>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.25">
                <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                <path d="M3 6h18" />
                <path d="M16 10a4 4 0 0 1-8 0" />
              </svg>
              <span>Add to Bag • {formatPaisaToINR(product.price_paisa)}</span>
            </>
          ) : (
            <span>Unavailable</span>
          )}
        </button>
      </div>
    </div>
  );
}

export function ProductQuickViewDrawer({
  product,
  dropId,
  storeName = 'LiveDrop Atelier',
  isOpen,
  onClose,
  onOpenCart,
}: ProductQuickViewDrawerProps) {
  // Handle escape key
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

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/75 backdrop-blur-sm transition-opacity duration-300"
      role="dialog"
      aria-modal="true"
      aria-labelledby="product-quick-view-title"
      data-testid="product-quick-view-drawer"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <ProductQuickViewContent
        key={product.id}
        product={product}
        dropId={dropId}
        storeName={storeName}
        onClose={onClose}
        onOpenCart={onOpenCart}
      />
    </div>
  );
}
