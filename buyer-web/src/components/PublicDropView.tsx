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

export function PublicDropView({
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

  // State: Live Catalog
  return (
    <div>
      {/* Sticky Drop Header */}
      <DropHeader drop={drop} realtimeStatus={realtimeStatus} />

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
          <ProductGrid products={filteredProducts} />
        )}
      </main>
    </div>
  );
}
