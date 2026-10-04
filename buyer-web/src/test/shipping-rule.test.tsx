/**
 * LiveDrop Buyer Webfront — single free-shipping rule (SA-PAY-008)
 *
 * The rule (same as create_order_with_reservation / resolve_free_shipping_threshold, migration 037):
 *   threshold = drop.free_shipping_threshold_paisa ?? seller.free_shipping_threshold_paisa ?? none
 *   fee       = drop.shipping_fee_paisa ?? seller.default_shipping_fee_paisa ?? 8000
 * Every buyer screen (drop banner, cart drawer, cart page, checkout review) uses it.
 */

import React from 'react';
import { describe, it, expect, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import {
  estimateShipping,
  resolveFreeShippingThresholdPaisa,
  resolveShippingFeePaisa,
  FALLBACK_SHIPPING_FEE_PAISA,
} from '../lib/checkout/shipping';
import { CartProvider, useCart, resetCartStore } from '../lib/cart/cart-context';
import { CartDrawer } from '../components/cart/CartDrawer';
import { CheckoutReview } from '../components/checkout/CheckoutReview';
import { DropHeader } from '../components/DropHeader';
import { PublicDropCatalog, PublicProductView } from '../types/domain';
import { ReconciledCartItem } from '../types/cart';

function makeDrop(
  dropThreshold: number | null,
  shopThreshold: number | null,
  dropFee: number | null = 8000,
  shopFee = 9000
): PublicDropCatalog {
  return {
    id: 'drop-ship-1',
    seller_id: 'seller-ship-1',
    title: 'Shipping Rule Drop',
    slug: 'shipping-rule-drop',
    status: 'live',
    shipping_fee_paisa: dropFee as number,
    free_shipping_threshold_paisa: dropThreshold,
    live_started_at: '2026-10-04T10:00:00Z',
    closed_at: null,
    created_at: '2026-10-04T09:00:00Z',
    updated_at: '2026-10-04T09:00:00Z',
    profiles: {
      store_name: 'Rule Boutique',
      store_slug: 'rule-boutique',
      default_shipping_fee_paisa: shopFee,
      free_shipping_threshold_paisa: shopThreshold,
      advance_confirmation_enabled: false,
      advance_amount_paisa: 0,
      hold_duration_days: 2,
    },
  };
}

const product: PublicProductView = {
  id: 'prod-ship-1',
  drop_id: 'drop-ship-1',
  title: 'Kantha Saree',
  price_paisa: 250000,
  code: '#S01',
  status: 'available',
  size: 'Free Size',
  image_url: 'https://example.com/s01.jpg',
  reserved_at: null,
  version: 1,
};

describe('shipping rule helper', () => {
  it('drop threshold beats the shop threshold (both directions)', () => {
    expect(resolveFreeShippingThresholdPaisa(makeDrop(299900, 200000))).toBe(299900);
    expect(resolveFreeShippingThresholdPaisa(makeDrop(100000, 300000))).toBe(100000);
  });

  it('falls back to the shop threshold, then to none — never to a hidden ₹2,000', () => {
    expect(resolveFreeShippingThresholdPaisa(makeDrop(null, 150000))).toBe(150000);
    expect(resolveFreeShippingThresholdPaisa(makeDrop(null, null))).toBeNull();
    expect(resolveFreeShippingThresholdPaisa(null)).toBeNull();
  });

  it('fee: drop fee, else shop fee, else the server fallback', () => {
    expect(resolveShippingFeePaisa(makeDrop(null, null, 7000, 9000))).toBe(7000);
    expect(resolveShippingFeePaisa(makeDrop(null, null, null, 9000))).toBe(9000);
    expect(resolveShippingFeePaisa(null)).toBe(FALLBACK_SHIPPING_FEE_PAISA);
  });

  it('estimates shipping like the server', () => {
    // subtotal below the drop threshold although above the shop threshold -> charged
    expect(estimateShipping(makeDrop(299900, 200000), 250000, 1)).toMatchObject({
      known: true, shippingPaisa: 8000, isFree: false, thresholdPaisa: 299900,
    });
    // subtotal at the threshold -> free
    expect(estimateShipping(makeDrop(250000, null), 250000, 1)).toMatchObject({ shippingPaisa: 0, isFree: true });
    // no threshold anywhere -> always charged
    expect(estimateShipping(makeDrop(null, null), 5000000, 3)).toMatchObject({
      shippingPaisa: 8000, isFree: false, thresholdPaisa: null,
    });
    // empty cart ships nothing
    expect(estimateShipping(makeDrop(null, null), 0, 0)).toMatchObject({ shippingPaisa: 0, isFree: false });
    // unknown drop -> unknown, never a guessed amount
    expect(estimateShipping(null, 250000, 1)).toMatchObject({ known: false, shippingPaisa: null });
  });
});

function DrawerRig({ drop }: { drop: PublicDropCatalog | null }) {
  const { addItem, openDrawer, isDrawerOpen, closeDrawer } = useCart();
  return (
    <div>
      <button
        data-testid="add-open"
        onClick={() => {
          addItem(product, 'drop-ship-1');
          openDrawer();
        }}
      >
        add
      </button>
      <CartDrawer isOpen={isDrawerOpen} onClose={closeDrawer} catalogProducts={[product]} drop={drop} />
    </div>
  );
}

describe('CartDrawer uses the single rule', () => {
  beforeEach(() => {
    window.localStorage.clear();
    resetCartStore();
  });

  it('charges shipping below the drop threshold even when the shop threshold is lower', () => {
    render(
      <CartProvider>
        <DrawerRig drop={makeDrop(299900, 200000)} />
      </CartProvider>
    );
    fireEvent.click(screen.getByTestId('add-open'));
    expect(screen.getByTestId('cart-shipping')).toHaveTextContent('₹80');
    expect(screen.getByTestId('cart-total')).toHaveTextContent('₹2,580');
  });

  it('gives free shipping above the drop threshold even when the shop threshold is higher', () => {
    render(
      <CartProvider>
        <DrawerRig drop={makeDrop(100000, 300000)} />
      </CartProvider>
    );
    fireEvent.click(screen.getByTestId('add-open'));
    expect(screen.getByTestId('cart-shipping')).toHaveTextContent('FREE');
    expect(screen.getByTestId('cart-total')).toHaveTextContent('₹2,500');
  });

  it('charges shipping when neither drop nor shop sets a threshold', () => {
    render(
      <CartProvider>
        <DrawerRig drop={makeDrop(null, null)} />
      </CartProvider>
    );
    fireEvent.click(screen.getByTestId('add-open'));
    expect(screen.getByTestId('cart-shipping')).toHaveTextContent('₹80');
    expect(screen.getByTestId('cart-total')).toHaveTextContent('₹2,580');
  });

  it('does not invent a threshold when the drop is unknown', () => {
    render(
      <CartProvider>
        <DrawerRig drop={null} />
      </CartProvider>
    );
    fireEvent.click(screen.getByTestId('add-open'));
    expect(screen.getByTestId('cart-shipping')).toHaveTextContent(/Calculated at checkout/i);
    expect(screen.getByTestId('cart-total')).toHaveTextContent('₹2,500');
  });
});

describe('CheckoutReview uses the single rule', () => {
  const items: ReconciledCartItem[] = [
    {
      productId: 'prod-ship-1',
      dropId: 'drop-ship-1',
      code: '#S01',
      title: 'Kantha Saree',
      pricePaisa: 250000,
      imageUrl: 'https://example.com/s01.jpg',
      size: 'Free Size',
      addedAt: Date.now(),
      status: 'available',
      isAvailable: true,
    },
  ];

  function renderReview(drop: PublicDropCatalog | null) {
    render(
      <CheckoutReview
        items={items}
        subtotalPaisa={250000}
        drop={drop}
        isSubmitting={false}
        hasUnavailableItems={false}
        onRemoveItem={() => {}}
        onSubmit={() => {}}
      />
    );
  }

  it('drop threshold beats shop threshold', () => {
    renderReview(makeDrop(299900, 200000));
    expect(screen.getByTestId('checkout-shipping')).toHaveTextContent('₹80');
    expect(screen.getByTestId('checkout-total')).toHaveTextContent('₹2,580');
  });

  it('shop threshold applies when the drop has none', () => {
    renderReview(makeDrop(null, 200000));
    expect(screen.getByTestId('checkout-shipping')).toHaveTextContent('FREE');
    expect(screen.getByTestId('checkout-total')).toHaveTextContent('₹2,500');
  });

  it('no threshold anywhere -> shipping charged', () => {
    renderReview(makeDrop(null, null));
    expect(screen.getByTestId('checkout-shipping')).toHaveTextContent('₹80');
  });

  it('unknown drop -> calculated at confirmation', () => {
    renderReview(null);
    expect(screen.getByTestId('checkout-shipping')).toHaveTextContent(/Calculated at confirmation/i);
    expect(screen.getByTestId('checkout-total')).toHaveTextContent('₹2,500');
  });
});

describe('DropHeader banner uses the single rule', () => {
  it('shows the shop threshold when the drop has none', () => {
    render(<DropHeader drop={makeDrop(null, 150000)} realtimeStatus="connected" />);
    expect(screen.getByTestId('shipping-notice')).toHaveTextContent('Free above ₹1,500');
  });

  it('shows the drop threshold over the shop threshold', () => {
    render(<DropHeader drop={makeDrop(299900, 150000)} realtimeStatus="connected" />);
    expect(screen.getByTestId('shipping-notice')).toHaveTextContent('Free above ₹2,999');
  });

  it('promises no free shipping when neither sets a threshold', () => {
    render(<DropHeader drop={makeDrop(null, null)} realtimeStatus="connected" />);
    expect(screen.getByTestId('shipping-notice')).toHaveTextContent('Standard Shipping: ₹80');
    expect(screen.getByTestId('shipping-notice')).not.toHaveTextContent(/Free/i);
  });
});
