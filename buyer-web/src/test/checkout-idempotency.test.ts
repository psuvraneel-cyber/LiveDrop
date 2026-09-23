import { describe, it, expect, beforeEach } from 'vitest';
import {
  generateIdempotencyKey,
  getCartSignature,
  getOrCreateCheckoutIdempotencyKey,
  clearCheckoutIdempotencyKey,
} from '../lib/checkout/idempotency';

describe('SPRINT 3: Client Checkout Idempotency Token Tests', () => {
  beforeEach(() => {
    window.sessionStorage.clear();
  });

  it('generates a valid UUID-based checkout idempotency key with req_chk_ prefix', () => {
    const key1 = generateIdempotencyKey();
    const key2 = generateIdempotencyKey();

    expect(key1).toMatch(/^req_chk_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
    expect(key2).toMatch(/^req_chk_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
    expect(key1).not.toBe(key2);
  });

  it('computes deterministic cart signature independent of item insertion order', () => {
    const sig1 = getCartSignature('drop-1', ['prod-B', 'prod-A', 'prod-C']);
    const sig2 = getCartSignature('drop-1', ['prod-A', 'prod-C', 'prod-B']);

    expect(sig1).toBe(sig2);
    expect(sig1).toBe('drop-1:prod-A,prod-B,prod-C');
  });

  it('preserves the same idempotency key across browser reload/re-invocations for identical cart', () => {
    const dropId = 'drop-100';
    const productIds = ['p1', 'p2'];

    const firstKey = getOrCreateCheckoutIdempotencyKey(dropId, productIds);
    expect(firstKey).toMatch(/^req_chk_/);

    // Simulate page reload by calling again with the same parameters
    const secondKey = getOrCreateCheckoutIdempotencyKey(dropId, productIds);
    expect(secondKey).toBe(firstKey);
  });

  it('rotates to a fresh idempotency key when cart items change', () => {
    const dropId = 'drop-100';
    const initialKey = getOrCreateCheckoutIdempotencyKey(dropId, ['p1', 'p2']);

    // Buyer modifies cart (adds p3)
    const modifiedKey = getOrCreateCheckoutIdempotencyKey(dropId, ['p1', 'p2', 'p3']);
    expect(modifiedKey).not.toBe(initialKey);

    // Calling again with the new items preserves the new key
    const repeatKey = getOrCreateCheckoutIdempotencyKey(dropId, ['p1', 'p2', 'p3']);
    expect(repeatKey).toBe(modifiedKey);
  });

  it('clears the cached idempotency key upon explicit clear call', () => {
    const dropId = 'drop-100';
    const initialKey = getOrCreateCheckoutIdempotencyKey(dropId, ['p1']);

    clearCheckoutIdempotencyKey(dropId);

    const postClearKey = getOrCreateCheckoutIdempotencyKey(dropId, ['p1']);
    expect(postClearKey).not.toBe(initialKey);
  });
});
