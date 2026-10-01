'use client';

import React, { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { HoldCountdown } from './HoldCountdown';
import {
  OrderReceipt,
  CreateOrderSuccessResponse,
  OrderStatus,
  OrderPaymentStatus,
  OrderFulfilmentStatus,
} from '../../types/domain';
import { CartItem } from '../../types/cart';
import { DirectUpiPaymentView } from './DirectUpiPaymentView';

export interface CheckoutSuccessViewProps {
  order: CreateOrderSuccessResponse | OrderReceipt;
  orderToken?: string;
  reservedItems?: CartItem[];
  dropSlug?: string | null;
}

// Golden Festive Confetti Animation Canvas
function ConfettiEffect() {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    let ctx: CanvasRenderingContext2D | null = null;
    try {
      ctx = typeof canvas.getContext === 'function' ? canvas.getContext('2d') : null;
    } catch {
      return;
    }
    if (!ctx) return;

    let animationFrameId: number;
    const width = (canvas.width = window.innerWidth);
    const height = (canvas.height = window.innerHeight);

    // Gold, champagne, bronze metallic particles
    const colors = ['#E5A93C', '#FDE68A', '#C88A24', '#FFFFFF', '#F59E0B', '#10B981'];
    const particles = Array.from({ length: 65 }, () => ({
      x: Math.random() * width,
      y: Math.random() * -height * 0.5,
      size: Math.random() * 7 + 4,
      color: colors[Math.floor(Math.random() * colors.length)],
      speedY: Math.random() * 2.5 + 1.2,
      speedX: Math.random() * 2 - 1,
      rotation: Math.random() * 360,
      rotationSpeed: Math.random() * 4 - 2,
    }));

    const startTime = Date.now();

    const render = () => {
      ctx.clearRect(0, 0, width, height);

      // Stop after 6 seconds to conserve battery
      if (Date.now() - startTime > 6000) {
        return;
      }

      particles.forEach((p) => {
        p.y += p.speedY;
        p.x += p.speedX;
        p.rotation += p.rotationSpeed;

        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate((p.rotation * Math.PI) / 180);
        ctx.fillStyle = p.color;
        ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6);
        ctx.restore();
      });

      animationFrameId = requestAnimationFrame(render);
    };

    render();

    return () => {
      cancelAnimationFrame(animationFrameId);
    };
  }, []);

  return <canvas ref={canvasRef} className="ld-confetti-canvas" aria-hidden="true" />;
}

function getOrderStateBadge(status: OrderStatus) {
  switch (status) {
    case 'confirmed':
      return { label: 'Confirmed', styleClass: 'ld-status-badge-order-confirmed' };
    case 'paid':
      return { label: 'Paid', styleClass: 'ld-status-badge-order-paid' };
    case 'shipped':
      return { label: 'Shipped', styleClass: 'ld-status-badge-order-shipped' };
    case 'cancelled':
      return { label: 'Cancelled', styleClass: 'ld-status-badge-order-cancelled' };
    case 'expired':
      return { label: 'Expired', styleClass: 'ld-status-badge-order-expired' };
    case 'pending':
    default:
      return { label: 'Pending', styleClass: 'ld-status-badge-order-pending' };
  }
}

function getPaymentStateBadge(status: OrderPaymentStatus) {
  switch (status) {
    case 'advance_paid':
      return { label: 'Advance Paid', styleClass: 'ld-status-badge-payment-advance' };
    case 'paid':
      return { label: 'Fully Paid', styleClass: 'ld-status-badge-payment-paid' };
    case 'unpaid':
    default:
      return { label: 'Unpaid', styleClass: 'ld-status-badge-payment-unpaid' };
  }
}

function getFulfilmentStateBadge(status: OrderFulfilmentStatus) {
  switch (status) {
    case 'ready_to_ship':
      return { label: 'Ready to Ship', styleClass: 'ld-status-badge-fulfilment-ready' };
    case 'shipped':
      return { label: 'Shipped', styleClass: 'ld-status-badge-fulfilment-shipped' };
    case 'not_ready':
    default:
      return { label: 'Not Ready', styleClass: 'ld-status-badge-fulfilment-not-ready' };
  }
}

export function CheckoutSuccessView({
  order,
  orderToken,
  reservedItems = [],
  dropSlug,
}: CheckoutSuccessViewProps) {
  const [currentOrder, setCurrentOrder] = React.useState<CreateOrderSuccessResponse | OrderReceipt>(order);
  const [isCopied, setIsCopied] = useState(false);

  const isReceipt = 'items' in currentOrder;
  const orderId = 'order_id' in currentOrder ? currentOrder.order_id : currentOrder.id;
  const orderCode = currentOrder.order_code;
  const subtotalPaisa = currentOrder.subtotal_paisa;
  const shippingPaisa = currentOrder.shipping_paisa;
  const totalPaisa = currentOrder.total_paisa;
  const holdExpiresAt = currentOrder.hold_expires_at;

  const resolvedToken = orderToken || ('order_token' in currentOrder ? currentOrder.order_token : '');

  const orderStatus: OrderStatus = 'status' in currentOrder ? currentOrder.status : 'pending';
  const paymentStatus: OrderPaymentStatus = currentOrder.payment_status || 'unpaid';
  const fulfilmentStatus: OrderFulfilmentStatus =
    'fulfilment_status' in currentOrder && currentOrder.fulfilment_status
      ? currentOrder.fulfilment_status
      : 'not_ready';

  const isTerminal = orderStatus === 'cancelled' || orderStatus === 'expired';

  const orderBadge = getOrderStateBadge(orderStatus);
  const paymentBadge = getPaymentStateBadge(paymentStatus);
  const fulfilmentBadge = getFulfilmentStateBadge(fulfilmentStatus);

  const storeName = 'store_name' in currentOrder ? currentOrder.store_name : null;
  const courierPartner = 'courier_partner' in currentOrder ? currentOrder.courier_partner : null;
  const trackingNumber = 'tracking_number' in currentOrder ? currentOrder.tracking_number : null;
  const shippedAt = 'shipped_at' in currentOrder ? currentOrder.shipped_at : null;

  const advanceRequiredPaisa = currentOrder.advance_required_paisa || 0;
  const advancePaidPaisa = currentOrder.advance_paid_paisa || 0;
  const balanceDuePaisa = currentOrder.balance_due_paisa || 0;
  const confirmationMode = currentOrder.confirmation_mode;

  const displayItems = isReceipt
    ? (order as OrderReceipt).items.map((item) => ({
        productId: item.product_id,
        code: item.code,
        title: item.title,
        imageUrl: item.image_url,
        pricePaisa: item.price_at_purchase_paisa,
      }))
    : reservedItems.map((item) => ({
        productId: item.productId,
        code: item.code,
        title: item.title,
        imageUrl: item.imageUrl,
        pricePaisa: item.pricePaisa,
      }));

  const backLink = dropSlug ? `/drop/${dropSlug}` : '/';

  const isPaid = paymentStatus === 'paid' || paymentStatus === 'advance_paid';
  const isClaimed =
    isPaid ||
    ('active_payment_attempt' in currentOrder &&
      Boolean(currentOrder.active_payment_attempt?.buyer_submitted_utr));

  const handleCopyTracking = (awb: string) => {
    if (typeof navigator !== 'undefined' && navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(awb).catch(() => {});
    }
    setIsCopied(true);
    setTimeout(() => setIsCopied(false), 2500);
  };

  return (
    <div className="ld-checkout-success" data-testid="checkout-success-view">
      {!isTerminal && <ConfettiEffect />}

      {/* Header Badge */}
      <div className="ld-success-icon-banner">
        <div
          className={`ld-success-circle ${isTerminal ? 'ld-success-circle-terminal' : ''}`}
          aria-hidden="true"
        >
          {orderStatus === 'cancelled' ? (
            <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          ) : orderStatus === 'expired' ? (
            <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="10" />
              <polyline points="12 6 12 12 16 14" />
            </svg>
          ) : (
            <svg
              width="36"
              height="36"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              strokeWidth="3"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <polyline points="20 6 9 17 4 12" />
            </svg>
          )}
        </div>
        <h1 className="ld-success-title">
          {orderStatus === 'cancelled'
            ? 'Order Cancelled'
            : orderStatus === 'expired'
            ? 'Reservation Expired'
            : 'Thank You!'}
        </h1>
        <p className="ld-success-subtitle">
          {orderStatus === 'cancelled'
            ? 'This order has been cancelled by the boutique. No further payment can be processed.'
            : orderStatus === 'expired'
            ? 'The reservation hold duration has ended. Reserved pieces have returned to boutique inventory.'
            : 'Your order has been placed. Your pieces are exclusively reserved for you.'}
        </p>
      </div>

      {/* Order Reference Card */}
      <div className="ld-success-card">
        {/* Terminal Alerts */}
        {orderStatus === 'cancelled' && (
          <div
            className="ld-terminal-banner ld-terminal-banner-cancelled"
            data-testid="order-cancelled-banner"
            role="alert"
          >
            <div className="ld-terminal-banner-icon" aria-hidden="true">✕</div>
            <div className="min-w-0">
              <h4 className="font-semibold text-red-200 text-sm">Order Cancellation Notice</h4>
              <p className="text-xs text-red-300/80 leading-relaxed">
                This order is no longer active. It cannot be paid or fulfilled.
              </p>
            </div>
          </div>
        )}

        {orderStatus === 'expired' && (
          <div
            className="ld-terminal-banner ld-terminal-banner-expired"
            data-testid="order-expired-banner"
            role="alert"
          >
            <div className="ld-terminal-banner-icon" aria-hidden="true">⏱</div>
            <div className="min-w-0">
              <h4 className="font-semibold text-amber-200 text-sm">Hold Duration Ended</h4>
              <p className="text-xs text-amber-300/80 leading-relaxed">
                The hold window expired before payment verification. Reserved pieces have been restored to live inventory.
              </p>
            </div>
          </div>
        )}

        {/* Advance Payment Notice */}
        {paymentStatus === 'advance_paid' && !isTerminal && (
          <div
            className="ld-advance-balance-box"
            data-testid="advance-paid-balance-notice"
            role="status"
          >
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-[#22c55e]" aria-hidden="true" />
              <span className="font-serif font-bold text-sm text-[#F4F1EA]">
                Advance Confirmed: {formatPaisaToINR(advancePaidPaisa)}
              </span>
            </div>
            <p className="text-xs text-[#AAA49A] leading-relaxed">
              Remaining balance of <span className="font-mono text-white font-semibold">{formatPaisaToINR(balanceDuePaisa)}</span> is due upon final fulfillment. Shipment remains held until balance settlement.
            </p>
          </div>
        )}

        {/* Fully Paid Notice */}
        {paymentStatus === 'paid' && !isTerminal && (
          <div
            className="ld-payment-complete-box"
            data-testid="order-fully-paid-notice"
            role="status"
          >
            <div className="flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-[#22c55e]" aria-hidden="true" />
              <span className="font-serif font-bold text-sm text-[#F4F1EA]">
                Payment Complete
              </span>
            </div>
            <p className="text-xs text-[#AAA49A] leading-relaxed">
              Order is fully paid and eligible for atelier garment inspection, packaging, and dispatch.
            </p>
          </div>
        )}

        {/* Code & Timer Row */}
        <div className="ld-success-meta-row">
          <div className="ld-success-code-box">
            <span className="ld-success-label">Order Code</span>
            <span className="ld-order-code-badge" data-testid="success-order-code">
              {orderCode}
            </span>
          </div>

          {/* Active Hold Countdown Timer (only when pending/unpaid) */}
          {!isTerminal && paymentStatus === 'unpaid' && (
            <HoldCountdown expiresAt={holdExpiresAt} />
          )}
        </div>

        {/* Three Distinct Status Badges (Never Merged) */}
        <div className="ld-status-trio" role="region" aria-label="Order Status Badges">
          <div className="ld-status-badge-item">
            <span className="ld-status-badge-label">Order State</span>
            <span
              className={`ld-status-badge ${orderBadge.styleClass}`}
              data-testid="status-badge-order"
            >
              {orderBadge.label}
            </span>
          </div>

          <div className="ld-status-badge-item">
            <span className="ld-status-badge-label">Payment State</span>
            <span
              className={`ld-status-badge ${paymentBadge.styleClass}`}
              data-testid="status-badge-payment"
            >
              {paymentBadge.label}
            </span>
          </div>

          <div className="ld-status-badge-item">
            <span className="ld-status-badge-label">Fulfillment State</span>
            <span
              className={`ld-status-badge ${fulfilmentBadge.styleClass}`}
              data-testid="status-badge-fulfilment"
            >
              {fulfilmentBadge.label}
            </span>
          </div>
        </div>

        {/* Dedicated Shipment & Tracking Card (Strictly requires authoritative Shipped fulfillment state) */}
        {fulfilmentStatus === 'shipped' && (
          <div className="ld-shipment-card" data-testid="shipment-tracking-card">
            <div className="ld-shipment-header">
              <div className="ld-shipment-icon" aria-hidden="true">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect x="1" y="3" width="15" height="13" />
                  <polygon points="16 8 20 8 23 11 23 16 16 16 16 8" />
                  <circle cx="5.5" cy="18.5" r="2.5" />
                  <circle cx="18.5" cy="18.5" r="2.5" />
                </svg>
              </div>
              <div className="min-w-0">
                <h3 className="ld-shipment-title text-sm font-serif font-bold text-white">
                  Carrier Dispatch & Tracking
                </h3>
                <p className="ld-shipment-courier text-xs text-[#AAA49A]">
                  Carrier:{' '}
                  <span className="font-semibold text-[#E2C27A]" data-testid="courier-partner-name">
                    {courierPartner || 'Designated Courier'}
                  </span>
                </p>
              </div>
            </div>

            <div className="ld-shipment-body mt-3 pt-3 border-t border-white/5 space-y-2">
              {trackingNumber ? (
                <div className="ld-tracking-row flex items-center justify-between gap-3 bg-black/40 p-2.5 rounded-xl border border-white/5">
                  <div className="min-w-0">
                    <span className="block text-[10px] uppercase font-mono text-[#AAA49A]">
                      Tracking Number / AWB
                    </span>
                    <span className="ld-tracking-awb font-mono text-sm font-bold text-white tracking-wider" data-testid="tracking-awb-number">
                      {trackingNumber}
                    </span>
                  </div>
                  <button
                    type="button"
                    onClick={() => handleCopyTracking(trackingNumber)}
                    className="ld-copy-btn px-3 py-1.5 rounded-lg bg-white/10 hover:bg-[#C79A45]/20 text-[#E2C27A] border border-white/10 text-xs font-mono font-medium transition-colors"
                    aria-label={isCopied ? 'Tracking number copied' : 'Copy Tracking Number'}
                    style={{ minHeight: '44px', minWidth: '44px' }}
                  >
                    {isCopied ? 'Copied ✓' : 'Copy AWB'}
                  </button>
                </div>
              ) : (
                <div
                  className="ld-tracking-pending-notice text-xs text-[#AAA49A] italic bg-white/[0.02] p-2.5 rounded-xl border border-white/5"
                  data-testid="tracking-pending-notice"
                >
                  AWB tracking number is being registered by the courier partner.
                </div>
              )}

              {shippedAt && (
                <div className="ld-shipment-time text-[11px] text-[#AAA49A] font-mono" data-testid="shipped-at-timestamp">
                  Dispatched: {new Date(shippedAt).toLocaleDateString('en-IN', {
                    day: 'numeric',
                    month: 'short',
                    year: 'numeric',
                    hour: '2-digit',
                    minute: '2-digit',
                  })}
                </div>
              )}
            </div>
          </div>
        )}

        {/* 6-Stage Order Tracking Status Timeline */}
        <div className="ld-order-timeline" aria-label="Order Status Progression">
          {/* Step 1: Payment Submitted */}
          <div
            className={`ld-timeline-step ${
              isTerminal
                ? 'halted'
                : isClaimed
                ? 'completed'
                : 'active'
            }`}
          >
            <div className="ld-timeline-icon-box">
              {isTerminal ? '✕' : isClaimed ? '✓' : '1'}
            </div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Payment Submitted</span>
              <span className="ld-timeline-step-desc">
                {isTerminal
                  ? (orderStatus === 'expired' ? 'Hold expired - reservation halted' : 'Order cancelled')
                  : isPaid
                  ? 'Payment confirmed'
                  : isClaimed
                  ? 'UTR claim submitted'
                  : 'Pending UPI submission'}
              </span>
            </div>
          </div>

          {/* Step 2: Awaiting Seller Verification */}
          <div
            className={`ld-timeline-step ${
              isTerminal
                ? 'halted'
                : isPaid
                ? 'completed'
                : isClaimed
                ? 'active'
                : 'pending'
            }`}
          >
            <div className="ld-timeline-icon-box">
              {isTerminal ? '✕' : isPaid ? '✓' : isClaimed ? '●' : '○'}
            </div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Awaiting Seller Verification</span>
              <span className="ld-timeline-step-desc">
                {isTerminal
                  ? 'Verification halted'
                  : paymentStatus === 'paid'
                  ? 'Payment confirmed by boutique'
                  : paymentStatus === 'advance_paid'
                  ? 'Advance payment confirmed (balance remains due)'
                  : isClaimed
                  ? "We'll notify you once verified by the boutique"
                  : 'Pending payment verification'}
              </span>
            </div>
          </div>

          {/* Step 3: Preparing Order / Ready to Ship */}
          <div
            className={`ld-timeline-step ${
              isTerminal
                ? 'halted'
                : fulfilmentStatus === 'ready_to_ship' || fulfilmentStatus === 'shipped'
                ? 'completed'
                : paymentStatus === 'advance_paid'
                ? 'held'
                : paymentStatus === 'paid'
                ? 'active'
                : 'pending'
            }`}
          >
            <div className="ld-timeline-icon-box">
              {isTerminal
                ? '✕'
                : fulfilmentStatus === 'ready_to_ship' || fulfilmentStatus === 'shipped'
                ? '✓'
                : paymentStatus === 'paid'
                ? '●'
                : '○'}
            </div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Preparing Order</span>
              <span className="ld-timeline-step-desc">
                {isTerminal
                  ? 'Preparation halted'
                  : fulfilmentStatus === 'ready_to_ship' || fulfilmentStatus === 'shipped'
                  ? 'Pieces inspected and cleared for dispatch'
                  : paymentStatus === 'advance_paid'
                  ? 'Held pending balance settlement'
                  : paymentStatus === 'paid'
                  ? 'Packaging pieces in atelier'
                  : 'Awaiting payment verification'}
              </span>
            </div>
          </div>

          {/* Step 4: Shipped */}
          <div
            className={`ld-timeline-step ${
              isTerminal
                ? 'halted'
                : fulfilmentStatus === 'shipped'
                ? 'completed'
                : fulfilmentStatus === 'ready_to_ship'
                ? 'active'
                : 'pending'
            }`}
          >
            <div className="ld-timeline-icon-box">
              {isTerminal
                ? '✕'
                : fulfilmentStatus === 'shipped'
                ? '✓'
                : fulfilmentStatus === 'ready_to_ship'
                ? '●'
                : '○'}
            </div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Shipped</span>
              <span className="ld-timeline-step-desc">
                {isTerminal
                  ? 'Dispatch halted'
                  : fulfilmentStatus === 'shipped'
                  ? (courierPartner ? `Handed over to ${courierPartner}` : 'Handed over to courier partner')
                  : fulfilmentStatus === 'ready_to_ship'
                  ? 'Awaiting courier pickup'
                  : 'Awaiting atelier completion'}
              </span>
            </div>
          </div>

          {/* Step 5: Out for Delivery */}
          <div className={`ld-timeline-step ${isTerminal ? 'halted' : 'pending'}`}>
            <div className="ld-timeline-icon-box">{isTerminal ? '✕' : '○'}</div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Out for Delivery</span>
              <span className="ld-timeline-step-desc">Arriving at your delivery address</span>
            </div>
          </div>

          {/* Step 6: Delivered */}
          <div className={`ld-timeline-step ${isTerminal ? 'halted' : 'pending'}`}>
            <div className="ld-timeline-icon-box">{isTerminal ? '✕' : '○'}</div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Delivered</span>
              <span className="ld-timeline-step-desc">Enjoy your handcrafted boutique piece</span>
            </div>
          </div>
        </div>

        {/* Reserved Items List */}
        <div className="ld-success-items-section">
          <h3 className="ld-success-section-title">
            Reserved Items ({displayItems.length})
          </h3>
          <div className="ld-success-items-list" role="list">
            {displayItems.map((item) => (
              <div
                key={item.productId}
                className="ld-success-item-row"
                data-testid={`success-item-${item.productId}`}
                role="listitem"
              >
                <div className="ld-success-item-media">
                  {item.imageUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={item.imageUrl}
                      alt={`${item.code} - ${item.title}`}
                      className="ld-success-item-img"
                    />
                  ) : (
                    <div className="ld-success-item-placeholder" aria-hidden="true">
                      <span>{item.code}</span>
                    </div>
                  )}
                </div>
                <div className="ld-success-item-details">
                  <div className="ld-success-item-header">
                    <span className="ld-product-code">{item.code}</span>
                    <span className="ld-success-item-price">
                      {formatPaisaToINR(item.pricePaisa)}
                    </span>
                  </div>
                  <span className="ld-success-item-title">{item.title}</span>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Authoritative Database Financial Breakdown */}
        <div className="ld-success-breakdown">
          {storeName && (
            <div className="ld-summary-row border-b border-white/5 pb-2 mb-2">
              <span className="ld-summary-label">Boutique Atelier</span>
              <span className="ld-summary-value font-serif text-[#E2C27A] font-semibold" data-testid="success-store-name">
                {storeName}
              </span>
            </div>
          )}
          <div className="ld-summary-row">
            <span className="ld-summary-label">Authoritative Subtotal</span>
            <span className="ld-summary-value" data-testid="success-subtotal">
              {formatPaisaToINR(subtotalPaisa)}
            </span>
          </div>
          <div className="ld-summary-row">
            <span className="ld-summary-label">Delivery Fee</span>
            <span className="ld-summary-value" data-testid="success-shipping">
              {shippingPaisa === 0 ? 'FREE' : formatPaisaToINR(shippingPaisa)}
            </span>
          </div>
          <div className="ld-summary-row ld-checkout-total-row">
            <span className="ld-total-label">Total Amount</span>
            <span className="ld-total-value" data-testid="success-total">
              {formatPaisaToINR(totalPaisa)}
            </span>
          </div>

          {confirmationMode === 'advance' && (
            <div className="mt-3 pt-3 border-t border-white/10 space-y-1.5 text-xs">
              <div className="ld-summary-row">
                <span className="ld-summary-label text-[#AAA49A]">Advance Required</span>
                <span className="ld-summary-value font-mono text-white/90" data-testid="success-advance-required">
                  {formatPaisaToINR(advanceRequiredPaisa)}
                </span>
              </div>
              <div className="ld-summary-row">
                <span className="ld-summary-label text-[#AAA49A]">Advance Settled</span>
                <span className="ld-summary-value font-mono text-[#22c55e]" data-testid="success-advance-paid">
                  {formatPaisaToINR(advancePaidPaisa)}
                </span>
              </div>
              <div className="ld-summary-row">
                <span className="ld-summary-label text-[#E2C27A] font-semibold">Remaining Balance Due</span>
                <span className="ld-summary-value font-mono text-[#E2C27A] font-bold" data-testid="success-balance-due">
                  {formatPaisaToINR(balanceDuePaisa)}
                </span>
              </div>
            </div>
          )}
        </div>

        {/* Direct UPI Payment & Manual Verification Section (TASK-2.4B) */}
        {!isTerminal && (
          <div data-testid="task-handoff-box">
            <DirectUpiPaymentView
              order={currentOrder}
              orderToken={resolvedToken}
              onOrderRefresh={(updated) => setCurrentOrder(updated)}
            />
          </div>
        )}

        {/* Navigation Return & Tracking Buttons */}
        <div className="ld-success-actions">
          {orderId && resolvedToken && (
            <Link
              href={`/order/${orderId}?token=${resolvedToken}`}
              className="ld-btn-gold-cta ld-btn-track-order"
              data-testid="success-track-order-link"
              style={{ minHeight: '48px', padding: '0 24px' }}
            >
              Track Order Live →
            </Link>
          )}

          <Link
            href={backLink}
            className="ld-btn-browse ld-btn-continue-shopping"
            data-testid="success-back-drop-btn"
            style={{ minHeight: '48px', padding: '0 24px' }}
          >
            Continue Shopping
          </Link>
        </div>
      </div>
    </div>
  );
}
