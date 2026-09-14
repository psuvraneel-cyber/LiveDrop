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
    const { data, error } = await client
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
        live_started_at,
        closed_at,
        created_at,
        updated_at,
        profiles (
          store_name,
          store_slug,
          phone_number,
          upi_id,
          upi_qr_url,
          default_shipping_fee_paisa,
          free_shipping_threshold_paisa,
          advance_confirmation_enabled,
          advance_amount_paisa,
          hold_duration_days
        )
      `
      )
      .eq('slug', slug)
      .eq('status', 'live')
      .maybeSingle();

    if (error) {
      throw new LiveDropError(`Failed to fetch catalog drop: ${error.message}`, 'UNKNOWN_ERROR');
    }

    if (!data) {
      return null;
    }

    // Supabase returns profiles as an object when joined on foreign key
    return data as unknown as PublicDropCatalog;
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
  if (!storeSlug || storeSlug.trim() === '') {
    return null;
  }

  try {
    const { data, error } = await client
      .from('profiles')
      .select(
        `
        id,
        store_name,
        store_slug,
        upi_id,
        upi_qr_url,
        default_shipping_fee_paisa,
        free_shipping_threshold_paisa,
        advance_confirmation_enabled,
        advance_amount_paisa,
        hold_duration_days
      `
      )
      .eq('store_slug', storeSlug)
      .maybeSingle();

    if (error) {
      throw new LiveDropError(`Failed to fetch seller storefront: ${error.message}`, 'UNKNOWN_ERROR');
    }

    return (data as unknown as PublicSellerStorefront) || null;
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
      .from('products')
      .select('id, code, title, price_paisa, size, image_url, status, reserved_at, version')
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

