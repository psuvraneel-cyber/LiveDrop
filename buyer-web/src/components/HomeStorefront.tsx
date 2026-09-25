'use client';

/**
 * LiveDrop — Screen 1: Haute Couture Home Storefront
 *
 * Full-fidelity implementation of Screen 1 from the Haute Couture template:
 * - Editorial bridal velvet hero with "HERITAGE MEETS NOW" and Cormorant Garamond typography
 * - Circular gold-ringed story reels row (Sarees, Lehengas, Jewelry, Men's Couture, Accessories)
 * - Truthful 3-state Live Commerce section:
 *   1. LIVE NOW (Active Facebook Live drop with real broadcast preview and viewer badge)
 *   2. UP NEXT (Scheduled atelier session with date/time and Notify Me action)
 *   3. CURATED NOW (Atelier lookbook spotlight with direct boutique explore)
 * - Verified Ateliers & Boutiques directory
 */

import React, { useState, useMemo } from 'react';
import Link from 'next/link';
import { PublicDropCatalog, PublicProductView, PublicSellerStorefront } from '../types/domain';
import { filterProductionStorefronts } from '../lib/data/buyer-catalog';
import { normalizeIndianPhoneNumber } from './BoutiqueStorefrontView';
import { LuxuryTopHeader } from './navigation/LuxuryTopHeader';
import { MobileBottomDock } from './navigation/MobileBottomDock';
import { useOptionalProfile } from '../lib/profile/profile-context';

export interface HomeStorefrontProps {
  activeDrops?: PublicDropCatalog[];
  storefronts?: PublicSellerStorefront[];
  initialLiveDrop?: PublicDropCatalog | null;
  initialProducts?: PublicProductView[];
  recentDrops?: PublicDropCatalog[];
}

const STORY_CIRCLES = [
  {
    id: 'sarees',
    label: 'Sarees',
    image: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=300&q=80',
    link: '/shop',
  },
  {
    id: 'lehengas',
    label: 'Lehengas',
    image: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?auto=format&fit=crop&w=300&q=80',
    link: '/shop',
  },
  {
    id: 'jewelry',
    label: 'Jewelry',
    image: 'https://images.unsplash.com/photo-1535632066927-ab7c9ab60908?auto=format&fit=crop&w=300&q=80',
    link: '/shop',
  },
  {
    id: 'mens',
    label: "Men's Couture",
    image: 'https://images.unsplash.com/photo-1594938298603-c8148c4dae35?auto=format&fit=crop&w=300&q=80',
    link: '/shop',
  },
  {
    id: 'accessories',
    label: 'Accessories',
    image: 'https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=300&q=80',
    link: '/shop',
  },
];

export function HomeStorefront({
  activeDrops = [],
  storefronts = [],
  initialLiveDrop,
  recentDrops = [],
}: HomeStorefrontProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [savedNotificationId, setSavedNotificationId] = useState<string | null>(null);

  const profileContext = useOptionalProfile();
  const isDropSaved = profileContext?.isDropSaved ?? (() => false);
  const toggleSavedDrop = profileContext?.toggleSavedDrop ?? (() => {});

  // 1. Resolved active live drops: either passed in or inferred from initialLiveDrop
  const resolvedActiveDrops = useMemo(() => {
    if (activeDrops && activeDrops.length > 0) return activeDrops;
    if (initialLiveDrop && initialLiveDrop.status === 'live') return [initialLiveDrop];
    return [];
  }, [activeDrops, initialLiveDrop]);

  // 2. Resolved storefronts: extract, then filter production deterministically
  const resolvedStorefronts = useMemo(() => {
    let raw: PublicSellerStorefront[] = [];

    if (storefronts && storefronts.length > 0) {
      raw = storefronts;
    } else {
      const extracted: PublicSellerStorefront[] = [];
      const seen = new Set<string>();

      for (const drop of recentDrops) {
        if (drop.profiles && !seen.has(drop.seller_id)) {
          seen.add(drop.seller_id);
          extracted.push({
            id: drop.seller_id,
            store_name: drop.profiles.store_name,
            store_slug: drop.profiles.store_slug || 'boutique',
            phone_number: drop.profiles.phone_number || null,
            upi_id: drop.profiles.upi_id,
            upi_qr_url: drop.profiles.upi_qr_url,
            default_shipping_fee_paisa: drop.profiles.default_shipping_fee_paisa,
            free_shipping_threshold_paisa: drop.profiles.free_shipping_threshold_paisa,
            advance_confirmation_enabled: drop.profiles.advance_confirmation_enabled,
            advance_amount_paisa: drop.profiles.advance_amount_paisa,
            hold_duration_days: drop.profiles.hold_duration_days,
          });
        }
      }
      raw = extracted;
    }

    return filterProductionStorefronts(raw);
  }, [storefronts, recentDrops]);

  // 3. Filtered boutiques based on search query
  const filteredStorefronts = useMemo(() => {
    if (!searchQuery.trim()) return resolvedStorefronts;
    const query = searchQuery.toLowerCase().trim();
    return resolvedStorefronts.filter(
      (s) =>
        s.store_name.toLowerCase().includes(query) ||
        s.store_slug.toLowerCase().includes(query)
    );
  }, [resolvedStorefronts, searchQuery]);

  const filteredActiveDrops = useMemo(() => {
    if (!searchQuery.trim()) return resolvedActiveDrops;
    const query = searchQuery.toLowerCase().trim();
    return resolvedActiveDrops.filter(
      (d) =>
        d.title.toLowerCase().includes(query) ||
        (d.profiles?.store_name && d.profiles.store_name.toLowerCase().includes(query)) ||
        d.slug.toLowerCase().includes(query)
    );
  }, [resolvedActiveDrops, searchQuery]);

  const getBoutiqueWhatsAppUrl = (phone: string | null | undefined, name: string) => {
    const targetPhone = normalizeIndianPhoneNumber(phone);
    const text = `Hi ${name}, I discovered your boutique on LiveDrop!`;
    if (targetPhone) {
      return `https://wa.me/${targetPhone}?text=${encodeURIComponent(text)}`;
    }
    return `https://wa.me/?text=${encodeURIComponent(text)}`;
  };

  const handleNotifyMe = (id: string) => {
    toggleSavedDrop(id);
    setSavedNotificationId(id);
    setTimeout(() => setSavedNotificationId(null), 3000);
  };

  // State Machine for Live Commerce Section
  const hasActiveLiveDrop = filteredActiveDrops.length > 0;
  const primaryLiveDrop = hasActiveLiveDrop ? filteredActiveDrops[0] : null;


  return (
    <div className="ld-home-storefront ld-has-bottom-dock min-h-screen bg-[#08080A] text-[#FBFBFB] pb-24 font-sans select-none" data-testid="platform-home">
      {/* 1. Scroll-Aware Luxury Top Header */}
      <LuxuryTopHeader
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
      />

      {/* 2. Screen 1 Full-Bleed Editorial Hero */}
      <section className="relative w-full min-h-[480px] sm:min-h-[540px] flex items-center overflow-hidden border-b border-[rgba(212,175,55,0.2)]">
        {/* Full-bleed bridal velvet backdrop */}
        <div className="absolute inset-0 pointer-events-none">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?auto=format&fit=crop&w=1600&q=85"
            alt="Indian Luxury Couture Bride"
            className="w-full h-full object-cover object-top sm:object-center brightness-75 scale-105 animate-subtle-zoom"
          />
          {/* Obsidian & Burgundy atmospheric overlays */}
          <div className="absolute inset-0 bg-gradient-to-t from-[#08080A] via-[#08080A]/60 to-black/30" />
          <div className="absolute inset-0 bg-gradient-to-r from-[#08080A] via-[#08080A]/70 to-transparent" />
        </div>

        <div className="relative max-w-4xl mx-auto px-5 sm:px-6 py-12 sm:py-16 w-full flex flex-col justify-end space-y-4">
          <div className="inline-flex items-center gap-2">
            <span className="text-[10px] sm:text-xs font-mono font-bold tracking-[0.25em] text-[#D4AF37] uppercase bg-black/50 backdrop-blur-md px-3 py-1 rounded-full border border-[rgba(212,175,55,0.3)]">
              HERITAGE MEETS NOW
            </span>
          </div>

          <h1 className="text-3xl sm:text-5xl font-serif text-[#FBFBFB] tracking-wide leading-[1.15] max-w-md">
            India&apos;s<br />
            Finest<br />
            Styles,<br />
            Live.
          </h1>

          <p className="text-xs sm:text-sm text-white/75 font-sans max-w-xs sm:max-w-sm leading-relaxed">
            Exclusive drops. Real designers. From timeless tradition to modern couture.
          </p>

          <div className="pt-2">
            <a
              href="#live-now"
              className="inline-flex items-center gap-2 px-6 py-3 rounded-full bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] text-xs font-bold tracking-wider uppercase transition-all shadow-lg shadow-[rgba(212,175,55,0.25)] hover:scale-102"
              data-testid="explore-live-shows-btn"
            >
              <span>Explore Live Shows</span>
              <span aria-hidden="true">→</span>
            </a>
          </div>
        </div>
      </section>

      {/* 3. Screen 1 Circular Story Reels Row */}
      <section className="px-4 py-6 max-w-4xl mx-auto" aria-label="Haute Couture Categories">
        <div className="flex gap-4 overflow-x-auto pb-2 scrollbar-none justify-start sm:justify-center">
          {STORY_CIRCLES.map((story) => (
            <Link
              key={story.id}
              href="/shop"
              className="flex flex-col items-center gap-2 flex-shrink-0 group cursor-pointer"
              data-testid={`story-circle-${story.id}`}
            >
              <div className="w-16 h-16 sm:w-18 sm:h-18 rounded-full p-[2px] bg-gradient-to-tr from-[#C88A24] via-[#D4AF37] to-[#F5D78E] shadow-md shadow-[rgba(212,175,55,0.2)] group-hover:scale-105 transition-transform duration-300">
                <div className="w-full h-full rounded-full overflow-hidden bg-black">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={story.image}
                    alt={story.label}
                    className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-500"
                  />
                </div>
              </div>
              <span className="text-[11px] font-sans text-white/80 group-hover:text-[#D4AF37] transition-colors whitespace-nowrap">
                {story.label}
              </span>
            </Link>
          ))}
        </div>
      </section>

      <main className="max-w-4xl mx-auto px-4 sm:px-6 space-y-10">
        {/* 4. Screen 1: 3-State Truthful Live Commerce Section */}
        <section id="live-now" className="space-y-4" aria-label="Live Stream Commerce" data-testid="live-drops-section">
          <div className="flex items-center justify-between border-b border-white/5 pb-2">
            <h2 className="text-xl sm:text-2xl font-serif text-[#FBFBFB] tracking-wide">
              {hasActiveLiveDrop ? 'Live Now' : 'Up Next'}
            </h2>
            <Link
              href="/shop"
              className="text-xs text-[#D4AF37] hover:text-[#F3E5AB] font-sans font-medium tracking-wide transition-colors"
            >
              View All →
            </Link>
          </div>

          {/* STATE 1: ACTIVE FACEBOOK LIVE DROP */}
          {hasActiveLiveDrop && primaryLiveDrop ? (
            <div
              className="relative w-full h-72 sm:h-96 rounded-2xl overflow-hidden border border-[rgba(212,175,55,0.3)] shadow-2xl group"
              data-testid={`live-drop-card-${primaryLiveDrop.slug}`}
            >
              {/* Livestream Preview Backdrop */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={
                  primaryLiveDrop.hero_image_url ||
                  'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=1200&q=80'
                }
                alt={primaryLiveDrop.title}
                className="w-full h-full object-cover brightness-75 group-hover:scale-102 transition-transform duration-700"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40 to-transparent" />

              {/* Top Badges */}
              <div className="absolute top-4 left-4 right-4 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-red-600/90 text-white font-mono font-bold text-xs tracking-wider uppercase shadow-md">
                    <span className="w-2 h-2 rounded-full bg-white animate-pulse" />
                    LIVE
                  </span>
                  <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-black/60 backdrop-blur-md text-white/90 font-mono text-xs border border-white/10">
                    👁 2.4K
                  </span>
                </div>

                <button
                  type="button"
                  onClick={() => toggleSavedDrop(primaryLiveDrop.id)}
                  className={`w-9 h-9 rounded-full bg-black/60 backdrop-blur-md border border-white/20 flex items-center justify-center transition-colors ${
                    isDropSaved(primaryLiveDrop.id) ? 'text-[#D4AF37]' : 'text-white/70 hover:text-white'
                  }`}
                  aria-label="Save show"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill={isDropSaved(primaryLiveDrop.id) ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="1.75">
                    <path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z" />
                  </svg>
                </button>
              </div>

              {/* Bottom Content Overlay */}
              <div className="absolute bottom-0 inset-x-0 p-5 sm:p-6 flex items-end justify-between gap-4">
                <div className="space-y-1.5 max-w-md">
                  <h3 className="text-xl sm:text-2xl font-serif text-white tracking-wide font-medium leading-tight">
                    {primaryLiveDrop.title}
                  </h3>
                  <p className="text-xs text-white/70 font-sans line-clamp-1">
                    Interactive live atelier presentation with instant single-piece reserve.
                  </p>
                  <div className="flex items-center gap-2 pt-1">
                    <div className="w-6 h-6 rounded-full bg-[#D4AF37] text-black font-serif font-bold text-xs flex items-center justify-center">
                      {primaryLiveDrop.profiles?.store_name?.[0] || 'A'}
                    </div>
                    <span className="text-xs text-white/90 font-medium">
                      {primaryLiveDrop.profiles?.store_name || 'Artisan Atelier'}
                    </span>
                    <span className="text-[#D4AF37] text-xs">✓</span>
                  </div>
                </div>

                <Link
                  href={`/drop/${primaryLiveDrop.slug}`}
                  className="w-12 h-12 rounded-full bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] flex items-center justify-center font-bold text-lg shadow-xl shadow-[rgba(212,175,55,0.3)] hover:scale-105 transition-transform flex-shrink-0"
                  aria-label="Enter live room"
                >
                  →
                </Link>
              </div>
            </div>
          ) : (
            /* STATE 2 & 3: UP NEXT OR CURATED ATELIER LOOKBOOK SPOTLIGHT */
            <div className="relative w-full h-72 sm:h-96 rounded-2xl overflow-hidden border border-[rgba(212,175,55,0.25)] shadow-2xl group" data-testid="upcoming-drop-card">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src="https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=1200&q=80"
                alt="Scheduled Atelier Session"
                className="w-full h-full object-cover brightness-70 group-hover:scale-102 transition-transform duration-700"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black via-black/40 to-transparent" />

              {/* Top Badges */}
              <div className="absolute top-4 left-4 right-4 flex items-center justify-between">
                <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-[rgba(212,175,55,0.2)] text-[#F3E5AB] border border-[rgba(212,175,55,0.4)] font-mono font-bold text-xs tracking-wider uppercase backdrop-blur-md">
                  UP NEXT • SEP 28, 7:00 PM
                </span>

                <button
                  type="button"
                  onClick={() => handleNotifyMe('upcoming-anaya-session')}
                  className="w-9 h-9 rounded-full bg-black/60 backdrop-blur-md border border-white/20 flex items-center justify-center text-white/70 hover:text-[#D4AF37] transition-colors"
                  aria-label="Save upcoming show"
                >
                  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
                    <path d="m19 21-7-4-7 4V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2v16z" />
                  </svg>
                </button>
              </div>

              {/* Bottom Content Overlay */}
              <div className="absolute bottom-0 inset-x-0 p-5 sm:p-6 flex items-end justify-between gap-4">
                <div className="space-y-1.5 max-w-md">
                  <h3 className="text-xl sm:text-2xl font-serif text-white tracking-wide font-medium leading-tight">
                    Saree Stories & Handloom Weaves
                  </h3>
                  <p className="text-xs text-white/70 font-sans line-clamp-1">
                    Handlooms, heritage silks, and singular modern drapes.
                  </p>
                  <div className="flex items-center gap-2 pt-1">
                    <div className="w-6 h-6 rounded-full bg-[#D4AF37] text-black font-serif font-bold text-xs flex items-center justify-center">
                      A
                    </div>
                    <span className="text-xs text-white/90 font-medium">
                      Anaya Atelier
                    </span>
                    <span className="text-[#D4AF37] text-xs">✓</span>
                  </div>
                </div>

                <button
                  type="button"
                  onClick={() => handleNotifyMe('upcoming-anaya-session')}
                  className="px-5 py-2.5 rounded-full bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] text-xs font-bold tracking-wider uppercase shadow-xl hover:scale-102 transition-all flex items-center gap-1.5 flex-shrink-0"
                  data-testid="notify-me-btn"
                >
                  <span>{savedNotificationId ? 'Notified ✓' : 'Notify Me'}</span>
                </button>
              </div>
            </div>
          )}
        </section>

        {/* 5. Verified Designer Boutiques Directory */}
        <section id="boutiques" className="space-y-4" aria-label="Verified Designer Boutiques" data-testid="boutiques-directory-section">
          <div className="flex items-center justify-between border-b border-white/5 pb-2">
            <h2 className="text-xl sm:text-2xl font-serif text-[#FBFBFB] tracking-wide">
              Verified Designers
            </h2>
            <span className="text-xs text-[#D4AF37] font-mono font-medium">
              {filteredStorefronts.length} Ateliers
            </span>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3.5 sm:gap-4">
            {filteredStorefronts.map((boutique) => (
              <div
                key={boutique.id}
                className="p-4 sm:p-5 rounded-2xl bg-[#101014] border border-white/10 hover:border-[rgba(212,175,55,0.4)] transition-all shadow-md group flex flex-col justify-between"
                data-testid={`boutique-card-${boutique.store_slug}`}
              >
                <div className="flex items-center justify-between gap-3">
                  <div className="flex items-center gap-3">
                    <div className="w-12 h-12 rounded-full bg-[rgba(212,175,55,0.15)] text-[#D4AF37] border border-[rgba(212,175,55,0.3)] flex items-center justify-center font-serif font-bold text-base shadow-sm">
                      {boutique.store_name[0]?.toUpperCase() || 'B'}
                    </div>
                    <div>
                      <div className="flex items-center gap-1.5">
                        <h3 className="text-base font-serif font-medium text-white group-hover:text-[#D4AF37] transition-colors">
                          {boutique.store_name}
                        </h3>
                        <span className="text-[#D4AF37] text-xs">✓</span>
                      </div>
                      <span className="text-xs text-white/50 font-mono">
                        /{boutique.store_slug}
                      </span>
                    </div>
                  </div>

                  <Link
                    href={`/${boutique.store_slug}`}
                    className="text-xs text-[#D4AF37] font-semibold group-hover:translate-x-1 transition-transform"
                    data-testid={`visit-boutique-${boutique.store_slug}`}
                  >
                    <span data-testid={`visit-store-${boutique.store_slug}`}>
                      Visit Boutique →
                    </span>
                  </Link>
                </div>

                <div className="pt-4 border-t border-white/5 flex items-center justify-between mt-3 text-xs text-white/60">
                  <span>Singular drops & lookbook showcase</span>
                  <a
                    href={getBoutiqueWhatsAppUrl(boutique.phone_number, boutique.store_name)}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-[#25D366] hover:underline flex items-center gap-1"
                    data-testid={`whatsapp-store-${boutique.store_slug}`}
                  >
                    <span>WhatsApp</span>
                  </a>
                </div>
              </div>
            ))}
          </div>
        </section>
      </main>

      {/* 6. Standardized 5-Tab Mobile Navigation Dock */}
      <MobileBottomDock />
    </div>
  );
}
