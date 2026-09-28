'use client';

/**
 * LiveDrop — Global App Overlays
 *
 * Renders global drawers (CartDrawer, BuyerProfileDrawer) connected
 * to their respective context managers.
 */

import React from 'react';
import { useProfile } from '../../lib/profile/profile-context';
import { BuyerProfileDrawer } from '../profile/BuyerProfileDrawer';

export function GlobalAppOverlays() {
  const { isProfileOpen, closeProfile } = useProfile();

  return (
    <>
      <BuyerProfileDrawer isOpen={isProfileOpen} onClose={closeProfile} />
    </>
  );
}
