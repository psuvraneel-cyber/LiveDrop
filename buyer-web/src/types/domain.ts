/**
 * LiveDrop — Domain & API Type Contracts
 *
 * All monetary amounts are non-negative integers in Paisa (1 INR = 100 Paisa).
 * Floating-point representation is strictly prohibited (ADR-009).
 */

export type ProductStatus = 'available' | 'reserved' | 'sold';
export type OrderStatus = 'pending' | 'paid' | 'cancelled' | 'shipped';
export type DropStatus = 'draft' | 'live' | 'closed';

export interface Profile {
  id: string; // UUID references auth.users(id)
  store_name: string;
  phone_number: string; // E.164 without leading '+' (e.g., '919830012345')
  upi_id: string;
  upi_qr_url: string | null;
  return_address: string;
  default_shipping_fee_paisa: number; // Integer Paisa
  free_shipping_threshold_paisa: number | null; // Integer Paisa
  created_at: string;
  updated_at: string;
}

export interface Drop {
  id: string; // UUID
  seller_id: string; // UUID references profiles(id)
  title: string;
  slug: string;
  status: DropStatus;
  shipping_fee_paisa: number; // Integer Paisa
  free_shipping_threshold_paisa: number | null; // Integer Paisa
  live_started_at: string | null;
  closed_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface PublicDropCatalog extends Drop {
  profiles: Pick<
    Profile,
    'store_name' | 'phone_number' | 'upi_id' | 'upi_qr_url' | 'default_shipping_fee_paisa' | 'free_shipping_threshold_paisa'
  >;
}

export interface Product {
  id: string; // UUID
  drop_id: string; // UUID references drops(id)
  code: string; // e.g., '#A01'
  title: string;
  price_paisa: number; // Integer Paisa (e.g., 185000 = ₹1,850.00)
  size: string;
  image_url: string;
  status: ProductStatus;
  reserved_at: string | null;
  reserved_by_order_id: string | null;
  version: number;
  created_at: string;
  updated_at: string;
}

export interface PublicProductView {
  id: string;
  code: string;
  title: string;
  price_paisa: number;
  size: string;
  image_url: string;
  status: ProductStatus;
  reserved_at: string | null;
  version: number;
}

export interface Order {
  id: string; // UUID
  drop_id: string; // UUID references drops(id)
  order_code: string; // 8-char randomized code
  order_token: string; // UUID capability token for receipt access
  buyer_name: string;
  buyer_phone: string;
  shipping_address: string;
  pincode: string;
  subtotal_paisa: number; // Integer Paisa
  shipping_paisa: number; // Integer Paisa
  total_paisa: number; // Integer Paisa
  status: OrderStatus;
  hold_expires_at: string | null;
  paid_at: string | null;
  shipped_at: string | null;
  tracking_number: string | null;
  courier_partner: string | null;
  created_at: string;
  updated_at: string;
}

export interface OrderItem {
  id: string; // UUID
  order_id: string; // UUID references orders(id)
  product_id: string; // UUID references products(id)
  price_at_purchase_paisa: number; // Integer Paisa
  created_at: string;
}

// -----------------------------------------------------------------------------
// RPC Contracts
// -----------------------------------------------------------------------------

export interface CreateOrderRequest {
  p_drop_id: string;
  p_product_ids: string[];
  p_buyer_name: string;
  p_buyer_phone: string;
  p_shipping_address: string;
  p_pincode: string;
}

export interface CreateOrderSuccessResponse {
  success: true;
  order_id: string;
  order_code: string;
  order_token: string;
  subtotal_paisa: number;
  shipping_paisa: number;
  total_paisa: number;
  hold_expires_at: string;
}

export interface CreateOrderErrorResponse {
  success: false;
  error: string;
  unavailable_product_ids?: string[];
  message?: string;
}

export type CreateOrderResponse = CreateOrderSuccessResponse | CreateOrderErrorResponse;

export interface GetOrderByTokenRequest {
  p_order_id: string;
  p_order_token: string;
}

export interface OrderReceiptItem {
  product_id: string;
  code: string;
  title: string;
  image_url: string;
  price_at_purchase_paisa: number;
}

export interface OrderReceipt {
  id: string;
  order_code: string;
  buyer_name: string;
  subtotal_paisa: number;
  shipping_paisa: number;
  total_paisa: number;
  status: OrderStatus;
  hold_expires_at: string | null;
  store_name: string;
  upi_id: string;
  upi_qr_url: string | null;
  items: OrderReceiptItem[];
}

export interface GetOrderByTokenSuccessResponse {
  success: true;
  order: OrderReceipt;
}

export interface GetOrderByTokenErrorResponse {
  success: false;
  error: string;
  message?: string;
}

export type GetOrderByTokenResponse = GetOrderByTokenSuccessResponse | GetOrderByTokenErrorResponse;
