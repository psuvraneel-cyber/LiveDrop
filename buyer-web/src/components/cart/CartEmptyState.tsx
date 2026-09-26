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
      <div className="text-4xl sm:text-5xl select-none" aria-hidden="true">
        🛍
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
          className="mt-2 px-6 py-2.5 rounded-full bg-[#C79A45] hover:bg-[#E2C27A] text-[#090909] font-serif font-semibold text-xs tracking-wider uppercase transition-colors shadow-md"
          onClick={onBrowse}
          data-testid="cart-browse-btn"
        >
          {actionLabel}
        </button>
      ) : (
        <Link
          href={browseHref}
          className="mt-2 inline-block px-6 py-2.5 rounded-full bg-[#C79A45] hover:bg-[#E2C27A] text-[#090909] font-serif font-semibold text-xs tracking-wider uppercase transition-colors shadow-md text-center"
          data-testid="cart-browse-btn"
        >
          {actionLabel}
        </Link>
      )}
    </div>
  );
}
