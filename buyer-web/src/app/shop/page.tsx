import type { Metadata } from 'next';
import { createBuyerClient } from '../../lib/supabase/client';
import { getAllVerifiedStorefronts, getAllProducts } from '../../lib/data/buyer-catalog';
import { ShopCategoryDirectory } from '../../components/shop/ShopCategoryDirectory';
import { PublicProductView, PublicSellerStorefront } from '../../types/domain';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export const metadata: Metadata = {
  title: 'Shop Boutique Fashion | LiveDrop',
  description: 'Explore handcrafted sarees, kurtis, lehengas, jewelry, and couture direct from independent Indian boutiques on LiveDrop.',
};

export default async function ShopPage() {
  let storefronts: PublicSellerStorefront[] = [];
  let products: PublicProductView[] = [];

  try {
    const client = createBuyerClient();
    const [sfData, prodData] = await Promise.all([
      getAllVerifiedStorefronts(client),
      getAllProducts(client, { limit: 80 }),
    ]);
    storefronts = sfData;
    products = prodData;
  } catch {
    storefronts = [];
    products = [];
  }

  return <ShopCategoryDirectory storefronts={storefronts} initialProducts={products} />;
}

