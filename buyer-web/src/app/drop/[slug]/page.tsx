import type { Metadata } from 'next';
import { PublicDropView, DropViewState } from '../../../components/PublicDropView';
import { getLiveDropBySlug, getPublicProductsForDrop } from '../../../lib/data/buyer-catalog';
import { createBuyerClient } from '../../../lib/supabase/client';
import { PublicDropCatalog, PublicProductView } from '../../../types/domain';

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

  let initialDrop: PublicDropCatalog | null = null;
  let initialProducts: PublicProductView[] = [];
  let initialState: DropViewState = 'loading';
  let initialError: string | null = null;

  try {
    const client = createBuyerClient();
    const drop = await getLiveDropBySlug(client, slug.trim());

    if (!drop) {
      initialState = 'not_found';
    } else if (drop.status !== 'live') {
      initialDrop = drop;
      initialState = 'closed';
    } else {
      initialDrop = drop;
      initialState = 'live';
      initialProducts = await getPublicProductsForDrop(client, drop.id);
    }
  } catch (err) {
    initialError = err instanceof Error ? err.message : String(err);
    initialState = 'error';
  }

  return (
    <PublicDropView
      slug={slug}
      initialDrop={initialDrop}
      initialProducts={initialProducts}
      initialState={initialState}
      initialError={initialError}
    />
  );
}
