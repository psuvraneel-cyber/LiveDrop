import { describe, it, expect } from 'vitest';
import { normalizeWhatsAppPhone, buildWhatsAppChatUrl } from '../lib/utils/whatsapp';

describe('WhatsApp Chat & Handoff Utilities', () => {
  describe('normalizeWhatsAppPhone', () => {
    it('normalizes 10-digit Indian mobile number with 91 prefix', () => {
      expect(normalizeWhatsAppPhone('9876543210')).toBe('919876543210');
    });

    it('preserves existing 91-prefixed 12-digit mobile number', () => {
      expect(normalizeWhatsAppPhone('919876543210')).toBe('919876543210');
    });

    it('strips non-digit characters (spaces, dashes, plus)', () => {
      expect(normalizeWhatsAppPhone('+91 98765-43210')).toBe('919876543210');
      expect(normalizeWhatsAppPhone('+91 (987) 654-3210')).toBe('919876543210');
    });

    it('returns null for empty, undefined, or invalid phone numbers', () => {
      expect(normalizeWhatsAppPhone('')).toBeNull();
      expect(normalizeWhatsAppPhone(null)).toBeNull();
      expect(normalizeWhatsAppPhone(undefined)).toBeNull();
      expect(normalizeWhatsAppPhone('12345')).toBeNull();
    });
  });

  describe('buildWhatsAppChatUrl', () => {
    it('builds direct wa.me link with pre-filled order context', () => {
      const url = buildWhatsAppChatUrl({
        phone: '9876543210',
        orderCode: 'LD-8X2M9P',
        items: [
          { code: '#01', title: 'Silk Kurti' },
          { code: '#02', title: 'Chiffon Dupatta' },
        ],
        totalPaisa: 150000,
        utr: '428739182734',
        storeName: "Mother's Boutique",
      });

      expect(url).toContain('https://wa.me/919876543210?text=');
      const textParam = decodeURIComponent(url.split('text=')[1]);

      expect(textParam).toContain("Mother's Boutique");
      expect(textParam).toContain('LD-8X2M9P');
      expect(textParam).toContain('1,500');
      expect(textParam).toContain('#01, #02');
      expect(textParam).toContain('428739182734');

      // Verify PII minimization: no buyer tokens or delivery addresses
      expect(textParam).not.toContain('order_token');
      expect(textParam).not.toContain('shipping_address');
    });

    it('falls back to generic WhatsApp intent when seller phone is not provided', () => {
      const url = buildWhatsAppChatUrl({
        phone: null,
        orderCode: 'LD-9Y3K1Q',
        totalPaisa: 99900,
      });

      expect(url.startsWith('https://api.whatsapp.com/send?text=')).toBe(true);
      const textParam = decodeURIComponent(url.split('text=')[1]);
      expect(textParam).toContain('LD-9Y3K1Q');
      expect(textParam).toContain('999');
    });
  });
});
