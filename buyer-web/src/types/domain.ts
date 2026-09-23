/**
 * LiveDrop — Domain & API Type Contracts
 *
 * All monetary amounts are non-negative integers in Paisa (1 INR = 100 Paisa).
 * Floating-point representation is strictly prohibited (ADR-009).
 */

export type ProductStatus = 'available' | 'reserved' | 'sold';
export type OrderStatus = 'pending' | 'confirmed' | 'paid' | 'cancelled' | 'shipped' | 'expired';
export type DropStatus = 'draft' | 'live' | 'closed';

export type OrderConfirmationMode = 'advance' | 'full_payment';
export type OrderPaymentStatus = 'unpaid' | 'advance_paid' | 'paid';
export type OrderFulfilmentStatus = 'not_ready' | 'ready_to_ship' | 'shipped';

export type PaymentRecordType = 'advance' | 'balance' | 'full';
export type PaymentRecordStatus = 'pending' | 'verified' | 'failed' | 'refunded';

export interface Profile {
  id: string; // UUID references auth.users(id)
  store_name: string;
  store_slug: string; // URL-safe unique storefront identifier (e.g. 'mothers-boutique')
  phone_number: string; // E.164 without leading '+' (e.g., '919830012345')
  upi_id: string;
  upi_qr_url: string | null;
  return_address: string;
  default_shipping_fee_paisa: number; // Integer Paisa
  free_shipping_threshold_paisa: number | null; // Integer Paisa
  advance_confirmation_enabled: boolean;
  advance_amount_paisa: number; // Integer Paisa (e.g. 25000 = ₹250.00)
  hold_duration_days: number; // 1 to 30 days
  created_at: string;
  updated_at: string;
}

export interface PublicSellerStorefront {
  id: string;
  store_name: string;
  store_slug: string;
  upi_id: string;
  upi_qr_url: string | null;
  default_shipping_fee_paisa: number;
  free_shipping_threshold_paisa: number | null;
  advance_confirmation_enabled: boolean;
  advance_amount_paisa: number;
  hold_duration_days: number;
  whatsapp_number?: string | null;
}

export interface Drop {
  id: string; // UUID
  seller_id: string; // UUID references profiles(id)
  title: string;
  slug: string;
  status: DropStatus;
  shipping_fee_paisa: number; // Integer Paisa
  free_shipping_threshold_paisa: number | null; // Integer Paisa
  advance_confirmation_enabled?: boolean | null;
  advance_amount_paisa?: number | null;
  hold_duration_days?: number | null;
  live_started_at: string | null;
  closed_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface PublicDropCatalog extends Drop {
  profiles: {
    store_name: string;
    store_slug: string;
    phone_number?: string;
    upi_id: string;
    upi_qr_url: string | null;
    default_shipping_fee_paisa: number;
    free_shipping_threshold_paisa: number | null;
    advance_confirmation_enabled: boolean;
    advance_amount_paisa: number;
    hold_duration_days: number;
  };
}

export interface Product {
  id: string; // UUID
  drop_id: string; // UUID references drops(id)
  code: string; // e.g., '#A01'
  title: string;
  price_paisa: number; // Integer Paisa (e.g., 185000 = ₹1,850.00)
  size: string;
  image_url: string;
  image_urls?: string[];
  description?: string;
  quantity_available?: number;
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
  image_urls?: string[];
  description?: string;
  quantity_available?: number;
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
  confirmation_mode: OrderConfirmationMode;
  advance_required_paisa: number;
  advance_paid_paisa: number;
  total_paid_paisa: number;
  balance_due_paisa: number;
  advance_paid_at: string | null;
  payment_status: OrderPaymentStatus;
  fulfilment_status: OrderFulfilmentStatus;
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

export interface OrderPayment {
  id: string; // UUID
  order_id: string; // UUID references orders(id)
  payment_type: PaymentRecordType;
  amount_paisa: number; // Integer Paisa
  status: PaymentRecordStatus;
  reference_id: string | null;
  verified_at: string | null;
  verified_by: string | null;
  metadata?: Record<string, unknown>;
  created_at: string;
  updated_at: string;
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
  p_confirmation_mode?: OrderConfirmationMode;
  p_idempotency_key?: string | null;
}

export interface CreateOrderSuccessResponse {
  success: true;
  order_id: string;
  order_code: string;
  order_token: string;
  subtotal_paisa: number;
  shipping_paisa: number;
  total_paisa: number;
  confirmation_mode: OrderConfirmationMode;
  advance_required_paisa: number;
  advance_paid_paisa: number;
  balance_due_paisa: number;
  total_paid_paisa: number;
  payment_status: OrderPaymentStatus;
  fulfilment_status: OrderFulfilmentStatus;
  hold_expires_at: string;
  shipped_at?: string | null;
  tracking_number?: string | null;
  courier_partner?: string | null;
  idempotent_replay?: boolean;
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
  confirmation_mode: OrderConfirmationMode;
  advance_required_paisa: number;
  advance_paid_paisa: number;
  total_paid_paisa: number;
  balance_due_paisa: number;
  payment_status: OrderPaymentStatus;
  fulfilment_status: OrderFulfilmentStatus;
  status: OrderStatus;
  hold_expires_at: string | null;
  shipped_at?: string | null;
  tracking_number?: string | null;
  courier_partner?: string | null;
  notes?: string | null;
  store_name: string;
  store_slug?: string;
  upi_id: string;
  upi_qr_url: string | null;
  upi_enabled?: boolean;
  upi_uri?: string | null;
  payment_instructions?: string | null;
  whatsapp_number?: string | null;
  active_payment_attempt?: PaymentAttempt | null;
  payment_attempt?: PaymentAttempt | null;
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

// -----------------------------------------------------------------------------
// Checkout Form & UI Contracts (TASK-2.3)
// -----------------------------------------------------------------------------

export interface CheckoutFormState {
  buyer_name: string;
  buyer_phone: string;
  shipping_address: string;
  pincode: string;
}

export interface CheckoutFormErrors {
  buyer_name?: string;
  buyer_phone?: string;
  shipping_address?: string;
  pincode?: string;
}

export type CheckoutSubmissionStatus =
  | 'idle'
  | 'validating'
  | 'submitting'
  | 'success'
  | 'failure'
  | 'network_ambiguous';

// -----------------------------------------------------------------------------
// Payment Verification Contracts (TASK-2.4A.1)
// -----------------------------------------------------------------------------

export interface RecordVerifiedPaymentRequest {
  p_order_id: string;
  p_payment_type: PaymentRecordType;
  p_amount_paisa: number;
  p_reference_id?: string | null;
  p_metadata?: Record<string, unknown>;
}

export interface RecordVerifiedPaymentSuccessResponse {
  success: true;
  order_id?: string;
  payment_type?: PaymentRecordType;
  amount_paisa?: number;
  status?: OrderStatus;
  payment_status?: OrderPaymentStatus;
  fulfilment_status?: OrderFulfilmentStatus;
  idempotent?: boolean;
  message?: string;
}

export interface RecordVerifiedPaymentErrorResponse {
  success: false;
  error: string;
  message?: string;
}

export type RecordVerifiedPaymentResponse =
  | RecordVerifiedPaymentSuccessResponse
  | RecordVerifiedPaymentErrorResponse;

// -----------------------------------------------------------------------------
// Direct UPI & Payment Attempt Contracts (TASK-2.4B)
// -----------------------------------------------------------------------------

export type PaymentAttemptStatus =
  | 'created'
  | 'awaiting_payment'
  | 'buyer_claimed'
  | 'awaiting_seller_verification'
  | 'late_claim_pending_review'
  | 'verified'
  | 'rejected'
  | 'expired';

export interface PaymentAttempt {
  id: string;
  order_id: string;
  payment_type: 'advance' | 'balance' | 'full';
  payment_method: 'upi';
  expected_amount_paisa: number;
  payee_vpa_snapshot: string;
  payee_display_name_snapshot: string | null;
  transaction_reference: string;
  status: PaymentAttemptStatus;
  buyer_claimed_at: string | null;
  buyer_submitted_utr: string | null;
  seller_verified_at: string | null;
  verified_by: string | null;
  rejection_reason: string | null;
  verification_expires_at?: string | null;
  expires_at: string;
  created_at: string;
  updated_at: string;
  upi_uri?: string;
}

export interface InitiatePaymentAttemptRequest {
  p_order_id: string;
  p_order_token: string;
  p_payment_type?: 'advance' | 'balance' | 'full';
}

export interface InitiatePaymentAttemptSuccessResponse {
  success: true;
  payment_attempt_id: string;
  order_id: string;
  payment_type: 'advance' | 'balance' | 'full';
  expected_amount_paisa: number;
  payee_vpa: string;
  payee_display_name: string;
  transaction_reference: string;
  status: PaymentAttemptStatus;
  upi_uri: string;
  verification_expires_at?: string | null;
  expires_at: string;
  is_existing?: boolean;
  message?: string;
}

export interface InitiatePaymentAttemptErrorResponse {
  success: false;
  error: string;
  message?: string;
}

export type InitiatePaymentAttemptResponse =
  | InitiatePaymentAttemptSuccessResponse
  | InitiatePaymentAttemptErrorResponse;

export interface SubmitBuyerPaymentClaimRequest {
  p_order_id: string;
  p_order_token: string;
  p_payment_attempt_id: string;
  p_utr: string;
}

export interface SubmitBuyerPaymentClaimSuccessResponse {
  success: true;
  payment_attempt_id: string;
  order_id: string;
  status: PaymentAttemptStatus;
  buyer_submitted_utr: string;
  buyer_claimed_at: string;
  verification_expires_at?: string | null;
  expires_at?: string;
  idempotent?: boolean;
  message: string;
}

export interface SubmitBuyerPaymentClaimErrorResponse {
  success: false;
  error: string;
  message?: string;
}

export type SubmitBuyerPaymentClaimResponse =
  | SubmitBuyerPaymentClaimSuccessResponse
  | SubmitBuyerPaymentClaimErrorResponse;

export interface VerifyManualUpiPaymentRequest {
  p_payment_attempt_id: string;
  p_override_reference?: string | null;
}

export interface VerifyManualUpiPaymentSuccessResponse {
  success: true;
  payment_attempt_id: string;
  order_id: string;
  payment_type: 'advance' | 'balance' | 'full';
  expected_amount_paisa: number;
  status: OrderStatus;
  payment_status: OrderPaymentStatus;
  fulfilment_status: OrderFulfilmentStatus;
  advance_paid_paisa: number;
  total_paid_paisa: number;
  balance_due_paisa: number;
  idempotent?: boolean;
  message?: string;
}

export interface VerifyManualUpiPaymentErrorResponse {
  success: false;
  error: string;
  message?: string;
}

export type VerifyManualUpiPaymentResponse =
  | VerifyManualUpiPaymentSuccessResponse
  | VerifyManualUpiPaymentErrorResponse;

export interface RejectManualUpiPaymentRequest {
  p_payment_attempt_id: string;
  p_rejection_reason?: string;
}

export interface RejectManualUpiPaymentSuccessResponse {
  success: true;
  payment_attempt_id: string;
  order_id: string;
  status: PaymentAttemptStatus;
  rejection_reason: string;
  message?: string;
}

export interface RejectManualUpiPaymentErrorResponse {
  success: false;
  error: string;
  message?: string;
}

export type RejectManualUpiPaymentResponse =
  | RejectManualUpiPaymentSuccessResponse
  | RejectManualUpiPaymentErrorResponse;


