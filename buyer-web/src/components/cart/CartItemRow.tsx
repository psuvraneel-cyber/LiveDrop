'use client';

/**
 * LiveDrop — Screen 6: Cart Item Row
 *
 * Displays a single cart item matching Screen 6 of the Haute Couture template:
 * square thumbnail, garment title, formatted INR price, size/variant details,
 * quantity stepper [-] N [+], and delete trash icon.
 */

import React from 'react';
import { CartItem } from '../../types/cart';
import { formatPaisaToINR } from '../../lib/utils/currency';

export interface CartItemRowProps {
  item: CartItem & { status?: string };
  onRemove: (productId: string) => void;
  isAvailable?: boolean;
  availabilityReason?: string;
}

export function CartItemRow({ item, onRemove, isAvailable = true, availabilityReason }: CartItemRowProps) {
  const [imgError, setImgError] = React.useState(false);

  return (
    <div
      className={`p-3.5 sm:p-4 rounded-2xl bg-[#101014] border ${
        isAvailable ? 'border-white/10 hover:border-[rgba(212,175,55,0.3)]' : 'border-red-500/40 bg-red-950/10'
      } flex gap-3.5 items-center transition-all shadow-md group`}
      data-testid={`cart-item-${item.productId}`}
    >
      {/* Square Thumbnail */}
      <div className="relative w-20 h-20 sm:w-22 sm:h-22 rounded-xl overflow-hidden bg-black/60 border border-white/10 flex-shrink-0">
        {!imgError && item.imageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={item.imageUrl}
            alt={item.title}
            className="w-full h-full object-cover"
            onError={() => setImgError(true)}
          />
        ) : (
          <div className="w-full h-full flex flex-col items-center justify-center bg-[#181715] text-[#C79A45] p-2 text-center">
            <span className="text-xs">✦</span>
            <span className="font-mono text-[10px] text-white/50">{item.code || 'LiveDrop'}</span>
          </div>
        )}
        {!isAvailable && (
          <span className="absolute inset-0 bg-black/80 flex items-center justify-center text-[10px] font-mono font-bold text-red-400 uppercase tracking-wider text-center p-1">
            Sold Out
          </span>
        )}
      </div>

      {/* Details & Controls */}
      <div className="flex-1 min-w-0 flex flex-col justify-between h-20 sm:h-22 py-0.5">
        <div>
          <div className="flex items-start justify-between gap-2">
            <h4 className="text-sm font-medium text-white truncate group-hover:text-[#D4AF37] transition-colors">
              {item.title}
            </h4>
            <button
              type="button"
              onClick={() => onRemove(item.productId)}
              className="text-white/40 hover:text-red-400 p-1 transition-colors flex-shrink-0"
              aria-label={`Remove ${item.title} from cart`}
              data-testid={`cart-remove-${item.productId}`}
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="3 6 5 6 21 6" />
                <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />
                <line x1="10" y1="11" x2="10" y2="17" />
                <line x1="14" y1="11" x2="14" y2="17" />
              </svg>
            </button>
          </div>

          <div className="text-xs font-bold text-[#F3E5AB] font-serif tracking-wide mt-0.5">
            {formatPaisaToINR(item.pricePaisa)}
          </div>

          <div className="flex items-center gap-1.5 text-[11px] text-white/50 font-sans truncate mt-0.5">
            <span>Size: <span className="text-white/80">{item.size || 'Free Size'}</span></span>
            {item.code && (
              <>
                <span>•</span>
                <span className="font-mono text-[#D4AF37] font-semibold">{item.code}</span>
              </>
            )}
          </div>

          {!isAvailable && (
            <div
              className="mt-1 text-[11px] text-red-400 font-medium tracking-wide flex items-center gap-1.5"
              data-testid={`cart-item-warning-${item.productId}`}
            >
              <span className="w-1.5 h-1.5 rounded-full bg-red-400 inline-block" aria-hidden="true" />
              <span>
                {item.status === 'reserved'
                  ? 'RESERVED — No longer available'
                  : item.status === 'sold'
                  ? 'SOLD OUT'
                  : availabilityReason || 'No longer available'}
              </span>
            </div>
          )}
        </div>

        {/* Quantity Indicator / Stepper */}
        <div className="flex items-center justify-between pt-1">
          <div className="inline-flex items-center rounded-lg bg-black/60 border border-white/10 px-2 py-0.5 gap-2.5 text-xs text-white/80">
            <button
              type="button"
              onClick={() => onRemove(item.productId)}
              className="text-white/50 hover:text-white font-mono leading-none transition-colors"
              aria-label="Decrease quantity"
            >
              −
            </button>
            <span className="font-mono text-[11px] font-semibold">1</span>
            <button
              type="button"
              disabled
              className="text-white/20 cursor-not-allowed font-mono leading-none"
              title="Single piece edition"
              aria-label="Increase quantity (single piece only)"
            >
              +
            </button>
          </div>

          <span className="text-[10px] font-mono text-[#D4AF37]/80 uppercase tracking-widest">
            Single Piece
          </span>
        </div>
      </div>
    </div>
  );
}
