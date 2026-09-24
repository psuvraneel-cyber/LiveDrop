'use client';

import React, { useEffect, useRef } from 'react';
import Link from 'next/link';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { HoldCountdown } from './HoldCountdown';
import { OrderReceipt, CreateOrderSuccessResponse } from '../../types/domain';
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

export function CheckoutSuccessView({
  order,
  orderToken,
  reservedItems = [],
  dropSlug,
}: CheckoutSuccessViewProps) {
  const [currentOrder, setCurrentOrder] = React.useState<CreateOrderSuccessResponse | OrderReceipt>(order);
  const isReceipt = 'items' in currentOrder;
  const orderId = 'order_id' in currentOrder ? currentOrder.order_id : currentOrder.id;
  const orderCode = currentOrder.order_code;
  const subtotalPaisa = currentOrder.subtotal_paisa;
  const shippingPaisa = currentOrder.shipping_paisa;
  const totalPaisa = currentOrder.total_paisa;
  const holdExpiresAt = currentOrder.hold_expires_at;

  const resolvedToken = orderToken || ('order_token' in currentOrder ? currentOrder.order_token : '');

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

  // Format order placed timestamp
  const orderTimestamp = new Date().toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });

  const isPaid = currentOrder.payment_status === 'paid' || currentOrder.payment_status === 'advance_paid';
  const isClaimed =
    isPaid ||
    ('active_payment_attempt' in currentOrder &&
      Boolean(currentOrder.active_payment_attempt?.buyer_submitted_utr));

  return (
    <div className="ld-checkout-success" data-testid="checkout-success-view">
      <ConfettiEffect />

      {/* Header Badge */}
      <div className="ld-success-icon-banner">
        <div className="ld-success-circle" aria-hidden="true">
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
        </div>
        <h1 className="ld-success-title">Thank You!</h1>
        <p className="ld-success-subtitle">
          Your order has been placed. Your pieces are exclusively reserved for you.
        </p>
      </div>

      {/* Order Reference Card */}
      <div className="ld-success-card">
        <div className="ld-success-meta-row">
          <div className="ld-success-code-box">
            <span className="ld-success-label">Order Code</span>
            <span className="ld-order-code-badge" data-testid="success-order-code">
              {orderCode}
            </span>
          </div>

          {/* Active Hold Countdown Timer */}
          <HoldCountdown expiresAt={holdExpiresAt} />
        </div>

        {/* 6-Stage Order Tracking Status Timeline (Template Screen 6) */}
        <div className="ld-order-timeline" aria-label="Order Status Progression">
          {/* Step 1: Payment Submitted */}
          <div className={`ld-timeline-step ${isClaimed ? 'completed' : 'active'}`}>
            <div className="ld-timeline-icon-box">
              {isClaimed ? '✓' : '1'}
            </div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Payment Submitted</span>
              <span className="ld-timeline-step-desc">
                {isClaimed ? `Verified on ${orderTimestamp}` : 'Pending UPI submission'}
              </span>
            </div>
          </div>

          {/* Step 2: Awaiting Verification */}
          <div className={`ld-timeline-step ${isPaid ? 'completed' : isClaimed ? 'active' : 'pending'}`}>
            <div className="ld-timeline-icon-box">
              {isPaid ? '✓' : '●'}
            </div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Awaiting Seller Verification</span>
              <span className="ld-timeline-step-desc">
                {isPaid ? 'Payment confirmed by boutique' : "We'll notify you once verified by the boutique"}
              </span>
            </div>
          </div>

          {/* Step 3: Preparing Order */}
          <div className="ld-timeline-step pending">
            <div className="ld-timeline-icon-box">○</div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Preparing Order</span>
              <span className="ld-timeline-step-desc">Packaging and preparing garment for shipment</span>
            </div>
          </div>

          {/* Step 4: Shipped */}
          <div className="ld-timeline-step pending">
            <div className="ld-timeline-icon-box">○</div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Shipped</span>
              <span className="ld-timeline-step-desc">Handed over to courier partner</span>
            </div>
          </div>

          {/* Step 5: Out for Delivery */}
          <div className="ld-timeline-step pending">
            <div className="ld-timeline-icon-box">○</div>
            <div className="ld-timeline-content">
              <span className="ld-timeline-step-title">Out for Delivery</span>
              <span className="ld-timeline-step-desc">Arriving at your delivery address</span>
            </div>
          </div>

          {/* Step 6: Delivered */}
          <div className="ld-timeline-step pending">
            <div className="ld-timeline-icon-box">○</div>
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
        </div>

        {/* Direct UPI Payment & Manual Verification Section (TASK-2.4B) */}
        <div data-testid="task-handoff-box">
          <DirectUpiPaymentView
            order={currentOrder}
            orderToken={resolvedToken}
            onOrderRefresh={(updated) => setCurrentOrder(updated)}
          />
        </div>

        {/* Navigation Return & Tracking Buttons */}
        <div className="ld-success-actions">
          {orderId && resolvedToken && (
            <Link
              href={`/order/${orderId}?token=${resolvedToken}`}
              className="ld-btn-gold-cta"
            >
              Track Order Live
            </Link>
          )}

          <Link href={backLink} className="ld-btn-browse" data-testid="success-back-drop-btn">
            Continue Shopping
          </Link>
        </div>
      </div>
    </div>
  );
}
