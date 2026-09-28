import React from 'react';
import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { BoutiqueStorefrontView } from '../components/BoutiqueStorefrontView';
import { CartProvider } from '../lib/cart/cart-context';
import { PublicSellerStorefront, PublicDropCatalog, PublicProductView, ShowcaseCollection } from '../types/domain';

const mockStorefront: PublicSellerStorefront = {
  id: 'seller-uuid-001',
  store_name: 'Ananya Studio',
  store_slug: 'ananya-studio',
  phone_number: '9830012345',
  upi_vpa: 'ananya@upi',
  upi_display_name: 'Ananya Studio',
  upi_qr_url: null,
  upi_enabled: true,
  default_shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 250000,
  advance_confirmation_enabled: true,
  advance_amount_paisa: 50000,
  hold_duration_days: 7,
  is_verified: true,
  created_at: '2026-09-01T10:00:00Z',
};

const mockLiveDrop: PublicDropCatalog = {
  id: 'drop-live-001',
  seller_id: 'seller-uuid-001',
  title: 'Diwali Couture Edit',
  slug: 'diwali-couture',
  status: 'live',
  shipping_fee_paisa: 8000,
  free_shipping_threshold_paisa: 250000,
  stream_url: 'https://www.facebook.com/ananya/videos/999999/',
  live_started_at: '2026-09-28T18:00:00Z',
  closed_at: null,
  created_at: '2026-09-28T17:00:00Z',
  updated_at: '2026-09-28T17:00:00Z',
  profiles: {
    store_name: 'Ananya Studio',
    store_slug: 'ananya-studio',
    phone_number: '9830012345',
    upi_id: 'ananya@upi',
    upi_qr_url: null,
    default_shipping_fee_paisa: 8000,
    free_shipping_threshold_paisa: 250000,
    advance_confirmation_enabled: true,
    advance_amount_paisa: 50000,
    hold_duration_days: 7,
  },
};

const mockLiveProducts: PublicProductView[] = [
  {
    id: 'prod-live-1',
    drop_id: 'drop-live-001',
    code: '#D01',
    title: 'Crimson Brocade Saree',
    price_paisa: 320000, // ₹3,200.00
    size: 'Free Size',
    image_url: 'https://example.com/crimson.jpg',
    status: 'available',
    reserved_at: null,
    version: 1,
  },
  {
    id: 'prod-live-2',
    drop_id: 'drop-live-001',
    code: '#D02',
    title: 'Marigold Silk Kurti',
    price_paisa: 150000, // ₹1,500.00
    size: 'M',
    image_url: 'https://example.com/marigold.jpg',
    status: 'reserved',
    reserved_at: '2026-09-28T18:15:00Z',
    version: 2,
  },
  {
    id: 'prod-live-3',
    drop_id: 'drop-live-001',
    code: '#D03',
    title: 'Zari Border Dupatta',
    price_paisa: 95000, // ₹950.00
    size: 'Free Size',
    image_url: 'https://example.com/dupatta.jpg',
    status: 'sold',
    reserved_at: null,
    version: 3,
  },
];

const mockPastCollections: ShowcaseCollection[] = [
  {
    drop: {
      id: 'drop-past-001',
      title: 'Summer Heritage Edit',
      slug: 'summer-heritage',
      status: 'closed',
      created_at: '2026-08-15T16:00:00Z',
      closed_at: '2026-08-15T21:00:00Z',
    },
    products: [
      {
        id: 'prod-past-1',
        drop_id: 'drop-past-001',
        code: '#S01',
        title: 'Chanderi Linen Tunic',
        price_paisa: 180000, // ₹1,800.00
        size: 'L',
        image_url: 'https://example.com/tunic.jpg',
        status: 'available',
        reserved_at: null,
        version: 1,
      },
    ],
  },
];

describe('Phase 1B: Boutique Storefront Behavior ([storeSlug])', () => {
  it('1. Valid storefront: renders boutique name, slug, verified tag, and normalized WhatsApp button', () => {
    render(
      <CartProvider>
        <BoutiqueStorefrontView
          storefront={mockStorefront}
          activeLiveDrop={null}
          liveProducts={[]}
          pastDropsWithProducts={mockPastCollections}
        />
      </CartProvider>
    );

    // Boutique Title & Slug
    expect(screen.getByTestId('storefront-title')).toHaveTextContent('Ananya Studio');
    expect(screen.getByText('ananya-studio')).toBeInTheDocument();

    // Verified Boutique Tag
    expect(screen.getByText('✦ Verified Boutique')).toBeInTheDocument();

    // WhatsApp Action Button with country code normalization (919830012345)
    const whatsappBtn = screen.getByTestId('boutique-whatsapp-btn');
    expect(whatsappBtn).toBeInTheDocument();
    expect(whatsappBtn).toHaveAttribute('href', expect.stringContaining('https://wa.me/919830012345'));
  });

  it('2. Live storefront: renders live sale banner, live badge, products, and enter CTA', () => {
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

    // Live drop badge & section
    expect(screen.getByTestId('live-drop-pill')).toHaveTextContent('LIVE FLASH SALE NOW');
    expect(screen.getByTestId('enter-live-room-btn')).toHaveAttribute('href', '/drop/diwali-couture');
    expect(screen.getByTestId('live-products-section')).toBeInTheDocument();
    expect(screen.getByText('Diwali Couture Edit')).toBeInTheDocument();

    // Products in live section
    expect(screen.getByText('Crimson Brocade Saree')).toBeInTheDocument();
    expect(screen.getByText('₹3,200')).toBeInTheDocument();
  });

  it('3. Storefront without active live drop: displays offline showcase pill and studio lookbooks', () => {
    render(
      <CartProvider>
        <BoutiqueStorefrontView
          storefront={mockStorefront}
          activeLiveDrop={null}
          liveProducts={[]}
          pastDropsWithProducts={mockPastCollections}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('offline-showcase-pill')).toHaveTextContent('NEXT LIVE DROP SOON');
    expect(screen.queryByTestId('live-products-section')).not.toBeInTheDocument();
    expect(screen.getByTestId('showcase-section')).toBeInTheDocument();
    expect(screen.getByText('Summer Heritage Edit')).toBeInTheDocument();
    expect(screen.getByText('Chanderi Linen Tunic')).toBeInTheDocument();
  });

  it('4. Storefront without collections: renders clean empty showcase state with WhatsApp inquiry', () => {
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
    expect(screen.getByText(/has not archived any past drop pieces yet/i)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Inquire on WhatsApp/i })).toBeInTheDocument();
  });

  it('5. Availability states: renders available, reserved, and sold out cards correctly', () => {
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

    // Available piece
    const availableBadge = screen.getByTestId('status-badge-prod-live-1');
    expect(availableBadge).toHaveTextContent('AVAILABLE');

    // Reserved piece
    const reservedBadge = screen.getByTestId('status-badge-prod-live-2');
    expect(reservedBadge).toHaveTextContent('RESERVED');

    // Sold out piece
    const soldBadge = screen.getByTestId('status-badge-prod-live-3');
    expect(soldBadge).toHaveTextContent('SOLD OUT');
  });

  it('6. Cart integration: adds product to cart and updates drawer in live mode', () => {
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

    // Click Add to Bag on available piece #D01
    const addBtn = screen.getByTestId('cart-btn-prod-live-1');
    fireEvent.click(addBtn);

    // Cart badge updates to 1
    expect(screen.getByTestId('storefront-cart-badge')).toHaveTextContent('1');

    // Click cart button in header to open drawer
    const cartBtn = screen.getByTestId('storefront-cart-btn');
    fireEvent.click(cartBtn);

    // Cart drawer is now visible
    expect(screen.getByTestId('cart-drawer')).toBeInTheDocument();
  });

  it('7. Showcase product navigation & image preview: opens accessible modal preview', () => {
    render(
      <CartProvider>
        <BoutiqueStorefrontView
          storefront={mockStorefront}
          activeLiveDrop={null}
          liveProducts={[]}
          pastDropsWithProducts={mockPastCollections}
        />
      </CartProvider>
    );

    const imgWrap = screen.getByLabelText('Preview image of Chanderi Linen Tunic');
    expect(imgWrap).toBeInTheDocument();

    // Click image to open preview
    fireEvent.click(imgWrap);

    // Modal dialog is opened
    const modal = screen.getByTestId('image-preview-modal');
    expect(modal).toBeInTheDocument();
    expect(modal).toHaveAttribute('role', 'dialog');

    // Close preview
    const closeBtn = screen.getByLabelText('Close image preview');
    fireEvent.click(closeBtn);
    expect(screen.queryByTestId('image-preview-modal')).not.toBeInTheDocument();
  });

  it('8. Responsive layout & navigation dock: includes persistent mobile bottom dock', () => {
    render(
      <CartProvider>
        <BoutiqueStorefrontView
          storefront={mockStorefront}
          activeLiveDrop={null}
          liveProducts={[]}
          pastDropsWithProducts={mockPastCollections}
        />
      </CartProvider>
    );

    expect(screen.getByTestId('mobile-bottom-dock')).toBeInTheDocument();
    expect(screen.getByTestId('global-buyer-header')).toBeInTheDocument();
  });
});
