'use client';

import React from 'react';
import Link from 'next/link';
import { PublicDropCatalog } from '../types/domain';

export interface HeroProps {
  activeDrop?: PublicDropCatalog | null;
  hasActiveLiveDrop?: boolean;
}

export function Hero({ activeDrop, hasActiveLiveDrop }: HeroProps) {
  const isLive = Boolean(
    hasActiveLiveDrop !== undefined ? hasActiveLiveDrop : activeDrop && activeDrop.status === 'live'
  );
  const primaryDrop = activeDrop;
  const dropTitle = primaryDrop?.title;
  const storeName = primaryDrop?.profiles?.store_name || 'Independent Boutique';
  const dropSlug = primaryDrop?.slug;

  const heroBackground = isLive && primaryDrop?.hero_image_url ? primaryDrop.hero_image_url : null;

  return (
    <div className="ld-home-hero-wrap w-full max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 pt-3 pb-2">
      <section
        id="live-drops"
        className="relative w-full h-[300px] sm:h-[320px] md:h-[350px] lg:h-[360px] flex items-end overflow-hidden rounded-2xl border border-white/10 bg-[#0e0e10] scroll-mt-16 shadow-2xl"
        aria-label="LiveDrop Spotlight Hero"
        data-testid={isLive ? 'live-drop-hero' : 'spotlight-hero'}
      >
        <div className="absolute inset-0 pointer-events-none overflow-hidden">
          {heroBackground ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={heroBackground}
              alt={isLive && primaryDrop ? primaryDrop.title : 'LiveDrop Spotlight'}
              className="w-full h-full object-cover object-[78%_26%] sm:object-[75%_32%] select-none brightness-95 contrast-[1.03] scale-[1.22] sm:scale-100 origin-[78%_26%] transition-transform duration-700"
              style={{ objectPosition: '78% 26%' }}
            />
          ) : (
            <div className="w-full h-full bg-gradient-to-br from-[#1b1613] via-[#121211] to-[#090909]" />
          )}
          {/* Directional read gradient - deep dark coverage on the left for text contrast */}
          <div className="absolute inset-0 bg-gradient-to-r from-[#08080A] via-[#08080A]/85 via-48% to-transparent" />
          {/* Vertical bottom gradient - seamless melt into dark background without harsh border */}
          <div className="absolute inset-0 bg-gradient-to-t from-[#08080A] via-[#08080A]/60 via-30% to-transparent" />
          {/* Subtle top ambient vignette */}
          <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-transparent" />
        </div>

        <div className="ld-hero-inner-content relative z-10 w-full p-4 sm:p-6 pb-5 sm:pb-6 flex flex-col justify-end">
          <div className="w-[85%] sm:w-[65%] md:w-[48%] lg:w-[42%] max-w-lg space-y-2 sm:space-y-2.5">
            {/* Live Indicator or Eyebrow */}
            {isLive && primaryDrop ? (
              <div className="inline-flex items-center">
                <span className="inline-flex items-center gap-2 h-7 sm:h-8 px-3 rounded-full bg-[#DC2626] text-white font-sans font-bold text-[11px] sm:text-xs tracking-wider uppercase shadow-lg shadow-red-950/40">
                  <span className="w-1.5 h-1.5 sm:w-2 sm:h-2 rounded-full bg-white animate-pulse" />
                  LIVE NOW
                </span>
              </div>
            ) : null}

            {/* Headline */}
            <h1 className="text-xl sm:text-2xl md:text-3xl font-serif text-[#FBFBFB] tracking-wide leading-tight drop-shadow-md">
              {isLive && primaryDrop ? dropTitle : 'NO LIVE DROP'}
            </h1>

            {/* Subtitle / Boutique Attribution */}
            <p className="text-xs sm:text-sm text-[#F4F1EA]/85 font-sans leading-snug drop-shadow line-clamp-2">
              {isLive && primaryDrop
                ? storeName
                : 'Explore pieces from independent boutiques.'}
            </p>

            {/* Luxury Feature Tags */}
            <div className="flex flex-wrap items-center gap-1.5 pt-0.5 pb-0.5">
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-[9px] sm:text-[10px] text-white/90">
                <span className="text-[#D4AF37]">✦</span> Live shopping
              </span>
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-[9px] sm:text-[10px] text-white/90">
                <span className="text-[#D4AF37]">✦</span> Exclusive pieces
              </span>
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-[9px] sm:text-[10px] text-white/90">
                <span className="text-[#D4AF37]">✦</span> Handpicked
              </span>
            </div>

            {/* Action CTA Row */}
            <div className="pt-1 flex items-center justify-between gap-3">
              {isLive && primaryDrop && dropSlug ? (
                <Link
                  href={`/drop/${dropSlug}`}
                  className="ld-gold-pill-btn inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] text-xs sm:text-sm font-bold tracking-wide transition-all shadow-lg hover:scale-[1.02] active:scale-[0.98] min-h-[44px]"
                  data-testid="shop-live-hero-btn"
                >
                  <span>Shop Live Drop</span>
                  <span aria-hidden="true">→</span>
                </Link>
              ) : (
                <Link
                  href="/shop"
                  className="ld-gold-pill-btn inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-[#D4AF37] hover:bg-[#E5C158] text-[#08080A] text-xs sm:text-sm font-bold tracking-wide transition-all shadow-lg hover:scale-[1.02] active:scale-[0.98] min-h-[44px]"
                  data-testid="explore-live-shows-btn"
                >
                  <span>Shop Collections</span>
                  <span aria-hidden="true">→</span>
                </Link>
              )}
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
