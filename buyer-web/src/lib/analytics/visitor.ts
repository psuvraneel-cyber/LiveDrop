/**
 * LiveDrop — anonymous visit counting (ADR-017)
 *
 * What the website shares, and only when counting is allowed:
 * - a random visitor id kept in this browser (not linked to a name, phone, order or IP address);
 * - the kind of page, the drop slug, where the visit came from, and mobile / tablet / desktop;
 * - whether this browser has placed a LiveDrop order before (from the orders it already remembers).
 *
 * Counting is off when the visitor opted out on /privacy, or the browser sends Do Not Track or
 * Global Privacy Control. Seller and admin pages are never counted.
 */

import { getRecentOrders } from '../cart/cart-storage';

export const VISITOR_ID_STORAGE_KEY = 'livedrop_visitor_id_v1';
export const ANALYTICS_OPT_OUT_STORAGE_KEY = 'livedrop_analytics_opt_out_v1';
export const ANALYTICS_NOTICE_STORAGE_KEY = 'livedrop_analytics_notice_seen_v1';
const SOURCE_SESSION_KEY = 'livedrop_visit_source_v1';

/** Realtime presence channel shared by the website (track) and /admin (listen). */
export const PRESENCE_CHANNEL = 'livedrop-site-presence';

export type PageKind = 'home' | 'shop' | 'store' | 'drop' | 'cart' | 'checkout' | 'order' | 'legal' | 'other';
export type VisitSource = 'whatsapp' | 'facebook' | 'instagram' | 'google' | 'direct' | 'other';
export type DeviceKind = 'mobile' | 'tablet' | 'desktop';

export interface PresencePayload {
  page: PageKind;
  drop: string | null;
  returning: boolean;
  activeOrder: boolean;
  source: VisitSource;
  device: DeviceKind;
  at: number;
}

const LEGAL_PATHS = new Set(['privacy', 'terms', 'refund-policy', 'grievance']);
const NEVER_COUNTED = new Set(['admin', 'seller']);
const STATIC_ROOTS = new Set(['shop', 'cart', 'checkout', 'order', 'drop', ...LEGAL_PATHS, ...NEVER_COUNTED]);

function storage(kind: 'local' | 'session'): Storage | null {
  try {
    return typeof window === 'undefined' ? null : kind === 'local' ? window.localStorage : window.sessionStorage;
  } catch {
    return null;
  }
}

/** Page kind and drop slug for a path, or null for pages that are never counted. */
export function pageFor(pathname: string): { kind: PageKind; drop: string | null } | null {
  const parts = pathname.split('?')[0].split('/').filter(Boolean);
  const first = (parts[0] ?? '').toLowerCase();
  if (NEVER_COUNTED.has(first)) return null;
  if (!first) return { kind: 'home', drop: null };
  if (first === 'drop') {
    const slug = (parts[1] ?? '').toLowerCase();
    return { kind: 'drop', drop: /^[a-z0-9][a-z0-9-]{0,79}$/.test(slug) ? slug : null };
  }
  if (first === 'shop' || first === 'cart' || first === 'checkout' || first === 'order') return { kind: first, drop: null };
  if (LEGAL_PATHS.has(first)) return { kind: 'legal', drop: null };
  if (!STATIC_ROOTS.has(first) && parts.length === 1) return { kind: 'store', drop: null };
  return { kind: 'other', drop: null };
}

/** Where this visit came from, decided once per browser session. */
export function sourceFor(referrer: string, search: string): VisitSource {
  const session = storage('session');
  const saved = session?.getItem(SOURCE_SESSION_KEY) as VisitSource | null;
  if (saved) return saved;
  const utm = new URLSearchParams(search).get('utm_source')?.toLowerCase() ?? '';
  const ref = referrer.toLowerCase();
  const probe = `${utm} ${ref}`;
  let source: VisitSource = 'other';
  if (/whatsapp|wa\.me/.test(probe)) source = 'whatsapp';
  else if (/facebook|fb\.com|fb\.watch|messenger/.test(probe)) source = 'facebook';
  else if (/instagram/.test(probe)) source = 'instagram';
  else if (/google\./.test(probe) || utm === 'google') source = 'google';
  else if (!utm && (!ref || ref.includes(typeof window !== 'undefined' ? window.location.host : ''))) source = 'direct';
  try {
    session?.setItem(SOURCE_SESSION_KEY, source);
  } catch {
    // Counting still works; the source is recomputed next time.
  }
  return source;
}

export function deviceFor(width: number, userAgent: string): DeviceKind {
  if (/ipad|tablet/i.test(userAgent) || (width >= 768 && width < 1024 && /android/i.test(userAgent))) return 'tablet';
  if (/mobi|android|iphone/i.test(userAgent) || width < 768) return 'mobile';
  return 'desktop';
}

export function isAnalyticsAllowed(): boolean {
  if (typeof navigator !== 'undefined') {
    const nav = navigator as Navigator & { globalPrivacyControl?: boolean };
    if (nav.doNotTrack === '1' || nav.globalPrivacyControl === true) return false;
  }
  return storage('local')?.getItem(ANALYTICS_OPT_OUT_STORAGE_KEY) !== '1';
}

export function setAnalyticsOptOut(optOut: boolean): void {
  const local = storage('local');
  try {
    if (optOut) {
      local?.setItem(ANALYTICS_OPT_OUT_STORAGE_KEY, '1');
      local?.removeItem(VISITOR_ID_STORAGE_KEY);
    } else {
      local?.removeItem(ANALYTICS_OPT_OUT_STORAGE_KEY);
    }
  } catch {
    // Without storage nothing is remembered, so nothing is counted across visits either.
  }
}

/** Random id for this browser; a new one if storage is unavailable. */
export function getVisitorId(): string {
  const local = storage('local');
  const existing = local?.getItem(VISITOR_ID_STORAGE_KEY);
  if (existing && /^[0-9a-f-]{36}$/i.test(existing)) return existing;
  const id = typeof crypto !== 'undefined' && 'randomUUID' in crypto ? crypto.randomUUID() : fallbackUuid();
  try {
    local?.setItem(VISITOR_ID_STORAGE_KEY, id);
  } catch {
    // Counted as a new visitor next time.
  }
  return id;
}

function fallbackUuid(): string {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

/** Whether this browser has ordered before, and whether an order is still unpaid. */
export function buyerStatus(): { returning: boolean; activeOrder: boolean } {
  try {
    const orders = getRecentOrders();
    return {
      returning: orders.length > 0,
      activeOrder: orders.some((o) => o.paymentStatus === 'unpaid' || o.paymentStatus === 'advance_paid'),
    };
  } catch {
    return { returning: false, activeOrder: false };
  }
}
