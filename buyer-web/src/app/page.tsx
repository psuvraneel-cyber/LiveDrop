import React from 'react';
import { createBuyerClient } from '../lib/supabase/client';
import { getAllActiveLiveDrops, getAllVerifiedStorefronts, getFeaturedProducts } from '../lib/data/buyer-catalog';
import { HomeStorefront } from '../components/HomeStorefront';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export default async function Home(): Promise<React.JSX.Element> {
  const client = createBuyerClient();
  const [activeDrops, storefronts, featuredProducts] = await Promise.all([
    getAllActiveLiveDrops(client).catch(() => []),
    getAllVerifiedStorefronts(client).catch(() => []),
    getFeaturedProducts(client, 12).catch(() => []),
  ]);

  return (
    <HomeStorefront
      activeDrops={activeDrops}
      storefronts={storefronts}
      featuredProducts={featuredProducts}
    />
  );
}

