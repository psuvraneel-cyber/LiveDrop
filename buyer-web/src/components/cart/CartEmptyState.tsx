import React from 'react';
import Link from 'next/link';

export interface CartEmptyStateProps {
  title?: string;
  description?: string;
  actionLabel?: string;
  onBrowse?: () => void;
  browseHref?: string;
}

export function CartEmptyState({
  title = 'Your bag is empty',
  description = 'Discover unique pieces from independent boutiques.',
  actionLabel = 'Explore Shop',
  onBrowse,
  browseHref = '/shop',
}: CartEmptyStateProps) {
  return (
    <div
      className="ld-cart-empty flex flex-col items-center justify-center text-center max-w-sm mx-auto px-4 py-8 space-y-4"
      data-testid="cart-empty-state"
    >
      <div className="relative w-24 h-24 mx-auto flex items-center justify-center select-none" aria-hidden="true">
        {/* Subtle radial glow */}
        <div className="absolute inset-0 rounded-full bg-[radial-gradient(circle,rgba(212,175,55,0.18)_0%,transparent_70%)]" />
        {/* Luxury Gold Shopping Bags Vector with Sparkles */}
        <svg
          width="64"
          height="64"
          viewBox="0 0 64 64"
          fill="none"
          xmlns="http://www.w3.org/2000/svg"
          className="relative z-10 text-[#D4AF37]"
        >
          {/* Back Bag */}
          <path
            d="M26 18H44L48 44H22L26 18Z"
            fill="rgba(212, 175, 55, 0.15)"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinejoin="round"
          />
          <path
            d="M31 18V14C31 11.79 32.79 10 35 10C37.21 10 39 11.79 39 14V18"
            stroke="currentColor"
            strokeWidth="1.5"
            strokeLinecap="round"
          />

          {/* Front Bag */}
          <path
            d="M16 26H38L42 54H12L16 26Z"
            fill="#121217"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinejoin="round"
          />
          <path
            d="M22 26V20C22 17.24 24.24 15 27 15C29.76 15 32 17.24 32 20V26"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
          />

          {/* Sparkles */}
          <path
            d="M48 20L49.5 24.5L54 26L49.5 27.5L48 32L46.5 27.5L42 26L46.5 24.5L48 20Z"
            fill="currentColor"
          />
          <path
            d="M14 16L14.8 18.2L17 19L14.8 19.8L14 22L13.2 19.8L11 19L13.2 18.2L14 16Z"
            fill="currentColor"
            opacity="0.8"
          />
          <circle cx="50" cy="42" r="1.5" fill="currentColor" opacity="0.6" />
        </svg>
      </div>

      <div className="space-y-1.5">
        <h3 className="text-lg sm:text-xl font-serif font-medium text-[#F4F1EA] tracking-wide">
          {title}
        </h3>
        <p className="text-xs sm:text-sm text-[#AAA49A] leading-relaxed max-w-xs mx-auto">
          {description}
        </p>
      </div>

      {onBrowse ? (
        <button
          type="button"
          className="mt-2 px-6 py-2.5 rounded-full bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] font-sans font-bold text-xs tracking-wider uppercase transition-all shadow-md active:scale-95 cursor-pointer"
          onClick={onBrowse}
          data-testid="cart-browse-btn"
        >
          {actionLabel}
        </button>
      ) : (
        <Link
          href={browseHref}
          className="mt-2 inline-block px-6 py-2.5 rounded-full bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] font-sans font-bold text-xs tracking-wider uppercase transition-all shadow-md active:scale-95 text-center cursor-pointer"
          data-testid="cart-browse-btn"
        >
          {actionLabel}
        </Link>
      )}
    </div>
  );
}
