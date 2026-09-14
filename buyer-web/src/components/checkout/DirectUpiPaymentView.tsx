'use client';

import React, { useState, useEffect, useCallback } from 'react';
import QRCode from 'qrcode';
import { formatPaisaToINR } from '../../lib/utils/currency';
import {
  OrderReceipt,
  CreateOrderSuccessResponse,
  PaymentAttempt,
} from '../../types/domain';
import {
  initiatePaymentAttempt,
  submitBuyerPaymentClaim,
  getOrderByToken,
} from '../../lib/data/buyer-catalog';
import { getBuyerClient } from '../../lib/supabase/client';

export interface DirectUpiPaymentViewProps {
  order: CreateOrderSuccessResponse | OrderReceipt;
  orderToken?: string;
  onOrderRefresh?: (updatedOrder: OrderReceipt) => void;
}

export function DirectUpiPaymentView({
  order,
  orderToken,
  onOrderRefresh,
}: DirectUpiPaymentViewProps) {
  const token = 'order_token' in order ? order.order_token : orderToken || '';
  const orderId = 'order_id' in order ? order.order_id : order.id;

  const initialPaymentType =
    order.confirmation_mode === 'advance' && order.payment_status === 'unpaid'
      ? 'advance'
      : 'full';

  const [paymentType, setPaymentType] = useState<'advance' | 'balance' | 'full'>(
    order.payment_status === 'advance_paid' ? 'balance' : initialPaymentType
  );

  const initialAttempt =
    'active_payment_attempt' in order && order.active_payment_attempt
      ? order.active_payment_attempt
      : null;

  const [activeAttempt, setActiveAttempt] = useState<PaymentAttempt | null>(initialAttempt);
  const [upiUri, setUpiUri] = useState<string>(
    initialAttempt?.upi_uri || ('upi_uri' in order && order.upi_uri ? order.upi_uri : '')
  );
  const [qrDataUrl, setQrDataUrl] = useState<string | null>(null);
  const [utrInput, setUtrInput] = useState<string>(initialAttempt?.buyer_submitted_utr || '');
  const [utrError, setUtrError] = useState<string | null>(null);
  const [isInitiating, setIsInitiating] = useState<boolean>(false);
  const [isSubmitting, setIsSubmitting] = useState<boolean>(false);
  const [copiedField, setCopiedField] = useState<'vpa' | 'ref' | 'amount' | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Derive active payment status and lifecycle
  const paymentStatus = order.payment_status;
  const isPaidInFull = paymentStatus === 'paid';
  const isAdvancePaid = paymentStatus === 'advance_paid';
  const orderLifecycleStatus = 'status' in order ? order.status : 'pending';
  const isTerminal = orderLifecycleStatus === 'cancelled' || orderLifecycleStatus === 'expired';

  // 1. Generate QR Code when UPI URI changes
  useEffect(() => {
    let active = true;
    if (!upiUri) {
      return;
    }
    QRCode.toDataURL(upiUri, {
      width: 240,
      margin: 1,
      color: {
        dark: '#0F172A',
        light: '#FFFFFF',
      },
    })
      .then((url) => {
        if (active) setQrDataUrl(url);
      })
      .catch(() => {
        if (active) setQrDataUrl(null);
      });
    return () => {
      active = false;
    };
  }, [upiUri]);

  // 2. Fetch or initiate a payment attempt when needed
  const ensurePaymentAttempt = useCallback(
    async (type: 'advance' | 'balance' | 'full') => {
      if (!orderId || !token || isPaidInFull || isTerminal) return;

      setIsInitiating(true);
      setErrorMessage(null);

      try {
        const client = getBuyerClient();
        const res = await initiatePaymentAttempt(client, orderId, token, type);
        if (res.success) {
          const attempt: PaymentAttempt = {
            id: res.payment_attempt_id,
            order_id: res.order_id,
            payment_type: res.payment_type,
            payment_method: 'upi',
            expected_amount_paisa: res.expected_amount_paisa,
            payee_vpa_snapshot: res.payee_vpa,
            payee_display_name_snapshot: res.payee_display_name,
            transaction_reference: res.transaction_reference,
            status: res.status,
            buyer_claimed_at: null,
            buyer_submitted_utr: null,
            seller_verified_at: null,
            verified_by: null,
            rejection_reason: null,
            expires_at: res.expires_at,
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
            upi_uri: res.upi_uri,
          };
          setActiveAttempt(attempt);
          setUpiUri(res.upi_uri);
        }
      } catch (err) {
        setErrorMessage(err instanceof Error ? err.message : 'Unable to initiate payment.');
      } finally {
        setIsInitiating(false);
      }
    },
    [orderId, token, isPaidInFull, isTerminal]
  );

  // Auto-initiate attempt if none is present and order is unpaid or advance_paid
  useEffect(() => {
    let active = true;
    if (!activeAttempt && !isPaidInFull && !isTerminal) {
      const timer = setTimeout(() => {
        if (active) {
          void ensurePaymentAttempt(paymentType);
        }
      }, 0);
      return () => {
        active = false;
        clearTimeout(timer);
      };
    }
  }, [activeAttempt, paymentType, isPaidInFull, isTerminal, ensurePaymentAttempt]);

  // 3. Handle copy to clipboard
  const handleCopy = (text: string, field: 'vpa' | 'ref' | 'amount') => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(text);
      setCopiedField(field);
      setTimeout(() => setCopiedField(null), 2000);
    }
  };

  // 4. Handle UTR claim submission
  const handleSubmitClaim = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeAttempt) return;

    const cleanUtr = utrInput.trim();
    if (!cleanUtr) {
      setUtrError('Please enter your 12-digit UPI reference (UTR).');
      return;
    }

    if (cleanUtr.length < 6 || cleanUtr.length > 30 || !/^[a-zA-Z0-9]+$/.test(cleanUtr)) {
      setUtrError('UTR must be 6–30 alphanumeric characters without symbols or spaces.');
      return;
    }

    setUtrError(null);
    setIsSubmitting(true);
    setErrorMessage(null);

    try {
      const client = getBuyerClient();
      const res = await submitBuyerPaymentClaim(
        client,
        orderId,
        token,
        activeAttempt.id,
        cleanUtr
      );

      if (res.success) {
        setActiveAttempt((prev) =>
          prev
            ? {
                ...prev,
                status: res.status,
                buyer_submitted_utr: res.buyer_submitted_utr,
                buyer_claimed_at: res.buyer_claimed_at,
              }
            : null
        );

        // Refresh full order receipt if parent listener provided
        if (onOrderRefresh && token) {
          try {
            const updated = await getOrderByToken(client, orderId, token);
            onOrderRefresh(updated);
          } catch {
            // Retain local optimistic state
          }
        }
      }
    } catch (err) {
      setErrorMessage(err instanceof Error ? err.message : 'Failed to submit payment claim.');
    } finally {
      setIsSubmitting(false);
    }
  };

  // ---------------------------------------------------------------------------
  // RENDER: Paid in full state
  // ---------------------------------------------------------------------------
  if (isPaidInFull) {
    return (
      <div className="ld-payment-box ld-payment-box-verified" data-testid="payment-verified-banner">
        <div className="ld-payment-status-badge ld-badge-paid">
          <span className="ld-status-dot" aria-hidden="true" />
          <span>Payment Verified</span>
        </div>
        <h3 className="ld-payment-headline">Full Payment Settled</h3>
        <p className="ld-payment-subtext">
          The boutique has verified your direct UPI payment. Your garments are marked as sold and ready for processing.
        </p>
        <div className="ld-payment-meta-grid">
          <div className="ld-meta-item">
            <span className="ld-meta-label">Total Paid</span>
            <span className="ld-meta-val ld-text-emerald" data-testid="verified-total-paid">
              {formatPaisaToINR(order.total_paid_paisa)}
            </span>
          </div>
          <div className="ld-meta-item">
            <span className="ld-meta-label">Balance Due</span>
            <span className="ld-meta-val">₹0.00</span>
          </div>
          <div className="ld-meta-item">
            <span className="ld-meta-label">Fulfilment</span>
            <span className="ld-meta-val ld-badge-ready" data-testid="verified-fulfilment-status">
              {order.fulfilment_status === 'shipped' ? 'Shipped' : 'Ready to Ship'}
            </span>
          </div>
        </div>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // RENDER: Terminal states (Cancelled / Expired)
  // ---------------------------------------------------------------------------
  if (isTerminal) {
    return (
      <div className="ld-payment-box ld-payment-box-terminal" data-testid="payment-terminal-banner">
        <div className="ld-payment-status-badge ld-badge-expired">
          <span>Order {orderLifecycleStatus === 'expired' ? 'Expired' : 'Cancelled'}</span>
        </div>
        <p className="ld-payment-subtext">
          This order is in terminal state ({orderLifecycleStatus}) and cannot accept new payments or claims.
        </p>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // RENDER: Advance paid state (Prompting balance payment)
  // ---------------------------------------------------------------------------
  const isClaimUnderReview =
    activeAttempt?.status === 'awaiting_seller_verification' ||
    activeAttempt?.status === 'buyer_claimed';

  return (
    <div className="ld-direct-upi-container" data-testid="direct-upi-payment-section">
      {/* Advance Confirmed Alert if applicable */}
      {isAdvancePaid && (
        <div className="ld-advance-confirmed-banner" data-testid="advance-verified-banner">
          <div className="ld-banner-header">
            <span className="ld-badge-confirmed">✓ Advance Payment Verified</span>
            <span className="ld-banner-amount">{formatPaisaToINR(order.advance_paid_paisa)} Paid</span>
          </div>
          <p className="ld-banner-subtext">
            Your reservation hold is confirmed! Remaining balance due is{' '}
            <strong>{formatPaisaToINR(order.balance_due_paisa)}</strong>. Complete payment before dispatch.
          </p>
        </div>
      )}

      {/* Main Payment Card */}
      <div className="ld-upi-card">
        <div className="ld-upi-header">
          <h3 className="ld-upi-title">
            {paymentType === 'advance'
              ? `Pay ${formatPaisaToINR(order.advance_required_paisa)} Advance`
              : paymentType === 'balance'
              ? `Pay Remaining Balance (${formatPaisaToINR(order.balance_due_paisa)})`
              : `Pay in Full (${formatPaisaToINR(order.total_paisa)})`}
          </h3>
          <p className="ld-upi-desc">
            Pay directly to the boutique using Google Pay, PhonePe, Paytm, BHIM, or any UPI app.
          </p>
        </div>

        {/* Payment Type Switcher (only if advance confirmation is supported on order and unpaid) */}
        {order.confirmation_mode === 'advance' && order.payment_status === 'unpaid' && (
          <div className="ld-payment-mode-tabs" role="tablist" aria-label="Payment Mode Options">
            <button
              type="button"
              role="tab"
              aria-selected={paymentType === 'advance'}
              className={`ld-tab-btn ${paymentType === 'advance' ? 'ld-tab-active' : ''}`}
              onClick={() => {
                setPaymentType('advance');
                void ensurePaymentAttempt('advance');
              }}
              data-testid="tab-pay-advance"
            >
              Option 1: Pay {formatPaisaToINR(order.advance_required_paisa)} Advance
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={paymentType === 'full'}
              className={`ld-tab-btn ${paymentType === 'full' ? 'ld-tab-active' : ''}`}
              onClick={() => {
                setPaymentType('full');
                void ensurePaymentAttempt('full');
              }}
              data-testid="tab-pay-full"
            >
              Option 2: Pay in Full ({formatPaisaToINR(order.total_paisa)})
            </button>
          </div>
        )}

        {/* Error Banner */}
        {errorMessage && (
          <div className="ld-payment-error" role="alert" data-testid="payment-error-banner">
            <span>{errorMessage}</span>
          </div>
        )}

        {/* Active Attempt Display */}
        {isInitiating ? (
          <div className="ld-upi-loading" data-testid="upi-loading-indicator">
            <div className="ld-spinner" />
            <span>Generating order-specific UPI payment request...</span>
          </div>
        ) : activeAttempt ? (
          <div className="ld-upi-body">
            {/* QR Code Section */}
            <div className="ld-qr-block">
              {qrDataUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={qrDataUrl}
                  alt={`UPI Payment QR Code for ${activeAttempt.payee_display_name_snapshot || 'Boutique'}`}
                  className="ld-qr-image"
                  data-testid="upi-qr-image"
                />
              ) : (
                <div className="ld-qr-placeholder" aria-hidden="true">
                  <span>QR Code Loading...</span>
                </div>
              )}
              <span className="ld-qr-caption">Scan with any UPI app to pay exact amount</span>
            </div>

            {/* Payee Details List */}
            <div className="ld-upi-details-list">
              <div className="ld-detail-row">
                <span className="ld-detail-label">Payee Name</span>
                <span className="ld-detail-val" data-testid="payee-name">
                  {activeAttempt.payee_display_name_snapshot || 'Boutique'}
                </span>
              </div>

              <div className="ld-detail-row">
                <span className="ld-detail-label">UPI ID</span>
                <div className="ld-copyable-box">
                  <code className="ld-vpa-code" data-testid="payee-vpa">
                    {activeAttempt.payee_vpa_snapshot}
                  </code>
                  <button
                    type="button"
                    className="ld-copy-btn"
                    onClick={() => handleCopy(activeAttempt.payee_vpa_snapshot, 'vpa')}
                    aria-label="Copy UPI ID"
                    data-testid="copy-vpa-btn"
                  >
                    {copiedField === 'vpa' ? 'Copied!' : 'Copy'}
                  </button>
                </div>
              </div>

              <div className="ld-detail-row">
                <span className="ld-detail-label">Exact Amount</span>
                <span className="ld-detail-val ld-detail-amount" data-testid="payment-expected-amount">
                  {formatPaisaToINR(activeAttempt.expected_amount_paisa)}
                </span>
              </div>

              <div className="ld-detail-row">
                <span className="ld-detail-label">Order Reference</span>
                <div className="ld-copyable-box">
                  <code className="ld-ref-code" data-testid="payment-reference">
                    {activeAttempt.transaction_reference}
                  </code>
                  <button
                    type="button"
                    className="ld-copy-btn"
                    onClick={() => handleCopy(activeAttempt.transaction_reference, 'ref')}
                    aria-label="Copy Reference"
                    data-testid="copy-ref-btn"
                  >
                    {copiedField === 'ref' ? 'Copied!' : 'Copy'}
                  </button>
                </div>
              </div>
            </div>

            {/* UPI App Launch Intent Button */}
            {upiUri && (
              <div className="ld-intent-cta-wrap">
                <a
                  href={upiUri}
                  className="ld-btn-upi-intent"
                  data-testid="pay-with-upi-intent-btn"
                  target="_self"
                  rel="noopener noreferrer"
                >
                  Pay {formatPaisaToINR(activeAttempt.expected_amount_paisa)} with UPI App
                </a>
                <span className="ld-intent-note">
                  Opens Google Pay, PhonePe, Paytm, or BHIM directly on mobile.
                </span>
              </div>
            )}

            {/* Claim / UTR Submission Workflow */}
            <div className="ld-claim-section" data-testid="payment-claim-section">
              <div className="ld-claim-header">
                <h4 className="ld-claim-title">Step 2: Submit Payment Confirmation</h4>
              </div>

              {isClaimUnderReview ? (
                /* State: Buyer Claimed & Awaiting Seller Manual Verification */
                <div className="ld-claim-submitted-box" data-testid="payment-claimed-card">
                  <div className="ld-claim-badge">
                    <span className="ld-pulse-dot" />
                    <span>Payment Submitted</span>
                  </div>
                  <h5 className="ld-claim-headline">Waiting for Boutique Verification</h5>
                  <p className="ld-claim-text">
                    We received your transaction reference. The boutique will check their bank account and manually verify the payment.
                  </p>
                  <div className="ld-submitted-meta">
                    <div className="ld-sub-row">
                      <span>Submitted UTR:</span>
                      <strong data-testid="submitted-utr-val">{activeAttempt.buyer_submitted_utr}</strong>
                    </div>
                    <div className="ld-sub-row">
                      <span>Amount:</span>
                      <strong>{formatPaisaToINR(activeAttempt.expected_amount_paisa)}</strong>
                    </div>
                    <div className="ld-sub-row">
                      <span>Status:</span>
                      <span className="ld-badge-waiting">Awaiting Seller Verification</span>
                    </div>
                  </div>
                </div>
              ) : activeAttempt.status === 'rejected' ? (
                /* State: Seller Rejected Claim */
                <div className="ld-claim-rejected-box" data-testid="payment-rejected-card">
                  <div className="ld-claim-badge ld-badge-error">
                    <span>Payment Verification Unsuccessful</span>
                  </div>
                  <p className="ld-reject-desc">
                    The boutique could not verify this transaction:{' '}
                    <strong>{activeAttempt.rejection_reason || 'Payment not found in bank statement.'}</strong>
                  </p>
                  <p className="ld-reject-action">
                    Please verify your transaction in your UPI app and re-submit the correct 12-digit UTR below.
                  </p>

                  <form onSubmit={handleSubmitClaim} className="ld-utr-form">
                    <label htmlFor="utr-retry-input" className="ld-utr-label">
                      UPI Transaction ID / 12-Digit UTR
                    </label>
                    <div className="ld-utr-input-wrap">
                      <input
                        id="utr-retry-input"
                        type="text"
                        className="ld-utr-input"
                        placeholder="e.g. 428739182734"
                        value={utrInput}
                        onChange={(e) => setUtrInput(e.target.value.toUpperCase())}
                        maxLength={30}
                        autoComplete="off"
                        data-testid="utr-retry-input"
                      />
                      <button
                        type="submit"
                        className="ld-btn-claim"
                        disabled={isSubmitting}
                        data-testid="retry-claim-btn"
                      >
                        {isSubmitting ? 'Submitting...' : 'Re-Submit Payment Claim'}
                      </button>
                    </div>
                    {utrError && <p className="ld-field-error">{utrError}</p>}
                  </form>
                </div>
              ) : (
                /* State: Awaiting Payment Claim */
                <form onSubmit={handleSubmitClaim} className="ld-utr-form" data-testid="utr-submission-form">
                  <p className="ld-form-instruction">
                    After completing the payment in your UPI app, enter the 12-digit UPI Transaction ID (UTR) from your bank receipt:
                  </p>
                  <div className="ld-form-group">
                    <label htmlFor="utr-input" className="ld-utr-label">
                      UPI Reference / UTR Number
                    </label>
                    <input
                      id="utr-input"
                      type="text"
                      className={`ld-utr-input ${utrError ? 'ld-input-error' : ''}`}
                      placeholder="e.g. 428739182734"
                      value={utrInput}
                      onChange={(e) => {
                        setUtrInput(e.target.value.trim());
                        if (utrError) setUtrError(null);
                      }}
                      maxLength={30}
                      autoComplete="off"
                      aria-required="true"
                      data-testid="utr-input-field"
                    />
                    {utrError && (
                      <span className="ld-field-error" role="alert" data-testid="utr-field-error">
                        {utrError}
                      </span>
                    )}
                  </div>

                  <button
                    type="submit"
                    className="ld-btn-claim"
                    disabled={isSubmitting}
                    data-testid="submit-payment-claim-btn"
                  >
                    {isSubmitting ? 'Submitting Claim...' : "I've Completed Payment"}
                  </button>

                  <p className="ld-claim-disclaimer">
                    Important: Submitting a UTR registers your payment claim for the boutique to manually verify. It does not immediately finalize payment.
                  </p>
                </form>
              )}
            </div>
          </div>
        ) : null}
      </div>
    </div>
  );
}
