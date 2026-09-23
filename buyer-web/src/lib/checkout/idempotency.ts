/**
 * LiveDrop Buyer Webfront — Checkout Idempotency Management (ADR-009)
 *
 * Prevents double-charge and double-reservation on network timeouts or mobile retry spam.
 * Generates, maintains, and recovers single-flight idempotency keys per checkout submission session.
 * Keys are persisted in sessionStorage scoped to the active drop ID and cart item signature.
 */

export function generateIdempotencyKey(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `req_chk_${crypto.randomUUID()}`;
  }

  // Cryptographically secure fallback
  const randomBytes = new Uint8Array(16);
  if (typeof crypto !== 'undefined' && typeof crypto.getRandomValues === 'function') {
    crypto.getRandomValues(randomBytes);
  } else {
    for (let i = 0; i < 16; i++) {
      randomBytes[i] = Math.floor(Math.random() * 256);
    }
  }

  // Format as standard UUID
  randomBytes[6] = (randomBytes[6] & 0x0f) | 0x40;
  randomBytes[8] = (randomBytes[8] & 0x3f) | 0x80;

  const hex = Array.from(randomBytes)
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  const uuid = `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}`;
  return `req_chk_${uuid}`;
}

export function getCartSignature(dropId: string, productIds: string[]): string {
  const sorted = [...productIds].sort().join(',');
  return `${dropId}:${sorted}`;
}

/**
 * Retrieves the existing idempotency key from sessionStorage if the cart signature
 * matches (dropId + sorted product IDs), or generates and caches a fresh key.
 * This guarantees resilience against browser reloads and network retries.
 */
export function getOrCreateCheckoutIdempotencyKey(dropId: string, productIds: string[]): string {
  if (!dropId || productIds.length === 0) {
    return generateIdempotencyKey();
  }

  if (typeof window === 'undefined' || !window.sessionStorage) {
    return generateIdempotencyKey();
  }

  try {
    const signature = getCartSignature(dropId, productIds);
    const storageKey = `livedrop_chk_idemp_${dropId}`;
    const raw = window.sessionStorage.getItem(storageKey);
    if (raw) {
      const parsed = JSON.parse(raw);
      if (parsed.signature === signature && typeof parsed.idempotencyKey === 'string') {
        return parsed.idempotencyKey;
      }
    }

    const newKey = generateIdempotencyKey();
    window.sessionStorage.setItem(
      storageKey,
      JSON.stringify({ signature, idempotencyKey: newKey, createdAt: Date.now() })
    );
    return newKey;
  } catch {
    return generateIdempotencyKey();
  }
}

/**
 * Clears the cached idempotency key for the given drop upon successful reservation.
 */
export function clearCheckoutIdempotencyKey(dropId: string): void {
  if (!dropId || typeof window === 'undefined' || !window.sessionStorage) {
    return;
  }
  try {
    const storageKey = `livedrop_chk_idemp_${dropId}`;
    window.sessionStorage.removeItem(storageKey);
  } catch {
    // Ignore storage errors in restricted browser contexts
  }
}
