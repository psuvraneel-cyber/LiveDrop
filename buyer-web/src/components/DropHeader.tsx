import React from 'react';
import { PublicDropCatalog } from '../types/domain';
import { formatPaisaToINR } from '../lib/utils/currency';
import { useOptionalCart } from '../lib/cart/cart-context';

export type RealtimeStatus = 'connected' | 'connecting' | 'polling' | 'disconnected';

export interface DropHeaderProps {
  drop: PublicDropCatalog;
  realtimeStatus: RealtimeStatus;
  onOpenCart?: () => void;
}

export function DropHeader({ drop, realtimeStatus, onOpenCart }: DropHeaderProps) {
  const storeName = drop.profiles?.store_name || 'LiveDrop Boutique';
  const shippingFeePaisa = drop.shipping_fee_paisa;
  const freeShippingThresholdPaisa = drop.free_shipping_threshold_paisa;

  const cart = useOptionalCart();
  const itemCount = cart?.itemCount ?? 0;
  const isHydrated = cart?.isHydrated ?? false;

  // Formatted initial of store name for avatar
  const avatarLetter = storeName.charAt(0).toUpperCase() || 'L';

  return (
    <header className="ld-header" data-testid="drop-header" role="banner">
      <div className="ld-header-inner">
        <div className="ld-header-top">
          {/* Boutique Store Branding */}
          <div className="ld-store-branding">
            <div className="ld-store-avatar" aria-hidden="true">
              {avatarLetter}
            </div>
            <div className="ld-store-info">
              <span className="ld-store-name" data-testid="header-store-name">{storeName}</span>
              <span className="ld-drop-title" data-testid="header-drop-title">{drop.title}</span>
            </div>
          </div>

          {/* Header Controls: Live Badge, Status, and Cart Button */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '4px' }}>
              <span className="ld-live-badge" data-testid="live-now-badge" aria-label="Drop is currently live">
                <span className="ld-live-dot" aria-hidden="true" />
                LIVE NOW
              </span>
              <span
                className="ld-realtime-pill"
                data-testid="realtime-status"
                title={
                  realtimeStatus === 'connected'
                    ? 'Realtime live inventory updates active'
                    : realtimeStatus === 'polling'
                    ? 'Live inventory updates via backup polling'
                    : realtimeStatus === 'connecting'
                    ? 'Connecting to live updates...'
                    : 'Live updates temporarily disconnected (catalog current)'
                }
              >
                <span className={`ld-realtime-indicator ${realtimeStatus}`} aria-hidden="true" />
                {realtimeStatus === 'connected'
                  ? 'Live updates'
                  : realtimeStatus === 'polling'
                  ? 'Backup Polling'
                  : realtimeStatus === 'connecting'
                  ? 'Connecting...'
                  : 'Offline'}
              </span>
            </div>

            {/* Accessible Header Cart Trigger */}
            <button
              type="button"
              className="ld-header-cart-btn"
              onClick={onOpenCart || cart?.openDrawer}
              data-testid="header-cart-btn"
              aria-label={`Shopping cart with ${itemCount} items`}
            >
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z" />
                <path d="M3 6h18" />
                <path d="M16 10a4 4 0 0 1-8 0" />
              </svg>
              {isHydrated && itemCount > 0 && (
                <span className="ld-header-cart-badge" data-testid="header-cart-count">
                  {itemCount}
                </span>
              )}
            </button>
          </div>
        </div>

        {/* Shipping Notice Banner (if configured) */}
        {shippingFeePaisa !== undefined && (
          <div className="ld-shipping-notice" data-testid="shipping-notice">
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M14 18V6a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2v11a1 1 0 0 0 1 1h2" />
              <path d="M15 18H9" />
              <path d="M19 18h2a1 1 0 0 0 1-1v-5l-3-4h-5v10Z" />
              <circle cx="7" cy="18" r="2" />
              <circle cx="17" cy="18" r="2" />
            </svg>
            <span>
              {freeShippingThresholdPaisa && freeShippingThresholdPaisa > 0 ? (
                <>Shipping: {formatPaisaToINR(shippingFeePaisa)} • <strong>Free above {formatPaisaToINR(freeShippingThresholdPaisa)}</strong></>
              ) : shippingFeePaisa === 0 ? (
                <strong>Free Shipping on all orders!</strong>
              ) : (
                <>Standard Shipping: {formatPaisaToINR(shippingFeePaisa)}</>
              )}
            </span>
          </div>
        )}
      </div>
    </header>
  );
}
