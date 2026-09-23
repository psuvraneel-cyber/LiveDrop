/**
 * LiveDrop — Buyer Cart Storage & Schema Validation (TASK-2.2)
 *
 * Implements defensive local persistence across page refreshes with schema versioning.
 * Recovers safely from malformed JSON, corrupted data, or disabled storage without crashing.
 */

import { CartItem, CartStorageSchema } from '../../types/cart';

export const CART_STORAGE_KEY = 'livedrop_buyer_cart_v1';
export const CURRENT_CART_SCHEMA_VERSION = 1;

/**
 * In-memory fallback if window.localStorage is blocked, disabled, or unavailable (e.g. SSR, Private Browsing).
 */
let memoryStorage: string | null = null;

function getRawStorage(): string | null {
  if (typeof window === 'undefined') {
    return memoryStorage;
  }
  try {
    return window.localStorage.getItem(CART_STORAGE_KEY);
  } catch {
    return memoryStorage;
  }
}

function setRawStorage(value: string): boolean {
  if (typeof window === 'undefined') {
    memoryStorage = value;
    return true;
  }
  try {
    window.localStorage.setItem(CART_STORAGE_KEY, value);
    return true;
  } catch {
    // QuotaExceededError or security policy restriction
    memoryStorage = value;
    return false;
  }
}

function removeRawStorage(): void {
  if (typeof window === 'undefined') {
    memoryStorage = null;
    return;
  }
  try {
    window.localStorage.removeItem(CART_STORAGE_KEY);
  } catch {
    memoryStorage = null;
  }
}

/**
 * Validates whether an unknown object conforms strictly to the CartItem contract.
 */
export function isValidCartItem(item: unknown): item is CartItem {
  if (!item || typeof item !== 'object') {
    return false;
  }

  const candidate = item as Record<string, unknown>;

  if (typeof candidate.productId !== 'string' || candidate.productId.trim() === '') {
    return false;
  }
  if (typeof candidate.dropId !== 'string' || candidate.dropId.trim() === '') {
    return false;
  }
  if (typeof candidate.code !== 'string' || candidate.code.trim() === '') {
    return false;
  }
  if (typeof candidate.title !== 'string') {
    return false;
  }
  if (
    typeof candidate.pricePaisa !== 'number' ||
    !Number.isInteger(candidate.pricePaisa) ||
    !Number.isFinite(candidate.pricePaisa) ||
    candidate.pricePaisa < 0
  ) {
    return false;
  }
  if (typeof candidate.imageUrl !== 'string') {
    return false;
  }
  if (typeof candidate.size !== 'string') {
    return false;
  }
  if (
    typeof candidate.addedAt !== 'number' ||
    !Number.isFinite(candidate.addedAt)
  ) {
    return false;
  }

  return true;
}

/**
 * Creates a clean default empty cart snapshot.
 */
export function createEmptyCart(dropId: string | null = null): CartStorageSchema {
  return {
    version: CURRENT_CART_SCHEMA_VERSION,
    dropId,
    items: [],
    updatedAt: Date.now(),
  };
}

/**
 * Safely loads and validates the persisted cart snapshot from localStorage.
 * Discards malformed JSON, incompatible schema versions, and corrupted items without crashing.
 */
export function loadStoredCart(): CartStorageSchema {
  const raw = getRawStorage();
  if (!raw) {
    return createEmptyCart();
  }

  try {
    const parsed = JSON.parse(raw);

    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return createEmptyCart();
    }

    // Version gate: if schema version does not match, discard stale format
    if (parsed.version !== CURRENT_CART_SCHEMA_VERSION) {
      return createEmptyCart();
    }

    if (!Array.isArray(parsed.items)) {
      return createEmptyCart();
    }

    const dropId = typeof parsed.dropId === 'string' && parsed.dropId.trim() !== '' ? parsed.dropId.trim() : null;
    const seenProductIds = new Set<string>();
    const sanitizedItems: CartItem[] = [];

    for (const rawItem of parsed.items) {
      if (isValidCartItem(rawItem)) {
        // Enforce single-piece uniqueness by productId (ADR-002, single-piece inventory)
        if (!seenProductIds.has(rawItem.productId)) {
          seenProductIds.add(rawItem.productId);
          sanitizedItems.push({
            productId: rawItem.productId,
            dropId: rawItem.dropId,
            code: rawItem.code,
            title: rawItem.title,
            pricePaisa: rawItem.pricePaisa,
            imageUrl: rawItem.imageUrl,
            size: rawItem.size,
            addedAt: rawItem.addedAt,
          });
        }
      }
    }

    return {
      version: CURRENT_CART_SCHEMA_VERSION,
      dropId,
      items: sanitizedItems,
      updatedAt: typeof parsed.updatedAt === 'number' && Number.isFinite(parsed.updatedAt) ? parsed.updatedAt : Date.now(),
    };
  } catch {
    // Malformed JSON parsing failure -> safely recover with empty cart
    return createEmptyCart();
  }
}

/**
 * Persists the cart snapshot to localStorage.
 */
export function saveStoredCart(cart: CartStorageSchema): boolean {
  try {
    const serialized = JSON.stringify({
      version: CURRENT_CART_SCHEMA_VERSION,
      dropId: cart.dropId,
      items: cart.items,
      updatedAt: Date.now(),
    });
    return setRawStorage(serialized);
  } catch {
    return false;
  }
}

/**
 * Clears the persisted cart from localStorage.
 */
export function clearStoredCart(): void {
  removeRawStorage();
}

/**
 * Cache an authentic order token strictly associated with an order ID.
 */
export function cacheOrderToken(orderId: string, orderToken: string): void {
  if (!orderId || !orderToken || typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(`livedrop_order_token_${orderId.trim()}`, orderToken.trim());
  } catch {
    // LocalStorage quota or access exception handled gracefully
  }
}

/**
 * Retrieves the cached order token strictly for the given order ID.
 */
export function getCachedOrderToken(orderId: string): string | null {
  if (!orderId || typeof window === 'undefined') return null;
  try {
    return window.localStorage.getItem(`livedrop_order_token_${orderId.trim()}`);
  } catch {
    return null;
  }
}

/**
 * Purges a cached order token when validation fails or order completes.
 */
export function clearCachedOrderToken(orderId: string): void {
  if (!orderId || typeof window === 'undefined') return;
  try {
    window.localStorage.removeItem(`livedrop_order_token_${orderId.trim()}`);
  } catch {
    // Ignore error
  }
}
