'use client';

import React, { useState, useMemo } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { PublicDropCatalog, PublicProductView } from '../../types/domain';
import { FacebookLivePlayer } from './FacebookLivePlayer';
import { ProductQuickViewDrawer } from '../product/ProductQuickViewDrawer';
import { CartDrawer } from '../cart/CartDrawer';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { useOptionalCart } from '../../lib/cart/cart-context';

export interface CinematicLiveRoomViewProps {
  drop: PublicDropCatalog;
  products: PublicProductView[];
  realtimeStatus?: 'connecting' | 'connected' | 'disconnected' | 'polling';
  onExitToGrid?: () => void;
}

interface MockChatMessage {
  id: string;
  sender: string;
  avatar: string;
  message: string;
}

const INITIAL_COMMENTS: MockChatMessage[] = [
  { id: 'c1', sender: 'Priya M.', avatar: 'P', message: 'That zari border is breathtaking! ✨' },
  { id: 'c2', sender: 'Ananya S.', avatar: 'A', message: 'Is this pure handloom silk?' },
  { id: 'c3', sender: 'Kavita R.', avatar: 'K', message: 'Just claimed #A01! Can’t wait ❤️' },
];

export function CinematicLiveRoomView({
  drop,
  products,
  onExitToGrid,
}: CinematicLiveRoomViewProps) {
  const [isCatalogExpanded, setIsCatalogExpanded] = useState(false);
  const [selectedProduct, setSelectedProduct] = useState<PublicProductView | null>(null);
  const [isQuickViewOpen, setIsQuickViewOpen] = useState(false);
  const [likesCount, setLikesCount] = useState(2480);
  const [hasLiked, setHasLiked] = useState(false);
  const [flyingHearts, setFlyingHearts] = useState<{ id: number; left: number }[]>([]);

  // Cart integration
  const cart = useOptionalCart();
  const itemCount = cart?.itemCount ?? 0;
  const isDrawerOpen = cart?.isDrawerOpen ?? false;
  const openDrawer = cart?.openDrawer;
  const closeDrawer = cart?.closeDrawer;

  // Selected pinned product (default to first available, or first piece)
  const availableProducts = useMemo(() => {
    return products.filter((p) => p.status === 'available');
  }, [products]);

  const [pinnedProductId, setPinnedProductId] = useState<string | null>(() => {
    return availableProducts[0]?.id || products[0]?.id || null;
  });

  const pinnedProduct = useMemo(() => {
    return products.find((p) => p.id === pinnedProductId) || products[0] || null;
  }, [products, pinnedProductId]);

  const handleLike = () => {
    setLikesCount((prev) => prev + (hasLiked ? -1 : 1));
    setHasLiked((prev) => !prev);

    // Spawn floating heart effect
    const newHeart = { id: Date.now(), left: Math.floor(Math.random() * 40) - 20 };
    setFlyingHearts((prev) => [...prev, newHeart]);
    setTimeout(() => {
      setFlyingHearts((prev) => prev.filter((h) => h.id !== newHeart.id));
    }, 1500);
  };

  const handleOpenProduct = (product: PublicProductView) => {
    setSelectedProduct(product);
    setIsQuickViewOpen(true);
  };

  const handleQuickAddPinned = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (!pinnedProduct || pinnedProduct.status !== 'available' || !cart) return;

    cart.addItem(pinnedProduct, drop.id);
    if (openDrawer) {
      openDrawer();
    }
  };

  const storeName = drop.profiles?.store_name || 'LiveDrop Atelier';

  return (
    <div
      className="relative w-full h-screen max-h-screen bg-[#08080A] text-[#FBFBFB] overflow-hidden select-none flex flex-col font-sans"
      data-testid="cinematic-live-room"
    >
      {/* 1. DOMINANT BACKGROUND: Embedded Facebook Live Stream */}
      <div className="absolute inset-0 w-full h-full z-0 pointer-events-auto">
        <FacebookLivePlayer
          streamUrl={drop.stream_url}
          dropTitle={drop.title}
          storeName={storeName}
          isLive={drop.status === 'live'}
        />
        {/* Subtle cinematic gradient vignette to keep UI text readable */}
        <div className="absolute inset-0 bg-gradient-to-b from-black/70 via-transparent to-black/85 pointer-events-none" />
      </div>

      {/* 2. TOP OVERLAY HEADER */}
      <header className="relative z-20 pt-3 px-4 flex items-center justify-between pointer-events-auto">
        <div className="flex items-center gap-2">
          {/* Back Button */}
          {onExitToGrid ? (
            <button
              type="button"
              onClick={onExitToGrid}
              className="w-9 h-9 rounded-full bg-black/60 backdrop-blur-md border border-white/10 flex items-center justify-center text-white/90 hover:text-white transition-colors cursor-pointer"
              aria-label="Back to catalog grid"
              data-testid="live-room-back-btn"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.25">
                <path d="M15 18l-6-6 6-6" />
              </svg>
            </button>
          ) : (
            <Link
              href="/"
              className="w-9 h-9 rounded-full bg-black/60 backdrop-blur-md border border-white/10 flex items-center justify-center text-white/90 hover:text-white transition-colors"
              aria-label="Return to LiveDrop home"
              data-testid="live-room-back-btn"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.25">
                <path d="M15 18l-6-6 6-6" />
              </svg>
            </Link>
          )}

          {/* Boutique Profile Pill */}
          <Link
            href={drop.profiles?.store_slug ? `/${drop.profiles.store_slug}` : '/'}
            className="flex items-center gap-2 px-2.5 py-1 rounded-full bg-black/60 backdrop-blur-md border border-white/10 hover:border-[rgba(212,175,55,0.4)] transition-all"
          >
            <div className="w-6 h-6 rounded-full bg-[rgba(212,175,55,0.2)] text-[#D4AF37] border border-[rgba(212,175,55,0.3)] flex items-center justify-center text-xs font-serif font-bold">
              {storeName.charAt(0)}
            </div>
            <div className="leading-tight pr-1">
              <div className="flex items-center gap-1">
                <span className="text-xs font-medium text-white tracking-tight">{storeName}</span>
                <span className="text-[#D4AF37] text-[10px]">✓</span>
              </div>
            </div>
          </Link>
        </div>

        {/* Live Badge & Dynamic Viewers */}
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1 px-2.5 py-1 rounded-full bg-[#EF4444] text-white text-[11px] font-bold tracking-wider uppercase shadow-md shadow-red-900/30">
            <span className="w-1.5 h-1.5 rounded-full bg-white animate-ping" />
            <span>LIVE</span>
          </div>

          <div className="flex items-center gap-1 px-2.5 py-1 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-white/90 text-xs font-mono">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7Z" />
              <circle cx="12" cy="12" r="3" />
            </svg>
            <span>{(likesCount / 1000).toFixed(1)}k</span>
          </div>
        </div>
      </header>

      {/* 3. RIGHT FLOATING INTERACTION COLUMN (Screen 3) */}
      <aside className="absolute right-3 bottom-44 z-20 flex flex-col items-center gap-4 pointer-events-auto">
        {/* Shopping Bag Trigger */}
        <button
          type="button"
          onClick={() => openDrawer?.()}
          className="relative w-11 h-11 rounded-full bg-black/60 backdrop-blur-md border border-white/15 hover:border-[#D4AF37] flex items-center justify-center text-white transition-all shadow-lg active:scale-95 cursor-pointer"
          aria-label={`Open Bag with ${itemCount} items`}
          data-testid="live-room-bag-btn"
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75">
            <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
            <path d="M3 6h18" />
            <path d="M16 10a4 4 0 0 1-8 0" />
          </svg>
          {itemCount > 0 && (
            <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 rounded-full bg-[#D4AF37] text-black font-bold text-[10px] flex items-center justify-center shadow-md">
              {itemCount}
            </span>
          )}
        </button>

        {/* Like / Heart Button with Floating Hearts */}
        <div className="relative flex flex-col items-center">
          {flyingHearts.map((h) => (
            <span
              key={h.id}
              className="absolute -top-10 text-red-500 text-xl pointer-events-none animate-bounce"
              style={{ left: `${h.left}px` }}
            >
              ❤️
            </span>
          ))}

          <button
            type="button"
            onClick={handleLike}
            className={`w-11 h-11 rounded-full backdrop-blur-md border flex items-center justify-center transition-all shadow-lg active:scale-90 cursor-pointer ${
              hasLiked
                ? 'bg-red-500/20 border-red-500 text-red-500'
                : 'bg-black/60 border-white/15 text-white hover:text-red-400'
            }`}
            aria-label="Like live stream"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill={hasLiked ? 'currentColor' : 'none'} stroke="currentColor" strokeWidth="2">
              <path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z" />
            </svg>
          </button>
          <span className="text-[10px] font-mono text-white/80 mt-1 font-medium">
            {likesCount}
          </span>
        </div>

        {/* Share Button */}
        <button
          type="button"
          onClick={() => {
            if (navigator.share) {
              navigator.share({
                title: drop.title,
                text: `Watching ${drop.title} on LiveDrop!`,
                url: window.location.href,
              }).catch(() => {});
            }
          }}
          className="w-11 h-11 rounded-full bg-black/60 backdrop-blur-md border border-white/15 hover:border-white/30 flex items-center justify-center text-white/80 hover:text-white transition-colors cursor-pointer"
          aria-label="Share broadcast"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="18" cy="5" r="3" />
            <circle cx="6" cy="12" r="3" />
            <circle cx="18" cy="19" r="3" />
            <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
            <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
          </svg>
        </button>
      </aside>

      {/* 4. BOTTOM-LEFT FLOATING CHAT OVERLAY */}
      <div className="absolute left-4 bottom-48 z-10 max-w-[70%] pointer-events-none space-y-1.5">
        {INITIAL_COMMENTS.map((chat) => (
          <div
            key={chat.id}
            className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-black/55 backdrop-blur-md border border-white/10 text-xs shadow-lg animate-in fade-in slide-in-from-left duration-300"
          >
            <span className="w-5 h-5 rounded-full bg-white/15 text-white text-[10px] font-bold flex items-center justify-center">
              {chat.avatar}
            </span>
            <span className="font-semibold text-white/90 text-[11px]">{chat.sender}:</span>
            <span className="text-white/80 text-[11px] truncate">{chat.message}</span>
          </div>
        ))}
      </div>

      {/* 5. PINNED PRODUCT BOTTOM SHEET (Screen 3) */}
      {pinnedProduct && (
        <div
          className="relative z-20 mt-auto px-4 pb-3 pt-2 bg-gradient-to-t from-black via-black/95 to-transparent pointer-events-auto"
          data-testid="pinned-product-card"
        >
          {/* Top affordance button to expand full catalog */}
          <div className="flex justify-center pb-2">
            <button
              type="button"
              onClick={() => setIsCatalogExpanded(true)}
              className="inline-flex items-center gap-1.5 px-4 py-1 rounded-full bg-black/60 backdrop-blur-md border border-[rgba(212,175,55,0.3)] text-[#D4AF37] text-xs font-semibold tracking-wider uppercase hover:bg-black/80 transition-all cursor-pointer"
              data-testid="expand-catalog-btn"
            >
              <span>View All {products.length} Pieces</span>
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="m18 15-6-6-6 6" />
              </svg>
            </button>
          </div>

          {/* Pinned Card */}
          <div
            onClick={() => handleOpenProduct(pinnedProduct)}
            className="w-full bg-[#121217]/95 border border-[rgba(212,175,55,0.28)] rounded-2xl p-3 flex items-center justify-between gap-3 shadow-2xl backdrop-blur-md cursor-pointer hover:border-[rgba(212,175,55,0.5)] transition-all"
          >
            {/* Left Thumbnail */}
            <div className="relative w-16 h-20 rounded-xl overflow-hidden bg-black/60 flex-shrink-0 border border-white/10">
              <Image
                src={pinnedProduct.image_url || '/placeholder-garment.jpg'}
                alt={pinnedProduct.title}
                fill
                className="object-cover"
                sizes="64px"
              />
              <span className="absolute top-1 left-1 px-1.5 py-0.5 rounded bg-black/80 font-mono text-[9px] text-[#D4AF37] font-bold">
                {pinnedProduct.code}
              </span>
            </div>

            {/* Middle Info */}
            <div className="flex-1 min-w-0 pr-1">
              <div className="flex items-center gap-1.5">
                <span className="text-[10px] text-[#D4AF37] font-semibold tracking-widest uppercase">
                  Spotlight Piece
                </span>
                {pinnedProduct.status === 'available' ? (
                  <span className="w-1.5 h-1.5 rounded-full bg-[#10B981]" />
                ) : (
                  <span className="w-1.5 h-1.5 rounded-full bg-[#F59E0B]" />
                )}
              </div>
              <h4 className="text-sm font-serif text-[#FBFBFB] font-medium truncate pt-0.5">
                {pinnedProduct.title}
              </h4>
              <div className="flex items-baseline gap-2 pt-1">
                <span className="text-base font-serif font-bold text-[#FBFBFB]">
                  {formatPaisaToINR(pinnedProduct.price_paisa)}
                </span>
                <span className="text-[11px] text-white/50 font-mono">
                  {pinnedProduct.size}
                </span>
              </div>
            </div>

            {/* Right Action: Instant Claim / Add to Bag */}
            <div className="flex-shrink-0">
              {pinnedProduct.status === 'available' ? (
                <button
                  type="button"
                  onClick={handleQuickAddPinned}
                  className="px-4 py-2.5 rounded-full bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] font-sans font-bold text-xs tracking-wide shadow-md hover:brightness-110 active:scale-95 transition-all cursor-pointer"
                  data-testid="pinned-claim-btn"
                >
                  Add to Bag
                </button>
              ) : (
                <span className="px-3 py-2 rounded-full bg-white/10 text-white/50 text-xs font-mono">
                  {pinnedProduct.status === 'reserved' ? 'Reserved' : 'Sold Out'}
                </span>
              )}
            </div>
          </div>
        </div>
      )}

      {/* 6. SWIPE-UP FULL CATALOG DRAWER (Facebook Live continues playing in background!) */}
      {isCatalogExpanded && (
        <div
          className="fixed inset-0 z-40 flex flex-col justify-end bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
          data-testid="full-catalog-drawer"
          onClick={() => setIsCatalogExpanded(false)}
        >
          <div
            className="w-full max-w-xl mx-auto h-[70vh] bg-[#0E0E12] border-t border-[rgba(212,175,55,0.3)] rounded-t-3xl shadow-2xl flex flex-col overflow-hidden animate-in slide-in-from-bottom duration-300"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header with Title and Close */}
            <div className="pt-3 pb-3 px-6 border-b border-white/5 bg-[#121217] flex items-center justify-between">
              <div className="w-10 h-1 bg-white/20 rounded-full absolute top-2 left-1/2 -translate-x-1/2" />
              <div>
                <h3 className="text-base font-serif text-[#FBFBFB] tracking-wide pt-1">
                  {drop.title}
                </h3>
                <p className="text-xs text-[#D4AF37] font-sans">
                  {products.length} exclusive couture pieces
                </p>
              </div>

              <button
                type="button"
                onClick={() => setIsCatalogExpanded(false)}
                className="w-8 h-8 rounded-full bg-white/5 hover:bg-white/10 flex items-center justify-center text-white/70 hover:text-white transition-colors"
                aria-label="Close catalog drawer"
              >
                ✕
              </button>
            </div>

            {/* Products Grid */}
            <div className="flex-1 overflow-y-auto p-4 grid grid-cols-2 gap-3 sm:gap-4">
              {products.map((item) => {
                const isPinned = item.id === pinnedProduct?.id;

                return (
                  <div
                    key={item.id}
                    onClick={() => {
                      setPinnedProductId(item.id);
                      handleOpenProduct(item);
                    }}
                    className={`relative rounded-xl overflow-hidden bg-[#14141A] border transition-all cursor-pointer group ${
                      isPinned
                        ? 'border-[#D4AF37] ring-1 ring-[#D4AF37]/50'
                        : 'border-white/5 hover:border-white/20'
                    }`}
                  >
                    <div className="relative aspect-[3/4] w-full bg-black/40">
                      <Image
                        src={item.image_url || '/placeholder-garment.jpg'}
                        alt={item.title}
                        fill
                        className="object-cover group-hover:scale-105 transition-transform duration-300"
                        sizes="(max-width: 640px) 50vw, 250px"
                      />
                      <span className="absolute top-2 left-2 px-2 py-0.5 rounded-full bg-black/80 font-mono text-[10px] text-[#D4AF37] font-bold">
                        {item.code}
                      </span>
                    </div>

                    <div className="p-2.5">
                      <h5 className="text-xs font-serif text-white truncate">
                        {item.title}
                      </h5>
                      <div className="flex items-center justify-between pt-1">
                        <span className="text-xs font-serif font-bold text-[#FBFBFB]">
                          {formatPaisaToINR(item.price_paisa)}
                        </span>
                        <span className="text-[10px] text-white/50 font-mono">
                          {item.size}
                        </span>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* 7. ADAPTIVE PRODUCT QUICK-VIEW DRAWER */}
      <ProductQuickViewDrawer
        product={selectedProduct}
        dropId={drop.id}
        storeName={storeName}
        isOpen={isQuickViewOpen}
        onClose={() => setIsQuickViewOpen(false)}
        onOpenCart={() => {
          setIsQuickViewOpen(false);
          openDrawer?.();
        }}
      />

      {/* 8. SLIDE-OVER CART DRAWER */}
      <CartDrawer
        isOpen={isDrawerOpen}
        onClose={closeDrawer || (() => {})}
        catalogProducts={products}
        drop={drop}
      />
    </div>
  );
}
