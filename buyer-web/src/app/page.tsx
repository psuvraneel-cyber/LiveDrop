import React from 'react';
import { createBuyerClient } from '../lib/supabase/client';
import { getPublicProductsForDrop } from '../lib/data/buyer-catalog';
import { HomeStorefront } from '../components/HomeStorefront';
import { CartProvider } from '../lib/cart/cart-context';
import { PublicDropCatalog, PublicProductView } from '../types/domain';

export default async function Home(): Promise<React.JSX.Element> {
  let liveDrop: PublicDropCatalog | null = null;
  let products: PublicProductView[] = [];
  let recentDrops: PublicDropCatalog[] = [];

  try {
    const client = createBuyerClient();

    // 1. Check for any currently live drop
    const { data: activeDrops } = await client
      .from('drops')
      .select('id, title, slug, status, shipping_fee_paisa, free_shipping_threshold_paisa, live_started_at, profiles(store_name, instagram_handle)')
      .eq('status', 'live')
      .order('live_started_at', { ascending: false })
      .limit(1);

    if (activeDrops && activeDrops.length > 0 && activeDrops[0]) {
      liveDrop = activeDrops[0] as unknown as PublicDropCatalog;
      try {
        products = await getPublicProductsForDrop(client, liveDrop.id);
      } catch {
        // Fallback handled in HomeStorefront
      }
    } else {
      // 2. If no drop is currently live, fetch most recent drops
      const { data: recents } = await client
        .from('drops')
        .select('id, title, slug, status, shipping_fee_paisa, free_shipping_threshold_paisa, created_at, profiles(store_name, instagram_handle)')
        .order('created_at', { ascending: false })
        .limit(3);

      if (recents && recents.length > 0) {
        recentDrops = recents as unknown as PublicDropCatalog[];
        try {
          products = await getPublicProductsForDrop(client, recentDrops[0].id);
        } catch {
          // Fallback handled in HomeStorefront
        }
      }
    }
  } catch {
    // If database is temporarily unreachable, render storefront with fallback boutique pieces
  }

  return (
    <CartProvider>
      <HomeStorefront
        initialLiveDrop={liveDrop}
        initialProducts={products}
        recentDrops={recentDrops}
      />
    </CartProvider>
  );
}
