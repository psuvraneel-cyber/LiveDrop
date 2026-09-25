'use client';

/**
 * LiveDrop — Dedicated Buyer Cart Page (/cart) (Screen 6)
 *
 * Full-fidelity implementation of Screen 6 from the Haute Couture template.
 * Features item cards with square thumbnails, quantity steppers, trash actions,
 * expandable gift note input, structured order summary, and luxury assurance badges.
 */

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useCart, CartProvider, useOptionalCart } from '../../lib/cart/cart-context';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { CartEmptyState } from '../../components/cart/CartEmptyState';
import { CartItemRow } from '../../components/cart/CartItemRow';
import { getBuyerClient } from '../../lib/supabase/client';
import { getPublicProductsForDrop } from '../../lib/data/buyer-catalog';
import { PublicProductView } from '../../types/domain';
import { MobileBottomDock } from '../../components/navigation/MobileBottomDock';

function CartPageContent() {
  const router = useRouter();
  const {
    items,
    itemCount,
    dropId,
    orderNote,
    setOrderNote,
    isHydrated,
    removeItem,
    clearCart,
    getReconciledItems,
  } = useCart();

  const [catalogProducts, setCatalogProducts] = useState<PublicProductView[]>([]);
  const [isNoteOpen, setIsNoteOpen] = useState(false);
  const [noteDraft, setNoteDraft] = useState(orderNote);
  const [prevOrderNote, setPrevOrderNote] = useState(orderNote);

  if (prevOrderNote !== orderNote) {
    setPrevOrderNote(orderNote);
    setNoteDraft(orderNote);
  }

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
      <div className="ld-cart-page-loading min-h-screen bg-[#08080A] flex items-center justify-center" data-testid="cart-page-loading">
        <div className="ld-spinner" />
      </div>
    );
  }

  const reconciledItems = getReconciledItems(catalogProducts);
  const hasUnavailableItems = reconciledItems.some((item) => !item.isAvailable);

  // Compute payable subtotal strictly from available items
  const availableItems = reconciledItems.filter((item) => item.isAvailable);
  const payableSubtotalPaisa = availableItems.reduce(
    (sum, item) => sum + Math.floor(item.pricePaisa),
    0
  );

  const freeThreshold = 200000;
  const standardFee = 8000;
  const isFreeShipping = payableSubtotalPaisa >= freeThreshold;
  const shippingFeePaisa = isFreeShipping || availableItems.length === 0 ? 0 : standardFee;
  const totalPaisa = payableSubtotalPaisa + shippingFeePaisa;

  const handleSaveNote = () => {
    setOrderNote(noteDraft.trim());
    setIsNoteOpen(false);
  };

  return (
    <div className="min-h-screen bg-[#090909] text-[#F4F1EA] pb-24 font-sans" data-testid="cart-page">
      {/* 1. Header: Back Arrow '<' + Title 'Your Cart (N)' */}
      <header className="px-4 py-4 border-b border-white/10 sticky top-0 bg-[#08080A]/95 backdrop-blur-md z-10">
        <div className="max-w-2xl mx-auto flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Link
              href="/"
              className="w-8 h-8 rounded-full bg-white/5 border border-white/10 hover:bg-white/10 flex items-center justify-center text-white/80 hover:text-white transition-colors"
              aria-label="Back to home"
              data-testid="cart-back-btn"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <line x1="19" y1="12" x2="5" y2="12" />
                <polyline points="12 19 5 12 12 5" />
              </svg>
            </Link>
            <h1 className="text-lg sm:text-xl font-serif tracking-wide text-white font-medium">
              Your Cart {itemCount > 0 ? `(${itemCount})` : ''}
            </h1>
          </div>

          {items.length > 0 && (
            <button
              type="button"
              onClick={clearCart}
              className="text-xs text-white/40 hover:text-red-400 font-mono transition-colors"
              data-testid="cart-page-clear-btn"
            >
              Clear
            </button>
          )}
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-4 pt-4 space-y-4" role="main">
        {/* Informational Stock Notice */}
        {items.length > 0 && (
          <div className="p-3 rounded-xl bg-[rgba(212,175,55,0.08)] border border-[rgba(212,175,55,0.2)] flex items-start gap-2.5 text-xs text-[#F3E5AB]">
            <span className="text-[#D4AF37] mt-0.5">✦</span>
            <span className="leading-relaxed">
              Items are not reserved until checkout. Live drops are single-piece limited editions.
            </span>
          </div>
        )}

        {/* Unavailable items alert banner */}
        {hasUnavailableItems && (
          <div className="p-3.5 rounded-xl bg-red-950/40 border border-red-500/40 text-xs text-red-300 flex items-start gap-2.5" data-testid="page-cart-unavailable-banner">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="flex-shrink-0 mt-0.5">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            <span>Some items in your cart were claimed by another buyer. Please remove them to proceed.</span>
          </div>
        )}

        {items.length === 0 ? (
          <div className="py-12 flex justify-center">
            <CartEmptyState />
          </div>
        ) : (
          <div className="space-y-4">
            {/* 3. Items List */}
            <div className="space-y-3" role="list" aria-label="Cart items" data-testid="cart-items-list">
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

            {/* 4. Add a Note (Optional) Card */}
            <div className="rounded-xl bg-[#101014] border border-white/10 overflow-hidden shadow-sm">
              <button
                type="button"
                onClick={() => setIsNoteOpen((prev) => !prev)}
                className="w-full p-3.5 flex items-center justify-between text-left hover:bg-white/5 transition-colors group"
                data-testid="cart-page-note-toggle"
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
                    data-testid="cart-page-note-input"
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
                      data-testid="cart-page-save-note-btn"
                    >
                      Save Note
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* 5. Order Summary Card */}
            <div className="p-4 sm:p-5 rounded-2xl bg-[#101014] border border-[rgba(212,175,55,0.2)] space-y-3 shadow-lg">
              <h3 className="text-base font-serif font-bold text-white tracking-wide border-b border-white/5 pb-2">
                Order Summary
              </h3>

              <div className="space-y-2 text-xs sm:text-sm text-white/70">
                <div className="flex justify-between">
                  <span>Subtotal</span>
                  <span className="font-mono text-white font-medium" data-testid="cart-page-subtotal">
                    {formatPaisaToINR(payableSubtotalPaisa)}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span>Shipping</span>
                  <span className="font-mono text-[#D4AF37] font-medium">
                    {isFreeShipping ? 'FREE' : formatPaisaToINR(shippingFeePaisa)}
                  </span>
                </div>
              </div>

              <div className="pt-2 border-t border-white/10 flex justify-between items-baseline">
                <span className="text-base font-serif font-bold text-white tracking-wide">Total</span>
                <span className="text-xl font-serif font-bold text-[#F3E5AB]" data-testid="cart-page-total">
                  {formatPaisaToINR(totalPaisa)}
                </span>
              </div>
            </div>

            {/* 6. Proceed to Checkout CTA */}
            <button
              type="button"
              onClick={() => {
                if (!hasUnavailableItems && availableItems.length > 0) {
                  router.push('/checkout');
                }
              }}
              disabled={hasUnavailableItems || availableItems.length === 0}
              className={`w-full py-4 rounded-full font-serif font-bold text-sm tracking-wider uppercase transition-all shadow-xl ${
                hasUnavailableItems || availableItems.length === 0
                  ? 'bg-white/10 text-white/30 cursor-not-allowed border border-white/5'
                  : 'bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] hover:scale-[1.01] shadow-[rgba(212,175,55,0.25)]'
              }`}
              data-testid="cart-page-checkout-btn"
            >
              Proceed to Checkout →
            </button>
          </div>
        )}
      </main>

      <MobileBottomDock />
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
