'use client';

/**
 * LiveDrop — Dedicated Order Tracking & Receipt Route (/order/[id])
 *
 * Implements token-gated order lookup for Indian DPDP Act 2023 compliance.
 * Resolves token from ?token= parameter with strict local fallback to
 * matching cached token for this exact order ID.
 */

import React, { Suspense, useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams, useSearchParams, useRouter } from 'next/navigation';
import { getBuyerClient } from '../../../lib/supabase/client';
import { getOrderByToken } from '../../../lib/data/buyer-catalog';
import {
  getCachedOrderToken,
  cacheOrderToken,
  clearCachedOrderToken,
  saveRecentOrderSummary,
} from '../../../lib/cart/cart-storage';
import { OrderReceipt } from '../../../types/domain';
import { CheckoutSuccessView } from '../../../components/checkout/CheckoutSuccessView';
import { MobileBottomDock } from '../../../components/navigation/MobileBottomDock';
import { GlobalBuyerHeader } from '../../../components/navigation/GlobalBuyerHeader';

function OrderTrackingContent() {
  const router = useRouter();
  const params = useParams();
  const searchParams = useSearchParams();

  const rawId = params?.id;
  const orderId = Array.isArray(rawId) ? rawId[0] : rawId;
  const urlToken = searchParams.get('token') || searchParams.get('order_token');

  const [order, setOrder] = useState<OrderReceipt | null>(null);
  const [activeToken, setActiveToken] = useState<string | null>(null);
  const [tokenOverride, setTokenOverride] = useState<string | null>(null);
  const [refreshNonce, setRefreshNonce] = useState<number>(0);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isRefreshing, setIsRefreshing] = useState<boolean>(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isTokenMissing, setIsTokenMissing] = useState<boolean>(false);
  const [manualTokenInput, setManualTokenInput] = useState<string>('');
  const [isNetworkFailure, setIsNetworkFailure] = useState<boolean>(false);
  const [screenReaderAnnouncement, setScreenReaderAnnouncement] = useState<string>('');

  useEffect(() => {
    let active = true;

    const fetchReceipt = async () => {
      if (!orderId || typeof orderId !== 'string') {
        if (active) {
          setIsLoading(false);
          setErrorMessage('Invalid order identifier.');
        }
        return;
      }

      // 1. Resolve token: parameter override, then URL parameter, then local cache
      const resolvedToken =
        tokenOverride?.trim() ||
        urlToken?.trim() ||
        getCachedOrderToken(orderId);

      if (!resolvedToken) {
        if (active) {
          setIsTokenMissing(true);
          setIsLoading(false);
          setScreenReaderAnnouncement('Verification required: Please provide your order access key.');
        }
        return;
      }

      try {
        const client = getBuyerClient();
        const receipt = await getOrderByToken(client, orderId, resolvedToken);
        if (active) {
          setOrder(receipt);
          setActiveToken(resolvedToken);
          setIsTokenMissing(false);
          setErrorMessage(null);
          setIsNetworkFailure(false);
          setIsLoading(false);
          setIsRefreshing(false);
          setScreenReaderAnnouncement(`Order receipt loaded. Status: ${receipt.status}.`);

          // Cache token and save recent order summary
          cacheOrderToken(receipt.id, resolvedToken);
          saveRecentOrderSummary({
            id: receipt.id,
            token: resolvedToken,
            orderCode: receipt.order_code,
            storeName: receipt.store_name,
            totalPaisa: receipt.total_paisa,
            paymentStatus: receipt.payment_status,
            fulfilmentStatus: receipt.fulfilment_status,
          });
        }
      } catch (err) {
        if (active) {
          const errorMsg =
            err instanceof Error
              ? err.message
              : 'Invalid or expired order access token. Verification failed.';

          const isNetworkErr =
            errorMsg.toLowerCase().includes('network') ||
            errorMsg.toLowerCase().includes('fetch') ||
            errorMsg.toLowerCase().includes('connection') ||
            errorMsg.toLowerCase().includes('failed to fetch');

          if (isNetworkErr) {
            setIsNetworkFailure(true);
            setErrorMessage('Connection issue retrieving order receipt. Please check your internet connection.');
          } else {
            // Validation failed: strictly purge cached token to prevent replay
            clearCachedOrderToken(orderId);
            setIsTokenMissing(true);
            setErrorMessage(errorMsg);
          }

          setIsLoading(false);
          setIsRefreshing(false);
          setScreenReaderAnnouncement('Verification failed: access key could not be verified.');
        }
      }
    };

    void fetchReceipt();

    return () => {
      active = false;
    };
  }, [orderId, urlToken, tokenOverride, refreshNonce]);

  const handleManualTokenSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const tokenVal = manualTokenInput.trim();
    if (!tokenVal) return;

    // Check if user entered a full link
    if (tokenVal.includes('order/') || tokenVal.includes('token=')) {
      try {
        const urlStr = tokenVal.startsWith('http')
          ? tokenVal
          : `https://livedrop.store${tokenVal.startsWith('/') ? '' : '/'}${tokenVal}`;
        const parsed = new URL(urlStr);
        const extracted = parsed.searchParams.get('token') || parsed.searchParams.get('order_token');
        if (extracted) {
          router.push(`/order/${encodeURIComponent(orderId || '')}?token=${encodeURIComponent(extracted)}`);
          setIsLoading(true);
          setTokenOverride(extracted);
          return;
        }
      } catch {
        // Fall back to direct value
      }
    }

    router.push(`/order/${encodeURIComponent(orderId || '')}?token=${encodeURIComponent(tokenVal)}`);
    setIsLoading(true);
    setTokenOverride(tokenVal);
  };

  const handleRefresh = () => {
    if (!activeToken && !urlToken) return;
    setIsRefreshing(true);
    setRefreshNonce((prev) => prev + 1);
  };

  if (isLoading) {
    return (
      <div className="ld-checkout-loading" data-testid="order-tracking-loading" role="status">
        <div className="ld-spinner" />
        <span className="sr-only">Loading order receipt...</span>
      </div>
    );
  }

  // Token missing or invalid or network error: Never expose order data based solely on route param
  if (isTokenMissing || !order) {
    return (
      <div className="ld-checkout-page ld-has-bottom-dock" data-testid="order-token-error-page">
        <GlobalBuyerHeader
          variant="minimal"
          backHref="/"
          backLabel="Return Home"
          backTestId="order-return-home-btn"
          title="LiveDrop"
        />

        <main className="ld-container ld-checkout-main" role="main">
          {/* Accessible Live Region */}
          <div className="sr-only" aria-live="assertive" role="alert">
            {screenReaderAnnouncement}
          </div>

          <div className="ld-checkout-empty" data-testid="order-access-restricted">
            <div
              style={{
                marginBottom: '16px',
                color: 'var(--champagne-gold, #D4AF37)',
                display: 'flex',
                justifyContent: 'center',
              }}
              aria-hidden="true"
            >
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
            </div>
            <h2 className="ld-checkout-empty-title">Order Access Restricted</h2>
            <p className="ld-checkout-empty-desc">
              {errorMessage ||
                'To protect customer privacy under the DPDP Act, orders require a verified access token. Please use the secure order link provided upon reservation.'}
            </p>

            {/* Network Failure Retry Action */}
            {isNetworkFailure && (
              <div style={{ marginTop: '16px' }}>
                <button
                  type="button"
                  onClick={() => {
                    setIsLoading(true);
                    setRefreshNonce((prev) => prev + 1);
                  }}
                  className="ld-btn-gold-cta"
                  data-testid="order-retry-btn"
                  style={{ minHeight: '44px', padding: '0 20px' }}
                >
                  Retry Verification
                </button>
              </div>
            )}

            {/* Inline Token Recovery Form */}
            {!isNetworkFailure && (
              <form onSubmit={handleManualTokenSubmit} className="mt-6 max-w-sm mx-auto space-y-3">
                <div className="space-y-1 text-left">
                  <label htmlFor="inlineTokenInput" className="block text-xs font-medium text-[#AAA49A]">
                    Have your receipt access key?
                  </label>
                  <input
                    id="inlineTokenInput"
                    aria-label="Enter Receipt Access Key"
                    type="text"
                    placeholder="Enter access key or paste order link"
                    value={manualTokenInput}
                    onChange={(e) => setManualTokenInput(e.target.value)}
                    className="w-full px-3 py-2 rounded-xl bg-black/60 border border-white/10 text-white text-xs focus:outline-none focus:border-[#C79A45] transition-colors"
                  />
                </div>
                <button
                  type="submit"
                  className="ld-btn-gold-cta w-full py-2.5 rounded-full text-xs font-semibold"
                  style={{ minHeight: '44px' }}
                >
                  Verify Key & Track Order →
                </button>
              </form>
            )}

            <div style={{ marginTop: '20px' }}>
              <Link href="/" className="ld-btn-browse" style={{ minHeight: '44px' }}>
                Browse Live Drops
              </Link>
            </div>
          </div>
        </main>
        <MobileBottomDock activeTabOverride="orders" />
      </div>
    );
  }

  return (
    <div className="ld-checkout-page ld-has-bottom-dock" data-testid="order-tracking-page">
      <GlobalBuyerHeader
        variant="minimal"
        backHref="/"
        backLabel="Return Home"
        backTestId="order-home-link"
        title="LiveDrop"
        rightAction={
          <button
            type="button"
            onClick={handleRefresh}
            className="p-2 rounded-lg bg-white/5 hover:bg-white/10 text-[#C79A45] transition-colors flex items-center gap-1.5 text-xs font-mono"
            aria-label="Refresh Order Status"
            data-testid="order-refresh-status-btn"
            style={{ minHeight: '44px', minWidth: '44px' }}
            disabled={isRefreshing}
          >
            <span className={isRefreshing ? 'animate-spin' : ''} aria-hidden="true">↻</span>
            <span className="hidden sm:inline">Refresh</span>
          </button>
        }
      />

      <main className="ld-container ld-checkout-main" role="main">
        {/* Screen Reader Status Announcements */}
        <div className="sr-only" aria-live="polite" role="status">
          {screenReaderAnnouncement}
        </div>

        <CheckoutSuccessView
          order={order}
          orderToken={activeToken || undefined}
          dropSlug={order.store_slug || null}
        />
      </main>
      <MobileBottomDock activeTabOverride="orders" />
    </div>
  );
}

export default function OrderTrackingPage() {
  return (
    <Suspense
      fallback={
        <div className="ld-checkout-loading" data-testid="order-tracking-loading" role="status">
          <div className="ld-spinner" />
          <span className="sr-only">Loading order tracking...</span>
        </div>
      }
    >
      <OrderTrackingContent />
    </Suspense>
  );
}
