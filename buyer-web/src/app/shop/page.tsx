import type { Metadata } from 'next';
import { createBuyerClient } from '../../lib/supabase/client';
import { getAllVerifiedStorefronts } from '../../lib/data/buyer-catalog';
import { ShopCategoryDirectory } from '../../components/shop/ShopCategoryDirectory';
import { PublicSellerStorefront } from '../../types/domain';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export const metadata: Metadata = {
  title: 'Shop Indian Luxury Couture | LiveDrop',
  description: 'Explore curated handcrafted sarees, lehengas, jewelry, and couture from verified independent boutiques on LiveDrop.',
};

export default async function ShopPage() {
  let storefronts: PublicSellerStorefront[] = [];

  try {
    const client = createBuyerClient();
    storefronts = await getAllVerifiedStorefronts(client);
  } catch {
    storefronts = [];
  }

  return <ShopCategoryDirectory storefronts={storefronts} />;
}
