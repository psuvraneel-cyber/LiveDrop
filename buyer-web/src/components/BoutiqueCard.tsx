'use client';

import React from 'react';
import Link from 'next/link';
import { PublicSellerStorefront } from '../types/domain';

export interface BoutiqueCardProps {
  boutique: PublicSellerStorefront;
  isLive?: boolean;
  liveDropSlug?: string;
}

export function normalizePhoneNumber(phone: string | null | undefined): string | null {
  if (!phone) return null;
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10) return `91${digits}`;
  if (digits.length === 12 && digits.startsWith('91')) return digits;
  return digits || null;
}

export function BoutiqueCard({
  boutique,
  isLive = false,
}: BoutiqueCardProps) {
  const storeSlug = boutique.store_slug || boutique.id;
  const visitHref = `/${storeSlug}`;
  const phone = normalizePhoneNumber(boutique.phone_number);
  const whatsappUrl = phone
    ? `https://wa.me/${phone}?text=${encodeURIComponent(`Hi ${boutique.store_name}, I discovered your boutique on LiveDrop!`)}`
    : `https://wa.me/?text=${encodeURIComponent(`Hi ${boutique.store_name}, I discovered your boutique on LiveDrop!`)}`;

  return (
    <div
      className={`ld-boutique-card ${isLive ? 'is-live' : ''} flex-shrink-0 w-[270px] sm:w-auto p-4 rounded-xl bg-[#121211] border border-white/5 hover:border-[rgba(199,154,69,0.3)] transition-all flex flex-col justify-between gap-3.5 shadow-sm snap-start`}
      data-testid={`boutique-card-${storeSlug}`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-3 min-w-0">
          <div className="ld-boutique-monogram w-10 h-10 rounded-full bg-[#181715] border border-[#C79A45]/30 flex items-center justify-center text-[#C79A45] font-serif font-bold text-sm flex-shrink-0">
            {boutique.store_name[0]?.toUpperCase() || 'B'}
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-1.5">
              <h3 className="text-xs sm:text-sm font-semibold text-white truncate">
                {boutique.store_name}
              </h3>
              <span className="text-[#C79A45] text-xs flex-shrink-0" title="Verified">✓</span>
            </div>
            <span className="text-[11px] text-[#AAA49A] block truncate">
              Independent Boutique
            </span>
          </div>
        </div>

        {isLive && (
          <span
            className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-[#E5484D]/15 border border-[#E5484D]/40 text-[#E5484D] text-[10px] font-mono font-bold uppercase tracking-wider flex-shrink-0"
            data-testid={`boutique-live-badge-${storeSlug}`}
          >
            <span className="w-1.5 h-1.5 rounded-full bg-[#E5484D] animate-pulse" />
            LIVE
          </span>
        )}
      </div>

      <div className="flex items-center justify-between pt-2.5 border-t border-white/5">
        <Link
          href={visitHref}
          className="min-h-[44px] min-w-[44px] inline-flex items-center gap-1.5 text-xs text-[#C79A45] hover:text-[#E2C27A] font-semibold transition-colors group"
          data-testid={`visit-boutique-${storeSlug}`}
        >
          <span>Visit</span>
          <span aria-hidden="true" className="group-hover:translate-x-0.5 transition-transform">→</span>
        </Link>
        <a
          href={whatsappUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="w-11 h-11 min-w-[44px] min-h-[44px] flex items-center justify-center text-xs text-[#25D366] hover:text-[#2fe671] p-2 transition-colors rounded-full hover:bg-white/5 focus-visible:outline-2 focus-visible:outline-[#25D366] focus-visible:outline-offset-2"
          title={`WhatsApp ${boutique.store_name}`}
          aria-label={`WhatsApp ${boutique.store_name}`}
          data-testid={`whatsapp-store-${storeSlug}`}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
          </svg>
        </a>
      </div>
    </div>
  );
}
