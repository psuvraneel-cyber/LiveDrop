'use client';

import React from 'react';
import { GlobalBuyerHeader, GlobalBuyerHeaderProps } from './GlobalBuyerHeader';

export type LuxuryTopHeaderProps = GlobalBuyerHeaderProps;

/**
 * LuxuryTopHeader — Backward-compatible wrapper for GlobalBuyerHeader (variant="storefront").
 * Eliminates unthrottled scroll listeners and flicker while preserving existing contracts.
 */
export function LuxuryTopHeader(props: LuxuryTopHeaderProps) {
  return <GlobalBuyerHeader variant="storefront" {...props} />;
}
