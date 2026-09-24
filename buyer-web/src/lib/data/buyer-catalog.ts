/**
 * LiveDrop Buyer Webfront — Application Data Access Layer
 *
 * All catalog queries operate under PostgreSQL Row-Level Security (RLS).
 * All order creations and inventory allocations are mediated exclusively
 * through atomic database RPCs.
 *
 * CRITICAL RULE: The client layer NEVER computes authoritative product prices,
 * subtotals, shipping fees, or order totals. All monetary calculations are
 * performed by the database engine in integer Paisa (ADR-002, ADR-009).
 */

import { SupabaseClient } from '@supabase/supabase-js';
import {
  PublicDropCatalog,
  PublicProductView,
  PublicSellerStorefront,
  StorefrontData,
  ShowcaseCollection,
  CreateOrderRequest,
  CreateOrderSuccessResponse,
  CreateOrderResponse,
  OrderReceipt,
  GetOrderByTokenResponse,
  GetOrderByTokenErrorResponse,
  InitiatePaymentAttemptSuccessResponse,
  InitiatePaymentAttemptResponse,
  SubmitBuyerPaymentClaimSuccessResponse,
  SubmitBuyerPaymentClaimResponse,
} from '../../types/domain';
import { classifyRpcError, ErrorCode, InvalidOrderTokenError, LiveDropError, NetworkError } from '../errors';

/**
 * Retrieves an active live drop by its URL slug.
 * Returns null if the drop does not exist or is not currently in 'live' status.
 */
export async function getLiveDropBySlug(
  client: SupabaseClient,
  slug: string
): Promise<PublicDropCatalog | null> {
  if (!slug || slug.trim() === '') {
    return null;
  }

  try {
    const { data: dropData, error: dropError } = await client
      .from('drops')
      .select(
        `
        id,
        seller_id,
        title,
        slug,
        status,
        shipping_fee_paisa,
        free_shipping_threshold_paisa,
        advance_confirmation_enabled,
        advance_amount_paisa,
        hold_duration_days,
        stream_url,
        live_started_at,
        closed_at,
        created_at,
        updated_at
      `
      )
      .eq('slug', slug)
      .eq('status', 'live')
      .maybeSingle();

    if (dropError) {
      throw new LiveDropError(`Failed to fetch catalog drop: ${dropError.message}`, 'UNKNOWN_ERROR');
    }

    if (!dropData) {
      return null;
    }

    const { data: storefrontData, error: storefrontError } = await client
      .from('public_seller_storefronts')
      .select(
        `
        id,
        store_name,
        store_slug,
        phone_number,
        upi_vpa,
        upi_display_name,
        upi_qr_url,
        upi_enabled,
        default_shipping_fee_paisa,
        free_shipping_threshold_paisa,
        advance_confirmation_enabled,
        advance_amount_paisa,
        hold_duration_days
      `
      )
      .eq('id', dropData.seller_id)
      .maybeSingle();

    if (storefrontError) {
      throw new LiveDropError(`Failed to fetch seller storefront: ${storefrontError.message}`, 'UNKNOWN_ERROR');
    }

    const profiles = storefrontData
      ? {
          store_name: storefrontData.store_name,
          store_slug: storefrontData.store_slug,
          phone_number: storefrontData.phone_number || undefined,
          upi_id: storefrontData.upi_vpa || ((storefrontData as Record<string, unknown>).upi_id as string) || '',
          upi_qr_url: storefrontData.upi_qr_url,
          default_shipping_fee_paisa: storefrontData.default_shipping_fee_paisa,
          free_shipping_threshold_paisa: storefrontData.free_shipping_threshold_paisa,
          advance_confirmation_enabled: storefrontData.advance_confirmation_enabled,
          advance_amount_paisa: storefrontData.advance_amount_paisa,
          hold_duration_days: storefrontData.hold_duration_days,
        }
      : {
          store_name: 'LiveDrop Boutique',
          store_slug: '',
          upi_id: '',
          upi_qr_url: null,
          default_shipping_fee_paisa: 0,
          free_shipping_threshold_paisa: null,
          advance_confirmation_enabled: false,
          advance_amount_paisa: 0,
          hold_duration_days: 2,
        };

    return {
      ...dropData,
      profiles,
    } as unknown as PublicDropCatalog;
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

/**
 * Retrieves a seller's public storefront information by store slug.
 */
export async function getStorefrontBySlug(
  client: SupabaseClient,
  storeSlug: string
): Promise<PublicSellerStorefront | null> {
  const cleanSlug = (storeSlug || '').trim().toLowerCase().replace(/^\/+|\/+$/g, '');
  if (!cleanSlug) {
    return null;
  }

  try {
    const { data, error } = await client
      .from('public_seller_storefronts')
      .select(
        `
        id,
        store_name,
        store_slug,
        phone_number,
        upi_vpa,
        upi_display_name,
        upi_qr_url,
        upi_enabled,
        default_shipping_fee_paisa,
        free_shipping_threshold_paisa,
        advance_confirmation_enabled,
        advance_amount_paisa,
        hold_duration_days,
        created_at
      `
      )
      .eq('store_slug', cleanSlug)
      .maybeSingle();

    if (error) {
      throw new LiveDropError(`Failed to fetch seller storefront: ${error.message}`, 'UNKNOWN_ERROR');
    }

    if (!data) return null;

    // Map upi_vpa back to upi_id if needed for interface compatibility
    const rawData = data as Record<string, unknown>;
    const storefront = {
      ...data,
      upi_id: (rawData.upi_vpa as string) || (rawData.upi_id as string) || '',
      is_approved: typeof rawData.is_approved === 'boolean' ? rawData.is_approved : true,
      is_verified: typeof rawData.is_verified === 'boolean' ? rawData.is_verified : undefined,
      is_published: typeof rawData.is_published === 'boolean' ? rawData.is_published : undefined,
      is_production: typeof rawData.is_production === 'boolean' ? rawData.is_production : undefined,
    };

    return (storefront as unknown as PublicSellerStorefront) || null;
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

export const getSellerStorefrontBySlug = getStorefrontBySlug;

/**
 * Retrieves full boutique storefront data:
 * - Seller profile info
 * - Active live drop (if any) and its live products
 * - Previous closed drops with available showcase items
 */
export async function getStorefrontData(
  client: SupabaseClient,
  storeSlug: string
): Promise<StorefrontData | null> {
  const storefront = await getStorefrontBySlug(client, storeSlug);
  if (!storefront) {
    return null;
  }

  let activeLiveDrop: PublicDropCatalog | null = null;
  let liveProducts: PublicProductView[] = [];

  // 1. Check for active live drop for this seller
  const { data: liveDropData } = await client
    .from('drops')
    .select(
      `
      id,
      seller_id,
      title,
      slug,
      status,
      shipping_fee_paisa,
      free_shipping_threshold_paisa,
      advance_confirmation_enabled,
      advance_amount_paisa,
      hold_duration_days,
      stream_url,
      live_started_at,
      closed_at,
      created_at,
      updated_at
    `
    )
    .eq('seller_id', storefront.id)
    .eq('status', 'live')
    .order('live_started_at', { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle();

  if (liveDropData) {
    activeLiveDrop = {
      ...liveDropData,
      profiles: {
        store_name: storefront.store_name,
        store_slug: storefront.store_slug,
        phone_number: storefront.phone_number || undefined,
        upi_id: storefront.upi_vpa || storefront.upi_id || '',
        upi_qr_url: storefront.upi_qr_url,
        default_shipping_fee_paisa: storefront.default_shipping_fee_paisa,
        free_shipping_threshold_paisa: storefront.free_shipping_threshold_paisa,
        advance_confirmation_enabled: storefront.advance_confirmation_enabled,
        advance_amount_paisa: storefront.advance_amount_paisa,
        hold_duration_days: storefront.hold_duration_days,
      },
    } as unknown as PublicDropCatalog;

    try {
      liveProducts = await getPublicProductsForDrop(client, liveDropData.id);
    } catch {
      liveProducts = [];
    }
  }

  // 2. Query closed drops for showcase lookbook
  const { data: closedDrops } = await client
    .from('drops')
    .select('id, seller_id, title, slug, status, created_at, closed_at')
    .eq('seller_id', storefront.id)
    .eq('status', 'closed')
    .order('created_at', { ascending: false });

  const pastDropsWithProducts: ShowcaseCollection[] = [];

  if (closedDrops && closedDrops.length > 0) {
    const dropIds = closedDrops.map((d) => d.id);
    const { data: availableItems } = await client
      .from('public_products_catalog')
      .select('id, drop_id, code, title, price_paisa, size, image_url, image_urls, status, reserved_at, version, drop_status, drop_title, drop_slug, drop_created_at, seller_id, created_at')
      .in('drop_id', dropIds)
      .eq('status', 'available')
      .order('code', { ascending: true });

    const itemsByDrop = new Map<string, PublicProductView[]>();
    for (const item of (availableItems || []) as PublicProductView[]) {
      if (item.drop_id) {
        if (!itemsByDrop.has(item.drop_id)) {
          itemsByDrop.set(item.drop_id, []);
        }
        itemsByDrop.get(item.drop_id)!.push(item);
      }
    }

    for (const drop of closedDrops) {
      const dropItems = itemsByDrop.get(drop.id) || [];
      if (dropItems.length > 0) {
        pastDropsWithProducts.push({
          drop: {
            id: drop.id,
            title: drop.title,
            slug: drop.slug,
            status: 'closed',
            created_at: drop.created_at,
            closed_at: drop.closed_at,
          },
          products: dropItems,
        });
      }
    }
  }

  return {
    storefront,
    activeLiveDrop,
    liveProducts,
    pastDropsWithProducts,
  };
}

/**
 * Known automated test, CI/CD, or seed storefront patterns.
 */
const TEST_STORE_PATTERNS = [
  /^racestore/i,
  /^race-store/i,
  /^race_store/i,
  /^staging/i,
  /^test[-_]?/i,
  /[-_]?test$/i,
  /^seed[-_]?/i,
  /^dummy[-_]?/i,
  /^mock[-_]?/i,
  /^e2e[-_]?/i,
  /^cypress[-_]?/i,
  /^sample[-_]?/i,
  /^fake[-_]?/i,
  /^temp[-_]?/i,
  /^placeholder/i,
  /soanlidnsn/i,
  /dheh/i,
  /asdf/i,
  /qwerty/i,
];

/**
 * Deterministically filters storefronts for production display.
 * Removes known test/seed records and only exposes storefronts satisfying explicit production/publication criteria.
 * Sorting and editorial prominence remain strictly separate concerns.
 */
export function filterProductionStorefronts(
  storefronts: PublicSellerStorefront[]
): PublicSellerStorefront[] {
  if (!Array.isArray(storefronts)) {
    return [];
  }

  return storefronts.filter((sf) => {
    if (!sf || typeof sf !== 'object') return false;
    if (!sf.id || typeof sf.id !== 'string' || !sf.id.trim()) return false;

    // Use an actual verified/published/production data property where available.
    // Explicit negative publication flags must be strictly respected.
    // Never infer verification merely because a store has imagery or a description.
    if (sf.is_approved !== undefined && sf.is_approved !== true) return false;
    if (sf.is_published !== undefined && sf.is_published !== true) return false;
    if (sf.is_production !== undefined && sf.is_production !== true) return false;
    if (sf.is_verified !== undefined && sf.is_verified !== true) return false;
    if (
      sf.status === 'draft' ||
      sf.status === 'archived' ||
      sf.status === 'suspended' ||
      sf.status === 'inactive'
    ) {
      return false;
    }

    const slug = (sf.store_slug || '').trim().toLowerCase();
    const name = (sf.store_name || '').trim();

    // Must satisfy explicit minimal publication criteria:
    // Non-empty slug with at least 2 chars, non-empty store name with at least 2 chars
    if (slug.length < 2 || name.length < 2) return false;
    if (slug === 'null' || slug === 'undefined') return false;

    // Reject known test / seed / automated patterns in slug or store name
    for (const pattern of TEST_STORE_PATTERNS) {
      if (pattern.test(slug) || pattern.test(name)) {
        return false;
      }
    }

    // Reject generic placeholder names
    const lowerName = name.toLowerCase();
    if (
      lowerName === 'test store' ||
      lowerName === 'seller a' ||
      lowerName === 'seller b' ||
      lowerName === 'store 1' ||
      lowerName === 'temp store' ||
      lowerName === 'sample store'
    ) {
      return false;
    }

    return true;
  });
}

/**
 * Retrieves all verified boutique storefronts for directory listing.
 */
export async function getAllVerifiedStorefronts(
  client: SupabaseClient
): Promise<PublicSellerStorefront[]> {
  try {
    const { data, error } = await client
      .from('public_seller_storefronts')
      .select(
        `
        id,
        store_name,
        store_slug,
        phone_number,
        upi_vpa,
        upi_display_name,
        upi_qr_url,
        upi_enabled,
        default_shipping_fee_paisa,
        free_shipping_threshold_paisa,
        advance_confirmation_enabled,
        advance_amount_paisa,
        hold_duration_days,
        created_at
      `
      )
      .order('created_at', { ascending: false });

    if (error) {
      throw new LiveDropError(`Failed to fetch storefronts: ${error.message}`, 'UNKNOWN_ERROR');
    }

    const mapped = (data || []).map((row) => {
      const raw = row as Record<string, unknown>;
      return {
        ...row,
        upi_id: (raw.upi_vpa as string) || (raw.upi_id as string) || '',
        is_approved: typeof raw.is_approved === 'boolean' ? raw.is_approved : true,
        is_verified: typeof raw.is_verified === 'boolean' ? raw.is_verified : undefined,
        is_published: typeof raw.is_published === 'boolean' ? raw.is_published : undefined,
        is_production: typeof raw.is_production === 'boolean' ? raw.is_production : undefined,
      } as PublicSellerStorefront;
    });

    return filterProductionStorefronts(mapped);
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

/**
 * Retrieves all currently active live drops across all boutiques.
 */
export async function getAllActiveLiveDrops(
  client: SupabaseClient
): Promise<PublicDropCatalog[]> {
  try {
    const { data: drops, error: dropsError } = await client
      .from('drops')
      .select(
        `
        id,
        seller_id,
        title,
        slug,
        status,
        shipping_fee_paisa,
        free_shipping_threshold_paisa,
        advance_confirmation_enabled,
        advance_amount_paisa,
        hold_duration_days,
        stream_url,
        live_started_at,
        closed_at,
        created_at,
        updated_at
      `
      )
      .eq('status', 'live')
      .order('live_started_at', { ascending: false, nullsFirst: false });

    if (dropsError) {
      throw new LiveDropError(`Failed to fetch live drops: ${dropsError.message}`, 'UNKNOWN_ERROR');
    }

    if (!drops || drops.length === 0) {
      return [];
    }

    const sellerIds = Array.from(new Set(drops.map((d) => d.seller_id).filter(Boolean)));
    const { data: sfs } = sellerIds.length > 0
      ? await client
          .from('public_seller_storefronts')
          .select('*')
          .in('id', sellerIds)
      : { data: [] };

    const sfMap = new Map<string, Record<string, unknown>>();
    for (const sf of (sfs || []) as Record<string, unknown>[]) {
      if (sf?.id) {
        sfMap.set(sf.id as string, sf);
      }
    }

    const enriched: PublicDropCatalog[] = drops.map((drop) => {
      const sf = sfMap.get(drop.seller_id);
      return {
        ...drop,
        profiles: sf
          ? {
              store_name: (sf.store_name as string) || 'LiveDrop Boutique',
              store_slug: (sf.store_slug as string) || '',
              phone_number: (sf.phone_number as string) || undefined,
              upi_id: (sf.upi_vpa as string) || (sf.upi_id as string) || '',
              upi_qr_url: (sf.upi_qr_url as string) || null,
              default_shipping_fee_paisa: (sf.default_shipping_fee_paisa as number) ?? 0,
              free_shipping_threshold_paisa: (sf.free_shipping_threshold_paisa as number) ?? null,
              advance_confirmation_enabled: Boolean(sf.advance_confirmation_enabled),
              advance_amount_paisa: (sf.advance_amount_paisa as number) ?? 0,
              hold_duration_days: (sf.hold_duration_days as number) ?? 2,
            }
          : {
              store_name: 'LiveDrop Boutique',
              store_slug: '',
              upi_id: '',
              upi_qr_url: null,
              default_shipping_fee_paisa: 0,
              free_shipping_threshold_paisa: null,
              advance_confirmation_enabled: false,
              advance_amount_paisa: 0,
              hold_duration_days: 2,
            },
      } as unknown as PublicDropCatalog;
    });

    // Deterministically remove drops from test / seed accounts or with test drop patterns
    const productionDrops = enriched.filter((drop) => {
      if (!drop.profiles?.store_slug || !drop.profiles?.store_name) return false;
      const storeSlug = drop.profiles.store_slug.toLowerCase();
      const storeName = drop.profiles.store_name.toLowerCase();
      const dropSlug = (drop.slug || '').toLowerCase();
      const dropTitle = (drop.title || '').toLowerCase();

      for (const pattern of TEST_STORE_PATTERNS) {
        if (
          pattern.test(storeSlug) ||
          pattern.test(storeName) ||
          pattern.test(dropSlug) ||
          pattern.test(dropTitle)
        ) {
          return false;
        }
      }
      return true;
    });

    return productionDrops;
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

/**
 * Retrieves the public product list for a live drop, ordered by flash code ascending.
 */
export async function getPublicProductsForDrop(
  client: SupabaseClient,
  dropId: string
): Promise<PublicProductView[]> {
  if (!dropId) {
    return [];
  }

  try {
    const { data, error } = await client
      .from('public_products_catalog')
      .select('id, drop_id, code, title, price_paisa, size, image_url, image_urls, status, reserved_at, version, drop_status, drop_title, drop_slug, drop_created_at, seller_id, created_at')
      .eq('drop_id', dropId)
      .order('code', { ascending: true });

    if (error) {
      throw new LiveDropError(`Failed to fetch products: ${error.message}`, 'UNKNOWN_ERROR');
    }

    return (data || []) as PublicProductView[];
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

/**
 * Submits an atomic checkout reservation request via the `create_order_with_reservation` RPC.
 * Returns authoritative server-calculated order and price details in integer Paisa.
 */
export async function createOrderWithReservation(
  client: SupabaseClient,
  request: CreateOrderRequest
): Promise<CreateOrderSuccessResponse> {
  // Input sanity guard
  if (!request.p_drop_id) {
    throw new LiveDropError('Drop ID is required.', 'INVALID_DROP');
  }
  if (!request.p_product_ids || request.p_product_ids.length === 0) {
    throw new LiveDropError('Cart cannot be empty.', 'EMPTY_CART');
  }

  try {
    const { data, error } = await client.rpc('create_order_with_reservation', {
      p_drop_id: request.p_drop_id,
      p_product_ids: request.p_product_ids,
      p_buyer_name: request.p_buyer_name,
      p_buyer_phone: request.p_buyer_phone,
      p_shipping_address: request.p_shipping_address,
      p_pincode: request.p_pincode,
      p_confirmation_mode: request.p_confirmation_mode || 'advance',
      p_idempotency_key: request.p_idempotency_key || null,
    });

    if (error) {
      throw new LiveDropError(
        `RPC execution failed: ${error.message}`,
        (error.code as ErrorCode) || 'UNKNOWN_ERROR'
      );
    }

    const response = data as CreateOrderResponse;

    if (!response || response.success !== true) {
      throw classifyRpcError(response || { error: 'UNKNOWN_ERROR' });
    }

    return response as CreateOrderSuccessResponse;
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

/**
 * Retrieves the token-gated order receipt via the `get_order_by_token` RPC.
 * Adheres strictly to PII minimization (exposing buyer_name, withholding phone & address).
 */
export async function getOrderByToken(
  client: SupabaseClient,
  orderId: string,
  orderToken: string
): Promise<OrderReceipt> {
  if (!orderId || !orderToken) {
    throw new InvalidOrderTokenError('Order ID and receipt token are required.');
  }

  try {
    const { data, error } = await client.rpc('get_order_by_token', {
      p_order_id: orderId,
      p_order_token: orderToken,
    });

    if (error) {
      throw new LiveDropError(
        `Receipt retrieval failed: ${error.message}`,
        (error.code as ErrorCode) || 'UNKNOWN_ERROR'
      );
    }

    const response = data as GetOrderByTokenResponse;

    if (!response || response.success !== true) {
      const errResponse = response as GetOrderByTokenErrorResponse | undefined;
      throw new InvalidOrderTokenError(errResponse?.error || 'Order receipt not found or access denied.');
    }

    if (!response.order) {
      throw new InvalidOrderTokenError('Order receipt payload is empty.');
    }

    return response.order;
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

/**
 * Initiates an order-specific payment attempt via `initiate_payment_attempt` RPC.
 * Server determines expected amount in integer Paisa and payee UPI VPA snapshot.
 */
export async function initiatePaymentAttempt(
  client: SupabaseClient,
  orderId: string,
  orderToken: string,
  paymentType: 'advance' | 'balance' | 'full' = 'advance'
): Promise<InitiatePaymentAttemptSuccessResponse> {
  if (!orderId || !orderToken) {
    throw new InvalidOrderTokenError('Order ID and receipt token are required.');
  }

  try {
    const { data, error } = await client.rpc('initiate_payment_attempt', {
      p_order_id: orderId,
      p_order_token: orderToken,
      p_payment_type: paymentType,
    });

    if (error) {
      throw new LiveDropError(
        `Failed to initiate payment attempt: ${error.message}`,
        (error.code as ErrorCode) || 'UNKNOWN_ERROR'
      );
    }

    const response = data as InitiatePaymentAttemptResponse;
    if (!response || response.success !== true) {
      throw new LiveDropError(
        response?.message || response?.error || 'Payment initiation failed.',
        (response?.error as ErrorCode) || 'UNKNOWN_ERROR'
      );
    }

    return response;
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

/**
 * Submits the buyer's payment claim (UTR / UPI Transaction ID) via `submit_buyer_payment_claim` RPC.
 * Does NOT mark payment verified; transitions attempt to awaiting_seller_verification.
 */
export async function submitBuyerPaymentClaim(
  client: SupabaseClient,
  orderId: string,
  orderToken: string,
  paymentAttemptId: string,
  utr: string
): Promise<SubmitBuyerPaymentClaimSuccessResponse> {
  if (!orderId || !orderToken || !paymentAttemptId || !utr) {
    throw new LiveDropError('Order ID, token, payment attempt ID, and UTR are required.', 'INVALID_INPUT');
  }

  try {
    const { data, error } = await client.rpc('submit_buyer_payment_claim', {
      p_order_id: orderId,
      p_order_token: orderToken,
      p_payment_attempt_id: paymentAttemptId,
      p_utr: utr,
    });

    if (error) {
      throw new LiveDropError(
        `Failed to submit payment claim: ${error.message}`,
        (error.code as ErrorCode) || 'UNKNOWN_ERROR'
      );
    }

    const response = data as SubmitBuyerPaymentClaimResponse;
    if (!response || response.success !== true) {
      throw new LiveDropError(
        response?.message || response?.error || 'Payment claim submission failed.',
        (response?.error as ErrorCode) || 'UNKNOWN_ERROR'
      );
    }

    return response;
  } catch (err: unknown) {
    if (err instanceof LiveDropError) throw err;
    throw new NetworkError(err instanceof Error ? err.message : String(err));
  }
}

