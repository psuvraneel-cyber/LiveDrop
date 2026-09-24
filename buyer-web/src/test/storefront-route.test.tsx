import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { PGlite } from '@electric-sql/pglite';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { BoutiqueStorefrontView, formatWhatsAppUrl } from '../components/BoutiqueStorefrontView';
import { HomeStorefront } from '../components/HomeStorefront';
import { CartProvider } from '../lib/cart/cart-context';
import { getStorefrontBySlug } from '../lib/data/buyer-catalog';
import { PublicSellerStorefront, PublicDropCatalog, PublicProductView } from '../types/domain';

describe('LiveDrop Storefront Architecture & Showcase Mode', () => {
  describe('Database & Migration 031 Verifications (PGlite)', () => {
    let db: PGlite;
    const migrationsDir = path.resolve(__dirname, '../../../supabase/migrations');

    const sellerId = 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11';
    const liveDropId = 'd1000000-0000-0000-0000-000000000001';
    const closedDropId = 'd2000000-0000-0000-0000-000000000002';
    const draftDropId = 'd3000000-0000-0000-0000-000000000003';

    beforeAll(async () => {
      db = new PGlite();

      // Setup auth schema mock
      await db.exec(`
        CREATE SCHEMA IF NOT EXISTS auth;
        CREATE TABLE IF NOT EXISTS auth.users (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          email TEXT UNIQUE,
          created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        );

        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
            CREATE ROLE anon NOLOGIN;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
            CREATE ROLE authenticated NOLOGIN;
          END IF;
          IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
            CREATE ROLE service_role NOLOGIN;
          END IF;
        END $$;

        CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
        LANGUAGE sql STABLE
        AS $$
          SELECT coalesce(
            nullif(current_setting('request.jwt.claim.sub', true), ''),
            (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
          )::uuid
        $$;
      `);

      // Apply migrations
      const migrationFiles = [
        '001_create_profiles.sql',
        '002_create_drops.sql',
        '003_create_products.sql',
        '004_create_orders.sql',
        '005_create_order_items.sql',
        '006_create_indexes.sql',
        '007_create_triggers.sql',
        '008_enable_rls_and_policies.sql',
        '010_seller_storefront_and_order_state_machine.sql',
        '013_direct_upi_and_manual_payment_verification.sql',
        '016_public_projection_views.sql',
        '029_add_image_urls_to_public_products_catalog.sql',
        '031_seller_storefronts_and_catalog_showcase.sql',
      ];

      for (const file of migrationFiles) {
        if (file === '029_add_image_urls_to_public_products_catalog.sql') {
          await db.exec(`ALTER TABLE products ADD COLUMN IF NOT EXISTS image_urls TEXT[] NOT NULL DEFAULT '{}';`);
        }
        const filePath = path.join(migrationsDir, file);
        const sql = fs.readFileSync(filePath, 'utf-8');
        await db.exec(sql);
      }

      // Seed approved seller
      await db.exec(`
        INSERT INTO auth.users (id, email) VALUES ('${sellerId}', 'suv@livedrop.in');
        INSERT INTO profiles (
          id, store_name, store_slug, phone_number, upi_id, upi_vpa, return_address, default_shipping_fee_paisa, is_approved
        ) VALUES (
          '${sellerId}', 'Suv Boutique', 'suv-s', '9830123456', 'suv@okaxis', 'suv@okaxis', 'Kolkata Studio, West Bengal', 8000, true
        );
      `);

      // Seed unapproved seller (must remain hidden from public projections per SEC-01)
      const unapprovedSellerId = 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380b22';
      const unapprovedDropId = 'd4000000-0000-0000-0000-000000000004';
      await db.exec(`
        INSERT INTO auth.users (id, email) VALUES ('${unapprovedSellerId}', 'fake@scam.in');
        INSERT INTO profiles (
          id, store_name, store_slug, phone_number, upi_id, upi_vpa, return_address, default_shipping_fee_paisa, is_approved
        ) VALUES (
          '${unapprovedSellerId}', 'Unapproved Boutique', 'unapproved-b', '9830999999', 'scam@upi', 'scam@upi', 'Fake Address, Delhi', 8000, false
        );
        INSERT INTO drops (id, seller_id, title, slug, status) VALUES
          ('${unapprovedDropId}', '${unapprovedSellerId}', 'Unapproved Live Drop', 'unapproved-live', 'live');
        INSERT INTO products (id, drop_id, code, title, price_paisa, size, status, image_url) VALUES
          ('ca000000-0000-0000-0000-000000000099', '${unapprovedDropId}', '#U01', 'Fake Piece', 50000, 'Free Size', 'available', 'https://example.com/u01.jpg');
      `);

      // Seed drops: live, closed, and draft
      await db.exec(`
        INSERT INTO drops (id, seller_id, title, slug, status) VALUES
          ('${liveDropId}', '${sellerId}', 'Festive Edit Live', 'festive-edit', 'live'),
          ('${closedDropId}', '${sellerId}', 'Heritage Silks Past', 'heritage-silks', 'closed'),
          ('${draftDropId}', '${sellerId}', 'Secret Draft Drop', 'secret-draft', 'draft');
      `);

      // Seed products:
      // Live drop has available and sold items
      // Closed drop has available and sold items
      // Draft drop has items
      await db.exec(`
        INSERT INTO products (id, drop_id, code, title, price_paisa, size, status, image_url) VALUES
          ('ca000000-0000-0000-0000-000000000001', '${liveDropId}', '#L01', 'Live Silk Saree', 185000, 'Free Size', 'available', 'https://example.com/l01.jpg'),
          ('ca000000-0000-0000-0000-000000000002', '${liveDropId}', '#L02', 'Live Sold Kurti', 125000, 'M', 'sold', 'https://example.com/l02.jpg'),
          ('ca000000-0000-0000-0000-000000000003', '${closedDropId}', '#C01', 'Archived Banarasi', 220000, 'Free Size', 'available', 'https://example.com/c01.jpg'),
          ('ca000000-0000-0000-0000-000000000004', '${closedDropId}', '#C02', 'Archived Sold Dupatta', 75000, 'Free Size', 'sold', 'https://example.com/c02.jpg'),
          ('ca000000-0000-0000-0000-000000000005', '${draftDropId}', '#D01', 'Draft Secret Saree', 300000, 'Free Size', 'available', 'https://example.com/d01.jpg');
      `);
    });

    afterAll(async () => {
      if (db) await db.close();
    });

    it('exposes phone_number and created_at in public_seller_storefronts view for approved sellers', async () => {
      const res = await db.query<{ phone_number: string; store_slug: string }>(`
        SELECT store_name, store_slug, phone_number, created_at FROM public_seller_storefronts WHERE store_slug = 'suv-s';
      `);
      expect(res.rows.length).toBe(1);
      expect(res.rows[0].phone_number).toBe('9830123456');
      expect(res.rows[0].store_slug).toBe('suv-s');
    });

    it('strictly hides unapproved sellers from public_seller_storefronts view (SEC-01)', async () => {
      const res = await db.query<{ store_slug: string }>(`
        SELECT store_slug FROM public_seller_storefronts WHERE store_slug = 'unapproved-b';
      `);
      expect(res.rows.length).toBe(0);
    });

    it('allows anonymous users to read live and closed drops for approved sellers, but strictly blocks draft drops', async () => {
      await db.exec(`SET ROLE anon;`);
      const res = await db.query<{ id: string; status: string }>(`
        SELECT id, status FROM drops ORDER BY status;
      `);
      const statuses = res.rows.map((r) => r.status);
      expect(statuses).toContain('live');
      expect(statuses).toContain('closed');
      expect(statuses).not.toContain('draft');
      // Unapproved seller's drop must not be readable
      const ids = res.rows.map((r) => r.id);
      expect(ids).not.toContain('d4000000-0000-0000-0000-000000000004');
      await db.exec(`RESET ROLE;`);
    });

    it('public_products_catalog projects all live drop products and ONLY available items for closed drops of approved sellers', async () => {
      await db.exec(`SET ROLE anon;`);
      const res = await db.query<{ code: string; status: string; drop_status: string }>(`
        SELECT code, status, drop_status FROM public_products_catalog ORDER BY code;
      `);
      const codes = res.rows.map((r) => r.code);
      // Live drop shows available and sold items
      expect(codes).toContain('#L01');
      expect(codes).toContain('#L02');
      // Closed drop shows only available items, excludes sold items
      expect(codes).toContain('#C01');
      expect(codes).not.toContain('#C02');
      // Draft drop items must never appear
      expect(codes).not.toContain('#D01');
      // Unapproved seller's items must never appear
      expect(codes).not.toContain('#U01');
      await db.exec(`RESET ROLE;`);
    });
  });

  describe('WhatsApp Inquiry Link Formatting', () => {
    const dummyProduct: PublicProductView = {
      id: 'p1',
      code: '#A10',
      title: 'Zari Kanjivaram Saree',
      price_paisa: 285000,
      size: 'Free Size',
      image_url: 'https://example.com/saree.jpg',
      status: 'available',
      reserved_at: null,
      version: 1,
    };

    it('formats 10-digit Indian phone numbers with country code 91', () => {
      const url = formatWhatsAppUrl('9830012345', 'Suv Boutique', dummyProduct, 'suv-s');
      expect(url).toContain('https://wa.me/919830012345?text=');
      expect(url).toContain(encodeURIComponent('Hi Suv Boutique'));
      expect(url).toContain(encodeURIComponent('#A10'));
      expect(url).toContain(encodeURIComponent('₹2,850'));
      expect(url).toContain(encodeURIComponent('/suv-s'));
    });

    it('handles phone numbers already formatted with 91 prefix without duplicating 91', () => {
      const url = formatWhatsAppUrl('919830012345', 'Suv Boutique', dummyProduct, 'suv-s');
      expect(url).toContain('https://wa.me/919830012345?text=');
      expect(url).not.toContain('9191');
    });

    it('handles phone numbers with trunk 0 (e.g. 09830012345) and strips leading 0', () => {
      const url = formatWhatsAppUrl('09830012345', 'Suv Boutique', dummyProduct, 'suv-s');
      expect(url).toContain('https://wa.me/919830012345?text=');
      expect(url).not.toContain('wa.me/0983');
    });

    it('handles formatted numbers with plus and spaces (+91 98300 12345)', () => {
      const url = formatWhatsAppUrl('+91 98300 12345', 'Suv Boutique', dummyProduct, 'suv-s');
      expect(url).toContain('https://wa.me/919830012345?text=');
    });

    it('falls back to generic wa.me link if phone number is absent', () => {
      const url = formatWhatsAppUrl(null, 'Suv Boutique', dummyProduct, 'suv-s');
      expect(url).toContain('https://wa.me/?text=');
    });
  });

  describe('BoutiqueStorefrontView Component Tests', () => {
    const mockStorefront: PublicSellerStorefront = {
      id: 's1',
      store_name: "Suv's",
      store_slug: 'suv-s',
      phone_number: '9830123456',
      upi_id: 'suv@okaxis',
      upi_qr_url: null,
      default_shipping_fee_paisa: 8000,
      free_shipping_threshold_paisa: 200000,
      advance_confirmation_enabled: true,
      advance_amount_paisa: 25000,
      hold_duration_days: 7,
    };

    const mockLiveDrop: PublicDropCatalog = {
      id: 'd-live',
      seller_id: 's1',
      title: 'Midnight Silk Flash Drop',
      slug: 'midnight-silk',
      status: 'live',
      shipping_fee_paisa: 8000,
      free_shipping_threshold_paisa: 200000,
      live_started_at: new Date().toISOString(),
      closed_at: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      profiles: {
        store_name: "Suv's",
        store_slug: 'suv-s',
        upi_id: 'suv@okaxis',
        upi_qr_url: null,
        default_shipping_fee_paisa: 8000,
        free_shipping_threshold_paisa: 200000,
        advance_confirmation_enabled: true,
        advance_amount_paisa: 25000,
        hold_duration_days: 7,
      },
    };

    const mockLiveProducts: PublicProductView[] = [
      {
        id: 'p-live-1',
        code: '#M01',
        title: 'Midnight Mulberry Silk',
        price_paisa: 215000,
        size: 'Free Size',
        image_url: 'https://example.com/live.jpg',
        status: 'available',
        reserved_at: null,
        version: 1,
      },
    ];

    it('renders Active Live Drop mode with live flash sale banner and products', () => {
      render(
        <CartProvider>
          <BoutiqueStorefrontView
            storefront={mockStorefront}
            activeLiveDrop={mockLiveDrop}
            liveProducts={mockLiveProducts}
            pastDropsWithProducts={[]}
          />
        </CartProvider>
      );

      expect(screen.getByTestId('live-drop-pill')).toHaveTextContent('LIVE FLASH SALE NOW');
      expect(screen.getByTestId('storefront-title')).toHaveTextContent("Suv's");
      expect(screen.getByText('Midnight Silk Flash Drop')).toBeInTheDocument();
      expect(screen.getByText('Midnight Mulberry Silk')).toBeInTheDocument();
      expect(screen.getByTestId('storefront-cart-btn')).toBeInTheDocument();
    });

    it('renders Showcase Lookbook mode when boutique has no active live drop', () => {
      const pastDrops = [
        {
          drop: {
            id: 'd-closed-1',
            title: 'Summer Heritage Archive',
            slug: 'summer-heritage',
            status: 'closed' as const,
            created_at: '2026-08-01T00:00:00Z',
            closed_at: '2026-08-01T02:00:00Z',
          },
          products: [
            {
              id: 'p-archive-1',
              code: '#S01',
              title: 'Handloom Jamdani Cotton',
              price_paisa: 165000,
              size: 'Free Size',
              image_url: 'https://example.com/jamdani.jpg',
              status: 'available' as const,
              reserved_at: null,
              version: 1,
            },
          ],
        },
      ];

      render(
        <CartProvider>
          <BoutiqueStorefrontView
            storefront={mockStorefront}
            activeLiveDrop={null}
            liveProducts={[]}
            pastDropsWithProducts={pastDrops}
          />
        </CartProvider>
      );

      // Verify offline showcase pill
      expect(screen.getByTestId('offline-showcase-pill')).toHaveTextContent('NEXT LIVE DROP SOON');
      expect(screen.getByTestId('storefront-title')).toHaveTextContent("Suv's");
      // Instant checkout cart button should NOT be rendered when no live drop is active
      expect(screen.queryByTestId('storefront-cart-btn')).not.toBeInTheDocument();
      // Collection title and product
      expect(screen.getByText('Summer Heritage Archive')).toBeInTheDocument();
      expect(screen.getByText('Handloom Jamdani Cotton')).toBeInTheDocument();
      expect(screen.getByText('₹1,650')).toBeInTheDocument();
      // WhatsApp inquiry action
      const inquireBtn = screen.getByTestId('whatsapp-inquire-btn-#S01');
      expect(inquireBtn).toBeInTheDocument();
      expect(inquireBtn).toHaveAttribute('href', expect.stringContaining('wa.me/919830123456'));
    });

    it('renders empty boutique state when boutique has no past collections', () => {
      render(
        <CartProvider>
          <BoutiqueStorefrontView
            storefront={mockStorefront}
            activeLiveDrop={null}
            liveProducts={[]}
            pastDropsWithProducts={[]}
          />
        </CartProvider>
      );

      expect(screen.getByTestId('empty-showcase')).toBeInTheDocument();
      expect(screen.getByText('No Previous Collections Listed')).toBeInTheDocument();
    });
  });

  describe('Platform Directory Homepage Tests', () => {
    const mockStorefronts: PublicSellerStorefront[] = [
      {
        id: 's1',
        store_name: "Suv's",
        store_slug: 'suv-s',
        phone_number: '9830123456',
        upi_id: 'suv@okaxis',
        upi_qr_url: null,
        default_shipping_fee_paisa: 8000,
        free_shipping_threshold_paisa: null,
        advance_confirmation_enabled: false,
        advance_amount_paisa: 0,
        hold_duration_days: 2,
      },
      {
        id: 's2',
        store_name: 'Anita Silks',
        store_slug: 'anita-silks',
        phone_number: '9876543210',
        upi_id: 'anita@upi',
        upi_qr_url: null,
        default_shipping_fee_paisa: 10000,
        free_shipping_threshold_paisa: 300000,
        advance_confirmation_enabled: true,
        advance_amount_paisa: 30000,
        hold_duration_days: 5,
      },
    ];

    it('renders multi-boutique directory with verified boutiques and no mock sarees', () => {
      render(
        <HomeStorefront
          activeDrops={[]}
          storefronts={mockStorefronts}
        />
      );

      // Verify platform header & directory
      expect(screen.getByTestId('boutiques-directory-section')).toBeInTheDocument();
      expect(screen.getByText("Suv's")).toBeInTheDocument();
      expect(screen.getByText('Anita Silks')).toBeInTheDocument();
      expect(screen.getByTestId('visit-boutique-suv-s')).toHaveAttribute('href', '/suv-s');
      expect(screen.getByTestId('visit-boutique-anita-silks')).toHaveAttribute('href', '/anita-silks');

      // CRITICAL: Ensure zero mock sarees or fake timers are rendered
      expect(screen.queryByText('Banarasi Silk Saree')).not.toBeInTheDocument();
      expect(screen.queryByText('Chikankari Kurti')).not.toBeInTheDocument();
      expect(screen.queryByText('Drop Ends In')).not.toBeInTheDocument();
    });

    it('filters boutique directory using search input', () => {
      render(
        <HomeStorefront
          activeDrops={[]}
          storefronts={mockStorefronts}
        />
      );

      const searchInput = screen.getByTestId('platform-search-input');
      fireEvent.change(searchInput, { target: { value: 'Anita' } });

      expect(screen.getByText('Anita Silks')).toBeInTheDocument();
      expect(screen.queryByText("Suv's")).not.toBeInTheDocument();
    });
  });

  describe('Store Slug Normalization & Resolution', () => {
    it('normalizes uppercase, slashes, and whitespace in getStorefrontBySlug', async () => {
      let queriedSlug = '';
      const mockClient = {
        from: () => ({
          select: () => ({
            eq: (_col: string, val: string) => {
              queriedSlug = val;
              return {
                maybeSingle: async () => ({
                  data: {
                    id: 's1',
                    store_name: "Suv's",
                    store_slug: val,
                    phone_number: '9830123456',
                    upi_vpa: 'suv@okaxis',
                  },
                  error: null,
                }),
              };
            },
          }),
        }),
      } as unknown as import('@supabase/supabase-js').SupabaseClient;

      // 1. Mixed case with slashes
      const res1 = await getStorefrontBySlug(mockClient, '/Suv-S/');
      expect(queriedSlug).toBe('suv-s');
      expect(res1?.store_slug).toBe('suv-s');

      // 2. Whitespace surrounding
      const res2 = await getStorefrontBySlug(mockClient, '  suv-s  ');
      expect(queriedSlug).toBe('suv-s');
      expect(res2?.store_slug).toBe('suv-s');

      // 3. Empty or slash only
      const res3 = await getStorefrontBySlug(mockClient, '///');
      expect(res3).toBeNull();
    });
  });

  describe('Showcase Multi-Photo Fallback & Badge Tests', () => {
    it('renders primary image from image_urls[0] when image_url is null and shows photo count badge', () => {
      const pastDropsWithMultiPhotos = [
        {
          drop: {
            id: 'd-arch-2',
            title: 'Kanjivaram Edition',
            slug: 'kanjivaram-edition',
            status: 'closed' as const,
            created_at: '2026-08-01T00:00:00Z',
            closed_at: '2026-08-01T02:00:00Z',
          },
          products: [
            {
              id: 'p-multi-1',
              code: '#K01',
              title: 'Pure Zari Brocade',
              price_paisa: 350000,
              size: 'Free Size',
              image_url: '',
              image_urls: ['https://example.com/multi1.jpg', 'https://example.com/multi2.jpg', 'https://example.com/multi3.jpg'],
              status: 'available' as const,
              reserved_at: null,
              version: 1,
            },
          ],
        },
      ];

      render(
        <BoutiqueStorefrontView
          storefront={{
            id: 's1',
            store_name: "Suv's",
            store_slug: 'suv-s',
            phone_number: '9830123456',
            default_shipping_fee_paisa: 8000,
            free_shipping_threshold_paisa: null,
            advance_confirmation_enabled: false,
            advance_amount_paisa: 0,
            hold_duration_days: 2,
            upi_qr_url: null,
          }}
          activeLiveDrop={null}
          liveProducts={[]}
          pastDropsWithProducts={pastDropsWithMultiPhotos}
        />
      );

      const img = screen.getByAltText('Pure Zari Brocade');
      expect(img).toHaveAttribute('src', 'https://example.com/multi1.jpg');
      expect(screen.getByTitle('3 photos')).toBeInTheDocument();
      expect(screen.getByText('📷 3')).toBeInTheDocument();
    });
  });
});
