'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { PublicSellerStorefront, PublicDropCatalog, PublicProductView, ShowcaseCollection } from '../types/domain';
import { formatPaisaToINR } from '../lib/utils/currency';
import { useOptionalCart } from '../lib/cart/cart-context';
import { ProductCard } from './ProductCard';
import { CartDrawer } from './cart/CartDrawer';
import { StickyCartBar } from './cart/StickyCartBar';
import { MobileBottomDock } from './navigation/MobileBottomDock';

export interface BoutiqueStorefrontViewProps {
  storefront: PublicSellerStorefront;
  activeLiveDrop: PublicDropCatalog | null;
  liveProducts: PublicProductView[];
  pastDropsWithProducts: ShowcaseCollection[];
}

/**
 * Robustly normalizes Indian phone numbers for WhatsApp API links.
 * Strips all non-digit characters, removes trunk prefix '0', and ensures international prefix '91'.
 */
export function normalizeIndianPhoneNumber(phone: string | null | undefined): string {
  if (!phone) return '';
  let digits = phone.replace(/\D/g, '');
  if (digits.startsWith('0')) {
    digits = digits.replace(/^0+/, '');
  }
  if (digits.length === 10) {
    return `91${digits}`;
  }
  if (digits.length === 12 && digits.startsWith('91')) {
    return digits;
  }
  return digits;
}

export function formatWhatsAppUrl(
  phone: string | null | undefined,
  storeName: string,
  product: PublicProductView,
  storeSlug: string
): string {
  const targetPhone = normalizeIndianPhoneNumber(phone);
  const baseUrl = typeof window !== 'undefined' ? window.location.origin : 'https://livedrop-in.vercel.app';
  const itemUrl = `${baseUrl}/${storeSlug}`;
  const text = `Hi ${storeName}, I saw ${product.code} (${product.title}, ${formatPaisaToINR(product.price_paisa)}) on your LiveDrop showcase (${itemUrl}). Is this piece still available?`;

  if (targetPhone) {
    return `https://wa.me/${targetPhone}?text=${encodeURIComponent(text)}`;
  }
  return `https://wa.me/?text=${encodeURIComponent(text)}`;
}

export function BoutiqueStorefrontView({
  storefront,
  activeLiveDrop,
  liveProducts,
  pastDropsWithProducts,
}: BoutiqueStorefrontViewProps) {
  const cart = useOptionalCart();
  const isDrawerOpen = cart?.isDrawerOpen ?? false;
  const openDrawer = cart?.openDrawer ?? (() => {});
  const closeDrawer = cart?.closeDrawer ?? (() => {});
  const itemCount = cart?.itemCount ?? 0;
  const isHydrated = cart?.isHydrated ?? false;

  const [copiedLink, setCopiedLink] = useState(false);
  const [selectedImage, setSelectedImage] = useState<{ url: string; title: string } | null>(null);

  useEffect(() => {
    if (!selectedImage) return;
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setSelectedImage(null);
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [selectedImage]);

  const hasLiveDrop = Boolean(activeLiveDrop && activeLiveDrop.status === 'live');
  const storeSlug = storefront.store_slug || 'boutique';
  const storeName = storefront.store_name || 'Boutique';

  const handleCopyLink = () => {
    const url = typeof window !== 'undefined' ? `${window.location.origin}/${storeSlug}` : `https://livedrop-in.vercel.app/${storeSlug}`;
    if (navigator?.clipboard) {
      void navigator.clipboard.writeText(url);
      setCopiedLink(true);
      setTimeout(() => setCopiedLink(false), 2500);
    }
  };

  const boutiqueWhatsAppGeneral = () => {
    const targetPhone = normalizeIndianPhoneNumber(storefront.phone_number);
    const text = `Hi ${storeName}, I am visiting your boutique on LiveDrop!`;
    if (targetPhone) {
      return `https://wa.me/${targetPhone}?text=${encodeURIComponent(text)}`;
    }
    return `https://wa.me/?text=${encodeURIComponent(text)}`;
  };

  return (
    <div className="ld-home-storefront ld-has-bottom-dock" data-testid="boutique-storefront">
      {/* 1. Global Boutique Navigation Bar */}
      <header className="ld-navbar" role="banner">
        <div className="ld-navbar-inner">
          <div className="ld-navbar-left">
            <Link href="/" className="ld-brand-emblem" aria-label="LiveDrop Home">
              <span className="ld-brand-sparkle">✦</span>
              <span className="ld-brand-title">LiveDrop</span>
              <span className="ld-brand-sub">BOUTIQUE</span>
            </Link>
          </div>

          <div className="ld-navbar-center">
            <span className="ld-storefront-nav-name" data-testid="storefront-name-badge">
              {storeName}
            </span>
          </div>

          <div className="ld-navbar-right">
            <button
              type="button"
              className="ld-share-btn"
              onClick={handleCopyLink}
              title="Copy boutique link"
              aria-label="Copy boutique link"
              data-testid="copy-storefront-link-btn"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <rect width="13" height="13" x="9" y="9" rx="2" ry="2" />
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
              </svg>
              <span>{copiedLink ? 'Copied!' : 'Share'}</span>
            </button>

            {hasLiveDrop && (
              <button
                type="button"
                className="ld-nav-cart-btn"
                onClick={openDrawer}
                aria-label={`Shopping bag with ${itemCount} items`}
                data-testid="storefront-cart-btn"
              >
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                  <path d="M3 6h18" />
                  <path d="M16 10a4 4 0 0 1-8 0" />
                </svg>
                {isHydrated && itemCount > 0 && (
                  <span className="ld-nav-cart-badge" data-testid="storefront-cart-badge">
                    {itemCount}
                  </span>
                )}
              </button>
            )}
          </div>
        </div>
      </header>

      {/* 2. Boutique Profile Header Hero */}
      <section className="ld-storefront-hero" data-testid="storefront-hero">
        <div className="ld-storefront-hero-inner">
          <div className="ld-storefront-badge-row">
            {hasLiveDrop ? (
              <span className="ld-hero-live-pill live" data-testid="live-drop-pill">
                <span className="ld-hero-live-dot" />
                LIVE FLASH SALE NOW
              </span>
            ) : (
              <span className="ld-hero-live-pill active" data-testid="offline-showcase-pill">
                <span className="ld-hero-live-dot" style={{ backgroundColor: 'var(--color-gold, #D4AF37)' }} />
                NEXT LIVE DROP SOON
              </span>
            )}
            {Boolean(storefront.is_verified) && (
              <span className="ld-verified-boutique-tag">✦ Verified Boutique</span>
            )}
          </div>

          <h1 className="ld-storefront-title" data-testid="storefront-title">
            {storeName}
          </h1>

          <p className="ld-storefront-slug-sub">
            livedrop-in.vercel.app/<strong>{storeSlug}</strong>
          </p>

          <p className="ld-storefront-desc">
            {hasLiveDrop
              ? `Currently live streaming: "${activeLiveDrop?.title}". Claim limited pieces before the drop ends!`
              : `Welcome to the studio catalog of ${storeName}. Browse available creations from our past collections or inquire directly via WhatsApp.`}
          </p>

          <div className="ld-storefront-actions">
            <a
              href={boutiqueWhatsAppGeneral()}
              target="_blank"
              rel="noopener noreferrer"
              className="ld-btn-whatsapp-hero"
              data-testid="boutique-whatsapp-btn"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
                <path d="M17.472 14.382c-.301-.15-1.78-.878-2.056-.978-.276-.101-.477-.15-.678.15-.2.301-.778.978-.954 1.18-.176.201-.351.226-.652.075-.301-.15-1.272-.469-2.423-1.496-.896-.799-1.5-1.787-1.677-2.088-.176-.301-.019-.464.132-.614.136-.135.301-.351.451-.527.151-.176.201-.301.301-.502.1-.201.05-.376-.025-.527-.075-.15-.678-1.632-.929-2.234-.244-.587-.492-.507-.677-.517l-.578-.01c-.201 0-.527.075-.803.376s-1.054 1.029-1.054 2.509c0 1.48 1.079 2.909 1.23 3.109.15.201 2.124 3.243 5.145 4.549.719.311 1.28.497 1.718.636.722.23 1.379.197 1.9.119.58-.088 1.78-.728 2.03-1.431.251-.703.251-1.305.176-1.431-.076-.126-.277-.201-.578-.352z" />
                <path d="M12 2C6.48 2 2 6.48 2 12c0 1.94.55 3.75 1.51 5.28L2 22l4.88-1.47C8.36 21.48 10.12 22 12 22c5.52 0 10-4.48 10-10S17.52 2 12 2zm0 18c-1.64 0-3.17-.49-4.46-1.34l-.32-.21-2.89.87.87-2.81-.23-.34C4.1 14.86 3.6 13.48 3.6 12c0-4.63 3.77-8.4 8.4-8.4s8.4 3.77 8.4 8.4-3.77 8.4-8.4 8.4z" />
              </svg>
              <span>Chat with Boutique</span>
            </a>

            {hasLiveDrop && (
              <Link
                href={`/drop/${activeLiveDrop?.slug}`}
                className="ld-btn-gold-cta"
                data-testid="enter-live-room-btn"
              >
                <span>Enter Live Flash Sale</span>
                <span>→</span>
              </Link>
            )}
          </div>
        </div>
      </section>

      {/* 3. Active Live Drop Mode (if live) */}
      {hasLiveDrop && (
        <main className="ld-catalog-section" data-testid="live-products-section">
          <div className="ld-catalog-header">
            <div className="ld-catalog-header-left">
              <span className="ld-live-pill-tag">
                <span className="ld-hero-live-dot" /> LIVE ATELIER SESSION
              </span>
              <h2 className="ld-catalog-title">{activeLiveDrop?.title}</h2>
              <span className="ld-catalog-subtitle">
                {liveProducts.length} flash sale piece{liveProducts.length === 1 ? '' : 's'} available
              </span>
            </div>
            <Link href={`/drop/${activeLiveDrop?.slug}`} className="ld-view-all-link">
              <span>Fullscreen Live Mode</span>
              <span>→</span>
            </Link>
          </div>

          <div className="ld-products-grid">
            {liveProducts.map((prod) => (
              <ProductCard
                key={prod.id}
                product={prod}
                dropId={activeLiveDrop?.id}
                storeName={storeName}
              />
            ))}
          </div>
        </main>
      )}

      {/* 4. Showcase Lookbook Mode (Past Collections with WhatsApp Inquiry) */}
      <section className="ld-showcase-section" data-testid="showcase-section">
        <div className="ld-showcase-container">
          <div className="ld-showcase-header">
            <div>
              <h2 className="ld-showcase-title">
                {hasLiveDrop ? 'Past Studio Lookbooks' : 'Studio Showcase & Available Pieces'}
              </h2>
              <p className="ld-showcase-subtitle">
                {hasLiveDrop
                  ? 'Exclusive remaining creations from previous boutique drops.'
                  : 'Instant cart checkout is offline between live sessions. Contact the boutique directly on WhatsApp to inquire or reserve these available pieces.'}
              </p>
            </div>
          </div>

          {pastDropsWithProducts.length === 0 ? (
            <div className="ld-empty-showcase" data-testid="empty-showcase">
              <span className="ld-empty-sparkle">✦</span>
              <h3>No Previous Collections Listed</h3>
              <p>
                {storeName} has not archived any past drop pieces yet. Follow our WhatsApp or check back soon for our next live stream!
              </p>
              <a
                href={boutiqueWhatsAppGeneral()}
                target="_blank"
                rel="noopener noreferrer"
                className="ld-btn-whatsapp-outline"
              >
                Inquire on WhatsApp
              </a>
            </div>
          ) : (
            <div className="ld-collections-list">
              {pastDropsWithProducts.map(({ drop, products }) => (
                <div key={drop.id} className="ld-collection-block" data-testid={`collection-${drop.slug}`}>
                  <div className="ld-collection-title-row">
                    <div className="ld-collection-tag">COLLECTION</div>
                    <h3 className="ld-collection-name">{drop.title}</h3>
                    <span className="ld-collection-count">
                      {products.length} piece{products.length === 1 ? '' : 's'} available
                    </span>
                  </div>

                  <div className="ld-products-grid">
                    {products.map((prod) => {
                      const displayImg = (prod.image_urls && prod.image_urls.length > 0 && prod.image_urls[0])
                        ? prod.image_urls[0]
                        : (prod.image_url || '/placeholder-garment.svg');
                      const photoCount = prod.image_urls?.length ?? (prod.image_url ? 1 : 0);

                      return (
                        <article key={prod.id} className="ld-showcase-card" data-testid={`showcase-card-${prod.code}`}>
                          <div
                            className="ld-showcase-img-wrap"
                            onClick={() => displayImg !== '/placeholder-garment.svg' && setSelectedImage({ url: displayImg, title: prod.title })}
                          >
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img
                              src={displayImg}
                              alt={prod.title}
                              className="ld-showcase-img"
                              loading="lazy"
                            />
                            <span className="ld-showcase-code-badge">{prod.code}</span>
                            <span className="ld-showcase-status-badge">Available</span>
                            {photoCount > 1 && (
                              <span className="ld-card-photo-count-badge" title={`${photoCount} photos`}>
                                📷 {photoCount}
                              </span>
                            )}
                          </div>

                        <div className="ld-showcase-info">
                          <h4 className="ld-showcase-product-title">{prod.title}</h4>
                          <div className="ld-showcase-meta-row">
                            <span className="ld-showcase-size">Size: {prod.size || 'Free Size'}</span>
                            <span className="ld-showcase-price">{formatPaisaToINR(prod.price_paisa)}</span>
                          </div>

                          <a
                            href={formatWhatsAppUrl(storefront.phone_number, storeName, prod, storeSlug)}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="ld-btn-whatsapp-inquire"
                            data-testid={`whatsapp-inquire-btn-${prod.code}`}
                          >
                            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                              <path d="M17.472 14.382c-.301-.15-1.78-.878-2.056-.978-.276-.101-.477-.15-.678.15-.2.301-.778.978-.954 1.18-.176.201-.351.226-.652.075-.301-.15-1.272-.469-2.423-1.496-.896-.799-1.5-1.787-1.677-2.088-.176-.301-.019-.464.132-.614.136-.135.301-.351.451-.527.151-.176.201-.301.301-.502.1-.201.05-.376-.025-.527-.075-.15-.678-1.632-.929-2.234-.244-.587-.492-.507-.677-.517l-.578-.01c-.201 0-.527.075-.803.376s-1.054 1.029-1.054 2.509c0 1.48 1.079 2.909 1.23 3.109.15.201 2.124 3.243 5.145 4.549.719.311 1.28.497 1.718.636.722.23 1.379.197 1.9.119.58-.088 1.78-.728 2.03-1.431.251-.703.251-1.305.176-1.431-.076-.126-.277-.201-.578-.352z" />
                              <path d="M12 2C6.48 2 2 6.48 2 12c0 1.94.55 3.75 1.51 5.28L2 22l4.88-1.47C8.36 21.48 10.12 22 12 22c5.52 0 10-4.48 10-10S17.52 2 12 2zm0 18c-1.64 0-3.17-.49-4.46-1.34l-.32-.21-2.89.87.87-2.81-.23-.34C4.1 14.86 3.6 13.48 3.6 12c0-4.63 3.77-8.4 8.4-8.4s8.4 3.77 8.4 8.4-3.77 8.4-8.4 8.4z" />
                            </svg>
                            <span>Inquire on WhatsApp</span>
                          </a>
                        </div>
                      </article>
                    );
                  })}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </section>

      {/* 5. Luxury Boutique Footer */}
      <footer className="ld-footer">
        <div className="ld-footer-top">
          <span className="ld-footer-brand">{storeName}</span>
          <span className="ld-footer-bullets">
            POWERED BY LIVEDROP • DIRECT TO BOUTIQUE • ZERO GATEWAY SURCHARGES
          </span>
          <div className="ld-footer-socials">
            <a
              href={boutiqueWhatsAppGeneral()}
              target="_blank"
              rel="noopener noreferrer"
              className="ld-social-icon"
              title="WhatsApp"
              aria-label="Contact Boutique on WhatsApp"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                <path d="M17.472 14.382c-.301-.15-1.78-.878-2.056-.978-.276-.101-.477-.15-.678.15-.2.301-.778.978-.954 1.18-.176.201-.351.226-.652.075-.301-.15-1.272-.469-2.423-1.496-.896-.799-1.5-1.787-1.677-2.088-.176-.301-.019-.464.132-.614.136-.135.301-.351.451-.527.151-.176.201-.301.301-.502.1-.201.05-.376-.025-.527-.075-.15-.678-1.632-.929-2.234-.244-.587-.492-.507-.677-.517l-.578-.01c-.201 0-.527.075-.803.376s-1.054 1.029-1.054 2.509c0 1.48 1.079 2.909 1.23 3.109.15.201 2.124 3.243 5.145 4.549.719.311 1.28.497 1.718.636.722.23 1.379.197 1.9.119.58-.088 1.78-.728 2.03-1.431.251-.703.251-1.305.176-1.431-.076-.126-.277-.201-.578-.352z" />
                <path d="M12 2C6.48 2 2 6.48 2 12c0 1.94.55 3.75 1.51 5.28L2 22l4.88-1.47C8.36 21.48 10.12 22 12 22c5.52 0 10-4.48 10-10S17.52 2 12 2zm0 18c-1.64 0-3.17-.49-4.46-1.34l-.32-.21-2.89.87.87-2.81-.23-.34C4.1 14.86 3.6 13.48 3.6 12c0-4.63 3.77-8.4 8.4-8.4s8.4 3.77 8.4 8.4-3.77 8.4-8.4 8.4z" />
              </svg>
            </a>
          </div>
        </div>
        <div className="ld-footer-bottom">
          <span className="ld-script-tagline">Crafted with passion ~</span>
          <span className="ld-copyright">
            © {new Date().getFullYear()} {storeName} on LiveDrop. All rights reserved.
          </span>
        </div>
      </footer>

      {/* Image Preview Modal */}
      {selectedImage && (
        <div className="ld-modal-backdrop" onClick={() => setSelectedImage(null)}>
          <div className="ld-img-preview-modal" onClick={(e) => e.stopPropagation()}>
            <button
              type="button"
              className="ld-sheet-btn-icon ld-preview-close"
              onClick={() => setSelectedImage(null)}
              aria-label="Close image preview"
            >
              ✕
            </button>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={selectedImage.url} alt={selectedImage.title} className="ld-preview-fullscreen-img" />
            <p className="ld-preview-title">{selectedImage.title}</p>
          </div>
        </div>
      )}

      {/* Cart Drawer & Sticky Bar for Live Drop Mode */}
      {hasLiveDrop && (
        <>
          <StickyCartBar onOpenCart={openDrawer} />
          <CartDrawer
            isOpen={isDrawerOpen}
            onClose={closeDrawer}
            catalogProducts={liveProducts}
            drop={activeLiveDrop}
          />
        </>
      )}

      {/* Persistent Mobile Bottom Dock */}
      <MobileBottomDock />
    </div>
  );
}
