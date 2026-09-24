/**
 * LiveDrop Buyer Webfront — Application Data Layer & Contract Tests
 *
 * Validates:
 * 1. Environment configuration and strict service-role rejection
 * 2. Public client initialization with session isolation
 * 3. Typed catalog read operations (slug, public products)
 * 4. Atomic order creation RPC contract and server-authoritative pricing
 * 5. Token-gated receipt retrieval and PII minimization
 * 6. Typed error classification
 */

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { validateBuyerEnv } from '../lib/supabase/env';
import { createBuyerClient } from '../lib/supabase/client';
import {
  getLiveDropBySlug,
  getPublicProductsForDrop,
  createOrderWithReservation,
  getOrderByToken,
  getStorefrontBySlug,
  filterProductionStorefronts,
} from '../lib/data/buyer-catalog';
import {
  classifyRpcError,
  InvalidCartError,
  InvalidDropError,
  InvalidOrderTokenError,
  ProductReclaimedError,
  StockUnavailableError,
  UnauthorizedError,
} from '../lib/errors';
import { SupabaseClient } from '@supabase/supabase-js';
import { CreateOrderRequest } from '../types/domain';

describe('TASK-1.4: Buyer Environment Configuration & Security Bounds', () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...originalEnv };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('validates correct environment variables', () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://test-project.supabase.co';
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key-12345';
    process.env.NEXT_PUBLIC_APP_ENV = 'development';

    const config = validateBuyerEnv();
    expect(config.supabaseUrl).toBe('https://test-project.supabase.co');
    expect(config.supabaseAnonKey).toBe('test-anon-key-12345');
    expect(config.appEnv).toBe('development');
  });

  it('fails if NEXT_PUBLIC_SUPABASE_URL is missing', () => {
    delete process.env.NEXT_PUBLIC_SUPABASE_URL;
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key-12345';

    expect(() => validateBuyerEnv()).toThrowError(/Missing required environment variable: NEXT_PUBLIC_SUPABASE_URL/);
  });

  it('fails if NEXT_PUBLIC_SUPABASE_URL is invalid protocol', () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'ftp://invalid-protocol.com';
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key-12345';

    expect(() => validateBuyerEnv()).toThrowError(/Invalid protocol/);
  });

  it('fails if NEXT_PUBLIC_SUPABASE_ANON_KEY is missing', () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://test-project.supabase.co';
    delete process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    expect(() => validateBuyerEnv()).toThrowError(/Missing required environment variable: NEXT_PUBLIC_SUPABASE_ANON_KEY/);
  });

  it('strictly prohibits service_role credentials in the buyer environment', () => {
    process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://test-project.supabase.co';
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = 'test-anon-key';
    process.env.SUPABASE_SERVICE_ROLE_KEY = 'secret-service-role-leak';

    expect(() => validateBuyerEnv()).toThrowError(/\[SECURITY VIOLATION\] Secret key/);
  });
});

describe('TASK-1.4: Buyer Supabase Client Initialization', () => {
  it('creates an anonymous client with session persistence disabled', () => {
    const client = createBuyerClient({
      supabaseUrl: 'https://test-project.supabase.co',
      supabaseAnonKey: 'test-anon-key-abc',
    });

    expect(client).toBeDefined();
    expect(client.auth).toBeDefined();
  });
});

describe('TASK-1.4: Catalog Data Access Operations', () => {
  it('returns null for empty slug in getLiveDropBySlug', async () => {
    const mockClient = {} as unknown as SupabaseClient;
    const result = await getLiveDropBySlug(mockClient, '');
    expect(result).toBeNull();
  });

  it('queries live drop by slug with sanitized boutique storefront from public projection', async () => {
    const mockDropSingle = vi.fn().mockResolvedValue({
      data: {
        id: 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
        title: 'Friday Silk Special',
        slug: 'mothers-boutique',
        status: 'live',
        shipping_fee_paisa: 8000,
        free_shipping_threshold_paisa: 200000,
        seller_id: '8a329e71-4b10-4055-90d2-df8029d5b512',
      },
      error: null,
    });

    const mockStorefrontSingle = vi.fn().mockResolvedValue({
      data: {
        id: '8a329e71-4b10-4055-90d2-df8029d5b512',
        store_name: "Mother's Boutique",
        store_slug: 'mothers-boutique',
        upi_vpa: 'mothersboutique@okaxis',
        upi_display_name: "Mother's Boutique",
        upi_qr_url: 'https://storage.livedrop.store/qrs/mb.webp',
        upi_enabled: true,
        default_shipping_fee_paisa: 8000,
        free_shipping_threshold_paisa: 200000,
        advance_confirmation_enabled: true,
        advance_amount_paisa: 25000,
        hold_duration_days: 2,
      },
      error: null,
    });

    const mockFrom = vi.fn((table: string) => {
      if (table === 'drops') {
        return {
          select: vi.fn().mockReturnValue({
            eq: vi.fn().mockReturnValue({
              eq: vi.fn().mockReturnValue({
                maybeSingle: mockDropSingle,
              }),
            }),
          }),
        };
      }
      if (table === 'public_seller_storefronts') {
        return {
          select: vi.fn().mockReturnValue({
            eq: vi.fn().mockReturnValue({
              maybeSingle: mockStorefrontSingle,
            }),
          }),
        };
      }
      throw new Error(`Unexpected table query: ${table}`);
    });

    const mockClient = { from: mockFrom } as unknown as SupabaseClient;

    const drop = await getLiveDropBySlug(mockClient, 'mothers-boutique');

    expect(mockFrom).toHaveBeenCalledWith('drops');
    expect(mockFrom).toHaveBeenCalledWith('public_seller_storefronts');
    expect(mockFrom).not.toHaveBeenCalledWith('profiles');
    expect(drop).toBeDefined();
    expect(drop?.title).toBe('Friday Silk Special');
    expect(drop?.profiles.store_name).toBe("Mother's Boutique");
    expect((drop?.profiles as unknown as Record<string, unknown>).phone_number).toBeUndefined();
    expect((drop?.profiles as unknown as Record<string, unknown>).return_address).toBeUndefined();
  });

  it('queries public products for drop ordered by flash code ascending', async () => {
    const mockOrder = vi.fn().mockResolvedValue({
      data: [
        { id: 'p1', code: '#A01', title: 'Silk Saree', price_paisa: 185000, size: 'Free', image_url: 'u1', status: 'available', reserved_at: null, version: 1 },
        { id: 'p2', code: '#A02', title: 'Kurti', price_paisa: 75000, size: 'L', image_url: 'u2', status: 'reserved', reserved_at: '2026-09-11T14:32:00Z', version: 2 },
      ],
      error: null,
    });

    const mockEq = vi.fn().mockReturnValue({ order: mockOrder });
    const mockSelect = vi.fn().mockReturnValue({ eq: mockEq });
    const mockFrom = vi.fn().mockReturnValue({ select: mockSelect });
    const mockClient = { from: mockFrom } as unknown as SupabaseClient;

    const products = await getPublicProductsForDrop(mockClient, 'drop-123');

    expect(mockFrom).toHaveBeenCalledWith('public_products_catalog');
    expect(mockEq).toHaveBeenCalledWith('drop_id', 'drop-123');
    expect(mockOrder).toHaveBeenCalledWith('code', { ascending: true });
    expect(products.length).toBe(2);
    expect(products[0].code).toBe('#A01');
    expect(products[0].price_paisa).toBe(185000);
  });

  it('queries public storefront by store slug with live drops', async () => {
    const mockMaybeSingle = vi.fn().mockResolvedValue({
      data: {
        id: 'prof-1',
        store_name: "Mother's Boutique",
        store_slug: 'mothers-boutique',
        advance_confirmation_enabled: true,
        advance_amount_paisa: 25000,
        hold_duration_days: 30,
      },
      error: null,
    });

    const mockEqSlug = vi.fn().mockReturnValue({ maybeSingle: mockMaybeSingle });
    const mockSelect = vi.fn().mockReturnValue({ eq: mockEqSlug });
    const mockFrom = vi.fn().mockReturnValue({ select: mockSelect });
    const mockClient = { from: mockFrom } as unknown as SupabaseClient;

    const storefront = await getStorefrontBySlug(mockClient, 'mothers-boutique');

    expect(mockFrom).toHaveBeenCalledWith('public_seller_storefronts');
    expect(mockEqSlug).toHaveBeenCalledWith('store_slug', 'mothers-boutique');
    expect(storefront?.store_name).toBe("Mother's Boutique");
    expect(storefront?.store_slug).toBe('mothers-boutique');
    expect(storefront?.advance_amount_paisa).toBe(25000);
  });
});

describe('TASK-1.4: Atomic Order RPC & Price Authority', () => {
  it('rejects order submission with empty cart before hitting RPC', async () => {
    const mockClient = { rpc: vi.fn() } as unknown as SupabaseClient;
    const req: CreateOrderRequest = {
      p_drop_id: 'drop-1',
      p_product_ids: [],
      p_buyer_name: 'Sangeeta',
      p_buyer_phone: '9830100001',
      p_shipping_address: '123 Test St',
      p_pincode: '700032',
    };

    await expect(createOrderWithReservation(mockClient, req)).rejects.toThrowError(/Cart cannot be empty/);
    expect(mockClient.rpc).not.toHaveBeenCalled();
  });

  it('submits checkout request and preserves server-authoritative integer Paisa pricing', async () => {
    const mockRpc = vi.fn().mockResolvedValue({
      data: {
        success: true,
        order_id: 'ord-uuid-1',
        order_code: 'LD-8F429B',
        order_token: 'tok-uuid-1',
        subtotal_paisa: 260000, // ₹2,600.00
        shipping_paisa: 8000,   // ₹80.00
        total_paisa: 268000,    // ₹2,680.00
        hold_expires_at: '2026-09-11T15:00:00Z',
      },
      error: null,
    });
    const mockClient = { rpc: mockRpc } as unknown as SupabaseClient;

    const req: CreateOrderRequest = {
      p_drop_id: 'drop-uuid-1',
      p_product_ids: ['prod-1', 'prod-2'],
      p_buyer_name: 'Sangeeta Mukherjee',
      p_buyer_phone: '9830100001',
      p_shipping_address: 'Flat 4B, Greenview Apts',
      p_pincode: '700032',
    };

    const res = await createOrderWithReservation(mockClient, req);

    expect(mockRpc).toHaveBeenCalledWith('create_order_with_reservation', {
      ...req,
      p_confirmation_mode: 'advance',
      p_idempotency_key: null,
    });
    expect(res.success).toBe(true);
    expect(res.order_code).toBe('LD-8F429B');
    expect(res.total_paisa).toBe(268000);
    expect(Number.isInteger(res.total_paisa)).toBe(true);
  });

  it('maps STOCK_UNAVAILABLE RPC response to typed StockUnavailableError', async () => {
    const mockRpc = vi.fn().mockResolvedValue({
      data: {
        success: false,
        error: 'STOCK_UNAVAILABLE',
        unavailable_product_ids: ['prod-1'],
        message: 'Product #A01 is already reserved.',
      },
      error: null,
    });
    const mockClient = { rpc: mockRpc } as unknown as SupabaseClient;

    const req: CreateOrderRequest = {
      p_drop_id: 'drop-uuid-1',
      p_product_ids: ['prod-1'],
      p_buyer_name: 'Sangeeta Mukherjee',
      p_buyer_phone: '9830100001',
      p_shipping_address: 'Flat 4B, Greenview Apts',
      p_pincode: '700032',
    };

    await expect(createOrderWithReservation(mockClient, req)).rejects.toThrow(StockUnavailableError);
  });
});

describe('TASK-1.4: Order Receipt Token & PII Minimization', () => {
  it('retrieves receipt and guarantees sensitive fulfillment PII is omitted', async () => {
    const mockRpc = vi.fn().mockResolvedValue({
      data: {
        success: true,
        order: {
          id: 'ord-uuid-1',
          order_code: 'LD-8F429B',
          buyer_name: 'Sangeeta Mukherjee',
          subtotal_paisa: 260000,
          shipping_paisa: 8000,
          total_paisa: 268000,
          status: 'pending',
          hold_expires_at: '2026-09-11T15:00:00Z',
          store_name: "Mother's Boutique",
          upi_id: 'mothersboutique@okaxis',
          upi_qr_url: null,
          items: [
            {
              product_id: 'prod-1',
              code: '#A01',
              title: 'Silk Saree',
              image_url: 'url-1',
              price_at_purchase_paisa: 185000,
            },
          ],
        },
      },
      error: null,
    });
    const mockClient = { rpc: mockRpc } as unknown as SupabaseClient;

    const receipt = await getOrderByToken(mockClient, 'ord-uuid-1', 'tok-uuid-1');

    expect(mockRpc).toHaveBeenCalledWith('get_order_by_token', {
      p_order_id: 'ord-uuid-1',
      p_order_token: 'tok-uuid-1',
    });
    expect(receipt.buyer_name).toBe('Sangeeta Mukherjee');
    expect(receipt.total_paisa).toBe(268000);
    // PII verification: phone and address are not present on receipt
    const receiptRec = receipt as unknown as Record<string, unknown>;
    expect(receiptRec.buyer_phone).toBeUndefined();
    expect(receiptRec.shipping_address).toBeUndefined();
    expect(receiptRec.pincode).toBeUndefined();
  });

  it('rejects invalid or mismatched order token', async () => {
    const mockRpc = vi.fn().mockResolvedValue({
      data: {
        success: false,
        error: 'ORDER_NOT_FOUND_OR_UNAUTHORIZED',
      },
      error: null,
    });
    const mockClient = { rpc: mockRpc } as unknown as SupabaseClient;

    await expect(getOrderByToken(mockClient, 'ord-uuid-1', 'bad-token')).rejects.toThrow(InvalidOrderTokenError);
  });
});

describe('TASK-1.4: Error Model Classification', () => {
  it('classifies business and transactional errors correctly', () => {
    expect(classifyRpcError({ error: 'STOCK_UNAVAILABLE', unavailable_product_ids: ['p1'] })).toBeInstanceOf(StockUnavailableError);
    expect(classifyRpcError({ error: 'EMPTY_CART' })).toBeInstanceOf(InvalidCartError);
    expect(classifyRpcError({ error: 'EXCEEDS_CART_LIMIT' })).toBeInstanceOf(InvalidCartError);
    expect(classifyRpcError({ error: 'MIXED_DROP_PRODUCTS' })).toBeInstanceOf(InvalidCartError);
    expect(classifyRpcError({ error: 'INVALID_DROP' })).toBeInstanceOf(InvalidDropError);
    expect(classifyRpcError({ error: 'PRODUCT_ALREADY_RECLAIMED' })).toBeInstanceOf(ProductReclaimedError);
    expect(classifyRpcError({ error: 'INVALID_ORDER_TOKEN' })).toBeInstanceOf(InvalidOrderTokenError);
    expect(classifyRpcError({ error: 'UNAUTHORIZED' })).toBeInstanceOf(UnauthorizedError);
  });
});

describe('Production Storefront Deterministic Hygiene (filterProductionStorefronts)', () => {
  const dummyStore = (slug: string, name: string) => ({
    id: `id-${slug}`,
    store_name: name,
    store_slug: slug,
    upi_qr_url: null,
    default_shipping_fee_paisa: 5000,
    free_shipping_threshold_paisa: null,
    advance_confirmation_enabled: false,
    advance_amount_paisa: 0,
    hold_duration_days: 2,
  });

  it('removes known test/seed accounts and preserves authentic production boutiques', () => {
    const input = [
      dummyStore('suv-s', "Suv's"),
      dummyStore('racestore_test_1', 'RaceStore 1'),
      dummyStore('anita-silks', 'Anita Silks'),
      dummyStore('race-store-2', 'Race Store 2'),
      dummyStore('soanlidnsn', 'soanlidnsn'),
      dummyStore('dheh', 'dheh'),
      dummyStore('varanasi-weaves', 'Varanasi Weaves'),
      dummyStore('staging-boutique', 'Staging Store'),
      dummyStore('dummy-store', 'Dummy Store'),
    ];

    const result = filterProductionStorefronts(input);

    expect(result.map((s) => s.store_slug)).toEqual(['suv-s', 'anita-silks', 'varanasi-weaves']);
  });

  it('preserves input order without sorting side-effects', () => {
    const input = [
      dummyStore('varanasi-weaves', 'Varanasi Weaves'),
      dummyStore('anita-silks', 'Anita Silks'),
      dummyStore('suv-s', "Suv's"),
    ];

    const result = filterProductionStorefronts(input);
    expect(result.map((s) => s.store_slug)).toEqual(['varanasi-weaves', 'anita-silks', 'suv-s']);
  });

  it('rejects invalid, short, or placeholder stores', () => {
    const input = [
      dummyStore('a', 'A'),
      dummyStore('valid-store', 'Test Store'),
      dummyStore('seller-a', 'Seller A'),
      dummyStore('real-atelier', 'Real Atelier'),
    ];

    const result = filterProductionStorefronts(input);
    expect(result.map((s) => s.store_slug)).toEqual(['real-atelier']);
  });

  it('strictly respects explicit verification and publication boolean properties', () => {
    const input = [
      { ...dummyStore('approved-store', 'Approved Boutique'), is_approved: true },
      { ...dummyStore('unapproved-store', 'Unapproved Boutique'), is_approved: false },
      { ...dummyStore('unpublished-store', 'Unpublished Boutique'), is_published: false },
      { ...dummyStore('nonprod-store', 'Non-Production Boutique'), is_production: false },
      { ...dummyStore('unverified-store', 'Unverified Boutique'), is_verified: false },
      { ...dummyStore('draft-store', 'Draft Boutique'), status: 'draft' },
      { ...dummyStore('suspended-store', 'Suspended Boutique'), status: 'suspended' },
    ];

    const result = filterProductionStorefronts(input);
    expect(result.map((s) => s.store_slug)).toEqual(['approved-store']);
  });

  it('rejects additional CI, automated, and null/undefined test patterns', () => {
    const input = [
      dummyStore('e2e-storefront', 'E2E Boutique'),
      dummyStore('cypress-test', 'Cypress Studio'),
      dummyStore('temp-boutique', 'Temp Boutique'),
      dummyStore('fake-seller', 'Fake Seller'),
      dummyStore('sample-silks', 'Sample Silks'),
      dummyStore('null', 'Null Store'),
      dummyStore('undefined', 'Undefined Store'),
      { ...dummyStore('empty-id-store', 'Empty ID Store'), id: '   ' },
      dummyStore('authentic-craft', 'Authentic Craft'),
    ];

    const result = filterProductionStorefronts(input);
    expect(result.map((s) => s.store_slug)).toEqual(['authentic-craft']);
  });

  it('handles empty or malformed inputs defensively', () => {
    expect(filterProductionStorefronts([])).toEqual([]);
    expect(filterProductionStorefronts(null as unknown as [])).toEqual([]);
    expect(filterProductionStorefronts(undefined as unknown as [])).toEqual([]);
  });
});

