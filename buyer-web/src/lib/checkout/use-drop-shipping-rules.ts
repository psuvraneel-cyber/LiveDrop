'use client';

/**
 * LiveDrop — shipping rules for the cart's drop (display only)
 *
 * Returns the cart's live drop with its seller's public shipping settings, so the cart and
 * checkout screens can show the same shipping rule the server applies (see ./shipping.ts).
 * Uses the drop already loaded by the drop page when it matches; otherwise loads it by id.
 * Returns null while loading, when the drop is no longer live, or on network errors — callers
 * then show shipping as "calculated at checkout".
 */

import { useEffect, useState } from 'react';
import { useOptionalCart } from '../cart/cart-context';
import { getBuyerClient } from '../supabase/client';
import { getLiveDropById } from '../data/buyer-catalog';
import { PublicDropCatalog } from '../../types/domain';

export function useDropShippingRules(dropId: string | null): PublicDropCatalog | null {
  const cart = useOptionalCart();
  const activeDrop = cart?.activeDrop ?? null;
  const matchingActiveDrop = activeDrop && dropId && activeDrop.id === dropId ? activeDrop : null;
  const [fetched, setFetched] = useState<{ id: string; drop: PublicDropCatalog | null } | null>(null);

  useEffect(() => {
    if (!dropId || matchingActiveDrop) return;
    let active = true;

    const load = async () => {
      let drop: PublicDropCatalog | null = null;
      try {
        drop = await getLiveDropById(getBuyerClient(), dropId);
      } catch {
        drop = null;
      }
      if (active) {
        setFetched({ id: dropId, drop });
      }
    };
    void load();

    return () => {
      active = false;
    };
  }, [dropId, matchingActiveDrop]);

  if (matchingActiveDrop) return matchingActiveDrop;
  return fetched && fetched.id === dropId ? fetched.drop : null;
}
