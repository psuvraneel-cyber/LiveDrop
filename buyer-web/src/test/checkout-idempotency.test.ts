import { describe, it, expect } from 'vitest';
import { generateIdempotencyKey } from '../lib/checkout/idempotency';

describe('SPRINT 3: Client Checkout Idempotency Token Tests', () => {
  it('generates a valid UUID-based checkout idempotency key with req_chk_ prefix', () => {
    const key1 = generateIdempotencyKey();
    const key2 = generateIdempotencyKey();

    expect(key1).toMatch(/^req_chk_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
    expect(key2).toMatch(/^req_chk_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i);
    expect(key1).not.toBe(key2);
  });
});
