'use client';

/**
 * LiveDrop — Global App Overlays
 *
 * Renders global drawers (CartDrawer, BuyerProfileDrawer) connected
 * to their respective context managers.
 */

import React, { useEffect } from 'react';
import { useCart } from '../../lib/cart/cart-context';
import { useProfile } from '../../lib/profile/profile-context';
import { CartDrawer } from '../cart/CartDrawer';
import { BuyerProfileDrawer } from '../profile/BuyerProfileDrawer';

export function GlobalAppOverlays() {
  const { isDrawerOpen, closeDrawer, activeDrop, catalogProducts, setHasGlobalCartDrawer } = useCart();
  const { isProfileOpen, closeProfile } = useProfile();

  useEffect(() => {
    setHasGlobalCartDrawer(true);
    return () => setHasGlobalCartDrawer(false);
  }, [setHasGlobalCartDrawer]);

  return (
    <>
      <CartDrawer
        isOpen={isDrawerOpen}
        onClose={closeDrawer}
        catalogProducts={catalogProducts}
        drop={activeDrop}
      />
      <BuyerProfileDrawer isOpen={isProfileOpen} onClose={closeProfile} />
    </>
  );
}
