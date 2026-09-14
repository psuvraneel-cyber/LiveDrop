'use client';

import React from 'react';
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

export function CheckoutSuccessView({
  order,
  orderToken,
  reservedItems = [],
  dropSlug,
}: CheckoutSuccessViewProps) {
  const [currentOrder, setCurrentOrder] = React.useState<CreateOrderSuccessResponse | OrderReceipt>(order);
  const isReceipt = 'items' in currentOrder;
  const orderCode = currentOrder.order_code;
  const subtotalPaisa = currentOrder.subtotal_paisa;
  const shippingPaisa = currentOrder.shipping_paisa;
  const totalPaisa = currentOrder.total_paisa;
  const holdExpiresAt = currentOrder.hold_expires_at;

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

  return (
    <div className="ld-checkout-success" data-testid="checkout-success-view">
      {/* Header Badge */}
      <div className="ld-success-icon-banner">
        <div className="ld-success-circle" aria-hidden="true">
          <svg
            width="32"
            height="32"
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
        <h1 className="ld-success-title">Garments Reserved!</h1>
        <p className="ld-success-subtitle">
          Your reservation has been created atomically in the database.
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
            orderToken={orderToken}
            onOrderRefresh={(updated) => setCurrentOrder(updated)}
          />
        </div>

        {/* Navigation Return Button */}
        <div className="ld-success-actions">
          <Link href={backLink} className="ld-btn-browse" data-testid="success-back-drop-btn">
            Return to Live Drop
          </Link>
        </div>
      </div>
    </div>
  );
}
