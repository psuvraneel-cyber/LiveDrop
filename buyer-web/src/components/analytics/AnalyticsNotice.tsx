'use client';

/**
 * One-time notice that LiveDrop counts visits anonymously, with a link to the privacy policy and a
 * way to opt out (ADR-017). Not shown on seller/admin pages or when counting is already off.
 */

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import {
  ANALYTICS_NOTICE_STORAGE_KEY,
  isAnalyticsAllowed,
  pageFor,
  setAnalyticsOptOut,
} from '../../lib/analytics/visitor';

export const ANALYTICS_NOTICE_TEXT =
  'LiveDrop counts visits anonymously (no name, phone number or IP address) to see how drops are doing.';

function readSeen(): boolean {
  try {
    return window.localStorage.getItem(ANALYTICS_NOTICE_STORAGE_KEY) === '1';
  } catch {
    return true; // No storage: do not nag on every page.
  }
}

function markSeen(): void {
  try {
    window.localStorage.setItem(ANALYTICS_NOTICE_STORAGE_KEY, '1');
  } catch {
    // Shown again next visit.
  }
}

export function AnalyticsNotice() {
  const pathname = usePathname() || '/';
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const show = pageFor(pathname) !== null && isAnalyticsAllowed() && !readSeen();
    // Decided after mount: storage is only available in the browser.
    const timer = setTimeout(() => setVisible(show), 0);
    return () => clearTimeout(timer);
  }, [pathname]);

  if (!visible) return null;

  return (
    <div
      role="region"
      aria-label="Visit counting notice"
      data-testid="analytics-notice"
      className="fixed bottom-0 inset-x-0 z-[60] border-t border-white/10 bg-[#0d0d10]/95 backdrop-blur px-4 py-3 text-xs text-[#E8E2D6]"
    >
      <div className="mx-auto flex max-w-4xl flex-wrap items-center gap-x-4 gap-y-2">
        <p className="flex-1 min-w-[220px]">
          {ANALYTICS_NOTICE_TEXT}{' '}
          <Link href="/privacy" className="underline text-[#D4AF37]">
            Privacy policy
          </Link>
        </p>
        <button
          type="button"
          data-testid="analytics-opt-out"
          className="underline text-[#AAA49A]"
          onClick={() => {
            setAnalyticsOptOut(true);
            markSeen();
            setVisible(false);
          }}
        >
          Don&apos;t count my visits
        </button>
        <button
          type="button"
          data-testid="analytics-notice-ok"
          className="rounded-full bg-[#D4AF37] px-4 py-1.5 font-semibold text-[#08080a]"
          onClick={() => {
            markSeen();
            setVisible(false);
          }}
        >
          OK
        </button>
      </div>
    </div>
  );
}
