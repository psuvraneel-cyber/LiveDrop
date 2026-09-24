'use client';

import React, { useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { PublicDropCatalog, PublicProductView } from '../types/domain';
import { getLiveDropBySlug, getPublicProductsForDrop } from '../lib/data/buyer-catalog';
import { getBuyerClient } from '../lib/supabase/client';
import { CatalogRealtimeSubscription } from '../lib/realtime/catalog-realtime';
import { DropHeader, RealtimeStatus } from './DropHeader';
import { CatalogToolbar, AvailabilityFilter } from './CatalogToolbar';
import { ProductGrid } from './ProductGrid';
import { CatalogLoadingSkeleton } from './states/CatalogLoadingSkeleton';
import { DropNotFoundState } from './states/DropNotFoundState';
import { DropUnavailableState } from './states/DropUnavailableState';
import { CatalogEmptyState } from './states/CatalogEmptyState';
import { CatalogSearchEmptyState } from './states/CatalogSearchEmptyState';
import { CatalogErrorState } from './states/CatalogErrorState';
import { LiveDropError } from '../lib/errors';
import { useCart, useOptionalCart, CartProvider } from '../lib/cart/cart-context';
import { StickyCartBar } from './cart/StickyCartBar';
import { CartDrawer } from './cart/CartDrawer';
import { InAppBrowserBanner } from './InAppBrowserBanner';
import { CinematicLiveRoomView } from './live/CinematicLiveRoomView';
import { FacebookLivePlayer } from './live/FacebookLivePlayer';

export type DropViewState = 'loading' | 'live' | 'closed' | 'not_found' | 'error';

export interface PublicDropViewProps {
  slug: string;
  initialDrop?: PublicDropCatalog | null;
  initialProducts?: PublicProductView[];
  initialState?: DropViewState;
  initialError?: string | null;
}

// Helper to sort products deterministically by flash code
function sortProducts(items: PublicProductView[]): PublicProductView[] {
  return [...items].sort((a, b) => a.code.localeCompare(b.code, undefined, { numeric: true, sensitivity: 'base' }));
}

function PublicDropContent({
  slug,
  initialDrop = null,
  initialProducts = [],
  initialState,
  initialError = null,
}: PublicDropViewProps) {
  // Drop lifecycle state
  const [viewState, setViewState] = useState<DropViewState>(() => {
    if (initialState) return initialState;
    if (initialDrop && initialDrop.status === 'live') return 'live';
    if (initialDrop && initialDrop.status !== 'live') return 'closed';
    if (initialDrop === null && initialError) return 'error';
    return 'loading';
  });

  const [drop, setDrop] = useState<PublicDropCatalog | null>(initialDrop);
  const [products, setProducts] = useState<PublicProductView[]>(initialProducts);
  const [errorMessage, setErrorMessage] = useState<string | null>(initialError);

  // Search & Filter state
  const [searchQuery, setSearchQuery] = useState('');
  const [activeFilter, setActiveFilter] = useState<AvailabilityFilter>('all');

  // Cart drawer control
  const { isDrawerOpen, openDrawer, closeDrawer } = useCart();

  // Cinematic live room mode (e.g. from ?view=live or button click)
  const [isCinematicMode, setIsCinematicMode] = useState<boolean>(() => {
    if (typeof window !== 'undefined') {
      const params = new URLSearchParams(window.location.search);
      return params.get('view') === 'live' || params.get('view') === 'cinematic';
    }
    return false;
  });

  // Realtime connection status
  const [realtimeStatus, setRealtimeStatus] = useState<RealtimeStatus>('connecting');

  // Active subscription ref for cleanup
  const activeSubRef = useRef<CatalogRealtimeSubscription | null>(null);
  const activeDropIdRef = useRef<string | null>(initialDrop?.id || null);

  const productsRef = useRef<PublicProductView[]>(products);
  useEffect(() => {
    productsRef.current = products;
  }, [products]);

  // Primary data loader (used on retry button click)
  const loadDropAndCatalog = useCallback(async (targetSlug: string) => {
    if (!targetSlug || targetSlug.trim() === '') {
      setViewState('not_found');
      return;
    }

    setViewState('loading');
    setErrorMessage(null);

    try {
      const client = getBuyerClient();
      const resolvedDrop = await getLiveDropBySlug(client, targetSlug.trim());

      if (!resolvedDrop) {
        setDrop(null);
        setProducts([]);
        setViewState('not_found');
        return;
      }

      if (resolvedDrop.status !== 'live') {
        setDrop(resolvedDrop);
        setProducts([]);
        setViewState('closed');
        return;
      }

      // Fetch active catalog products
      const catalogProducts = await getPublicProductsForDrop(client, resolvedDrop.id);
      const sorted = sortProducts(catalogProducts);

      setDrop(resolvedDrop);
      setProducts(sorted);
      activeDropIdRef.current = resolvedDrop.id;
      setViewState('live');
    } catch (err: unknown) {
      const msg = err instanceof LiveDropError || err instanceof Error ? err.message : String(err);
      setErrorMessage(msg);
      setViewState('error');
    }
  }, []);

  // Initial load if not pre-populated
  useEffect(() => {
    let cancelled = false;

    if (!initialDrop && !initialState) {
      const run = async () => {
        try {
          const client = getBuyerClient();
          const resolvedDrop = await getLiveDropBySlug(client, slug.trim());
          if (cancelled) return;

          if (!resolvedDrop) {
            setDrop(null);
            setProducts([]);
            setViewState('not_found');
            return;
          }

          if (resolvedDrop.status !== 'live') {
            setDrop(resolvedDrop);
            setProducts([]);
            setViewState('closed');
            return;
          }

          const catalogProducts = await getPublicProductsForDrop(client, resolvedDrop.id);
          if (cancelled) return;

          const sorted = sortProducts(catalogProducts);
          setDrop(resolvedDrop);
          setProducts(sorted);
          activeDropIdRef.current = resolvedDrop.id;
          setViewState('live');
        } catch (err: unknown) {
          if (cancelled) return;
          const msg = err instanceof LiveDropError || err instanceof Error ? err.message : String(err);
          setErrorMessage(msg);
          setViewState('error');
        }
      };

      void run();
    }

    return () => {
      cancelled = true;
    };
  }, [slug, initialDrop, initialState]);

  // Realtime Subscription Setup & Cleanup
  useEffect(() => {
    if (viewState !== 'live' || !drop?.id) {
      return;
    }

    const client = getBuyerClient();
    const dropId = drop.id;
    activeDropIdRef.current = dropId;

    const subscription = new CatalogRealtimeSubscription(client, {
      dropId,
      onProductChange: (updatedProduct) => {
        // Cross-drop defense: ensure event matches currently viewed drop
        if (activeDropIdRef.current !== dropId) {
          return;
        }

        setProducts((prev) => {
          const index = prev.findIndex((p) => p.id === updatedProduct.id);
          let nextList: PublicProductView[];

          if (index >= 0) {
            // Update existing product state in place
            nextList = [...prev];
            nextList[index] = updatedProduct;
          } else {
            // New product inserted dynamically into the catalog
            nextList = [...prev, updatedProduct];
          }

          // Deterministic sort preserved
          return sortProducts(nextList);
        });
      },
      onStatusChange: (status) => {
        if (status === 'SUBSCRIBED') {
          setRealtimeStatus('connected');
        } else if (status === 'POLLING') {
          setRealtimeStatus('polling');
        } else if (status === 'TIMED_OUT' || status === 'CHANNEL_ERROR' || status === 'CLOSED') {
          setRealtimeStatus('disconnected');
        }
      },
      onReconnectRequired: () => {
        setRealtimeStatus('connecting');
      },
    });

    // Seed existing known versions
    subscription.seedVersions(productsRef.current);
    subscription.subscribe();
    activeSubRef.current = subscription;

    return () => {
      activeSubRef.current = null;
      void subscription.unsubscribe();
    };
  }, [drop?.id, viewState]);

  // Update seeded versions whenever base products change
  useEffect(() => {
    if (activeSubRef.current && products.length > 0) {
      activeSubRef.current.seedVersions(products);
    }
  }, [products]);

  // Client-side search and filtering logic
  const filteredProducts = useMemo(() => {
    let result = products;

    // 1. Availability filter
    if (activeFilter === 'available') {
      result = result.filter((p) => p.status === 'available');
    } else if (activeFilter === 'unavailable') {
      result = result.filter((p) => p.status === 'reserved' || p.status === 'sold');
    }

    // 2. Search query filter
    const query = searchQuery.trim().toLowerCase();
    if (query !== '') {
      // Normalize query to allow searching with or without '#'
      const cleanCodeQuery = query.startsWith('#') ? query : `#${query}`;

      result = result.filter((p) => {
        const titleMatch = p.title.toLowerCase().includes(query);
        const codeLower = p.code.toLowerCase();
        const codeMatch = codeLower.includes(query) || codeLower.includes(cleanCodeQuery);
        return titleMatch || codeMatch;
      });
    }

    return result;
  }, [products, activeFilter, searchQuery]);

  // State: Loading
  if (viewState === 'loading') {
    return <CatalogLoadingSkeleton />;
  }

  // State: Error
  if (viewState === 'error') {
    return (
      <CatalogErrorState
        message={errorMessage || undefined}
        onRetry={() => loadDropAndCatalog(slug)}
      />
    );
  }

  // State: Not Found
  if (viewState === 'not_found' || !drop) {
    return <DropNotFoundState slug={slug} />;
  }

  // State: Closed / Unavailable
  if (viewState === 'closed') {
    return (
      <DropUnavailableState
        title={drop.title}
        storeName={drop.profiles?.store_name}
      />
    );
  }

  // State: Live Catalog (Cinematic Fullscreen Room)
  if (viewState === 'live' && isCinematicMode && drop) {
    return (
      <CinematicLiveRoomView
        drop={drop}
        products={products}
        realtimeStatus={realtimeStatus}
        onExitToGrid={() => setIsCinematicMode(false)}
      />
    );
  }

  // State: Live Catalog (Grid View with Live Stream Banner)
  return (
    <div>
      {/* Social In-App Browser Guidance Banner */}
      <InAppBrowserBanner />

      {/* Sticky Drop Header */}
      <DropHeader drop={drop} realtimeStatus={realtimeStatus} onOpenCart={openDrawer} />

      {/* Live Stream Spotlight Header Banner */}
      <section className="px-4 pt-3 pb-2 max-w-4xl mx-auto" aria-label="Live Stream Preview">
        <div className="relative w-full rounded-2xl overflow-hidden border border-[rgba(212,175,55,0.25)] bg-[#0E0E12] shadow-xl">
          <div className="relative aspect-video sm:aspect-[21/9] w-full bg-black/80">
            <FacebookLivePlayer
              streamUrl={drop.stream_url}
              dropTitle={drop.title}
              storeName={drop.profiles?.store_name}
              isLive={true}
            />
          </div>
          <div className="p-3 bg-[#121217] flex items-center justify-between gap-3 border-t border-white/5">
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse" />
              <span className="text-xs text-white/90 font-medium">Broadcast Active</span>
            </div>
            <button
              type="button"
              onClick={() => setIsCinematicMode(true)}
              className="px-3.5 py-1.5 rounded-full bg-gradient-to-r from-[#F5D78E] via-[#D4AF37] to-[#C88A24] text-[#08080A] text-xs font-bold font-sans shadow-md hover:brightness-110 active:scale-95 transition-all cursor-pointer flex items-center gap-1.5"
              data-testid="enter-cinematic-mode-btn"
            >
              <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
                <polygon points="5 3 19 12 5 21 5 3" />
              </svg>
              <span>Watch Live Fullscreen</span>
            </button>
          </div>
        </div>
      </section>

      {/* Main Catalog View Container */}
      <main className="ld-container" role="main">
        {/* Search & Filter Toolbar */}
        <CatalogToolbar
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          activeFilter={activeFilter}
          onFilterChange={setActiveFilter}
          totalCount={products.length}
          filteredCount={filteredProducts.length}
        />

        {/* Catalog Feed Section */}
        {products.length === 0 ? (
          <CatalogEmptyState />
        ) : filteredProducts.length === 0 ? (
          <CatalogSearchEmptyState
            searchQuery={searchQuery}
            onClearSearch={() => {
              setSearchQuery('');
              setActiveFilter('all');
            }}
          />
        ) : (
          <ProductGrid products={filteredProducts} dropId={drop.id} />
        )}
      </main>

      {/* Sticky Bottom Cart Bar */}
      <StickyCartBar onOpenCart={openDrawer} />

      {/* Slide-over Cart Drawer */}
      <CartDrawer
        isOpen={isDrawerOpen}
        onClose={closeDrawer}
        catalogProducts={products}
        drop={drop}
      />
    </div>
  );
}

export function PublicDropView(props: PublicDropViewProps) {
  const existingCart = useOptionalCart();
  if (existingCart) {
    return <PublicDropContent {...props} />;
  }

  return (
    <CartProvider>
      <PublicDropContent {...props} />
    </CartProvider>
  );
}
