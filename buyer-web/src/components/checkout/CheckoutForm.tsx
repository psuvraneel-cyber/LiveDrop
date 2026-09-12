'use client';

import React from 'react';
import { CheckoutFormErrors, CheckoutFormState } from '../../types/domain';

export interface CheckoutFormProps {
  form: CheckoutFormState;
  errors: CheckoutFormErrors;
  touched: Record<keyof CheckoutFormState, boolean>;
  isSubmitting: boolean;
  onChange: (field: keyof CheckoutFormState, value: string) => void;
  onBlur: (field: keyof CheckoutFormState) => void;
}

export function CheckoutForm({
  form,
  errors,
  touched,
  isSubmitting,
  onChange,
  onBlur,
}: CheckoutFormProps) {
  return (
    <section className="ld-checkout-section" aria-labelledby="delivery-info-title">
      <h2 id="delivery-info-title" className="ld-checkout-card-title">
        Delivery Information
      </h2>
      <p className="ld-checkout-card-subtitle">
        Enter the delivery details for your order. Only required fulfillment details are collected.
      </p>

      <div className="ld-checkout-form-fields">
        {/* Full Name */}
        <div className="ld-form-group">
          <label htmlFor="buyer_name" className="ld-form-label">
            Full Name <span className="ld-required-star" aria-hidden="true">*</span>
          </label>
          <input
            id="buyer_name"
            name="buyer_name"
            type="text"
            className={`ld-form-input ${touched.buyer_name && errors.buyer_name ? 'invalid' : ''}`}
            placeholder="e.g. Sangeeta Mukherjee"
            value={form.buyer_name}
            disabled={isSubmitting}
            autoComplete="name"
            aria-required="true"
            aria-invalid={Boolean(touched.buyer_name && errors.buyer_name)}
            aria-describedby={touched.buyer_name && errors.buyer_name ? 'error-buyer_name' : undefined}
            onChange={(e) => onChange('buyer_name', e.target.value)}
            onBlur={() => onBlur('buyer_name')}
            data-testid="input-buyer-name"
          />
          {touched.buyer_name && errors.buyer_name && (
            <p id="error-buyer_name" className="ld-field-error" role="alert" data-testid="error-buyer-name">
              {errors.buyer_name}
            </p>
          )}
        </div>

        {/* Mobile Number */}
        <div className="ld-form-group">
          <label htmlFor="buyer_phone" className="ld-form-label">
            Mobile Number (WhatsApp) <span className="ld-required-star" aria-hidden="true">*</span>
          </label>
          <input
            id="buyer_phone"
            name="buyer_phone"
            type="tel"
            className={`ld-form-input ${touched.buyer_phone && errors.buyer_phone ? 'invalid' : ''}`}
            placeholder="10-digit Indian mobile number"
            value={form.buyer_phone}
            disabled={isSubmitting}
            autoComplete="tel"
            inputMode="numeric"
            aria-required="true"
            aria-invalid={Boolean(touched.buyer_phone && errors.buyer_phone)}
            aria-describedby={touched.buyer_phone && errors.buyer_phone ? 'error-buyer_phone' : 'hint-buyer_phone'}
            onChange={(e) => onChange('buyer_phone', e.target.value)}
            onBlur={() => onBlur('buyer_phone')}
            data-testid="input-buyer-phone"
          />
          {touched.buyer_phone && errors.buyer_phone ? (
            <p id="error-buyer_phone" className="ld-field-error" role="alert" data-testid="error-buyer-phone">
              {errors.buyer_phone}
            </p>
          ) : (
            <span id="hint-buyer_phone" className="ld-form-hint">
              Used for delivery coordination and payment verification in the next step.
            </span>
          )}
        </div>

        {/* Pincode */}
        <div className="ld-form-group">
          <label htmlFor="pincode" className="ld-form-label">
            Delivery Pincode <span className="ld-required-star" aria-hidden="true">*</span>
          </label>
          <input
            id="pincode"
            name="pincode"
            type="text"
            inputMode="numeric"
            maxLength={6}
            className={`ld-form-input ${touched.pincode && errors.pincode ? 'invalid' : ''}`}
            placeholder="6-digit pincode (e.g. 700019)"
            value={form.pincode}
            disabled={isSubmitting}
            autoComplete="postal-code"
            aria-required="true"
            aria-invalid={Boolean(touched.pincode && errors.pincode)}
            aria-describedby={touched.pincode && errors.pincode ? 'error-pincode' : undefined}
            onChange={(e) => onChange('pincode', e.target.value)}
            onBlur={() => onBlur('pincode')}
            data-testid="input-pincode"
          />
          {touched.pincode && errors.pincode && (
            <p id="error-pincode" className="ld-field-error" role="alert" data-testid="error-pincode">
              {errors.pincode}
            </p>
          )}
        </div>

        {/* Shipping Address */}
        <div className="ld-form-group">
          <label htmlFor="shipping_address" className="ld-form-label">
            Full Street Address <span className="ld-required-star" aria-hidden="true">*</span>
          </label>
          <textarea
            id="shipping_address"
            name="shipping_address"
            rows={3}
            className={`ld-form-textarea ${touched.shipping_address && errors.shipping_address ? 'invalid' : ''}`}
            placeholder="Flat/House no., building, street name, landmark"
            value={form.shipping_address}
            disabled={isSubmitting}
            autoComplete="street-address"
            aria-required="true"
            aria-invalid={Boolean(touched.shipping_address && errors.shipping_address)}
            aria-describedby={touched.shipping_address && errors.shipping_address ? 'error-shipping_address' : undefined}
            onChange={(e) => onChange('shipping_address', e.target.value)}
            onBlur={() => onBlur('shipping_address')}
            data-testid="input-shipping-address"
          />
          {touched.shipping_address && errors.shipping_address && (
            <p id="error-shipping_address" className="ld-field-error" role="alert" data-testid="error-shipping-address">
              {errors.shipping_address}
            </p>
          )}
        </div>
      </div>
    </section>
  );
}
