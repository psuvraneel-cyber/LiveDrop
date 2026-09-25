import { createRequire } from 'node:module';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const require = createRequire(path.resolve(__dirname, '../buyer-web/package.json'));
const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://aoagqdtnrbmayfoajzes.supabase.co';
const ANON_KEY = 'sb_publishable_7jbVHNR-o2ZTQZJzapUctg_uHil0B15';

const SELLER_EMAIL = 'september@gmail.com';
const SELLER_PASSWORD = 'LiveDropSeller2026!';

const GARMENT_IMAGES = [
  {
    code: '#A01',
    title: 'Banarasi Katan Silk Saree',
    price_paisa: 245000, // ₹2,450
    size: 'Free Size',
    source_url: 'https://images.unsplash.com/photo-1610030469983-98e550d6193c?auto=format&fit=crop&w=800&q=80',
    file_name: 'banarasi_katan_silk_saree.jpg'
  },
  {
    code: '#A02',
    title: 'Chanderi Cotton Kurti Set',
    price_paisa: 165000, // ₹1,650
    size: 'M',
    source_url: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b?auto=format&fit=crop&w=800&q=80',
    file_name: 'chanderi_cotton_kurti_set.jpg'
  },
  {
    code: '#A03',
    title: 'Handloom Tussar Silk Saree',
    price_paisa: 310000, // ₹3,100
    size: 'Free Size',
    source_url: 'https://images.unsplash.com/photo-1617627143750-d86bc21e42bb?auto=format&fit=crop&w=800&q=80',
    file_name: 'handloom_tussar_silk_saree.jpg'
  },
  {
    code: '#A04',
    title: 'Zari Embroidered Georgette Dupatta',
    price_paisa: 85000, // ₹850
    size: 'Free Size',
    source_url: 'https://images.unsplash.com/photo-1546804784-896d0dca3805?auto=format&fit=crop&w=800&q=80',
    file_name: 'zari_embroidered_georgette_dupatta.jpg'
  }
];

async function main() {
  console.log('================================================================');
  console.log('🛍️  LiveDrop Staging Ingestion & Verification');
  console.log('================================================================');

  const client = createClient(SUPABASE_URL, ANON_KEY);

  // 1. Authenticate as approved seller
  console.log('1. Authenticating as seller:', SELLER_EMAIL);
  const { data: authData, error: authError } = await client.auth.signInWithPassword({
    email: SELLER_EMAIL,
    password: SELLER_PASSWORD,
  });

  if (authError || !authData.session) {
    throw new Error(`Authentication failed: ${authError?.message}`);
  }

  const sellerId = authData.user.id;
  console.log('   ✓ Authenticated seller UID:', sellerId);

  // 2. Check for existing drops for this seller
  const { data: existingDrops } = await client
    .from('drops')
    .select('id, title, slug, status')
    .eq('seller_id', sellerId);

  let dropId;
  const liveOrExisting = existingDrops?.find(d => d.slug === 'festive-silk-handloom-collection');

  if (liveOrExisting) {
    dropId = liveOrExisting.id;
    console.log('2. Reusing existing drop:', dropId, 'Status:', liveOrExisting.status);
    // If not live, ensure it is set to live
    if (liveOrExisting.status !== 'live') {
      await client
        .from('drops')
        .update({ status: 'live', live_started_at: new Date().toISOString() })
        .eq('id', dropId);
      console.log('   ✓ Transitioned drop to live');
    }
  } else {
    console.log('2. Creating new drop: "Festive Silk & Handloom Collection"');
    const { data: newDrop, error: dropError } = await client
      .from('drops')
      .insert({
        seller_id: sellerId,
        title: 'Festive Silk & Handloom Collection',
        slug: 'festive-silk-handloom-collection',
        status: 'draft',
        shipping_fee_paisa: 8000,
        free_shipping_threshold_paisa: 200000,
        advance_confirmation_enabled: false,
        advance_amount_paisa: 25000,
        hold_duration_days: 30
      })
      .select()
      .single();

    if (dropError) {
      throw new Error(`Failed to create drop: ${dropError.message}`);
    }
    dropId = newDrop.id;
    console.log('   ✓ Created drop ID:', dropId);
  }

  // 3. Download and upload each garment image to Supabase Storage
  console.log('3. Uploading product images to Supabase Storage bucket: product-images');
  const uploadedProducts = [];

  for (const item of GARMENT_IMAGES) {
    console.log(`   - Processing ${item.code}: ${item.title}...`);
    const resp = await fetch(item.source_url);
    if (!resp.ok) {
      throw new Error(`Failed to fetch image source: ${resp.status} ${item.source_url}`);
    }
    const arrayBuffer = await resp.arrayBuffer();
    const buffer = Buffer.from(arrayBuffer);

    const storagePath = `${sellerId}/${dropId}/${item.file_name}`;

    const { error: uploadError } = await client.storage
      .from('product-images')
      .upload(storagePath, buffer, {
        contentType: 'image/jpeg',
        upsert: true
      });

    if (uploadError) {
      throw new Error(`Storage upload failed for ${storagePath}: ${uploadError.message}`);
    }

    const { data: { publicUrl } } = client.storage
      .from('product-images')
      .getPublicUrl(storagePath);

    console.log(`     ✓ Uploaded to: ${publicUrl}`);

    uploadedProducts.push({
      ...item,
      image_url: publicUrl
    });
  }

  // 4. Upsert products into database
  console.log('4. Upserting products into public.products table');
  for (const prod of uploadedProducts) {
    // Check if product exists by drop_id and code
    const { data: existing } = await client
      .from('products')
      .select('id')
      .eq('drop_id', dropId)
      .eq('code', prod.code)
      .maybeSingle();

    if (existing) {
      const { error: updateError } = await client
        .from('products')
        .update({
          title: prod.title,
          price_paisa: prod.price_paisa,
          size: prod.size,
          image_url: prod.image_url,
          image_urls: [prod.image_url],
          status: 'available'
        })
        .eq('id', existing.id);

      if (updateError) throw new Error(`Product update failed: ${updateError.message}`);
      console.log(`   ✓ Updated ${prod.code}: ${prod.title}`);
    } else {
      const { error: insertError } = await client
        .from('products')
        .insert({
          drop_id: dropId,
          code: prod.code,
          title: prod.title,
          price_paisa: prod.price_paisa,
          size: prod.size,
          image_url: prod.image_url,
          image_urls: [prod.image_url],
          status: 'available'
        });

      if (insertError) throw new Error(`Product insert failed: ${insertError.message}`);
      console.log(`   ✓ Inserted ${prod.code}: ${prod.title}`);
    }
  }

  // 5. Publish drop to live
  console.log('5. Publishing drop status to live');
  const { error: publishError } = await client
    .from('drops')
    .update({
      status: 'live',
      live_started_at: new Date().toISOString()
    })
    .eq('id', dropId);

  if (publishError) {
    throw new Error(`Failed to publish drop to live: ${publishError.message}`);
  }
  console.log('   ✓ Drop is now LIVE');

  // 6. Anonymous Buyer Verification
  console.log('6. Verifying public buyer visibility as unauthenticated user');
  const anonClient = createClient(SUPABASE_URL, ANON_KEY);
  const { data: publicCatalog, error: catalogError } = await anonClient
    .from('public_products_catalog')
    .select('id, code, title, price_paisa, status, drop_title, drop_slug, image_url')
    .eq('drop_id', dropId);

  if (catalogError) {
    throw new Error(`Anonymous query failed: ${catalogError.message}`);
  }

  console.log(`   ✓ Anonymous catalog returned ${publicCatalog?.length || 0} products:`);
  for (const p of publicCatalog || []) {
    console.log(`     - [${p.code}] ${p.title} | ₹${p.price_paisa / 100} | ${p.status} | ${p.image_url.slice(0, 70)}...`);
  }

  console.log('================================================================');
  console.log('🎉 Staging ingestion & verification COMPLETE!');
  console.log('================================================================');
}

main().catch((err) => {
  console.error('❌ Ingestion failed:', err);
  process.exit(1);
});
