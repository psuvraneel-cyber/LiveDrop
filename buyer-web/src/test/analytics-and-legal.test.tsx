/**
 * Anonymous visit counting (ADR-017) and the legal pages.
 */
import React from 'react';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type { SupabaseClient } from '@supabase/supabase-js';

let mockPath = '/drop/puja-collection';
vi.mock('next/navigation', () => ({ usePathname: () => mockPath }));

import {
  ANALYTICS_OPT_OUT_STORAGE_KEY,
  VISITOR_ID_STORAGE_KEY,
  deviceFor,
  isAnalyticsAllowed,
  pageFor,
  setAnalyticsOptOut,
  sourceFor,
} from '../lib/analytics/visitor';
import { summarisePresence } from '../lib/admin/console';
import { SiteAnalytics } from '../components/analytics/SiteAnalytics';
import { AnalyticsNotice } from '../components/analytics/AnalyticsNotice';
import { RECENT_ORDERS_STORAGE_KEY } from '../lib/cart/cart-storage';
import { LEGAL, legalValue, missingLegalFields } from '../lib/legal/legal-config';
import PrivacyPage from '../app/privacy/page';
import GrievancePage from '../app/grievance/page';
import { Footer } from '../components/Footer';

function mockClient() {
  const channel = {
    subscribe: vi.fn((cb?: (status: string) => void) => {
      cb?.('SUBSCRIBED');
      return channel;
    }),
    track: vi.fn().mockResolvedValue('ok'),
    untrack: vi.fn().mockResolvedValue('ok'),
    unsubscribe: vi.fn().mockResolvedValue('ok'),
  };
  const rpc = vi.fn().mockResolvedValue({ data: { success: true }, error: null });
  return { client: { rpc, channel: vi.fn(() => channel) } as unknown as SupabaseClient, rpc, channel };
}

beforeEach(() => {
  window.localStorage.clear();
  window.sessionStorage.clear();
  mockPath = '/drop/puja-collection';
});
afterEach(() => {
  vi.restoreAllMocks();
});

describe('visitor helpers', () => {
  it('classifies pages and never counts seller or admin pages', () => {
    expect(pageFor('/')).toEqual({ kind: 'home', drop: null });
    expect(pageFor('/drop/Puja-Collection')).toEqual({ kind: 'drop', drop: 'puja-collection' });
    expect(pageFor('/checkout')?.kind).toBe('checkout');
    expect(pageFor('/aarohi')?.kind).toBe('store');
    expect(pageFor('/privacy')?.kind).toBe('legal');
    expect(pageFor('/admin')).toBeNull();
    expect(pageFor('/seller/reset-password')).toBeNull();
  });

  it('reads the source from utm or referrer, once per session', () => {
    expect(sourceFor('https://l.facebook.com/', '')).toBe('facebook');
    expect(sourceFor('https://www.google.com/', '')).toBe('facebook'); // remembered for the session
    window.sessionStorage.clear();
    expect(sourceFor('', '?utm_source=whatsapp')).toBe('whatsapp');
    window.sessionStorage.clear();
    expect(sourceFor('', '')).toBe('direct');
  });

  it('sorts devices coarsely', () => {
    expect(deviceFor(390, 'Mozilla/5.0 (Linux; Android 13) Mobile')).toBe('mobile');
    expect(deviceFor(1440, 'Mozilla/5.0 (Windows NT 10.0)')).toBe('desktop');
    expect(deviceFor(800, 'Mozilla/5.0 (iPad)')).toBe('tablet');
  });

  it('respects opt-out and Do Not Track; opting out forgets the visitor id', () => {
    expect(isAnalyticsAllowed()).toBe(true);
    window.localStorage.setItem(VISITOR_ID_STORAGE_KEY, '11111111-1111-4111-8111-111111111111');
    setAnalyticsOptOut(true);
    expect(isAnalyticsAllowed()).toBe(false);
    expect(window.localStorage.getItem(VISITOR_ID_STORAGE_KEY)).toBeNull();
    setAnalyticsOptOut(false);
    expect(isAnalyticsAllowed()).toBe(true);
    Object.defineProperty(navigator, 'doNotTrack', { value: '1', configurable: true });
    expect(isAnalyticsAllowed()).toBe(false);
    Object.defineProperty(navigator, 'doNotTrack', { value: null, configurable: true });
  });

  it('summarises presence: one count per visitor, returning buyers, viewers per drop', () => {
    const s = summarisePresence({
      a: [{ page: 'home' }, { page: 'drop', drop: 'puja', returning: true, source: 'whatsapp' }],
      b: [{ page: 'drop', drop: 'puja', activeOrder: true, source: 'facebook' }],
    });
    expect(s.total).toBe(2);
    expect(s.returningBuyers).toBe(1);
    expect(s.withActiveOrder).toBe(1);
    expect(s.byDrop).toEqual({ puja: 2 });
    expect(s.byPage).toEqual({ drop: 2 });
  });
});

describe('<SiteAnalytics />', () => {
  it('logs an anonymous page view and announces presence, with no personal data', async () => {
    window.localStorage.setItem(RECENT_ORDERS_STORAGE_KEY, JSON.stringify([{ id: 'o1', token: 't', paymentStatus: 'paid' }]));
    const { client, rpc, channel } = mockClient();
    render(<SiteAnalytics clientFactory={() => client} />);
    await waitFor(() => expect(rpc).toHaveBeenCalled());
    const [fn, args] = rpc.mock.calls[0];
    expect(fn).toBe('log_page_view');
    expect(args).toMatchObject({ p_page_kind: 'drop', p_drop_slug: 'puja-collection', p_returning_buyer: true });
    expect(Object.keys(args).sort()).toEqual(
      ['p_device', 'p_drop_slug', 'p_page_kind', 'p_returning_buyer', 'p_source', 'p_visitor_id'].sort()
    );
    await waitFor(() => expect(channel.track).toHaveBeenCalled());
    expect(channel.track.mock.calls[0][0]).toMatchObject({ page: 'drop', drop: 'puja-collection', returning: true });
  });

  it('does nothing after opting out, or on admin pages', async () => {
    window.localStorage.setItem(ANALYTICS_OPT_OUT_STORAGE_KEY, '1');
    const first = mockClient();
    const { unmount } = render(<SiteAnalytics clientFactory={() => first.client} />);
    await new Promise((r) => setTimeout(r, 20));
    expect(first.rpc).not.toHaveBeenCalled();
    unmount();

    window.localStorage.clear();
    mockPath = '/admin';
    const second = mockClient();
    render(<SiteAnalytics clientFactory={() => second.client} />);
    await new Promise((r) => setTimeout(r, 20));
    expect(second.rpc).not.toHaveBeenCalled();
  });
});

describe('visit notice and legal pages', () => {
  it('shows the notice once, and "Don\'t count my visits" opts out', async () => {
    render(<AnalyticsNotice />);
    fireEvent.click(await screen.findByTestId('analytics-opt-out'));
    expect(isAnalyticsAllowed()).toBe(false);
    expect(screen.queryByTestId('analytics-notice')).not.toBeInTheDocument();
  });

  it('lists missing business details and shows visible placeholders until they are filled', () => {
    expect(missingLegalFields({ ...LEGAL, operatorName: 'Sonali Paul (proprietor)' })).not.toContain('Business / operator name');
    expect(missingLegalFields()).toContain('Grievance Officer name');
    expect(legalValue('supportEmail')).toBe('[Support e-mail — to be added]');
    render(<GrievancePage />);
    expect(screen.getByTestId('legal-operator').textContent).toContain('to be added');
  });

  it('privacy policy explains visit counting and offers the opt-out switch; footer links the legal pages', async () => {
    render(<PrivacyPage />);
    expect(screen.getByText(/Anonymous visit counts/)).toBeInTheDocument();
    expect(await screen.findByTestId('analytics-toggle')).toBeInTheDocument();
    render(<Footer />);
    const links = screen.getByTestId('footer-legal-links').querySelectorAll('a');
    expect([...links].map((a) => a.getAttribute('href'))).toEqual(['/privacy', '/terms', '/refund-policy', '/grievance']);
  });
});
