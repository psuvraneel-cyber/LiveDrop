import { describe, it, expect } from 'vitest';
import {
  validateBuyerName,
  validateBuyerPhone,
  validatePincode,
  validateShippingAddress,
  validateCheckoutForm,
  normalizePhone,
} from '../lib/checkout/checkout-validator';

describe('TASK-2.3: Checkout Input Validation', () => {
  describe('normalizePhone', () => {
    it('strips spaces, dashes, parentheses and + prefix', () => {
      expect(normalizePhone('+91 98300 12345')).toBe('919830012345');
      expect(normalizePhone('98300-12345')).toBe('9830012345');
      expect(normalizePhone('09830012345')).toBe('9830012345');
    });
  });

  describe('validateBuyerName', () => {
    it('accepts valid names between 3 and 100 chars', () => {
      expect(validateBuyerName('Pooja Sen')).toBeUndefined();
      expect(validateBuyerName('   Anu Roy   ')).toBeUndefined();
    });

    it('rejects empty or short names', () => {
      expect(validateBuyerName('')).toMatch(/required/);
      expect(validateBuyerName('   ')).toMatch(/required/);
      expect(validateBuyerName('Al')).toMatch(/at least 3 characters/);
    });

    it('rejects names exceeding 100 characters', () => {
      const longName = 'A'.repeat(101);
      expect(validateBuyerName(longName)).toMatch(/cannot exceed 100 characters/);
    });
  });

  describe('validateBuyerPhone', () => {
    it('accepts 10-digit Indian numbers starting with 6, 7, 8, 9', () => {
      expect(validateBuyerPhone('9830012345')).toBeUndefined();
      expect(validateBuyerPhone('8123456789')).toBeUndefined();
      expect(validateBuyerPhone('7000000000')).toBeUndefined();
      expect(validateBuyerPhone('6290000000')).toBeUndefined();
      expect(validateBuyerPhone('+91 98300 12345')).toBeUndefined();
    });

    it('rejects numbers starting with invalid digits or invalid lengths', () => {
      expect(validateBuyerPhone('')).toMatch(/required/);
      expect(validateBuyerPhone('5830012345')).toMatch(/Valid 10-digit Indian mobile number/);
      expect(validateBuyerPhone('98300123')).toMatch(/Valid 10-digit Indian mobile number/);
      expect(validateBuyerPhone('9830012345678')).toMatch(/Valid 10-digit Indian mobile number/);
      expect(validateBuyerPhone('abcdefghij')).toMatch(/Valid 10-digit Indian mobile number/);
    });
  });

  describe('validatePincode', () => {
    it('accepts 6-digit postal codes', () => {
      expect(validatePincode('700032')).toBeUndefined();
      expect(validatePincode('110001')).toBeUndefined();
    });

    it('rejects invalid pincodes', () => {
      expect(validatePincode('')).toMatch(/required/);
      expect(validatePincode('70003')).toMatch(/Valid 6-digit/);
      expect(validatePincode('7000321')).toMatch(/Valid 6-digit/);
      expect(validatePincode('ABCDEF')).toMatch(/Valid 6-digit/);
    });
  });

  describe('validateShippingAddress', () => {
    it('accepts addresses between 10 and 500 characters', () => {
      expect(validateShippingAddress('Flat 4B, 22 Park Street, Kolkata')).toBeUndefined();
    });

    it('rejects short or empty addresses', () => {
      expect(validateShippingAddress('')).toMatch(/required/);
      expect(validateShippingAddress('Short')).toMatch(/at least 10 characters/);
    });

    it('rejects addresses over 500 characters', () => {
      const longAddress = 'X'.repeat(501);
      expect(validateShippingAddress(longAddress)).toMatch(/cannot exceed 500 characters/);
    });
  });

  describe('validateCheckoutForm', () => {
    it('returns isValid: true with clean sanitized data for valid form', () => {
      const form = {
        buyer_name: '   Pooja Sen   ',
        buyer_phone: ' +91 98300 12345 ',
        shipping_address: '  Flat 4B, 22 Park Street, Kolkata 700016  ',
        pincode: '  700016  ',
      };

      const result = validateCheckoutForm(form);
      expect(result.isValid).toBe(true);
      expect(result.errors).toEqual({});
      expect(result.sanitized.buyer_name).toBe('Pooja Sen');
      expect(result.sanitized.buyer_phone).toBe('919830012345');
      expect(result.sanitized.shipping_address).toBe('Flat 4B, 22 Park Street, Kolkata 700016');
      expect(result.sanitized.pincode).toBe('700016');
    });

    it('accumulates field errors for invalid form', () => {
      const form = {
        buyer_name: 'Al',
        buyer_phone: '12345',
        shipping_address: 'Short',
        pincode: '123',
      };

      const result = validateCheckoutForm(form);
      expect(result.isValid).toBe(false);
      expect(result.errors.buyer_name).toBeDefined();
      expect(result.errors.buyer_phone).toBeDefined();
      expect(result.errors.shipping_address).toBeDefined();
      expect(result.errors.pincode).toBeDefined();
    });
  });
});
