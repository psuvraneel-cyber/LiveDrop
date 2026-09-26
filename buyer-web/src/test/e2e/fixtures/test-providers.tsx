/**
 * LiveDrop E2E Test Suite — Providers & Render Utilities
 */

import React, { ReactNode } from 'react';
import { render, RenderOptions, RenderResult } from '@testing-library/react';
import { CartProvider, resetCartStore } from '../../../lib/cart/cart-context';
import { ProfileProvider } from '../../../lib/profile/profile-context';
import { CART_STORAGE_KEY } from '../../../lib/cart/cart-storage';

export function AllTestProviders({ children }: { children: ReactNode }) {
  return (
    <ProfileProvider>
      <CartProvider>{children}</CartProvider>
    </ProfileProvider>
  );
}

export function renderWithProviders(
  ui: React.ReactElement,
  options?: Omit<RenderOptions, 'wrapper'>
): RenderResult {
  return render(ui, { wrapper: AllTestProviders, ...options });
}

export function seedCartStorage(
  items: Array<{
    id: string;
    code: string;
    title: string;
    pricePaisa: number;
    size?: string;
    dropId?: string;
    imageUrl?: string;
  }>
) {
  const cartItems = items.map((item) => ({
    productId: item.id,
    code: item.code,
    title: item.title,
    pricePaisa: item.pricePaisa,
    size: item.size || 'Free Size',
    dropId: item.dropId || 'drop-live-festival-01',
    imageUrl: item.imageUrl || 'https://images.livedrop.store/default.webp',
    addedAt: Date.now(),
  }));

  window.localStorage.setItem(
    CART_STORAGE_KEY,
    JSON.stringify({
      version: 1,
      items: cartItems,
      dropId: items[0]?.dropId || 'drop-live-festival-01',
      updatedAt: Date.now(),
      note: '',
    })
  );
  resetCartStore();
}
