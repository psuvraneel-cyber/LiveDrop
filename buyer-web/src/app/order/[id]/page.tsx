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
import { getCachedOrderToken, clearCachedOrderToken, saveRecentOrderSummary } from '../../../lib/cart/cart-storage';
import { OrderReceipt } from '../../../types/domain';
import { CheckoutSuccessView } from '../../../components/checkout/CheckoutSuccessView';
import { MobileBottomDock } from '../../../components/navigation/MobileBottomDock';
import { GlobalBuyerHeader } from '../../../components/navigation/GlobalBuyerHeader';

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
      <div className="ld-checkout-page ld-has-bottom-dock" data-testid="order-token-error-page">
        <GlobalBuyerHeader
          variant="minimal"
          backHref="/"
          backLabel="Return Home"
          backTestId="order-return-home-btn"
          title="LiveDrop"
        />

        <main className="ld-container ld-checkout-main" role="main">
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
            <div style={{ marginTop: '20px' }}>
              <Link href="/" className="ld-btn-browse">
                Browse Live Drops
              </Link>
            </div>
          </div>
        </main>
        <MobileBottomDock />
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
      />

      <main className="ld-container ld-checkout-main" role="main">
        <CheckoutSuccessView
          order={order}
          orderToken={activeToken || undefined}
          dropSlug={order.store_slug || null}
        />
      </main>
      <MobileBottomDock />
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
