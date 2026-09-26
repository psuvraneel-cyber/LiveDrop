'use client';

import React, { useState, useMemo, useSyncExternalStore } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { MobileBottomDock } from '../../components/navigation/MobileBottomDock';
import { getRecentOrders, CachedOrderSummary } from '../../lib/cart/cart-storage';
import { formatPaisaToINR } from '../../lib/utils/currency';

function subscribe(cb: () => void) {
  if (typeof window === 'undefined') return () => {};
  window.addEventListener('storage', cb);
  return () => window.removeEventListener('storage', cb);
}

function getCachedOrdersSnapshot(): string {
  if (typeof window === 'undefined') return '[]';
  try {
    return JSON.stringify(getRecentOrders());
  } catch {
    return '[]';
  }
}

function getServerOrdersSnapshot(): string {
  return '[]';
}

function formatOrderStatus(status?: string, paymentStatus?: string, fulfilmentStatus?: string): string {
  if (fulfilmentStatus === 'delivered') return 'Delivered';
  if (fulfilmentStatus === 'shipped') return 'Shipped';
  if (fulfilmentStatus === 'preparing') return 'Preparing';
  if (paymentStatus === 'verified') return 'Payment Verified';
  if (paymentStatus === 'pending') return 'Payment Pending';
  if (status === 'cancelled') return 'Cancelled';
  return 'Order Placed';
}

export default function OrderLookupPage() {
  const router = useRouter();
  const [orderQuery, setOrderQuery] = useState('');
  const [orderToken, setOrderToken] = useState('');
  const [error, setError] = useState<string | null>(null);

  const cachedOrdersRaw = useSyncExternalStore(
    subscribe,
    getCachedOrdersSnapshot,
    getServerOrdersSnapshot
  );

  const cachedOrders = useMemo<CachedOrderSummary[]>(() => {
    try {
      return JSON.parse(cachedOrdersRaw) as CachedOrderSummary[];
    } catch {
      return [];
    }
  }, [cachedOrdersRaw]);

  const handleLookup = (e: React.FormEvent) => {
    e.preventDefault();
    const query = orderQuery.trim();
    const manualToken = orderToken.trim();

    if (!query) {
      setError('Please enter your order number or tracking link');
      return;
    }

    // 1. Check if user pasted a full tracking URL or relative path
    if (query.includes('order/') || query.includes('token=')) {
      try {
        const urlStr = query.startsWith('http') ? query : `https://livedrop.store${query.startsWith('/') ? '' : '/'}${query}`;
        const url = new URL(urlStr);
        const pathParts = url.pathname.split('/').filter(Boolean);
        const idIndex = pathParts.indexOf('order');
        const extractedId = idIndex >= 0 && pathParts[idIndex + 1] ? pathParts[idIndex + 1] : '';
        const extractedToken = url.searchParams.get('token') || url.searchParams.get('order_token') || manualToken;

        if (extractedId && extractedToken) {
          router.push(`/order/${encodeURIComponent(extractedId)}?token=${encodeURIComponent(extractedToken)}`);
          return;
        }
      } catch {
        // Fall back to direct ID parsing
      }
    }

    // 2. Check if the query matches an order safely cached on this device
    const matched = cachedOrders.find(
      (o) =>
        o.id.toLowerCase() === query.toLowerCase() ||
        (o.orderCode && o.orderCode.toLowerCase() === query.toLowerCase()) ||
        query.toLowerCase().includes(o.id.toLowerCase())
    );

    if (matched && matched.token) {
      router.push(`/order/${encodeURIComponent(matched.id)}?token=${encodeURIComponent(matched.token)}`);
      return;
    }

    // 3. For new devices without local token cache, an access token is required
    if (!manualToken) {
      setError('Please enter your receipt access key (or paste your order link)');
      return;
    }

    router.push(`/order/${encodeURIComponent(query)}?token=${encodeURIComponent(manualToken)}`);
  };

  return (
    <div className="ld-home-storefront ld-has-bottom-dock min-h-screen bg-[#090909] text-[#F4F1EA]">
      <header className="ld-navbar" role="banner">
        <div className="ld-navbar-inner">
          <Link href="/" className="ld-brand-emblem" aria-label="LiveDrop Home">
            <span className="ld-brand-sparkle">✦</span>
            <span className="ld-brand-title">LiveDrop</span>
            <span className="ld-brand-sub">ORDERS</span>
          </Link>
          <Link href="/" className="ld-nav-link text-xs sm:text-sm text-[#AAA49A] hover:text-[#C79A45] transition-colors">
            ← Return to Boutiques
          </Link>
        </div>
      </header>

      <main className="ld-container ld-order-lookup-main max-w-xl mx-auto px-4 py-8 space-y-8" role="main">
        {/* Header Mental Model: Track Your Order */}
        <div className="ld-order-lookup-header space-y-2 text-center">
          <div className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full bg-white/5 border border-white/10 text-[11px] font-mono font-bold tracking-wider text-[#C79A45] uppercase">
            <span className="w-1.5 h-1.5 rounded-full bg-[#C79A45]" />
            ATELIER TRACKING
          </div>
          <h1 className="ld-order-lookup-title text-2xl sm:text-3xl font-serif text-[#F4F1EA] tracking-wide">
            Track Your Order
          </h1>
          <p className="ld-order-lookup-subtitle text-xs sm:text-sm text-[#AAA49A] leading-relaxed max-w-md mx-auto">
            View payment status, preparation, shipping, and delivery updates.
          </p>
        </div>

        {/* 1. Recent Orders on This Device */}
        {cachedOrders.length > 0 && (
          <div className="ld-recent-orders-card p-4 sm:p-5 rounded-2xl bg-[#121211] border border-white/10 space-y-3.5 shadow-lg">
            <div className="flex items-center justify-between border-b border-white/5 pb-2.5">
              <h2 className="ld-recent-orders-title text-sm sm:text-base font-serif font-semibold text-[#F4F1EA]">
                Recent Orders on This Device
              </h2>
              <span className="text-[11px] text-[#AAA49A] font-mono">
                {cachedOrders.length} saved
              </span>
            </div>

            <div className="ld-recent-orders-list space-y-2.5">
              {cachedOrders.map((ord) => {
                const displayCode = ord.orderCode || (ord.id.startsWith('ord-') ? ord.id : `Order #${ord.id.slice(0, 8)}...`);
                const formattedCode = displayCode.startsWith('Order #') ? displayCode : (displayCode.startsWith('#') ? `Order ${displayCode}` : `Order #${displayCode}`);

                return (
                  <Link
                    key={ord.id}
                    href={`/order/${encodeURIComponent(ord.id)}?token=${encodeURIComponent(ord.token)}`}
                    className="ld-recent-order-link p-3 rounded-xl bg-white/[0.03] hover:bg-white/[0.06] border border-white/5 hover:border-[rgba(199,154,69,0.3)] transition-all flex items-center justify-between gap-3 group"
                    data-testid={`recent-order-item-${ord.id}`}
                  >
                    <div className="min-w-0 space-y-0.5">
                      <div className="flex items-center gap-2">
                        <span className="ld-recent-order-code font-mono text-xs sm:text-sm font-bold text-white group-hover:text-[#E2C27A] transition-colors truncate">
                          {formattedCode}
                        </span>
                        {ord.paymentStatus && (
                          <span className="text-[10px] px-2 py-0.5 rounded bg-[#C79A45]/15 text-[#E2C27A] border border-[#C79A45]/30 font-medium">
                            {formatOrderStatus(undefined, ord.paymentStatus, ord.fulfilmentStatus)}
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2 text-[11px] text-[#AAA49A]">
                        <span>{ord.storeName || 'Independent Boutique'}</span>
                        {typeof ord.totalPaisa === 'number' && ord.totalPaisa > 0 && (
                          <>
                            <span>•</span>
                            <span className="font-mono text-white/80">{formatPaisaToINR(ord.totalPaisa)}</span>
                          </>
                        )}
                      </div>
                    </div>

                    <span className="ld-recent-order-cta text-xs text-[#C79A45] font-semibold group-hover:translate-x-0.5 transition-transform flex-shrink-0">
                      View Receipt →
                    </span>
                  </Link>
                );
              })}
            </div>
          </div>
        )}

        {/* 2. Manual Lookup Form */}
        <form onSubmit={handleLookup} className="ld-order-lookup-form p-5 sm:p-6 rounded-2xl bg-[#121211] border border-white/10 space-y-4 shadow-lg">
          <div className="space-y-1">
            <h2 className="ld-order-form-title text-base font-serif font-semibold text-white">
              Have an order link?
            </h2>
            <p className="text-xs text-[#AAA49A]">
              Enter your order number or paste the tracking link sent upon reservation.
            </p>
          </div>

          {error && (
            <div className="ld-order-error-alert p-3 rounded-lg bg-red-950/40 border border-red-500/40 text-xs text-red-300" role="alert">
              {error}
            </div>
          )}

          <div className="ld-order-input-group space-y-1.5">
            <label htmlFor="orderIdInput" className="ld-order-input-label block text-xs font-medium text-[#AAA49A]">
              Order Number or Tracking Link
            </label>
            <input
              id="orderIdInput"
              aria-label="Order Number or Tracking Link"
              type="text"
              placeholder="e.g. LD7840 or paste order link"
              value={orderQuery}
              onChange={(e) => setOrderQuery(e.target.value)}
              className="ld-nav-search-input ld-order-input w-full px-3.5 py-2.5 rounded-xl bg-black/60 border border-white/10 text-white text-xs sm:text-sm focus:outline-none focus:border-[#C79A45] transition-colors"
            />
          </div>

          <div className="ld-order-input-group space-y-1.5">
            <label htmlFor="orderTokenInput" className="ld-order-input-label block text-xs font-medium text-[#AAA49A]">
              Receipt Access Key (for new devices)
            </label>
            <input
              id="orderTokenInput"
              aria-label="Receipt Access Key"
              type="text"
              placeholder="Access key from order confirmation SMS or link"
              value={orderToken}
              onChange={(e) => setOrderToken(e.target.value)}
              className="ld-nav-search-input ld-order-input w-full px-3.5 py-2.5 rounded-xl bg-black/60 border border-white/10 text-white text-xs sm:text-sm focus:outline-none focus:border-[#C79A45] transition-colors"
            />
          </div>

          <button
            type="submit"
            className="ld-btn-gold-cta ld-order-submit-btn w-full py-3 rounded-full bg-gradient-to-r from-[#E2C27A] via-[#C79A45] to-[#B58632] text-[#090909] font-serif font-bold text-xs sm:text-sm tracking-wide transition-all shadow-md hover:scale-[1.01] active:scale-[0.99] cursor-pointer"
            aria-label="Retrieve Order Receipt"
          >
            Find Order →
          </button>
        </form>
      </main>

      <MobileBottomDock />
    </div>
  );
}
