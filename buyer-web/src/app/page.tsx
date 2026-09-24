import React from 'react';
import { createBuyerClient } from '../lib/supabase/client';
import { getAllActiveLiveDrops, getAllVerifiedStorefronts } from '../lib/data/buyer-catalog';
import { HomeStorefront } from '../components/HomeStorefront';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export default async function Home(): Promise<React.JSX.Element> {
  const client = createBuyerClient();
  const [activeDrops, storefronts] = await Promise.all([
    getAllActiveLiveDrops(client).catch(() => []),
    getAllVerifiedStorefronts(client).catch(() => []),
  ]);

  return (
    <HomeStorefront
      activeDrops={activeDrops}
      storefronts={storefronts}
    />
  );
}
