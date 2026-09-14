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

function maskUtr(utr: string | null | undefined): string {
  if (!utr) return '';
  if (utr.length <= 4) return utr;
  return '•'.repeat(Math.max(0, utr.length - 4)) + utr.slice(-4);
}

function formatDeadline(isoString: string | null | undefined): string {
  if (!isoString) return '24 hours from submission';
  try {
    const d = new Date(isoString);
    if (isNaN(d.getTime())) return isoString;
    return d.toLocaleString('en-IN', {
      dateStyle: 'medium',
      timeStyle: 'short',
    });
  } catch {
    return isoString;
  }
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

  const resolveAttempt = (src: CreateOrderSuccessResponse | OrderReceipt): PaymentAttempt | null => {
    if ('active_payment_attempt' in src && src.active_payment_attempt) {
      return src.active_payment_attempt;
    }
    if ('payment_attempt' in src && (src as { payment_attempt?: PaymentAttempt | null }).payment_attempt) {
      return (src as { payment_attempt?: PaymentAttempt | null }).payment_attempt || null;
    }
    return null;
  };

  const initialAttempt = resolveAttempt(order);

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
  const [refreshError, setRefreshError] = useState<string | null>(null);
  const [isRefreshing, setIsRefreshing] = useState<boolean>(false);

  // Synchronize internal state if order prop changes from parent
  const [prevOrder, setPrevOrder] = useState(order);
  if (order !== prevOrder) {
    setPrevOrder(order);
    const freshAttempt = resolveAttempt(order);
    if (freshAttempt) {
      setActiveAttempt(freshAttempt);
      if (freshAttempt.upi_uri) setUpiUri(freshAttempt.upi_uri);
      if (freshAttempt.buyer_submitted_utr) setUtrInput(freshAttempt.buyer_submitted_utr);
    }
  }

  // Derive active payment status and lifecycle
  const paymentStatus = order.payment_status;
  const isPaidInFull = paymentStatus === 'paid';
  const isAdvancePaid = paymentStatus === 'advance_paid';
  const orderLifecycleStatus = 'status' in order ? order.status : 'pending';
  const isExpiredClaim =
    activeAttempt?.status === 'expired' || orderLifecycleStatus === 'expired';
  const isTerminal = orderLifecycleStatus === 'cancelled' || orderLifecycleStatus === 'expired';

  // 1. Authoritative Refresh Handler
  const refreshOrderState = useCallback(async () => {
    if (!orderId || !token) return;
    setIsRefreshing(true);
    setRefreshError(null);

    try {
      const client = getBuyerClient();
      const updated = await getOrderByToken(client, orderId, token);
      if (onOrderRefresh) {
        onOrderRefresh(updated);
      }
      const newAttempt = resolveAttempt(updated);
      if (newAttempt) {
        setActiveAttempt(newAttempt);
        if (newAttempt.upi_uri) setUpiUri(newAttempt.upi_uri);
        if (newAttempt.buyer_submitted_utr) setUtrInput(newAttempt.buyer_submitted_utr);
      }
    } catch {
      setRefreshError('Unable to refresh order status. Please try again.');
    } finally {
      setIsRefreshing(false);
    }
  }, [orderId, token, onOrderRefresh]);

  // 2. Tab Resume / Visibility Handlers (Re-fetch fresh server state on return)
  useEffect(() => {
    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        void refreshOrderState();
      }
    };
    const handleFocus = () => {
      void refreshOrderState();
    };

    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('focus', handleFocus);

    return () => {
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('focus', handleFocus);
    };
  }, [refreshOrderState]);

  // 3. Scoped Realtime Invalidation Listener
  useEffect(() => {
    if (!orderId) return;

    const client = getBuyerClient();
    const channel = client
      .channel(`buyer-order-${orderId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'orders',
          filter: `id=eq.${orderId}`,
        },
        () => {
          void refreshOrderState();
        }
      )
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'payment_attempts',
          filter: `order_id=eq.${orderId}`,
        },
        () => {
          void refreshOrderState();
        }
      )
      .subscribe();

    return () => {
      void client.removeChannel(channel);
    };
  }, [orderId, refreshOrderState]);

  // 4. Generate QR Code when UPI URI changes
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

  // 5. Fetch or initiate a payment attempt when needed
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
            verification_expires_at: res.verification_expires_at || null,
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

  // 6. Handle copy to clipboard
  const handleCopy = (text: string, field: 'vpa' | 'ref' | 'amount') => {
    if (navigator.clipboard) {
      navigator.clipboard.writeText(text);
      setCopiedField(field);
      setTimeout(() => setCopiedField(null), 2000);
    }
  };

  // 7. Handle UTR claim submission
  const handleSubmitClaim = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!activeAttempt) return;

    const cleanUtr = utrInput.trim();
    if (!cleanUtr) {
      setUtrError('Please enter your 12-digit UPI reference (UTR).');
      return;
    }

    if (cleanUtr.length < 6 || cleanUtr.length > 35 || !/^[a-zA-Z0-9_\-]+$/.test(cleanUtr)) {
      setUtrError('UTR must be 6–35 alphanumeric characters without special symbols.');
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
                verification_expires_at: res.verification_expires_at || prev.verification_expires_at,
                expires_at: res.expires_at || prev.expires_at,
              }
            : null
        );

        // Authoritatively refresh parent order state
        await refreshOrderState();
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
  // RENDER: Expired state
  // ---------------------------------------------------------------------------
  if (isExpiredClaim) {
    return (
      <div className="ld-payment-box ld-payment-box-terminal" data-testid="verification-expired-banner">
        <div className="ld-payment-status-badge ld-badge-expired">
          <span>Payment Verification Expired</span>
        </div>
        <h3 className="ld-payment-headline">Verification Window Elapsed</h3>
        <p className="ld-payment-subtext">
          This order could not be confirmed because the payment was not verified within the 24-hour verification window. The product reservation has been released.
        </p>
        <p className="ld-payment-subtext" style={{ marginTop: '8px', fontSize: '13px', color: '#64748B' }}>
          If money was debited from your bank account, please contact the boutique directly with your UPI UTR reference for out-of-band resolution.
        </p>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // RENDER: Terminal states (Cancelled)
  // ---------------------------------------------------------------------------
  if (isTerminal) {
    return (
      <div className="ld-payment-box ld-payment-box-terminal" data-testid="payment-terminal-banner">
        <div className="ld-payment-status-badge ld-badge-expired">
          <span>Order Cancelled</span>
        </div>
        <p className="ld-payment-subtext">
          This order is cancelled and cannot accept new payments or claims.
        </p>
      </div>
    );
  }

  // ---------------------------------------------------------------------------
  // RENDER: Active Payment or Verification Queue
  // ---------------------------------------------------------------------------
  const isClaimUnderReview =
    activeAttempt?.status === 'awaiting_seller_verification' ||
    activeAttempt?.status === 'buyer_claimed';

  const verificationDeadline =
    activeAttempt?.verification_expires_at || activeAttempt?.expires_at;

  const balanceAfterVerification =
    order.total_paisa - (order.advance_required_paisa || activeAttempt?.expected_amount_paisa || 0);

  return (
    <div className="ld-direct-upi-container" data-testid="direct-upi-payment-section">
      {/* Network Refresh Error Banner */}
      {refreshError && (
        <div className="ld-payment-error" role="alert" data-testid="network-refresh-error" style={{ marginBottom: '12px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span>{refreshError}</span>
            <button
              type="button"
              className="ld-btn-claim"
              style={{ width: 'auto', padding: '4px 12px', fontSize: '12px' }}
              onClick={() => void refreshOrderState()}
              disabled={isRefreshing}
              data-testid="retry-refresh-btn"
            >
              {isRefreshing ? 'Retrying...' : 'Retry'}
            </button>
          </div>
        </div>
      )}

      {/* Advance Confirmed Alert if applicable */}
      {isAdvancePaid && (
        <div className="ld-advance-confirmed-banner" data-testid="advance-verified-banner">
          <div className="ld-banner-header">
            <span className="ld-badge-confirmed">✓ Advance Payment Verified</span>
            <span className="ld-banner-amount">{formatPaisaToINR(order.advance_paid_paisa)} Paid</span>
          </div>
          <p className="ld-banner-subtext">
            Your order is confirmed! The {formatPaisaToINR(order.advance_paid_paisa)} advance is part of your purchase price and has been deducted from your remaining balance.
          </p>
          <div className="ld-submitted-meta" style={{ marginTop: '8px' }}>
            <div className="ld-sub-row">
              <span>Remaining Balance:</span>
              <strong>{formatPaisaToINR(order.balance_due_paisa)}</strong>
            </div>
            {order.hold_expires_at && (
              <div className="ld-sub-row">
                <span>Reserved Until:</span>
                <strong>{formatDeadline(order.hold_expires_at)}</strong>
              </div>
            )}
          </div>
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
        {order.confirmation_mode === 'advance' && order.payment_status === 'unpaid' && !isClaimUnderReview && (
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
            {/* If claim is NOT submitted yet, show QR & UPI details */}
            {!isClaimUnderReview && (
              <>
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
              </>
            )}

            {/* Claim / UTR Submission Workflow */}
            <div className="ld-claim-section" data-testid="payment-claim-section">
              {!isClaimUnderReview && (
                <div className="ld-claim-header">
                  <h4 className="ld-claim-title">Step 2: Submit Payment Confirmation</h4>
                </div>
              )}

              {isClaimUnderReview ? (
                /* State: Buyer Claimed & Awaiting Seller Manual Verification (TASK-2.4C Resume-Safe UX) */
                <div className="ld-claim-submitted-box" data-testid="payment-claimed-card">
                  <div className="ld-claim-badge">
                    <span className="ld-pulse-dot" />
                    <span>Payment Submitted</span>
                  </div>
                  <h5 className="ld-claim-headline">Payment Verification Pending</h5>
                  <p className="ld-claim-text">
                    Your {formatPaisaToINR(activeAttempt.expected_amount_paisa)} payment claim has been saved.
                    The boutique needs to verify the payment from their UPI/bank transaction history.
                  </p>

                  <div
                    style={{
                      backgroundColor: '#ECFDF5',
                      border: '1px solid #A7F3D0',
                      borderRadius: '8px',
                      padding: '12px',
                      margin: '12px 0',
                    }}
                    data-testid="safe-to-close-notice"
                  >
                    <strong style={{ color: '#065F46', display: 'block', marginBottom: '4px' }}>
                      You can safely close this page.
                    </strong>
                    <span style={{ color: '#047857', fontSize: '13px' }}>
                      Save this order link to check your payment and order status later. When the boutique verifies your payment, this page will reflect the updated status immediately.
                    </span>
                  </div>

                  <div className="ld-submitted-meta">
                    <div className="ld-sub-row">
                      <span>Order:</span>
                      <strong>{order.order_code}</strong>
                    </div>
                    <div className="ld-sub-row">
                      <span>Payment:</span>
                      <strong>
                        {formatPaisaToINR(activeAttempt.expected_amount_paisa)}{' '}
                        {activeAttempt.payment_type === 'advance' ? 'Advance' : 'Payment'}
                      </strong>
                    </div>
                    <div className="ld-sub-row">
                      <span>Status:</span>
                      <span className="ld-badge-waiting">Verification Pending</span>
                    </div>
                    <div className="ld-sub-row">
                      <span>Submitted UTR:</span>
                      <strong data-testid="submitted-utr-val">
                        {maskUtr(activeAttempt.buyer_submitted_utr)}
                      </strong>
                    </div>
                    <div className="ld-sub-row">
                      <span>Verification Deadline:</span>
                      <strong data-testid="verification-deadline">
                        {formatDeadline(verificationDeadline)}
                      </strong>
                    </div>
                    {activeAttempt.payment_type === 'advance' && (
                      <div className="ld-sub-row">
                        <span>Balance after verification:</span>
                        <strong>{formatPaisaToINR(balanceAfterVerification)}</strong>
                      </div>
                    )}
                  </div>

                  <div
                    style={{
                      backgroundColor: '#FFFBEB',
                      border: '1px solid #FDE68A',
                      borderRadius: '8px',
                      padding: '10px 12px',
                      marginTop: '12px',
                    }}
                    data-testid="do-not-pay-again-warning"
                  >
                    <span style={{ color: '#92400E', fontSize: '13px', fontWeight: 600 }}>
                      ⚠️ Do not pay again unless the boutique asks you to.
                    </span>
                  </div>
                </div>
              ) : activeAttempt.status === 'rejected' ? (
                /* State: Seller Rejected Claim (Non-accusatory message) */
                <div className="ld-claim-rejected-box" data-testid="payment-rejected-card">
                  <div className="ld-claim-badge ld-badge-error">
                    <span>Payment Could Not Be Verified</span>
                  </div>
                  <p className="ld-reject-desc">
                    The boutique was unable to verify this payment claim (
                    {activeAttempt.rejection_reason || 'Payment not found in bank statement'}).
                  </p>
                  <p className="ld-reject-action">
                    Please verify your transaction in your UPI app and re-submit the correct 12-digit UTR below. If needed, contact the boutique directly.
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
                        maxLength={35}
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
                      maxLength={35}
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
