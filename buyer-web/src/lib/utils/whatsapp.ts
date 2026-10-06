/**
 * LiveDrop — WhatsApp Chat & Handoff Utilities
 *
 * Formats token-safe pre-filled WhatsApp messages for seller boutique support.
 * Minimizes PII (excludes buyer address and token; includes only Order Code,
 * Items, Total Amount, and UTR).
 */

import { formatPaisaToINR } from './currency';

export interface WhatsAppOrderMessageParams {
  phone?: string | null;
  orderCode: string;
  items?: Array<{ code: string; title: string }>;
  totalPaisa: number;
  utr?: string | null;
  storeName?: string | null;
}

/**
 * Normalizes Indian mobile number to WhatsApp international standard (e.g., 919876543210).
 */
export function normalizeWhatsAppPhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  const digitsOnly = phone.replace(/\D/g, '');

  if (digitsOnly.length === 10 && /^[6-9]\d{9}$/.test(digitsOnly)) {
    return `91${digitsOnly}`;
  }
  if (digitsOnly.length === 12 && /^91[6-9]\d{9}$/.test(digitsOnly)) {
    return digitsOnly;
  }

  // Non-standard or international format with at least 8 digits
  if (digitsOnly.length >= 8 && digitsOnly.length <= 15) {
    return digitsOnly;
  }

  return null;
}

/**
 * Builds a direct wa.me link with sanitized, pre-filled order context.
 */
export function buildWhatsAppChatUrl(params: WhatsAppOrderMessageParams): string {
  const { phone, orderCode, items = [], totalPaisa, utr, storeName } = params;

  const itemSummary =
    items.length > 0
      ? items.slice(0, 5).map((i) => i.code).join(', ') + (items.length > 5 ? ` (+${items.length - 5} more)` : '')
      : null;

  const lines = [
    `Namaste! I've placed an order on LiveDrop${storeName ? ` with ${storeName}` : ''}.`,
    '',
    `• Order Code: ${orderCode}`,
    `• Total: ${formatPaisaToINR(totalPaisa)}`,
  ];

  if (itemSummary) {
    lines.push(`• Garments: ${itemSummary}`);
  }

  if (utr && utr.trim() !== '') {
    lines.push(`• Payment UTR: ${utr.trim()}`);
  }

  lines.push('', 'Please confirm when verified. Thank you!');

  const messageText = lines.join('\n');
  const encodedText = encodeURIComponent(messageText);
  const cleanPhone = normalizeWhatsAppPhone(phone);

  if (cleanPhone) {
    return `https://wa.me/${cleanPhone}?text=${encodedText}`;
  }

  // Fallback to generic WhatsApp share URL if no specific seller phone is configured
  return `https://api.whatsapp.com/send?text=${encodedText}`;
}

export interface WhatsAppPaymentMessageParams {
  phone?: string | null;
  orderCode: string;
  amountPaisa: number;
  paymentType: 'advance' | 'balance' | 'full';
  storeName?: string | null;
}

/**
 * Opens the seller's WhatsApp chat with a message announcing the payment (owner decision
 * 2026-10-05). The buyer then pays inside the chat (₹ → amount → PIN): a payment the buyer starts
 * themselves, which UPI apps accept for personal UPI IDs, unlike payment links. WhatsApp offers no
 * link that pre-fills the payment amount, so the message states it. Null without a seller number.
 */
export function buildWhatsAppPaymentUrl(params: WhatsAppPaymentMessageParams): string | null {
  const cleanPhone = normalizeWhatsAppPhone(params.phone);
  if (!cleanPhone) return null;
  const label =
    params.paymentType === 'advance' ? 'advance' : params.paymentType === 'balance' ? 'balance' : 'full payment';
  const text = [
    `Namaste${params.storeName ? ` ${params.storeName}` : ''}! I'm paying ${formatPaisaToINR(params.amountPaisa)} (${label}) for my LiveDrop order ${params.orderCode}.`,
    '',
    'I will send it here with WhatsApp Pay and submit the UPI transaction ID on the order page.',
  ].join('\n');
  return `https://wa.me/${cleanPhone}?text=${encodeURIComponent(text)}`;
}
