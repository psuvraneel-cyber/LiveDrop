'use client';

/**
 * LiveDrop — Global App Overlays
 *
 * Renders global drawers (CartDrawer, BuyerProfileDrawer) connected
 * to their respective context managers.
 */

import React from 'react';
import { useCart } from '../../lib/cart/cart-context';
import { useProfile } from '../../lib/profile/profile-context';
import { CartDrawer } from '../cart/CartDrawer';
import { BuyerProfileDrawer } from '../profile/BuyerProfileDrawer';

export function GlobalAppOverlays() {
  const { isDrawerOpen, closeDrawer } = useCart();
  const { isProfileOpen, closeProfile } = useProfile();

  return (
    <>
      <CartDrawer isOpen={isDrawerOpen} onClose={closeDrawer} />
      <BuyerProfileDrawer isOpen={isProfileOpen} onClose={closeProfile} />
    </>
  );
}
