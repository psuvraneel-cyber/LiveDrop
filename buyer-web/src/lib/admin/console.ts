/**
 * LiveDrop — operator console data layer (/admin, SA-OPS-002 / SA-ONB-001, ADR-016)
 *
 * The console signs in as a normal Supabase user with the anon key. Every call goes through an
 * admin_* RPC (migration 042) that checks platform_admins itself, so nothing here grants access:
 * a non-admin account only ever gets UNAUTHORIZED back. No service-role key is involved.
 *
 * - session kept in memory only, never persisted or auto-refreshed: closing the tab signs out
 * - writes need a password sign-in within 10 minutes; the server answers REAUTH_REQUIRED after that
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { validateBuyerEnv } from '../supabase/env';

export type SellerStatus = 'pending' | 'approved' | 'suspended';
export type SellerFilter = SellerStatus | 'all';

export interface AdminSeller {
  id: string;
  store_name: string;
  store_slug: string;
  phone_number: string | null;
  upi_id: string | null;
  email: string | null;
  email_confirmed: boolean;
  onboarding_fee_utr: string | null;
  status: SellerStatus;
  last_suspension_reason: string | null;
  created_at: string;
  approved_at: string | null;
}

export interface AdminOrder {
  id: string;
  order_code: string;
  status: string;
  store_name: string | null;
  total_paisa: number;
  total_paid_paisa: number;
  refund_status: 'none' | 'required' | 'refunded';
  refund_amount_paisa: number;
  refund_reason: string | null;
  refund_required_at: string | null;
  refund_reference: string | null;
  refunded_at: string | null;
  created_at: string;
}

export class AdminError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
    this.name = 'AdminError';
  }
}

export function createAdminClient(): SupabaseClient {
  const { supabaseUrl, supabaseAnonKey } = validateBuyerEnv();
  return createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
      storageKey: 'livedrop-admin-console',
    },
  });
}

type RpcResult = { success?: boolean; error?: string; message?: string; [key: string]: unknown };

async function call(client: SupabaseClient, fn: string, args: Record<string, unknown> = {}): Promise<RpcResult> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new AdminError('NETWORK_ERROR', 'Could not reach LiveDrop. Check your connection and try again.');
  }
  const result = (data ?? {}) as RpcResult;
  if (result.success !== true) {
    throw new AdminError(result.error ?? 'UNKNOWN_ERROR', result.message ?? 'Something went wrong.');
  }
  return result;
}

export async function isAdmin(client: SupabaseClient): Promise<boolean> {
  const r = await call(client, 'admin_whoami');
  return r.is_admin === true;
}

export async function listSellers(client: SupabaseClient, status: SellerFilter): Promise<AdminSeller[]> {
  const r = await call(client, 'admin_list_sellers', { p_status: status });
  return (r.sellers as AdminSeller[]) ?? [];
}

export async function setSellerApproval(
  client: SupabaseClient,
  sellerId: string,
  approved: boolean,
  reason?: string
): Promise<string> {
  const r = await call(client, 'admin_set_seller_approval', {
    p_seller_id: sellerId,
    p_approved: approved,
    p_reason: reason ?? null,
  });
  return (r.message as string) ?? '';
}

export async function refundsDue(client: SupabaseClient): Promise<AdminOrder[]> {
  const r = await call(client, 'admin_refunds_due');
  return (r.orders as AdminOrder[]) ?? [];
}

export async function findOrder(client: SupabaseClient, orderCode: string): Promise<AdminOrder> {
  const r = await call(client, 'admin_find_order', { p_order_code: orderCode });
  return r.order as AdminOrder;
}

export async function recordRefund(
  client: SupabaseClient,
  orderId: string,
  reference: string,
  note?: string
): Promise<string> {
  const r = await call(client, 'admin_record_refund', {
    p_order_id: orderId,
    p_refund_reference: reference,
    p_note: note?.trim() ? note.trim() : null,
  });
  return (r.message as string) ?? '';
}

// ---------------------------------------------------------------------------
// Dashboard (migration 045, ADR-017)
// ---------------------------------------------------------------------------

export interface LiveDropRow {
  id: string;
  title: string;
  slug: string;
  live_started_at: string | null;
  store_name: string;
  store_slug: string;
  available: number;
  held: number;
  sold: number;
  orders_last_hour: number;
  verified_paisa_last_hour: number;
  payments_waiting: number;
}

export interface SalesOverview {
  days: number;
  orders: number;
  paid_orders: number;
  cancelled_orders: number;
  verified_paisa: number;
  refunds_owed_paisa: number;
  visitors: number;
  conversion_pct: number | null;
  daily: { date: string; orders: number; verified_paisa: number }[];
  top_sellers: { store_name: string; store_slug: string; orders: number; verified_paisa: number }[];
  top_products: { code: string; title: string | null; store_name: string; sold: number; revenue_paisa: number }[];
}

export interface PaymentAttention {
  waiting: {
    order_code: string;
    store_name: string;
    payment_type: string;
    expected_amount_paisa: number;
    status: string;
    claimed_at: string;
    minutes_waiting: number;
  }[];
  refunds_owed: { order_code: string; store_name: string; refund_amount_paisa: number; refund_reason: string | null; refund_required_at: string | null }[];
  recently_rejected: { order_code: string; store_name: string; expected_amount_paisa: number; rejection_reason: string | null; updated_at: string }[];
}

export interface TrafficReport {
  days: number;
  totals: { visitors: number; page_views: number; returning_buyer_visitors: number };
  daily: { date: string; visitors: number; page_views: number }[];
  by_source: { source: string; visitors: number }[];
  by_device: { device: string; visitors: number }[];
  by_page: { page: string; views: number }[];
  top_drops: { drop_slug: string; visitors: number }[];
}

export async function liveDrops(client: SupabaseClient): Promise<LiveDropRow[]> {
  const r = await call(client, 'admin_live_drops');
  return (r.drops as LiveDropRow[]) ?? [];
}

export async function salesOverview(client: SupabaseClient, days: number): Promise<SalesOverview> {
  return (await call(client, 'admin_sales_overview', { p_days: days })) as unknown as SalesOverview;
}

export async function paymentAttention(client: SupabaseClient): Promise<PaymentAttention> {
  return (await call(client, 'admin_payment_attention')) as unknown as PaymentAttention;
}

export async function traffic(client: SupabaseClient, days: number): Promise<TrafficReport> {
  return (await call(client, 'admin_traffic', { p_days: days })) as unknown as TrafficReport;
}

/** Live visitors from the website's presence channel, summarised. */
export interface LiveVisitors {
  total: number;
  returningBuyers: number;
  withActiveOrder: number;
  byPage: Record<string, number>;
  byDrop: Record<string, number>;
  bySource: Record<string, number>;
}

interface PresenceMeta {
  page?: string;
  drop?: string | null;
  returning?: boolean;
  activeOrder?: boolean;
  source?: string;
}

/** One entry per visitor (presence key); a visitor with several tabs counts once, on their latest page. */
export function summarisePresence(state: Record<string, PresenceMeta[]>): LiveVisitors {
  const summary: LiveVisitors = { total: 0, returningBuyers: 0, withActiveOrder: 0, byPage: {}, byDrop: {}, bySource: {} };
  for (const metas of Object.values(state)) {
    const meta = metas[metas.length - 1];
    if (!meta) continue;
    summary.total += 1;
    if (meta.returning) summary.returningBuyers += 1;
    if (meta.activeOrder) summary.withActiveOrder += 1;
    const page = meta.page ?? 'other';
    summary.byPage[page] = (summary.byPage[page] ?? 0) + 1;
    if (meta.drop) summary.byDrop[meta.drop] = (summary.byDrop[meta.drop] ?? 0) + 1;
    const source = meta.source ?? 'other';
    summary.bySource[source] = (summary.bySource[source] ?? 0) + 1;
  }
  return summary;
}
