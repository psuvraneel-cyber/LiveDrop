/**
 * LiveDrop — Shipping estimate (display only)
 *
 * Mirrors the authoritative rule in create_order_with_reservation (migration 037,
 * public.resolve_free_shipping_threshold):
 *   free-shipping threshold = drop.free_shipping_threshold_paisa
 *                             ?? seller.free_shipping_threshold_paisa
 *                             ?? none (no free shipping)
 *   shipping fee            = drop.shipping_fee_paisa ?? seller.default_shipping_fee_paisa ?? 8000
 *   shipping                = subtotal >= threshold ? 0 : fee
 *
 * The server always recomputes the amounts at checkout; this module only keeps every screen
 * (drop banner, cart drawer, cart page, checkout review) showing the same promise.
 * All amounts are integer paisa.
 */

/** Fallback fee used by create_order_with_reservation when neither drop nor seller sets one. */
export const FALLBACK_SHIPPING_FEE_PAISA = 8000;

export interface ShippingRuleSource {
  shipping_fee_paisa?: number | null;
  free_shipping_threshold_paisa?: number | null;
  profiles?: {
    default_shipping_fee_paisa?: number | null;
    free_shipping_threshold_paisa?: number | null;
  } | null;
}

export type ShippingEstimate =
  | {
      /** The drop's rules are not loaded: the amount is shown as "calculated at checkout". */
      known: false;
      shippingPaisa: null;
      isFree: false;
      thresholdPaisa: null;
      feePaisa: null;
    }
  | {
      known: true;
      shippingPaisa: number;
      isFree: boolean;
      /** null = this drop has no free-shipping threshold. */
      thresholdPaisa: number | null;
      feePaisa: number;
    };

function asPaisa(value: number | null | undefined): number | null {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
    return null;
  }
  return Math.floor(value);
}

/** Drop threshold, else the seller's shop threshold, else null (no free shipping). */
export function resolveFreeShippingThresholdPaisa(
  drop: ShippingRuleSource | null | undefined
): number | null {
  if (!drop) return null;
  return asPaisa(drop.free_shipping_threshold_paisa) ?? asPaisa(drop.profiles?.free_shipping_threshold_paisa);
}

/** Drop fee, else the seller's default fee, else the server fallback. */
export function resolveShippingFeePaisa(drop: ShippingRuleSource | null | undefined): number {
  return (
    asPaisa(drop?.shipping_fee_paisa) ??
    asPaisa(drop?.profiles?.default_shipping_fee_paisa) ??
    FALLBACK_SHIPPING_FEE_PAISA
  );
}

/**
 * Shipping for a cart. An empty cart ships for free (nothing to ship); an unknown drop yields
 * `known: false` so the UI never invents a threshold.
 */
export function estimateShipping(
  drop: ShippingRuleSource | null | undefined,
  subtotalPaisa: number,
  itemCount: number
): ShippingEstimate {
  if (!drop) {
    return { known: false, shippingPaisa: null, isFree: false, thresholdPaisa: null, feePaisa: null };
  }

  const thresholdPaisa = resolveFreeShippingThresholdPaisa(drop);
  const feePaisa = resolveShippingFeePaisa(drop);
  const subtotal = Math.floor(subtotalPaisa);

  if (itemCount <= 0) {
    return { known: true, shippingPaisa: 0, isFree: false, thresholdPaisa, feePaisa };
  }

  const isFree = feePaisa === 0 || (thresholdPaisa !== null && subtotal >= thresholdPaisa);
  return { known: true, shippingPaisa: isFree ? 0 : feePaisa, isFree, thresholdPaisa, feePaisa };
}
