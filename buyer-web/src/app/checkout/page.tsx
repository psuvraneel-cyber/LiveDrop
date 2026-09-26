'use client';

/**
 * LiveDrop — Buyer Checkout & Atomic Reservation Route (/checkout) (TASK-2.3)
 *
 * Enforces transactional boundaries:
 * 1. The client cart is purely untrusted intent.
 * 2. Authoritative reservation occurs ONLY via create_order_with_reservation().
 * 3. All monetary totals are computed by the database engine in integer Paisa.
 * 4. PII is strictly minimized (Name, Phone, Address, Pincode).
 * 5. Safe retry semantics & single-flight submission protection.
 */

import React, { Suspense, useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { useCart, CartProvider, useOptionalCart } from '../../lib/cart/cart-context';
import { getBuyerClient } from '../../lib/supabase/client';
import {
  getPublicProductsForDrop,
  createOrderWithReservation,
  getOrderByToken,
} from '../../lib/data/buyer-catalog';
import { GlobalBuyerHeader } from '../../components/navigation/GlobalBuyerHeader';
import {
  getOrCreateCheckoutIdempotencyKey,
  clearCheckoutIdempotencyKey,
} from '../../lib/checkout/idempotency';
import { cacheOrderToken, saveRecentOrderSummary } from '../../lib/cart/cart-storage';
import {
  CheckoutFormErrors,
  CheckoutFormState,
  CheckoutSubmissionStatus,
  CreateOrderRequest,
  CreateOrderSuccessResponse,
  OrderReceipt,
  PublicProductView,
} from '../../types/domain';
import { validateCheckoutForm, validateBuyerName, validateBuyerPhone, validatePincode, validateShippingAddress } from '../../lib/checkout/checkout-validator';
import {
  StockUnavailableError,
  CheckoutIdempotencyConflictError,
  NetworkError,
  LiveDropError,
} from '../../lib/errors';
import { EmptyCheckoutState } from '../../components/checkout/EmptyCheckoutState';
import { CheckoutForm } from '../../components/checkout/CheckoutForm';
import { CheckoutReview } from '../../components/checkout/CheckoutReview';
import { CheckoutSuccessView } from '../../components/checkout/CheckoutSuccessView';
import { CartItem } from '../../types/cart';

function CheckoutPageContent() {
  const searchParams = useSearchParams();
  const urlOrderId = searchParams.get('order_id');
  const urlToken = searchParams.get('token') || searchParams.get('order_token');

  const { items, subtotalPaisa, dropId, isHydrated, removeItem, clearCart, getReconciledItems } = useCart();

  // Existing receipt lookup state (token-gated)
  const [existingOrder, setExistingOrder] = useState<OrderReceipt | null>(null);
  const [receiptLoading, setReceiptLoading] = useState<boolean>(Boolean(urlOrderId && urlToken));
  const [receiptError, setReceiptError] = useState<string | null>(null);

  // Active checkout state
  const [catalogProducts, setCatalogProducts] = useState<PublicProductView[]>([]);
  const [reservedSnapshot, setReservedSnapshot] = useState<CartItem[]>([]);
  const [submittedOrder, setSubmittedOrder] = useState<CreateOrderSuccessResponse | null>(null);
  const [submissionStatus, setSubmissionStatus] = useState<CheckoutSubmissionStatus>('idle');
  const [generalError, setGeneralError] = useState<string | null>(null);
  const [collisionError, setCollisionError] = useState<{ message: string; unavailableIds: string[] } | null>(null);

  // Form State
  const [form, setForm] = useState<CheckoutFormState>({
    buyer_name: '',
    buyer_phone: '',
    shipping_address: '',
    pincode: '',
  });
  const [errors, setErrors] = useState<CheckoutFormErrors>({});
  const [touched, setTouched] = useState<Record<keyof CheckoutFormState, boolean>>({
    buyer_name: false,
    buyer_phone: false,
    shipping_address: false,
    pincode: false,
  });

  // 1. If order_id and token exist in URL, fetch authoritative receipt
  useEffect(() => {
    let active = true;

    if (urlOrderId && urlToken) {
      const fetchReceipt = async () => {
        try {
          const client = getBuyerClient();
          const receipt = await getOrderByToken(client, urlOrderId, urlToken);
          if (active) {
            setExistingOrder(receipt);
            setReceiptLoading(false);
          }
        } catch (err) {
          if (active) {
            setReceiptError(err instanceof Error ? err.message : 'Failed to retrieve order receipt.');
            setReceiptLoading(false);
          }
        }
      };
      void fetchReceipt();
    }

    return () => {
      active = false;
    };
  }, [urlOrderId, urlToken]);

  // 2. Fetch drop & catalog products for availability reconciliation
  const fetchCatalogData = useCallback(async () => {
    if (!dropId) return;

    try {
      const client = getBuyerClient();
      const products = await getPublicProductsForDrop(client, dropId);
      setCatalogProducts(products);
    } catch {
      // Retain existing view if background refresh fails
    }
  }, [dropId]);

  useEffect(() => {
    let active = true;
    if (dropId && !urlOrderId) {
      const load = async () => {
        try {
          const client = getBuyerClient();
          const products = await getPublicProductsForDrop(client, dropId);
          if (active) {
            setCatalogProducts(products);
          }
        } catch {
          // Keep current view
        }
      };
      void load();
    }
    return () => {
      active = false;
    };
  }, [dropId, urlOrderId]);


  // Form Field Change Handler
  const handleFieldChange = (field: keyof CheckoutFormState, value: string) => {
    setForm((prev) => ({ ...prev, [field]: value }));

    // Real-time revalidation if field was already marked invalid
    if (errors[field]) {
      setErrors((prev) => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    }
  };

  // Form Field Blur Handler
  const handleFieldBlur = (field: keyof CheckoutFormState) => {
    setTouched((prev) => ({ ...prev, [field]: true }));

    let fieldError: string | undefined;
    if (field === 'buyer_name') fieldError = validateBuyerName(form.buyer_name);
    else if (field === 'buyer_phone') fieldError = validateBuyerPhone(form.buyer_phone);
    else if (field === 'shipping_address') fieldError = validateShippingAddress(form.shipping_address);
    else if (field === 'pincode') fieldError = validatePincode(form.pincode);

    if (fieldError) {
      setErrors((prev) => ({ ...prev, [field]: fieldError }));
    } else {
      setErrors((prev) => {
        const next = { ...prev };
        delete next[field];
        return next;
      });
    }
  };

  // Checkout Submission Action
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    // Prevent duplicate clicks while in-flight
    if (submissionStatus === 'submitting' || submissionStatus === 'validating') {
      return;
    }

    setGeneralError(null);
    setCollisionError(null);

    // 1. Client-side Tier 1 Validation
    const validation = validateCheckoutForm(form);
    if (!validation.isValid) {
      setTouched({
        buyer_name: true,
        buyer_phone: true,
        shipping_address: true,
        pincode: true,
      });
      setErrors(validation.errors);
      setSubmissionStatus('idle');
      return;
    }

    // 2. Pre-submission Cart Boundary Verification
    if (items.length === 0) {
      setGeneralError('Your bag is empty. Please add items before reserving.');
      return;
    }

    if (!dropId) {
      setGeneralError('Unable to identify the active drop. Please return to the drop page.');
      return;
    }

    // Guard single-drop invariant
    const hasMixedDrops = items.some((item) => item.dropId !== dropId);
    if (hasMixedDrops) {
      setGeneralError('All items in your bag must belong to the same live drop.');
      return;
    }

    // Guard availability reconciliation before submit
    const reconciledItems = getReconciledItems(catalogProducts);
    const contestedItems = reconciledItems.filter((item) => !item.isAvailable);
    if (contestedItems.length > 0) {
      setCollisionError({
        message: 'Some items in your bag have already been claimed by another buyer.',
        unavailableIds: contestedItems.map((i) => i.productId),
      });
      return;
    }

    // 3. Initiate Atomic Reservation Transaction
    setSubmissionStatus('submitting');

    const productIds = items.map((i) => i.productId);
    const idempotencyKey = getOrCreateCheckoutIdempotencyKey(dropId, productIds);

    const requestPayload: CreateOrderRequest = {
      p_drop_id: dropId,
      p_product_ids: productIds,
      p_buyer_name: validation.sanitized.buyer_name,
      p_buyer_phone: validation.sanitized.buyer_phone,
      p_shipping_address: validation.sanitized.shipping_address,
      p_pincode: validation.sanitized.pincode,
      p_idempotency_key: idempotencyKey,
    };

    try {
      const client = getBuyerClient();
      const response = await createOrderWithReservation(client, requestPayload);

      // Snapshot items before clearing cart
      setReservedSnapshot([...items]);
      clearCheckoutIdempotencyKey(dropId);
      clearCart();

      setSubmittedOrder(response);
      setSubmissionStatus('success');

      // Cache token strictly for this order ID in localStorage for resume-safe tracking
      cacheOrderToken(response.order_id, response.order_token);
      saveRecentOrderSummary({
        id: response.order_id,
        token: response.order_token,
        orderCode: response.order_code,
        totalPaisa: response.total_paisa,
        paymentStatus: response.payment_status,
        fulfilmentStatus: response.fulfilment_status,
      });

      // Update URL safely without full page reload for bookmarkability & back-button safety
      if (typeof window !== 'undefined') {
        const safeUrl = `/checkout?order_id=${encodeURIComponent(response.order_id)}&token=${encodeURIComponent(response.order_token)}`;
        window.history.replaceState(null, '', safeUrl);
      }
    } catch (err: unknown) {
      if (err instanceof StockUnavailableError) {
        setSubmissionStatus('failure');
        setCollisionError({
          message: err.message,
          unavailableIds: err.unavailableProductIds,
        });
        // Refresh catalog to update availability indicators in UI
        void fetchCatalogData();
      } else if (err instanceof CheckoutIdempotencyConflictError) {
        clearCheckoutIdempotencyKey(dropId);
        setSubmissionStatus('failure');
        setGeneralError('Your cart items have changed since a prior submission attempt. Please review and try again.');
      } else if (err instanceof NetworkError) {
        setSubmissionStatus('network_ambiguous');
        setGeneralError(
          'We were unable to confirm whether your reservation succeeded due to a network interruption. To avoid duplicate orders, please do not click submit repeatedly. Check your connection or refresh to verify.'
        );
      } else if (err instanceof LiveDropError) {
        setSubmissionStatus('failure');
        setGeneralError(err.message);
      } else {
        setSubmissionStatus('failure');
        setGeneralError('An unexpected error occurred while reserving your items. Please try again.');
      }
    }
  };

  // Loading state (Hydration or Receipt Lookup)
  if (!isHydrated || receiptLoading) {
    return (
      <div className="ld-checkout-loading" data-testid="checkout-loading">
        <div className="ld-spinner" />
      </div>
    );
  }

  // Token-gated Receipt Mode: If user opened via bookmark or direct link with order_id & token
  if (existingOrder) {
    return (
      <div className="ld-checkout-page" data-testid="checkout-page-receipt">
        <GlobalBuyerHeader
          variant="minimal"
          backHref="/"
          backLabel="Return Home"
          title="LiveDrop"
        />

        <main className="ld-container ld-checkout-main" role="main">
          <CheckoutSuccessView order={existingOrder} orderToken={urlToken || undefined} />
        </main>
      </div>
    );
  }

  // Receipt lookup error
  if (urlOrderId && receiptError) {
    return (
      <div className="ld-checkout-page" data-testid="checkout-receipt-error">
        <GlobalBuyerHeader
          variant="minimal"
          backHref="/"
          backLabel="Return Home"
          title="LiveDrop"
        />
        <main className="ld-container ld-checkout-main" role="main">
          <div className="ld-checkout-empty">
            <h2 className="ld-checkout-empty-title">Order Receipt Not Found</h2>
            <p className="ld-checkout-empty-desc">{receiptError}</p>
            <Link href="/" className="ld-btn-browse">
              Browse Live Drops
            </Link>
          </div>
        </main>
      </div>
    );
  }

  // Success Mode (just completed checkout submission)
  if (submittedOrder && submissionStatus === 'success') {
    return (
      <div className="ld-checkout-page" data-testid="checkout-page-success">
        <GlobalBuyerHeader
          variant="minimal"
          title="LiveDrop"
        />
        <main className="ld-container ld-checkout-main" role="main">
          <div className="ld-checkout-breadcrumbs" aria-label="Checkout Progress">
            <div className="ld-step-item completed">
              <span className="ld-step-dot">✓</span>
              <span className="ld-step-label">Details</span>
            </div>
            <div className="ld-step-connector" />
            <div className="ld-step-item active">
              <span className="ld-step-dot">2</span>
              <span className="ld-step-label">Payment</span>
            </div>
            <div className="ld-step-connector" />
            <div className="ld-step-item">
              <span className="ld-step-dot">3</span>
              <span className="ld-step-label">Review</span>
            </div>
          </div>
          <CheckoutSuccessView
            order={submittedOrder}
            reservedItems={reservedSnapshot}
          />
        </main>
      </div>
    );
  }

  // Empty Bag Mode
  if (items.length === 0) {
    return (
      <div className="ld-checkout-page" data-testid="checkout-page-empty">
        <GlobalBuyerHeader
          variant="minimal"
          backHref="/cart"
          backLabel="Back to Bag"
          title="LiveDrop"
        />
        <main className="ld-container ld-checkout-main" role="main">
          <EmptyCheckoutState />
        </main>
      </div>
    );
  }

  // Reconciled Items
  const reconciledItems = getReconciledItems(catalogProducts);
  const hasUnavailableItems = reconciledItems.some((item) => !item.isAvailable);

  return (
    <div className="ld-checkout-page" data-testid="checkout-page">
      <GlobalBuyerHeader
        variant="minimal"
        backHref="/cart"
        backLabel="Back to Bag"
        backTestId="checkout-back-cart-btn"
        title="LiveDrop"
      />

      <main className="ld-container ld-checkout-main" role="main">
        {/* Breadcrumb Steps matching luxury template */}
        <div className="ld-checkout-breadcrumbs" aria-label="Checkout Progress">
          <div className="ld-step-item active">
            <span className="ld-step-dot">1</span>
            <span className="ld-step-label">Details</span>
          </div>
          <div className="ld-step-connector" />
          <div className="ld-step-item">
            <span className="ld-step-dot">2</span>
            <span className="ld-step-label">Payment</span>
          </div>
          <div className="ld-step-connector" />
          <div className="ld-step-item">
            <span className="ld-step-dot">3</span>
            <span className="ld-step-label">Review</span>
          </div>
        </div>

        <div className="ld-checkout-title-row">
          <h1 className="ld-checkout-title">Checkout & Reserve</h1>
          <span className="ld-checkout-step-badge">Step 1 of 2</span>
        </div>

        {/* Ambiguous Network Failure Alert */}
        {submissionStatus === 'network_ambiguous' && generalError && (
          <div
            className="ld-checkout-error-banner ld-network-error"
            data-testid="checkout-network-error-banner"
            role="alert"
          >
            <div className="ld-error-banner-icon" aria-hidden="true">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
            </div>
            <div className="ld-error-banner-body">
              <strong>Connection Warning</strong>
              <p>{generalError}</p>
            </div>
          </div>
        )}

        {/* General Error Banner */}
        {submissionStatus === 'failure' && generalError && (
          <div
            className="ld-checkout-error-banner"
            data-testid="checkout-general-error-banner"
            role="alert"
          >
            <div className="ld-error-banner-icon" aria-hidden="true">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
            </div>
            <div className="ld-error-banner-body">
              <strong>Reservation Could Not Be Completed</strong>
              <p>{generalError}</p>
            </div>
          </div>
        )}

        {/* Stock Collision Banner */}
        {collisionError && (
          <div
            className="ld-checkout-error-banner ld-collision-error"
            data-testid="checkout-collision-error-banner"
            role="alert"
          >
            <div className="ld-error-banner-icon" aria-hidden="true">
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="10" />
                <line x1="12" y1="8" x2="12" y2="12" />
                <line x1="12" y1="16" x2="12.01" y2="16" />
              </svg>
            </div>
            <div className="ld-error-banner-body">
              <strong>Inventory Conflict Detected</strong>
              <p>{collisionError.message}</p>
              <p className="ld-collision-hint">
                Please remove the unavailable garment(s) from your order summary below to continue reserving the available pieces.
              </p>
            </div>
          </div>
        )}

        {/* Checkout Grid: Form & Review */}
        <div className="ld-checkout-grid">
          {/* Buyer Information Form */}
          <div className="ld-checkout-form-column">
            <CheckoutForm
              form={form}
              errors={errors}
              touched={touched}
              isSubmitting={submissionStatus === 'submitting'}
              onChange={handleFieldChange}
              onBlur={handleFieldBlur}
            />
          </div>

          {/* Pre-checkout Order Review */}
          <div className="ld-checkout-review-column">
            <CheckoutReview
              items={reconciledItems}
              subtotalPaisa={subtotalPaisa}
              drop={null}
              isSubmitting={submissionStatus === 'submitting'}
              hasUnavailableItems={hasUnavailableItems}
              onRemoveItem={removeItem}
              onSubmit={handleSubmit}
            />
          </div>
        </div>
      </main>
    </div>
  );
}

export default function CheckoutPage() {
  const existingCart = useOptionalCart();
  const content = (
    <Suspense
      fallback={
        <div className="ld-checkout-loading" data-testid="checkout-loading">
          <div className="ld-spinner" />
        </div>
      }
    >
      <CheckoutPageContent />
    </Suspense>
  );

  if (existingCart) {
    return content;
  }

  return <CartProvider>{content}</CartProvider>;
}
