/**
 * LiveDrop E2E Test Suite — Authoritative Mock Catalog Data
 *
 * All financial values are strictly integers in Paisa (ADR-009).
 * All schema fields conform to domain definitions in src/types/domain.ts.
 */

import {
  PublicDropCatalog,
  PublicProductView,
  PublicSellerStorefront,
  OrderReceipt,
  CreateOrderSuccessResponse,
  PaymentAttempt,
} from '../../../types/domain';

export const mockBoutiqueSonali: PublicSellerStorefront = {
  id: 'seller-sonali-uuid',
  store_name: "Sonali's Boutique",
  store_slug: 'sonalis-boutique',
  phone_number: '919876543210',
  upi_id: 'sonali@okhdfc',
  upi_qr_url: null,
  default_shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: 200000,
  advance_confirmation_enabled: false,
  advance_amount_paisa: 0,
  hold_duration_days: 2,
  is_approved: true,
};

export const mockBoutiqueSuv: PublicSellerStorefront = {
  id: 'seller-suv-uuid',
  store_name: "Suv's Atelier",
  store_slug: 'suvs-atelier',
  phone_number: '919830012345',
  upi_id: 'suv@okaxis',
  upi_qr_url: null,
  default_shipping_fee_paisa: 15000,
  free_shipping_threshold_paisa: 250000,
  advance_confirmation_enabled: true,
  advance_amount_paisa: 50000,
  hold_duration_days: 3,
  is_approved: true,
};

export const mockLiveDrop: PublicDropCatalog = {
  id: 'drop-live-festival-01',
  seller_id: 'seller-sonali-uuid',
  title: 'Festive Silk & Handloom Collection',
  slug: 'festive-silk-handloom',
  status: 'live',
  shipping_fee_paisa: 0,
  free_shipping_threshold_paisa: 200000,
  live_started_at: '2026-09-26T18:00:00Z',
  closed_at: null,
  created_at: '2026-09-26T17:00:00Z',
  updated_at: '2026-09-26T18:00:00Z',
  profiles: {
    store_name: "Sonali's Boutique",
    store_slug: 'sonalis-boutique',
    phone_number: '919876543210',
    upi_id: 'sonali@okhdfc',
    upi_qr_url: null,
    default_shipping_fee_paisa: 0,
    free_shipping_threshold_paisa: 200000,
    advance_confirmation_enabled: false,
    advance_amount_paisa: 0,
    hold_duration_days: 2,
  },
};

export const mockClosedDrop: PublicDropCatalog = {
  id: 'drop-closed-02',
  seller_id: 'seller-suv-uuid',
  title: 'Royal Heritage Archive',
  slug: 'royal-heritage-archive',
  status: 'closed',
  shipping_fee_paisa: 15000,
  free_shipping_threshold_paisa: 250000,
  live_started_at: '2026-09-20T10:00:00Z',
  closed_at: '2026-09-20T12:00:00Z',
  created_at: '2026-09-20T09:00:00Z',
  updated_at: '2026-09-20T12:00:00Z',
  profiles: {
    store_name: "Suv's Atelier",
    store_slug: 'suvs-atelier',
    phone_number: '919830012345',
    upi_id: 'suv@okaxis',
    upi_qr_url: null,
    default_shipping_fee_paisa: 15000,
    free_shipping_threshold_paisa: 250000,
    advance_confirmation_enabled: true,
    advance_amount_paisa: 50000,
    hold_duration_days: 3,
  },
};

export const mockProducts: PublicProductView[] = [
  {
    id: 'prod-saree-a01',
    seller_id: 'seller-sonali-uuid',
    drop_id: 'drop-live-festival-01',
    code: '#A01',
    title: 'Handloom Tussar Silk Saree',
    description: 'Authentic hand-woven pure Tussar silk saree featuring rich temple zari border.',
    size: 'Free Size',
    price_paisa: 185000, // ₹1,850.00
    image_url: 'https://images.livedrop.store/saree-tussar-01.webp',
    image_urls: [
      'https://images.livedrop.store/saree-tussar-01.webp',
      'https://images.livedrop.store/saree-tussar-02.webp',
      'https://images.livedrop.store/saree-tussar-03.webp',
    ],
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-kurti-a02',
    seller_id: 'seller-sonali-uuid',
    drop_id: 'drop-live-festival-01',
    code: '#A02',
    title: 'Chanderi Cotton Kurti',
    description: 'Lightweight summer Chanderi kurti with delicate gold embroidery.',
    size: 'M',
    price_paisa: 75000, // ₹750.00
    image_url: 'https://images.livedrop.store/kurti-chanderi-01.webp',
    image_urls: ['https://images.livedrop.store/kurti-chanderi-01.webp'],
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-dupatta-a03',
    seller_id: 'seller-sonali-uuid',
    drop_id: 'drop-live-festival-01',
    code: '#A03',
    title: 'Pure Jamdani Silk Dupatta',
    description: 'Heritage Jamdani floral motifs hand-woven by master weavers in Bengal.',
    size: 'Free Size',
    price_paisa: 125000, // ₹1,250.00
    image_url: 'https://images.livedrop.store/dupatta-jamdani-01.webp',
    image_urls: ['https://images.livedrop.store/dupatta-jamdani-01.webp'],
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-lehenga-a04',
    seller_id: 'seller-sonali-uuid',
    drop_id: 'drop-live-festival-01',
    code: '#A04',
    title: 'Banarasi Katan Silk Lehenga',
    description: 'Exquisite bridal Banarasi lehenga with antique gold zari kalis.',
    size: 'L',
    price_paisa: 310000, // ₹3,100.00
    image_url: 'https://images.livedrop.store/lehenga-banarasi-01.webp',
    image_urls: ['https://images.livedrop.store/lehenga-banarasi-01.webp'],
    status: 'reserved',
    reserved_at: '2026-09-26T18:15:00Z',
    version: 2,
  },
  {
    id: 'prod-jewellery-a05',
    seller_id: 'seller-sonali-uuid',
    drop_id: 'drop-live-festival-01',
    code: '#A05',
    title: 'Temple Gold Choker Set',
    description: 'Handcrafted antique matte finish brass-alloy temple choker necklace.',
    size: 'Free Size',
    price_paisa: 220000, // ₹2,200.00
    image_url: 'https://images.livedrop.store/jewel-choker-01.webp',
    image_urls: ['https://images.livedrop.store/jewel-choker-01.webp'],
    status: 'sold',
    reserved_at: null,
    version: 3,
  },
];

export const mockPaymentAttempt: PaymentAttempt = {
  id: 'attempt-uuid-001',
  order_id: 'order-uuid-101',
  payment_type: 'full',
  payment_method: 'upi',
  expected_amount_paisa: 185000,
  payee_vpa_snapshot: 'sonali@okhdfc',
  payee_display_name_snapshot: "Sonali's Boutique",
  transaction_reference: 'LD-9X4M2P-F',
  upi_uri: 'upi://pay?pa=sonali@okhdfc&pn=Sonalis%20Boutique&am=1850.00&cu=INR&tr=LD-9X4M2P-F',
  buyer_submitted_utr: null,
  buyer_claimed_at: null,
  seller_verified_at: null,
  verified_by: null,
  rejection_reason: null,
  expires_at: '2026-09-26T18:35:00Z',
  status: 'awaiting_payment',
  created_at: '2026-09-26T18:20:00Z',
  updated_at: '2026-09-26T18:20:00Z',
};

export const mockClaimedPaymentAttempt: PaymentAttempt = {
  ...mockPaymentAttempt,
  buyer_submitted_utr: '428739182734',
  buyer_claimed_at: '2026-09-26T18:22:00Z',
  verification_expires_at: '2026-09-27T18:22:00Z',
  status: 'buyer_claimed',
};

export const mockCreateOrderResponse: CreateOrderSuccessResponse = {
  success: true,
  order_id: 'order-uuid-101',
  order_token: '8f7a6c9d-1234-4567-89ab-cdef01234567',
  order_code: 'LD-9X4M2P',
  subtotal_paisa: 185000,
  shipping_paisa: 0,
  total_paisa: 185000,
  advance_required_paisa: 0,
  advance_paid_paisa: 0,
  balance_due_paisa: 185000,
  total_paid_paisa: 0,
  confirmation_mode: 'full_payment',
  payment_status: 'unpaid',
  fulfilment_status: 'not_ready',
  hold_expires_at: '2026-09-26T18:35:00Z',
};

export const mockOrderReceiptFull: OrderReceipt = {
  id: 'order-uuid-101',
  order_code: 'LD-9X4M2P',
  buyer_name: 'Priya Sharma',
  subtotal_paisa: 185000,
  shipping_paisa: 0,
  total_paisa: 185000,
  confirmation_mode: 'full_payment',
  advance_required_paisa: 0,
  advance_paid_paisa: 0,
  total_paid_paisa: 0,
  balance_due_paisa: 185000,
  payment_status: 'unpaid',
  fulfilment_status: 'not_ready',
  status: 'pending',
  hold_expires_at: new Date(Date.now() + 15 * 60 * 1000).toISOString(),
  store_name: "Sonali's Boutique",
  store_slug: 'sonalis-boutique',
  upi_id: 'sonali@okhdfc',
  upi_qr_url: null,
  active_payment_attempt: mockPaymentAttempt,
  items: [
    {
      product_id: 'prod-saree-a01',
      code: '#A01',
      title: 'Handloom Tussar Silk Saree',
      image_url: 'https://images.livedrop.store/saree-tussar-01.webp',
      price_at_purchase_paisa: 185000,
    },
  ],
};
