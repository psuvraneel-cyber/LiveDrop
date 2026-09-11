/**
 * LiveDrop Buyer Webfront — Cart Storage & Schema Validation Tests (TASK-2.2)
 *
 * Tests defensive persistence, JSON parsing error recovery, schema versioning,
 * corrupted item discarding, single-piece deduplication, and integer Paisa integrity.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import {
  CART_STORAGE_KEY,
  CURRENT_CART_SCHEMA_VERSION,
  loadStoredCart,
  saveStoredCart,
  clearStoredCart,
  isValidCartItem,
  createEmptyCart,
} from '../lib/cart/cart-storage';
import { CartItem, CartStorageSchema } from '../types/cart';

describe('TASK-2.2: Cart Storage & Schema Validation', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('creates a clean empty cart snapshot', () => {
    const empty = createEmptyCart('drop-01');
    expect(empty.version).toBe(CURRENT_CART_SCHEMA_VERSION);
    expect(empty.dropId).toBe('drop-01');
    expect(empty.items).toEqual([]);
    expect(typeof empty.updatedAt).toBe('number');
  });

  it('validates genuine CartItem objects correctly', () => {
    const validItem: CartItem = {
      productId: 'b4b1a111-1111-4111-a111-111111111111',
      dropId: 'd4d1a111-1111-4111-a111-111111111111',
      code: '#A01',
      title: 'Handloom Tussar Saree',
      pricePaisa: 185000,
      imageUrl: 'https://images.livedrop.store/saree.webp',
      size: 'Free Size',
      addedAt: 1726050000000,
    };

    expect(isValidCartItem(validItem)).toBe(true);
  });

  it('rejects invalid or corrupted cart items', () => {
    // Missing productId
    expect(isValidCartItem({ code: '#A01', pricePaisa: 1000 })).toBe(false);

    // Negative price
    expect(
      isValidCartItem({
        productId: 'prod-01',
        dropId: 'drop-01',
        code: '#A01',
        title: 'Item',
        pricePaisa: -500,
        imageUrl: '',
        size: '',
        addedAt: Date.now(),
      })
    ).toBe(false);

    // Floating-point price (prohibited by ADR-009)
    expect(
      isValidCartItem({
        productId: 'prod-01',
        dropId: 'drop-01',
        code: '#A01',
        title: 'Item',
        pricePaisa: 1850.5,
        imageUrl: '',
        size: '',
        addedAt: Date.now(),
      })
    ).toBe(false);

    // NaN or Infinity price
    expect(
      isValidCartItem({
        productId: 'prod-01',
        dropId: 'drop-01',
        code: '#A01',
        title: 'Item',
        pricePaisa: NaN,
        imageUrl: '',
        size: '',
        addedAt: Date.now(),
      })
    ).toBe(false);

    // Null or undefined
    expect(isValidCartItem(null)).toBe(false);
    expect(isValidCartItem(undefined)).toBe(false);
    expect(isValidCartItem('string')).toBe(false);
  });

  it('loads empty cart when localStorage is empty', () => {
    const loaded = loadStoredCart();
    expect(loaded.version).toBe(CURRENT_CART_SCHEMA_VERSION);
    expect(loaded.items).toEqual([]);
    expect(loaded.dropId).toBeNull();
  });

  it('recovers safely from malformed JSON in localStorage without throwing', () => {
    window.localStorage.setItem(CART_STORAGE_KEY, '{ malformed json :: [');
    const loaded = loadStoredCart();
    expect(loaded.version).toBe(CURRENT_CART_SCHEMA_VERSION);
    expect(loaded.items).toEqual([]);
  });

  it('discards incompatible schema versions and resets cleanly', () => {
    window.localStorage.setItem(
      CART_STORAGE_KEY,
      JSON.stringify({
        version: 99, // Unknown future or incompatible version
        dropId: 'drop-01',
        items: [{ productId: 'p1' }],
      })
    );

    const loaded = loadStoredCart();
    expect(loaded.version).toBe(CURRENT_CART_SCHEMA_VERSION);
    expect(loaded.items).toEqual([]);
  });

  it('safely discards corrupted items while preserving valid items', () => {
    const validItem: CartItem = {
      productId: 'prod-valid-1',
      dropId: 'drop-01',
      code: '#A01',
      title: 'Silk Saree',
      pricePaisa: 185000,
      imageUrl: 'https://images.livedrop.store/saree.webp',
      size: 'Free',
      addedAt: Date.now(),
    };

    const payload = {
      version: 1,
      dropId: 'drop-01',
      items: [
        validItem,
        { productId: '', title: 'Missing ID' }, // Corrupt
        { productId: 'prod-corrupt-price', pricePaisa: '1500' }, // Invalid price type
        { productId: 'prod-negative', pricePaisa: -100 }, // Negative price
        null,
      ],
      updatedAt: Date.now(),
    };

    window.localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(payload));
    const loaded = loadStoredCart();

    expect(loaded.items).toHaveLength(1);
    expect(loaded.items[0].productId).toBe('prod-valid-1');
    expect(loaded.items[0].pricePaisa).toBe(185000);
  });

  it('deduplicates duplicate product IDs on load (single-piece invariant)', () => {
    const item1: CartItem = {
      productId: 'prod-dup-1',
      dropId: 'drop-01',
      code: '#A01',
      title: 'Silk Saree',
      pricePaisa: 185000,
      imageUrl: '',
      size: 'Free',
      addedAt: Date.now(),
    };

    const duplicateItem1: CartItem = {
      ...item1,
      addedAt: Date.now() + 1000,
    };

    const item2: CartItem = {
      productId: 'prod-dup-2',
      dropId: 'drop-01',
      code: '#A02',
      title: 'Kurti',
      pricePaisa: 75000,
      imageUrl: '',
      size: 'M',
      addedAt: Date.now(),
    };

    const payload = {
      version: 1,
      dropId: 'drop-01',
      items: [item1, duplicateItem1, item2],
      updatedAt: Date.now(),
    };

    window.localStorage.setItem(CART_STORAGE_KEY, JSON.stringify(payload));
    const loaded = loadStoredCart();

    // Only 2 unique products must exist
    expect(loaded.items).toHaveLength(2);
    expect(loaded.items[0].productId).toBe('prod-dup-1');
    expect(loaded.items[1].productId).toBe('prod-dup-2');
  });

  it('saves and reloads valid cart snapshots', () => {
    const item: CartItem = {
      productId: 'prod-01',
      dropId: 'drop-01',
      code: '#A01',
      title: 'Handloom Saree',
      pricePaisa: 185000,
      imageUrl: 'https://images.livedrop.store/saree.webp',
      size: 'Free Size',
      addedAt: 1726050000000,
    };

    const snapshot: CartStorageSchema = {
      version: 1,
      dropId: 'drop-01',
      items: [item],
      updatedAt: 1726050000000,
    };

    const saved = saveStoredCart(snapshot);
    expect(saved).toBe(true);

    const loaded = loadStoredCart();
    expect(loaded.version).toBe(1);
    expect(loaded.dropId).toBe('drop-01');
    expect(loaded.items).toHaveLength(1);
    expect(loaded.items[0]).toEqual(item);
  });

  it('clears stored cart completely', () => {
    const snapshot: CartStorageSchema = {
      version: 1,
      dropId: 'drop-01',
      items: [
        {
          productId: 'prod-01',
          dropId: 'drop-01',
          code: '#A01',
          title: 'Saree',
          pricePaisa: 185000,
          imageUrl: '',
          size: '',
          addedAt: Date.now(),
        },
      ],
      updatedAt: Date.now(),
    };

    saveStoredCart(snapshot);
    expect(window.localStorage.getItem(CART_STORAGE_KEY)).not.toBeNull();

    clearStoredCart();
    expect(window.localStorage.getItem(CART_STORAGE_KEY)).toBeNull();
  });
});
