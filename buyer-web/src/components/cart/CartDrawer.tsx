'use client';

/**
 * LiveDrop — Screen 6: Cart Drawer
 *
 * Full-fidelity implementation of Screen 6 from the Haute Couture template.
 * Features item cards with square thumbnails, quantity steppers, trash actions,
 * expandable gift note input, structured order summary, and luxury assurance badges.
 */

import React, { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { useCart } from '../../lib/cart/cart-context';
import { PublicDropCatalog, PublicProductView } from '../../types/domain';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { CartEmptyState } from './CartEmptyState';
import { CartItemRow } from './CartItemRow';

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
  const {
    items,
    itemCount,
    orderNote,
    setOrderNote,
    removeItem,
    clearCart,
    getReconciledItems,
  } = useCart();

  const [isNoteOpen, setIsNoteOpen] = useState(false);
  const [noteDraft, setNoteDraft] = useState(orderNote);
  const [prevOrderNote, setPrevOrderNote] = useState(orderNote);
  const drawerRef = useRef<HTMLDivElement>(null);
  const router = useRouter();

  if (prevOrderNote !== orderNote) {
    setPrevOrderNote(orderNote);
    setNoteDraft(orderNote);
  }

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

  // Compute payable subtotal strictly from available items
  const availableItems = reconciledItems.filter((item) => item.isAvailable);
  const payableSubtotalPaisa = availableItems.reduce(
    (sum, item) => sum + Math.floor(item.pricePaisa),
    0
  );

  // Compute shipping fee based on drop or seller thresholds
  const freeThreshold = drop?.profiles?.free_shipping_threshold_paisa ?? 200000;
  const standardFee = drop?.profiles?.default_shipping_fee_paisa ?? 8000;
  const isFreeShipping = payableSubtotalPaisa >= freeThreshold;
  const shippingFeePaisa = isFreeShipping || availableItems.length === 0 ? 0 : standardFee;
  const totalPaisa = payableSubtotalPaisa + shippingFeePaisa;

  const handleProceedToCheckout = () => {
    onClose();
    router.push('/checkout');
  };

  const handleSaveNote = () => {
    setOrderNote(noteDraft.trim());
    setIsNoteOpen(false);
  };

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
        {/* 1. Header: Back Arrow '<' + Title 'Your Cart (N)' */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-white/10 sticky top-0 bg-[#08080A]/95 backdrop-blur-md z-10">
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={onClose}
              className="w-8 h-8 rounded-full bg-white/5 border border-white/10 hover:bg-white/10 flex items-center justify-center text-white/80 hover:text-white transition-colors"
              aria-label="Back to shopping"
              data-testid="cart-back-btn"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="19" y1="12" x2="5" y2="12" />
                <polyline points="12 19 5 12 12 5" />
              </svg>
            </button>
            <h2 id="cart-drawer-title" className="text-base sm:text-lg font-serif tracking-wide text-white font-medium">
              Your Cart {itemCount > 0 ? `(${itemCount})` : ''}
            </h2>
          </div>

          <div className="flex items-center gap-2">
            {items.length > 0 && (
              <button
                type="button"
                onClick={clearCart}
                className="text-xs text-white/40 hover:text-red-400 font-mono transition-colors"
                data-testid="cart-clear-btn"
              >
                Clear
              </button>
            )}
            <button
              type="button"
              onClick={onClose}
              className="w-8 h-8 rounded-full bg-white/5 border border-white/10 hover:bg-white/10 flex items-center justify-center text-white/60 hover:text-white transition-colors"
              aria-label="Close cart drawer"
              data-testid="cart-drawer-close"
            >
              ✕
            </button>
          </div>
        </div>

        {/* 2. Drawer Content */}
        {items.length === 0 ? (
          <div className="flex-1 flex items-center justify-center p-6">
            <CartEmptyState onBrowse={onClose} />
          </div>
        ) : (
          <div className="flex-1 overflow-y-auto p-4 sm:p-5 space-y-4 scrollbar-none">
            {/* Informational Stock Notice */}
            <div className="p-3 rounded-xl bg-[rgba(212,175,55,0.08)] border border-[rgba(212,175,55,0.2)] flex items-start gap-2.5 text-xs text-[#F3E5AB]">
              <span className="text-[#D4AF37] mt-0.5">✦</span>
              <span className="leading-relaxed">
                Garments are held temporarily during active checkout. Live drops are single-piece limited editions.
              </span>
            </div>

            {/* Unavailable items alert banner */}
            {hasUnavailableItems && (
              <div
                className="p-3.5 rounded-xl bg-red-950/40 border border-red-500/40 text-xs text-red-300 space-y-2.5"
                data-testid="cart-unavailable-banner"
              >
                <div className="flex items-start gap-2">
                  <span className="font-bold">Notice:</span>
                  <span>
                    {availableItems.length === 0
                      ? 'All items in your bag were claimed offline or by another buyer. Please remove them to continue.'
                      : 'One or more items in your cart were claimed offline or by another buyer. Please remove them to proceed.'}
                  </span>
                </div>
                <div className="flex justify-end">
                  <button
                    type="button"
                    onClick={() => {
                      reconciledItems
                        .filter((item) => !item.isAvailable)
                        .forEach((item) => removeItem(item.productId));
                    }}
                    className="px-3 py-1 rounded bg-red-900/60 hover:bg-red-800/80 text-red-200 border border-red-500/30 text-[11px] font-mono transition-colors"
                    data-testid="cart-remove-unavailable-btn"
                  >
                    Remove Unavailable Items
                  </button>
                </div>
              </div>
            )}

            {/* 3. Items List */}
            <div className="space-y-3" data-testid="cart-items-list">
              {reconciledItems.map((item) => (
                <CartItemRow
                  key={item.productId}
                  item={item}
                  onRemove={removeItem}
                  isAvailable={item.isAvailable}
                  availabilityReason={item.availabilityReason}
                />
              ))}
            </div>

            {/* When NO items are available in the bag */}
            {availableItems.length === 0 ? (
              <div className="p-4 rounded-xl bg-white/[0.03] border border-white/10 text-center space-y-3 shadow-md">
                <p className="text-xs text-white/70">
                  No available pieces remaining in your bag. Explore available collections from active boutique drops.
                </p>
                <button
                  type="button"
                  onClick={() => {
                    onClose();
                    router.push('/shop');
                  }}
                  className="w-full py-3 rounded-full bg-[#D4AF37] hover:bg-[#F3E5AB] text-[#08080A] font-serif font-bold text-xs tracking-wider uppercase transition-colors shadow-md"
                  data-testid="cart-continue-shopping-btn"
                >
                  Explore Collections →
                </button>
                <button
                  type="button"
                  disabled
                  className="w-full py-2.5 rounded-full font-sans text-xs text-white/30 bg-transparent border border-white/5 cursor-not-allowed"
                  data-testid="cart-checkout-btn"
                >
                  Checkout Unavailable (0 Pieces)
                </button>
              </div>
            ) : (
              <>
                {/* 4. Add a Note (Optional) Card */}
                <div className="rounded-xl bg-[#101014] border border-white/10 overflow-hidden shadow-sm">
                  <button
                    type="button"
                    onClick={() => setIsNoteOpen((prev) => !prev)}
                    className="w-full p-3.5 flex items-center justify-between text-left hover:bg-white/5 transition-colors group"
                    data-testid="cart-note-toggle"
                  >
                    <div className="flex items-center gap-2.5">
                      <span className="text-base" role="img" aria-label="Gift">🎁</span>
                      <span className="text-xs font-medium text-white/90">
                        {orderNote ? `Note: "${orderNote.slice(0, 30)}${orderNote.length > 30 ? '...' : ''}"` : 'Add a note (optional)'}
                      </span>
                    </div>
                    <span className="text-xs text-white/40 group-hover:text-[#D4AF37] transition-colors">
                      {isNoteOpen ? '▲' : '▼'}
                    </span>
                  </button>

                  {isNoteOpen && (
                    <div className="p-3 border-t border-white/5 space-y-2.5 bg-black/40">
                      <textarea
                        rows={2}
                        value={noteDraft}
                        onChange={(e) => setNoteDraft(e.target.value)}
                        placeholder="Special delivery instructions or personalized gift message..."
                        maxLength={300}
                        className="w-full p-2.5 rounded-lg bg-black/70 border border-white/15 text-white text-xs focus:outline-none focus:border-[#D4AF37] transition-colors resize-none"
                        data-testid="cart-note-input"
                      />
                      <div className="flex justify-end gap-2">
                        <button
                          type="button"
                          onClick={() => setIsNoteOpen(false)}
                          className="px-3 py-1 rounded text-[11px] text-white/50 hover:text-white"
                        >
                          Cancel
                        </button>
                        <button
                          type="button"
                          onClick={handleSaveNote}
                          className="px-3 py-1 rounded bg-[#D4AF37] text-[#08080A] text-[11px] font-bold uppercase tracking-wider hover:bg-[#F3E5AB]"
                          data-testid="cart-save-note-btn"
                        >
                          Save Note
                        </button>
                      </div>
                    </div>
                  )}
                </div>

                {/* 5. Order Summary Card */}
                <div className="p-4 rounded-2xl bg-[#101014] border border-[rgba(212,175,55,0.2)] space-y-3 shadow-lg">
                  <h3 className="text-sm font-serif font-bold text-white tracking-wide border-b border-white/5 pb-2">
                    Order Summary
                  </h3>

                  <div className="space-y-1.5 text-xs text-white/70">
                    <div className="flex justify-between">
                      <span>Subtotal</span>
                      <span className="font-mono text-white" data-testid="cart-subtotal">
                        {formatPaisaToINR(payableSubtotalPaisa)}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span>Shipping</span>
                      <span className="font-mono text-[#D4AF37]">
                        {isFreeShipping ? 'FREE' : formatPaisaToINR(shippingFeePaisa)}
                      </span>
                    </div>
                  </div>

                  <div className="pt-2 border-t border-white/10 flex justify-between items-baseline">
                    <span className="text-sm font-serif font-bold text-white tracking-wide">Total</span>
                    <span className="text-lg font-serif font-bold text-[#F3E5AB]" data-testid="cart-total">
                      {formatPaisaToINR(totalPaisa)}
                    </span>
                  </div>
                </div>

                {/* 6. Proceed to Checkout CTA */}
                <button
                  type="button"
                  onClick={handleProceedToCheckout}
                  disabled={hasUnavailableItems}
                  className={`w-full py-3.5 rounded-full font-serif font-bold text-sm tracking-wider uppercase transition-all shadow-xl ${
                    hasUnavailableItems
                      ? 'bg-white/10 text-white/30 cursor-not-allowed border border-white/5'
                      : 'bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] hover:scale-[1.01] shadow-[rgba(212,175,55,0.25)]'
                  }`}
                  data-testid="cart-checkout-btn"
                >
                  {hasUnavailableItems ? 'Remove Unavailable Items to Checkout' : 'Proceed to Checkout →'}
                </button>
              </>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
