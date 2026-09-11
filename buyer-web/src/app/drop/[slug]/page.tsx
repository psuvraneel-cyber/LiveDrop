import type { Metadata } from 'next';
import { PublicDropView } from '../../../components/PublicDropView';
import { getLiveDropBySlug } from '../../../lib/data/buyer-catalog';
import { createBuyerClient } from '../../../lib/supabase/client';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;

  try {
    const client = createBuyerClient();
    const drop = await getLiveDropBySlug(client, slug);

    if (drop && drop.title) {
      const storeName = drop.profiles?.store_name || 'LiveDrop';
      return {
        title: `${drop.title} — ${storeName} | LiveDrop`,
        description: `Browse live flash catalog for ${drop.title} by ${storeName} on LiveDrop.`,
      };
    }
  } catch {
    // Fallback if database or client environment is unavailable during static collection
  }

  return {
    title: 'Live Drop Catalog | LiveDrop',
    description: 'Browse live flash sale boutique drops on LiveDrop.',
  };
}

export default async function DropPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;

  return <PublicDropView slug={slug} />;
}
