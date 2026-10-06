/**
 * LiveDrop Buyer Webfront — /admin operator console (SA-OPS-002 / SA-ONB-001, ADR-016)
 *
 * The server (admin_* RPCs, migration 042) decides access; these tests check that the page shows
 * what the RPCs return, sends the right arguments, and handles REAUTH_REQUIRED. Supabase is mocked.
 */

import React from 'react';
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { AdminConsoleView, NOT_ADMIN_MESSAGE } from '../components/admin/AdminConsoleView';
import { metadata } from '../app/admin/page';

// Test-only value typed into the form; not a credential.
const TEST_PASSWORD = 'Adm1n-test-only'; // gitleaks:allow

const PENDING = {
  id: 's-1', store_name: 'Aarohi Boutique', store_slug: 'aarohi', phone_number: '9876500001', upi_id: 'aarohi@okaxis',
  email: 'aarohi@example.com', email_confirmed: true, onboarding_fee_utr: '412345678901', status: 'pending',
  last_suspension_reason: null, created_at: '2026-10-01T10:00:00Z', approved_at: null,
};
const LIVE_DROP = {
  id: 'd-1', title: 'Puja Collection', slug: 'puja', live_started_at: '2026-10-06T08:00:00Z', store_name: 'Aarohi Boutique',
  store_slug: 'aarohi', available: 4, held: 1, sold: 2, orders_last_hour: 3, verified_paisa_last_hour: 250000, payments_waiting: 1,
};
const SALES = {
  orders: 12, paid_orders: 9, cancelled_orders: 1, verified_paisa: 1840000, refunds_owed_paisa: 0, visitors: 300, conversion_pct: 4,
  daily: [{ date: '2026-10-06', orders: 12, verified_paisa: 1840000 }],
  top_sellers: [{ store_name: 'Aarohi Boutique', store_slug: 'aarohi', orders: 12, verified_paisa: 1840000 }],
  top_products: [{ code: '#A01', title: 'Kantha Saree', store_name: 'Aarohi Boutique', sold: 1, revenue_paisa: 150000 }],
};
const WAITING = {
  order_code: 'LD-WAIT01', store_name: 'Aarohi Boutique', payment_type: 'full', expected_amount_paisa: 158000,
  status: 'awaiting_seller_verification', claimed_at: '2026-10-06T08:10:00Z', minutes_waiting: 42,
};
const TRAFFIC = {
  totals: { visitors: 300, page_views: 1200, returning_buyer_visitors: 40 },
  daily: [{ date: '2026-10-06', visitors: 300, page_views: 1200 }],
  by_source: [{ source: 'whatsapp', visitors: 200 }], by_device: [{ device: 'mobile', visitors: 280 }],
  by_page: [{ page: 'drop', views: 900 }], top_drops: [{ drop_slug: 'puja', visitors: 250 }],
};
const OWED = {
  id: 'o-1', order_code: 'LD-ABC123', status: 'cancelled', store_name: 'Aarohi Boutique', total_paisa: 150000,
  total_paid_paisa: 150000, refund_status: 'required', refund_amount_paisa: 150000, refund_reason: 'sold elsewhere',
  refund_required_at: '2026-10-02T10:00:00Z', refund_reference: null, refunded_at: null, created_at: '2026-10-02T09:00:00Z',
};

function mockClient(opts: { admin?: boolean; reauthOnce?: boolean } = {}) {
  let reauth = opts.reauthOnce ?? false;
  const rpc = vi.fn(async (fn: string, args: Record<string, unknown> = {}) => {
    switch (fn) {
      case 'admin_whoami':
        return { data: { success: true, is_admin: opts.admin ?? true }, error: null };
      case 'admin_list_sellers':
        return { data: { success: true, sellers: args.p_status === 'pending' ? [PENDING] : [] }, error: null };
      case 'admin_set_seller_approval':
        if (reauth) {
          reauth = false;
          return { data: { success: false, error: 'REAUTH_REQUIRED', message: 'Sign in again with your password to continue.' }, error: null };
        }
        return { data: { success: true, message: args.p_approved ? 'Seller approved.' : 'Seller suspended. Their live drops were closed.' }, error: null };
      case 'admin_refunds_due':
        return { data: { success: true, orders: [OWED] }, error: null };
      case 'admin_find_order':
        return { data: { success: true, order: OWED }, error: null };
      case 'admin_record_refund':
        return { data: { success: true, message: 'Refund recorded.' }, error: null };
      case 'admin_live_drops':
        return { data: { success: true, drops: [LIVE_DROP] }, error: null };
      case 'admin_sales_overview':
        return { data: { success: true, ...SALES, days: args.p_days }, error: null };
      case 'admin_payment_attention':
        return { data: { success: true, waiting: [WAITING], refunds_owed: [], recently_rejected: [] }, error: null };
      case 'admin_traffic':
        return { data: { success: true, ...TRAFFIC, days: args.p_days }, error: null };
      default:
        return { data: null, error: { message: 'unknown rpc' } };
    }
  });
  const presence: Record<string, { page: string; drop: string | null; returning: boolean; activeOrder: boolean; source: string }[]> = {
    v1: [{ page: 'drop', drop: 'puja', returning: true, activeOrder: false, source: 'whatsapp' }],
    v2: [{ page: 'drop', drop: 'puja', returning: false, activeOrder: false, source: 'facebook' }],
    v3: [{ page: 'home', drop: null, returning: false, activeOrder: false, source: 'direct' }],
  };
  let syncHandler: (() => void) | null = null;
  const channel = {
    on: vi.fn((_type: string, _filter: unknown, cb: () => void) => {
      syncHandler = cb;
      return channel;
    }),
    subscribe: vi.fn(() => {
      setTimeout(() => syncHandler?.(), 0);
      return channel;
    }),
    unsubscribe: vi.fn().mockResolvedValue('ok'),
    presenceState: vi.fn(() => presence),
  };
  const auth = {
    signInWithPassword: vi.fn().mockResolvedValue({ data: { session: {} }, error: null }),
    signOut: vi.fn().mockResolvedValue({ error: null }),
  };
  return { client: { auth, rpc, channel: vi.fn(() => channel) } as unknown as SupabaseClient, auth, rpc, channel };
}

async function signIn(client: SupabaseClient) {
  render(<AdminConsoleView clientFactory={() => client} />);
  fireEvent.change(screen.getByTestId('admin-email'), { target: { value: 'ops@livedrop.test' } });
  fireEvent.change(screen.getByTestId('admin-password'), { target: { value: TEST_PASSWORD } });
  fireEvent.click(screen.getByTestId('admin-sign-in-submit'));
}

describe('/admin operator console', () => {
  it('is never indexed and sends no Referer', () => {
    expect(metadata.robots).toMatchObject({ index: false, follow: false });
    expect(metadata.referrer).toBe('no-referrer');
  });

  it('refuses a signed-in account that is not an administrator and signs it out', async () => {
    const { client, auth } = mockClient({ admin: false });
    await signIn(client);
    expect(await screen.findByText(NOT_ADMIN_MESSAGE)).toBeTruthy();
    expect(auth.signOut).toHaveBeenCalled();
    expect(screen.queryByTestId('admin-sellers')).toBeNull();
  });

  it('lists pending sellers with the onboarding-fee UTR and approves one', async () => {
    const { client, rpc } = mockClient();
    await signIn(client);
    fireEvent.click(await screen.findByTestId('admin-tab-sellers'));
    const card = await screen.findByTestId('admin-seller-aarohi');
    expect(within(card).getByTestId('admin-seller-utr').textContent).toBe('412345678901');
    fireEvent.click(within(card).getByTestId('admin-approve'));
    await waitFor(() =>
      expect(rpc).toHaveBeenCalledWith('admin_set_seller_approval', { p_seller_id: 's-1', p_approved: true, p_reason: null })
    );
    expect((await screen.findByTestId('admin-notice')).textContent).toContain('Seller approved.');
  });

  it('needs a reason to suspend', async () => {
    const { client, rpc } = mockClient();
    await signIn(client);
    fireEvent.click(await screen.findByTestId('admin-tab-sellers'));
    const card = await screen.findByTestId('admin-seller-aarohi');
    fireEvent.click(within(card).getByTestId('admin-suspend'));
    const confirm = within(card).getByTestId('admin-suspend-confirm') as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
    fireEvent.change(within(card).getByTestId('admin-suspend-reason'), { target: { value: 'Fee chargeback' } });
    fireEvent.click(confirm);
    await waitFor(() =>
      expect(rpc).toHaveBeenCalledWith('admin_set_seller_approval', { p_seller_id: 's-1', p_approved: false, p_reason: 'Fee chargeback' })
    );
  });

  it('asks for the password again when the server says REAUTH_REQUIRED, then retries', async () => {
    const { client, rpc, auth } = mockClient({ reauthOnce: true });
    await signIn(client);
    fireEvent.click(await screen.findByTestId('admin-tab-sellers'));
    const card = await screen.findByTestId('admin-seller-aarohi');
    fireEvent.click(within(card).getByTestId('admin-approve'));
    fireEvent.change(await screen.findByTestId('admin-reauth-password'), { target: { value: TEST_PASSWORD } });
    fireEvent.click(screen.getByTestId('admin-reauth-submit'));
    expect((await screen.findByTestId('admin-notice')).textContent).toContain('Seller approved.');
    expect(auth.signInWithPassword).toHaveBeenCalledTimes(2);
    expect(rpc.mock.calls.filter(([fn]) => fn === 'admin_set_seller_approval')).toHaveLength(2);
  });

  it('shows refunds owed and records one with its reference', async () => {
    const { client, rpc } = mockClient();
    await signIn(client);
    fireEvent.click(await screen.findByTestId('admin-tab-refunds'));
    const card = await screen.findByTestId('admin-order-LD-ABC123');
    expect(card.textContent).toContain('1,500');
    fireEvent.click(within(card).getByTestId('admin-record-refund'));
    fireEvent.change(within(card).getByTestId('admin-refund-reference'), { target: { value: 'IMPS 5123 4567' } });
    fireEvent.click(within(card).getByTestId('admin-refund-confirm'));
    await waitFor(() =>
      expect(rpc).toHaveBeenCalledWith('admin_record_refund', { p_order_id: 'o-1', p_refund_reference: 'IMPS 5123 4567', p_note: null })
    );
    expect((await screen.findByTestId('admin-notice')).textContent).toContain('Refund recorded.');
  });

  it('opens on Live: visitors now (with returning buyers) and every live drop with its viewers', async () => {
    const { client, channel } = mockClient();
    await signIn(client);
    expect(await screen.findByTestId('admin-live')).toBeTruthy();
    await waitFor(() => expect(screen.getByTestId('live-visitors-total').textContent).toContain('3'));
    expect(screen.getByTestId('live-visitors-returning').textContent).toContain('1');
    const drop = await screen.findByTestId('live-drop-puja');
    expect(within(drop).getByTestId('live-drop-viewers').textContent).toContain('2 watching');
    expect(drop.textContent).toContain('1 payments to verify');
    expect(channel.subscribe).toHaveBeenCalled();
  });

  it('shows sales for the chosen period and payments waiting too long', async () => {
    const { client, rpc } = mockClient();
    await signIn(client);
    fireEvent.click(await screen.findByTestId('admin-tab-sales'));
    expect((await screen.findByTestId('sales-orders')).textContent).toContain('12');
    expect(screen.getByTestId('sales-verified').textContent).toContain('18,400');
    fireEvent.click(screen.getByTestId('days-30'));
    await waitFor(() => expect(rpc).toHaveBeenCalledWith('admin_sales_overview', { p_days: 30 }));
    fireEvent.click(screen.getByTestId('admin-tab-payments'));
    expect((await screen.findByTestId('waiting-LD-WAIT01')).textContent).toContain('waiting 42 min');
    fireEvent.click(screen.getByTestId('admin-tab-traffic'));
    expect((await screen.findByTestId('traffic-visitors')).textContent).toContain('300');
  });

  it('warns while the legal pages still miss business details', async () => {
    const { client } = mockClient();
    await signIn(client);
    expect((await screen.findByTestId('admin-legal-missing')).textContent).toContain('Grievance Officer name');
  });
});
