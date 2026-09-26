'use client';

import React from 'react';
import { GlobalBuyerHeader, GlobalBuyerHeaderProps } from '../navigation/GlobalBuyerHeader';
import { MobileBottomDock } from '../navigation/MobileBottomDock';

export interface BuyerShellProps {
  children: React.ReactNode;
  headerProps?: GlobalBuyerHeaderProps;
  showHeader?: boolean;
  showBottomDock?: boolean;
  className?: string;
}

/**
 * BuyerShell — Unified Layout Shell for LiveDrop Buyer Experience.
 * Coordinates the sticky non-flickering GlobalBuyerHeader, MainContent container,
 * and standard fixed MobileBottomDock with safe-area insets.
 */
export function BuyerShell({
  children,
  headerProps,
  showHeader = true,
  showBottomDock = true,
  className = '',
}: BuyerShellProps) {
  return (
    <div
      className={`ld-buyer-shell min-h-screen flex flex-col bg-[#08080A] text-[#FBFBFB] ${
        showBottomDock ? 'ld-has-bottom-dock' : ''
      }`}
    >
      {showHeader && <GlobalBuyerHeader {...headerProps} />}
      <div className={`ld-shell-content flex-1 w-full ${className}`}>
        {children}
      </div>
      {showBottomDock && <MobileBottomDock />}
    </div>
  );
}
