/**
 * LiveDrop — which confirmation mode a checkout asks for
 *
 * The server (create_order_with_reservation) accepts 'advance' only when advance confirmation is
 * on for the drop, or else for its seller: COALESCE(drop, seller, false). Otherwise it answers
 * ADVANCE_CONFIRMATION_DISABLED and the buyer could not place the order at all. This mirrors that
 * rule so the request matches the seller's setting.
 */

import type { OrderConfirmationMode, PublicDropCatalog } from '../../types/domain';

/** Mode for the cart's drop, or null when the drop's settings are not loaded yet. */
export function confirmationModeFor(drop: PublicDropCatalog | null): OrderConfirmationMode | null {
  if (!drop) return null;
  const enabled = drop.advance_confirmation_enabled ?? drop.profiles?.advance_confirmation_enabled ?? false;
  return enabled ? 'advance' : 'full_payment';
}

/**
 * Server answers to an 'advance' request after which the same order is placed as a full payment:
 * advance is off for this drop, or the advance would be more than the order total.
 */
export const ADVANCE_FALLBACK_ERRORS: ReadonlySet<string> = new Set([
  'ADVANCE_CONFIRMATION_DISABLED',
  'ADVANCE_EXCEEDS_TOTAL',
]);
