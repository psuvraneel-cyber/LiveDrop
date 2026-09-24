'use client';

import React, { useState, useMemo, useSyncExternalStore } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { MobileBottomDock } from '../../components/navigation/MobileBottomDock';

function subscribe(cb: () => void) {
  if (typeof window === 'undefined') return () => {};
  window.addEventListener('storage', cb);
  return () => window.removeEventListener('storage', cb);
}

function getCachedOrdersSnapshot(): string {
  if (typeof window === 'undefined') return '[]';
  try {
    const found: { id: string; token: string }[] = [];
    for (let i = 0; i < window.localStorage.length; i++) {
      const key = window.localStorage.key(i);
      if (key && key.startsWith('livedrop_order_token_')) {
        const id = key.replace('livedrop_order_token_', '');
        const token = window.localStorage.getItem(key);
        if (id && token) {
          found.push({ id, token });
        }
      }
    }
    return JSON.stringify(found);
  } catch {
    return '[]';
  }
}

function getServerOrdersSnapshot(): string {
  return '[]';
}

export default function OrderLookupPage() {
  const router = useRouter();
  const [orderId, setOrderId] = useState('');
  const [orderToken, setOrderToken] = useState('');
  const [error, setError] = useState<string | null>(null);

  const cachedOrdersRaw = useSyncExternalStore(
    subscribe,
    getCachedOrdersSnapshot,
    getServerOrdersSnapshot
  );

  const cachedOrders = useMemo<{ id: string; token: string }[]>(() => {
    try {
      return JSON.parse(cachedOrdersRaw) as { id: string; token: string }[];
    } catch {
      return [];
    }
  }, [cachedOrdersRaw]);

  const handleLookup = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanId = orderId.trim();
    const cleanToken = orderToken.trim();

    if (!cleanId) {
      setError('Please enter your Order ID');
      return;
    }
    if (!cleanToken) {
      setError('Please enter your Order Access Token');
      return;
    }

    router.push(`/order/${encodeURIComponent(cleanId)}?token=${encodeURIComponent(cleanToken)}`);
  };

  return (
    <div className="ld-home-storefront ld-has-bottom-dock">
      <header className="ld-navbar" role="banner">
        <div className="ld-navbar-inner">
          <Link href="/" className="ld-brand-emblem" aria-label="LiveDrop Home">
            <span className="ld-brand-sparkle">✦</span>
            <span className="ld-brand-title">LiveDrop</span>
            <span className="ld-brand-sub">ORDERS</span>
          </Link>
          <Link href="/" className="ld-nav-link">
            ← Return to Boutiques
          </Link>
        </div>
      </header>

      <main className="ld-container ld-order-lookup-main" role="main">
        <div className="ld-order-lookup-header">
          <span className="ld-hero-live-pill active">
            <span className="ld-hero-live-dot" />
            ATELIER TRACKING
          </span>
          <h1 className="ld-order-lookup-title">
            Track Your Order
          </h1>
          <p className="ld-order-lookup-subtitle">
            Access your order receipt, UPI payment verification status, and studio dispatch details.
          </p>
        </div>

        {/* Recent orders on this device */}
        {cachedOrders.length > 0 && (
          <div className="ld-recent-orders-card">
            <h2 className="ld-recent-orders-title">
              Recent Orders on This Device
            </h2>
            <div className="ld-recent-orders-list">
              {cachedOrders.map((ord) => (
                <Link
                  key={ord.id}
                  href={`/order/${encodeURIComponent(ord.id)}?token=${encodeURIComponent(ord.token)}`}
                  className="ld-recent-order-link"
                >
                  <span className="ld-recent-order-code">
                    Order #{ord.id.slice(0, 8)}...
                  </span>
                  <span className="ld-recent-order-cta">
                    View Receipt →
                  </span>
                </Link>
              ))}
            </div>
          </div>
        )}

        {/* Manual Lookup Form */}
        <form onSubmit={handleLookup} className="ld-order-lookup-form">
          <h2 className="ld-order-form-title">
            Access by Order Details
          </h2>

          {error && (
            <div className="ld-order-error-alert" role="alert">
              {error}
            </div>
          )}

          <div className="ld-order-input-group">
            <label htmlFor="orderIdInput" className="ld-order-input-label">
              Order Identifier (UUID)
            </label>
            <input
              id="orderIdInput"
              type="text"
              placeholder="e.g. 8a329e71-4b10-4055-..."
              value={orderId}
              onChange={(e) => setOrderId(e.target.value)}
              className="ld-nav-search-input ld-order-input"
            />
          </div>

          <div className="ld-order-input-group">
            <label htmlFor="orderTokenInput" className="ld-order-input-label">
              Order Security Token
            </label>
            <input
              id="orderTokenInput"
              type="text"
              placeholder="Receipt access token from SMS / link"
              value={orderToken}
              onChange={(e) => setOrderToken(e.target.value)}
              className="ld-nav-search-input ld-order-input"
            />
          </div>

          <button
            type="submit"
            className="ld-btn-gold-cta ld-order-submit-btn"
          >
            Retrieve Order Receipt →
          </button>
        </form>
      </main>

      <MobileBottomDock />
    </div>
  );
}
