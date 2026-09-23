/**
 * LiveDrop — Typed Application Error Model
 *
 * Maps PostgREST and transactional RPC errors to strongly typed error classes.
 * Masks internal database stack traces while presenting actionable error context.
 */

export type ErrorCode =
  | 'EMPTY_CART'
  | 'EXCEEDS_CART_LIMIT'
  | 'MIXED_DROP_PRODUCTS'
  | 'STOCK_UNAVAILABLE'
  | 'INVALID_DROP'
  | 'DROP_NOT_ACTIVE'
  | 'INVALID_BUYER_NAME'
  | 'INVALID_BUYER_PHONE'
  | 'INVALID_SHIPPING_ADDRESS'
  | 'INVALID_PINCODE'
  | 'PRODUCT_ALREADY_RECLAIMED'
  | 'UNAUTHORIZED'
  | 'INVALID_ORDER_TOKEN'
  | 'ORDER_NOT_FOUND_OR_UNAUTHORIZED'
  | 'HOLD_EXPIRED'
  | 'ALREADY_PAID'
  | 'ALREADY_SOLD'
  | 'INVALID_INPUT'
  | 'INVALID_UTR'
  | 'INVALID_UTR_FORMAT'
  | 'INVALID_ORDER_STATE'
  | 'REFERENCE_USED_ON_ANOTHER_ORDER'
  | 'PAYMENT_NOT_FOUND'
  | 'AMOUNT_MISMATCH'
  | 'CHECKOUT_IDEMPOTENCY_CONFLICT'
  | 'NETWORK_ERROR'
  | 'UNKNOWN_ERROR';

export class LiveDropError extends Error {
  readonly code: ErrorCode;
  readonly isOperational: boolean;

  constructor(message: string, code: ErrorCode = 'UNKNOWN_ERROR', isOperational: boolean = true) {
    super(message);
    this.name = 'LiveDropError';
    this.code = code;
    this.isOperational = isOperational;
    Object.setPrototypeOf(this, new.target.prototype);
  }
}

export class StockUnavailableError extends LiveDropError {
  readonly unavailableProductIds: string[];

  constructor(unavailableProductIds: string[] = [], message?: string) {
    super(
      message || 'One or more items in your cart have already been reserved or sold.',
      'STOCK_UNAVAILABLE'
    );
    this.name = 'StockUnavailableError';
    this.unavailableProductIds = unavailableProductIds;
  }
}

export class InvalidCartError extends LiveDropError {
  constructor(code: 'EMPTY_CART' | 'EXCEEDS_CART_LIMIT' | 'MIXED_DROP_PRODUCTS', message: string) {
    super(message, code);
    this.name = 'InvalidCartError';
  }
}

export class InvalidDropError extends LiveDropError {
  constructor(message: string = 'The selected drop is not currently active.') {
    super(message, 'INVALID_DROP');
    this.name = 'InvalidDropError';
  }
}

export class ProductReclaimedError extends LiveDropError {
  constructor(
    message: string = 'One or more items in this order were claimed by another buyer after the hold expired.'
  ) {
    super(message, 'PRODUCT_ALREADY_RECLAIMED');
    this.name = 'ProductReclaimedError';
  }
}

export class InvalidOrderTokenError extends LiveDropError {
  constructor(message: string = 'Order receipt could not be found or access is unauthorized.') {
    super(message, 'INVALID_ORDER_TOKEN');
    this.name = 'InvalidOrderTokenError';
  }
}

export class UnauthorizedError extends LiveDropError {
  constructor(message: string = 'You are not authorized to perform this operation.') {
    super(message, 'UNAUTHORIZED');
    this.name = 'UnauthorizedError';
  }
}

export class NetworkError extends LiveDropError {
  constructor(message: string = 'Network connection failed. Please check your connectivity.') {
    super(message, 'NETWORK_ERROR');
    this.name = 'NetworkError';
  }
}

export class InvalidBuyerInputError extends LiveDropError {
  readonly field: 'buyer_name' | 'buyer_phone' | 'shipping_address' | 'pincode';

  constructor(
    field: 'buyer_name' | 'buyer_phone' | 'shipping_address' | 'pincode',
    code: 'INVALID_BUYER_NAME' | 'INVALID_BUYER_PHONE' | 'INVALID_SHIPPING_ADDRESS' | 'INVALID_PINCODE',
    message: string
  ) {
    super(message, code);
    this.name = 'InvalidBuyerInputError';
    this.field = field;
  }
}

export class CheckoutIdempotencyConflictError extends LiveDropError {
  constructor(message: string = 'This checkout request conflict with a prior order submitted under the same key.') {
    super(message, 'CHECKOUT_IDEMPOTENCY_CONFLICT');
    this.name = 'CheckoutIdempotencyConflictError';
  }
}

/**
 * Classifies an RPC failure response into a typed LiveDropError instance.
 */
export function classifyRpcError(errPayload: {
  error?: string;
  unavailable_product_ids?: string[];
  message?: string;
}): LiveDropError {
  const code = (errPayload.error || 'UNKNOWN_ERROR').toUpperCase() as ErrorCode;

  switch (code) {
    case 'CHECKOUT_IDEMPOTENCY_CONFLICT':
      return new CheckoutIdempotencyConflictError(errPayload.message);
    case 'STOCK_UNAVAILABLE':
      return new StockUnavailableError(
        errPayload.unavailable_product_ids || [],
        errPayload.message
      );
    case 'EMPTY_CART':
      return new InvalidCartError('EMPTY_CART', errPayload.message || 'Cart cannot be empty.');
    case 'EXCEEDS_CART_LIMIT':
      return new InvalidCartError(
        'EXCEEDS_CART_LIMIT',
        errPayload.message || 'Cart exceeds the maximum limit of 10 items.'
      );
    case 'MIXED_DROP_PRODUCTS':
      return new InvalidCartError(
        'MIXED_DROP_PRODUCTS',
        errPayload.message || 'All items in an order must belong to the same drop.'
      );
    case 'INVALID_DROP':
    case 'DROP_NOT_ACTIVE':
      return new InvalidDropError(errPayload.message || 'This drop is not currently active.');
    case 'INVALID_BUYER_NAME':
      return new InvalidBuyerInputError(
        'buyer_name',
        'INVALID_BUYER_NAME',
        errPayload.message || 'Buyer name must be between 3 and 100 characters.'
      );
    case 'INVALID_BUYER_PHONE':
      return new InvalidBuyerInputError(
        'buyer_phone',
        'INVALID_BUYER_PHONE',
        errPayload.message || 'Valid 10-digit Indian mobile number required.'
      );
    case 'INVALID_SHIPPING_ADDRESS':
      return new InvalidBuyerInputError(
        'shipping_address',
        'INVALID_SHIPPING_ADDRESS',
        errPayload.message || 'Shipping address must be between 10 and 500 characters.'
      );
    case 'INVALID_PINCODE':
      return new InvalidBuyerInputError(
        'pincode',
        'INVALID_PINCODE',
        errPayload.message || 'Valid 6-digit Indian pincode required.'
      );
    case 'PRODUCT_ALREADY_RECLAIMED':
      return new ProductReclaimedError(errPayload.message);
    case 'INVALID_ORDER_TOKEN':
    case 'ORDER_NOT_FOUND_OR_UNAUTHORIZED':
      return new InvalidOrderTokenError(errPayload.message);
    case 'UNAUTHORIZED':
      return new UnauthorizedError(errPayload.message);
    default:
      return new LiveDropError(
        errPayload.message || `Operation failed: ${errPayload.error}`,
        code
      );
  }
}

