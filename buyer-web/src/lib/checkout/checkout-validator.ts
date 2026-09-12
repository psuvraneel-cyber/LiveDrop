/**
 * LiveDrop — Client-Side Checkout Input Validator (TASK-2.3)
 *
 * Implements Tier-1 form validation matching the PostgreSQL constraints defined in
 * migration 004_create_orders.sql and RPC create_order_with_reservation.
 *
 * CRITICAL RULE: Client-side validation is UX feedback only.
 * The database remains the authoritative validator.
 */

import { CheckoutFormErrors, CheckoutFormState } from '../../types/domain';

export const INDIAN_PHONE_REGEX = /^(?:91)?[6-9]\d{9}$/;
export const INDIAN_PINCODE_REGEX = /^\d{6}$/;

export interface ValidationResult {
  isValid: boolean;
  errors: CheckoutFormErrors;
  sanitized: CheckoutFormState;
}

/**
 * Normalizes phone input by stripping whitespace, hyphens, and leading '+'.
 */
export function normalizePhone(rawPhone: string): string {
  let cleaned = rawPhone.trim().replace(/[\s\-()+]/g, '');
  // If user entered +91 or 091, strip the leading 0 if present (e.g. 09830123456 -> 9830123456)
  if (cleaned.startsWith('0') && cleaned.length === 11 && /^[6-9]/.test(cleaned.slice(1))) {
    cleaned = cleaned.slice(1);
  }
  return cleaned;
}

/**
 * Validates buyer name field.
 */
export function validateBuyerName(name: string): string | undefined {
  const trimmed = name.trim();
  if (!trimmed) {
    return 'Full name is required.';
  }
  if (trimmed.length < 3) {
    return 'Name must be at least 3 characters.';
  }
  if (trimmed.length > 100) {
    return 'Name cannot exceed 100 characters.';
  }
  return undefined;
}

/**
 * Validates 10-digit Indian phone number.
 */
export function validateBuyerPhone(phone: string): string | undefined {
  const normalized = normalizePhone(phone);
  if (!normalized) {
    return 'Mobile number is required.';
  }
  if (!INDIAN_PHONE_REGEX.test(normalized)) {
    return 'Valid 10-digit Indian mobile number required (e.g., 9830012345).';
  }
  return undefined;
}

/**
 * Validates 6-digit Indian delivery pincode.
 */
export function validatePincode(pincode: string): string | undefined {
  const trimmed = pincode.trim();
  if (!trimmed) {
    return 'Delivery pincode is required.';
  }
  if (!INDIAN_PINCODE_REGEX.test(trimmed)) {
    return 'Valid 6-digit pincode required (e.g., 700001).';
  }
  return undefined;
}

/**
 * Validates shipping address.
 */
export function validateShippingAddress(address: string): string | undefined {
  const trimmed = address.trim();
  if (!trimmed) {
    return 'Delivery address is required.';
  }
  if (trimmed.length < 10) {
    return 'Address must be at least 10 characters (include street/flat).';
  }
  if (trimmed.length > 500) {
    return 'Address cannot exceed 500 characters.';
  }
  return undefined;
}

/**
 * Validates the full checkout form and returns sanitized data.
 */
export function validateCheckoutForm(form: CheckoutFormState): ValidationResult {
  const sanitized: CheckoutFormState = {
    buyer_name: form.buyer_name.trim(),
    buyer_phone: normalizePhone(form.buyer_phone),
    shipping_address: form.shipping_address.trim(),
    pincode: form.pincode.trim(),
  };

  const errors: CheckoutFormErrors = {};

  const nameError = validateBuyerName(sanitized.buyer_name);
  if (nameError) errors.buyer_name = nameError;

  const phoneError = validateBuyerPhone(sanitized.buyer_phone);
  if (phoneError) errors.buyer_phone = phoneError;

  const addressError = validateShippingAddress(sanitized.shipping_address);
  if (addressError) errors.shipping_address = addressError;

  const pincodeError = validatePincode(sanitized.pincode);
  if (pincodeError) errors.pincode = pincodeError;

  const isValid = Object.keys(errors).length === 0;

  return {
    isValid,
    errors,
    sanitized,
  };
}
