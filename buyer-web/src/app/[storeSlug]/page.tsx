import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { createBuyerClient } from '../../lib/supabase/client';
import { getStorefrontBySlug, getStorefrontData } from '../../lib/data/buyer-catalog';
import { CartProvider } from '../../lib/cart/cart-context';
import { BoutiqueStorefrontView } from '../../components/BoutiqueStorefrontView';

export const dynamic = 'force-dynamic';
export const revalidate = 0;

export async function generateMetadata({
  params,
}: {
  params: Promise<{ storeSlug: string }>;
}): Promise<Metadata> {
  const { storeSlug } = await params;

  try {
    const client = createBuyerClient();
    const storefront = await getStorefrontBySlug(client, storeSlug.trim());

    if (storefront) {
      return {
        title: `${storefront.store_name} | LiveDrop Boutique`,
        description: `Shop exclusive collections and live streaming drops from ${storefront.store_name} on LiveDrop.`,
      };
    }
  } catch {
    // Fallback if database or client environment is unavailable during static collection
  }

  return {
    title: 'Boutique Storefront | LiveDrop',
    description: 'Exclusive Indian boutique fashion on LiveDrop.',
  };
}

export default async function BoutiqueStorefrontPage({
  params,
}: {
  params: Promise<{ storeSlug: string }>;
}) {
  const { storeSlug } = await params;

  const client = createBuyerClient();
  const data = await getStorefrontData(client, storeSlug.trim());

  if (!data) {
    notFound();
  }

  return (
    <CartProvider>
      <BoutiqueStorefrontView
        storefront={data.storefront}
        activeLiveDrop={data.activeLiveDrop}
        liveProducts={data.liveProducts}
        pastDropsWithProducts={data.pastDropsWithProducts}
      />
    </CartProvider>
  );
}
