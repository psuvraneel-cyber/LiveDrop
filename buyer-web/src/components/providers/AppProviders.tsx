'use client';

/**
 * LiveDrop — Global App Providers & Overlays
 *
 * Wraps the app with CartProvider, ProfileProvider, and mounts global drawers.
 */

import React, { ReactNode } from 'react';
import { CartProvider } from '../../lib/cart/cart-context';
import { ProfileProvider } from '../../lib/profile/profile-context';
import { GlobalAppOverlays } from './GlobalAppOverlays';
import { SiteAnalytics } from '../analytics/SiteAnalytics';
import { AnalyticsNotice } from '../analytics/AnalyticsNotice';

export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <CartProvider>
      <ProfileProvider>
        {children}
        <GlobalAppOverlays />
        <SiteAnalytics />
        <AnalyticsNotice />
      </ProfileProvider>
    </CartProvider>
  );
}
