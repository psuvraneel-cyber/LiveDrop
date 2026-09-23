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
import { useParams, useSearchParams } from 'next/navigation';
import { getBuyerClient } from '../../../lib/supabase/client';
import { getOrderByToken } from '../../../lib/data/buyer-catalog';
import { getCachedOrderToken, clearCachedOrderToken } from '../../../lib/cart/cart-storage';
import { OrderReceipt } from '../../../types/domain';
import { CheckoutSuccessView } from '../../../components/checkout/CheckoutSuccessView';

function OrderTrackingContent() {
  const params = useParams();
  const searchParams = useSearchParams();

  const rawId = params?.id;
  const orderId = Array.isArray(rawId) ? rawId[0] : rawId;
  const urlToken = searchParams.get('token') || searchParams.get('order_token');

  const [order, setOrder] = useState<OrderReceipt | null>(null);
  const [activeToken, setActiveToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [isTokenMissing, setIsTokenMissing] = useState<boolean>(false);

  useEffect(() => {
    let active = true;

    const fetchOrder = async () => {
      if (!orderId || typeof orderId !== 'string') {
        if (active) {
          setIsLoading(false);
          setErrorMessage('Invalid order identifier.');
        }
        return;
      }

      // 1. Resolve token: URL parameter takes precedence, then local order-specific cache
      const resolvedToken = urlToken?.trim() || getCachedOrderToken(orderId);

      if (!resolvedToken) {
        if (active) {
          setIsTokenMissing(true);
          setIsLoading(false);
        }
        return;
      }

      try {
        const client = getBuyerClient();
        const receipt = await getOrderByToken(client, orderId, resolvedToken);
        if (active) {
          setOrder(receipt);
          setActiveToken(resolvedToken);
          setIsLoading(false);
        }
      } catch (err) {
        if (active) {
          // Validation failed: strictly purge cached token to prevent replay
          clearCachedOrderToken(orderId);
          setIsTokenMissing(true);
          setErrorMessage(
            err instanceof Error
              ? err.message
              : 'Invalid or expired order access token. Verification failed.'
          );
          setIsLoading(false);
        }
      }
    };

    void fetchOrder();

    return () => {
      active = false;
    };
  }, [orderId, urlToken]);

  if (isLoading) {
    return (
      <div className="ld-checkout-loading" data-testid="order-tracking-loading">
        <div className="ld-spinner" />
      </div>
    );
  }

  // Token missing or invalid: Never expose order data based solely on route param
  if (isTokenMissing || !order) {
    return (
      <div className="ld-checkout-page" data-testid="order-token-error-page">
        <header className="ld-checkout-header">
          <div className="ld-checkout-nav">
            <Link href="/" className="ld-back-link" data-testid="order-return-home-btn">
              ← Return Home
            </Link>
            <span className="ld-checkout-brand">LiveDrop</span>
          </div>
        </header>

        <main className="ld-container ld-checkout-main" role="main">
          <div className="ld-checkout-empty" data-testid="order-access-restricted">
            <div
              style={{
                fontSize: '44px',
                marginBottom: '16px',
                color: 'var(--stock-reserved)',
              }}
              aria-hidden="true"
            >
              🔒
            </div>
            <h2 className="ld-checkout-empty-title">Order Access Restricted</h2>
            <p className="ld-checkout-empty-desc">
              {errorMessage ||
                'To protect customer privacy under the DPDP Act, orders require a verified access token. Please use the secure order link provided upon reservation.'}
            </p>
            <div style={{ marginTop: '20px' }}>
              <Link href="/" className="ld-btn-browse">
                Browse Live Drops
              </Link>
            </div>
          </div>
        </main>
      </div>
    );
  }

  return (
    <div className="ld-checkout-page" data-testid="order-tracking-page">
      <header className="ld-checkout-header">
        <div className="ld-checkout-nav">
          <Link href="/" className="ld-back-link" data-testid="order-home-link">
            ← Return Home
          </Link>
          <span className="ld-checkout-brand">LiveDrop</span>
        </div>
      </header>

      <main className="ld-container ld-checkout-main" role="main">
        <CheckoutSuccessView
          order={order}
          orderToken={activeToken || undefined}
          dropSlug={order.store_slug || null}
        />
      </main>
    </div>
  );
}

export default function OrderTrackingPage() {
  return (
    <Suspense
      fallback={
        <div className="ld-checkout-loading" data-testid="order-tracking-loading">
          <div className="ld-spinner" />
        </div>
      }
    >
      <OrderTrackingContent />
    </Suspense>
  );
}
