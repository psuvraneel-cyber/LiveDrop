'use client';

/**
 * LiveDrop — operator dashboard panels (ADR-017): live visitors and drops, sales, payments needing
 * attention, traffic history. Data comes from admin-only RPCs (migration 045) and, for live
 * visitors, from the website's anonymous presence channel. No buyer contact details are shown.
 */

import React, { useEffect, useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { Button } from '../ui/Button';
import { formatPaisaToINR } from '../../lib/utils/currency';
import { PRESENCE_CHANNEL } from '../../lib/analytics/visitor';
import {
  AdminError,
  liveDrops,
  paymentAttention,
  salesOverview,
  summarisePresence,
  traffic,
  type LiveDropRow,
  type LiveVisitors,
  type PaymentAttention,
  type SalesOverview,
  type TrafficReport,
} from '../../lib/admin/console';

interface DashProps {
  client: SupabaseClient;
  onError: (message: string | null) => void;
}

const card: React.CSSProperties = {
  border: '1px solid rgba(255,255,255,0.1)',
  borderRadius: '14px',
  padding: '14px',
  background: 'rgba(255,255,255,0.03)',
};

function messageOf(err: unknown): string {
  return err instanceof AdminError ? err.message : 'Could not load this section. Please try again.';
}

function Stat({ label, value, testId }: { label: string; value: React.ReactNode; testId?: string }) {
  return (
    <div style={card} data-testid={testId}>
      <div className="ld-form-hint" style={{ fontSize: '12px' }}>{label}</div>
      <div style={{ fontSize: '24px', fontWeight: 700, marginTop: '4px' }}>{value}</div>
    </div>
  );
}

function Grid({ children }: { children: React.ReactNode }) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: '10px', marginBottom: '16px' }}>
      {children}
    </div>
  );
}

function Bars({ rows, testId }: { rows: { label: string; value: number }[]; testId?: string }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  if (rows.length === 0) return <p className="ld-form-hint">No data yet.</p>;
  return (
    <ul style={{ listStyle: 'none', padding: 0, display: 'grid', gap: '6px' }} data-testid={testId}>
      {rows.map((r) => (
        <li key={r.label} style={{ display: 'grid', gridTemplateColumns: 'minmax(90px, 30%) 1fr 48px', gap: '8px', alignItems: 'center', fontSize: '13px' }}>
          <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.label}</span>
          <span aria-hidden="true" style={{ height: '10px', borderRadius: '6px', background: 'rgba(212,175,55,0.15)' }}>
            <span style={{ display: 'block', height: '100%', width: `${(100 * r.value) / max}%`, borderRadius: '6px', background: '#D4AF37' }} />
          </span>
          <span style={{ textAlign: 'right' }}>{r.value}</span>
        </li>
      ))}
    </ul>
  );
}

function toRows(record: Record<string, number>): { label: string; value: number }[] {
  return Object.entries(record)
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
}

function DaysPicker({ days, onChange }: { days: number; onChange: (d: number) => void }) {
  return (
    <div role="group" aria-label="Period" style={{ display: 'flex', gap: '6px', marginBottom: '14px' }}>
      {[1, 7, 30, 90].map((d) => (
        <Button key={d} size="sm" variant={days === d ? 'gold' : 'outline'} onClick={() => onChange(d)} data-testid={`days-${d}`}>
          {d === 1 ? 'Today' : `${d} days`}
        </Button>
      ))}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Live: visitors right now + every live drop
// ---------------------------------------------------------------------------
export function LivePanel({ client, onError }: DashProps) {
  const [visitors, setVisitors] = useState<LiveVisitors | null>(null);
  const [drops, setDrops] = useState<LiveDropRow[] | null>(null);

  useEffect(() => {
    const channel = client.channel(PRESENCE_CHANNEL);
    channel
      .on('presence', { event: 'sync' }, () => {
        setVisitors(summarisePresence(channel.presenceState() as Record<string, { page?: string }[]>));
      })
      .subscribe();
    return () => {
      void channel.unsubscribe();
    };
  }, [client]);

  useEffect(() => {
    let active = true;
    const load = () =>
      liveDrops(client).then(
        (rows) => { if (active) setDrops(rows); },
        (err) => { if (active) onError(messageOf(err)); }
      );
    void load();
    const timer = setInterval(load, 30_000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [client, onError]);

  const v = visitors ?? { total: 0, returningBuyers: 0, withActiveOrder: 0, byPage: {}, byDrop: {}, bySource: {} };

  return (
    <section aria-label="Live" data-testid="admin-live">
      <p className="ld-form-hint" style={{ marginBottom: '10px' }}>
        {visitors ? 'Updates as visitors arrive and leave.' : 'Connecting to live visitors…'}
      </p>
      <Grid>
        <Stat label="Visitors on the website now" value={v.total} testId="live-visitors-total" />
        <Stat label="Have ordered before" value={v.returningBuyers} testId="live-visitors-returning" />
        <Stat label="New visitors" value={v.total - v.returningBuyers} />
        <Stat label="With an unpaid order" value={v.withActiveOrder} />
      </Grid>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '12px', marginBottom: '18px' }}>
        <div style={card}>
          <strong>Where they are</strong>
          <Bars rows={toRows(v.byPage)} testId="live-by-page" />
        </div>
        <div style={card}>
          <strong>Where they came from</strong>
          <Bars rows={toRows(v.bySource)} />
        </div>
      </div>

      <h2 className="ld-form-label">Live drops</h2>
      {drops === null && <p className="ld-form-hint" role="status">Loading…</p>}
      {drops?.length === 0 && <p className="ld-form-hint" data-testid="live-drops-empty">No drop is live right now.</p>}
      <ul style={{ display: 'grid', gap: '10px', listStyle: 'none', padding: 0 }}>
        {drops?.map((d) => (
          <li key={d.id} style={card} data-testid={`live-drop-${d.slug}`}>
            <div style={{ display: 'flex', justifyContent: 'space-between', flexWrap: 'wrap', gap: '6px' }}>
              <strong>{d.title}</strong>
              <span className="ld-form-hint">{d.store_name} · /drop/{d.slug}</span>
            </div>
            <div className="ld-form-hint" style={{ display: 'flex', flexWrap: 'wrap', gap: '14px', marginTop: '6px', fontSize: '13px' }}>
              <span data-testid="live-drop-viewers">👀 {v.byDrop[d.slug] ?? 0} watching</span>
              <span>{d.available} available · {d.held} held · {d.sold} sold</span>
              <span>{d.orders_last_hour} orders in the last hour</span>
              <span>{formatPaisaToINR(d.verified_paisa_last_hour)} verified in the last hour</span>
              <span style={{ color: d.payments_waiting > 0 ? '#F5C451' : undefined }}>{d.payments_waiting} payments to verify</span>
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Sales overview
// ---------------------------------------------------------------------------
export function SalesPanel({ client, onError }: DashProps) {
  const [days, setDays] = useState(7);
  const [data, setData] = useState<SalesOverview | null>(null);

  useEffect(() => {
    let active = true;
    salesOverview(client, days).then(
      (r) => { if (active) setData(r); },
      (err) => { if (active) onError(messageOf(err)); }
    );
    return () => { active = false; };
  }, [client, days, onError]);

  return (
    <section aria-label="Sales" data-testid="admin-sales">
      <DaysPicker days={days} onChange={setDays} />
      {!data ? (
        <p className="ld-form-hint" role="status">Loading…</p>
      ) : (
        <>
          <Grid>
            <Stat label="Orders" value={data.orders} testId="sales-orders" />
            <Stat label="Paid orders" value={data.paid_orders} />
            <Stat label="Money verified by sellers" value={formatPaisaToINR(data.verified_paisa)} testId="sales-verified" />
            <Stat label="Visitors → orders" value={data.conversion_pct === null ? '—' : `${data.conversion_pct}%`} />
            <Stat label="Cancelled orders" value={data.cancelled_orders} />
            <Stat label="Refunds owed now" value={formatPaisaToINR(data.refunds_owed_paisa)} />
          </Grid>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: '12px' }}>
            <div style={card}>
              <strong>Orders per day</strong>
              <Bars rows={data.daily.map((d) => ({ label: d.date.slice(5), value: d.orders }))} />
            </div>
            <div style={card}>
              <strong>Top sellers (money verified)</strong>
              <ul style={{ listStyle: 'none', padding: 0, fontSize: '13px', display: 'grid', gap: '4px' }}>
                {data.top_sellers.length === 0 && <li className="ld-form-hint">No sales yet.</li>}
                {data.top_sellers.map((s) => (
                  <li key={s.store_slug} style={{ display: 'flex', justifyContent: 'space-between' }}>
                    <span>{s.store_name} · {s.orders} orders</span>
                    <span>{formatPaisaToINR(s.verified_paisa)}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div style={card}>
              <strong>Top products</strong>
              <ul style={{ listStyle: 'none', padding: 0, fontSize: '13px', display: 'grid', gap: '4px' }}>
                {data.top_products.length === 0 && <li className="ld-form-hint">No paid orders yet.</li>}
                {data.top_products.map((p) => (
                  <li key={`${p.store_name}-${p.code}`} style={{ display: 'flex', justifyContent: 'space-between', gap: '8px' }}>
                    <span>{p.code} {p.title ?? ''} · {p.store_name}</span>
                    <span>{formatPaisaToINR(p.revenue_paisa)}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </>
      )}
    </section>
  );
}

// ---------------------------------------------------------------------------
// Payments needing attention
// ---------------------------------------------------------------------------
export function PaymentsPanel({ client, onError }: DashProps) {
  const [data, setData] = useState<PaymentAttention | null>(null);

  useEffect(() => {
    let active = true;
    const load = () =>
      paymentAttention(client).then(
        (r) => { if (active) setData(r); },
        (err) => { if (active) onError(messageOf(err)); }
      );
    void load();
    const timer = setInterval(load, 60_000);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, [client, onError]);

  if (!data) return <p className="ld-form-hint" role="status">Loading…</p>;

  return (
    <section aria-label="Payments needing attention" data-testid="admin-payments" style={{ display: 'grid', gap: '16px' }}>
      <div style={card}>
        <strong>Waiting for the seller to verify ({data.waiting.length})</strong>
        {data.waiting.length === 0 && <p className="ld-form-hint">Nothing waiting.</p>}
        <ul style={{ listStyle: 'none', padding: 0, fontSize: '13px', display: 'grid', gap: '6px', marginTop: '6px' }}>
          {data.waiting.map((w) => (
            <li key={`${w.order_code}-${w.claimed_at}`} data-testid={`waiting-${w.order_code}`}
              style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: '6px',
                color: w.minutes_waiting > 30 ? '#F5C451' : undefined }}>
              <span>{w.order_code} · {w.store_name} · {w.payment_type}{w.status === 'late_claim_pending_review' ? ' (late)' : ''}</span>
              <span>{formatPaisaToINR(w.expected_amount_paisa)} · waiting {w.minutes_waiting} min</span>
            </li>
          ))}
        </ul>
      </div>
      <div style={card}>
        <strong>Refunds owed ({data.refunds_owed.length})</strong>
        {data.refunds_owed.length === 0 && <p className="ld-form-hint">No refunds owed.</p>}
        <ul style={{ listStyle: 'none', padding: 0, fontSize: '13px', display: 'grid', gap: '6px', marginTop: '6px' }}>
          {data.refunds_owed.map((r) => (
            <li key={r.order_code} style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: '6px' }}>
              <span>{r.order_code} · {r.store_name}{r.refund_reason ? ` · ${r.refund_reason}` : ''}</span>
              <span>{formatPaisaToINR(r.refund_amount_paisa)}</span>
            </li>
          ))}
        </ul>
        <p className="ld-form-hint" style={{ fontSize: '12px' }}>Record a paid refund in the Refunds tab.</p>
      </div>
      <div style={card}>
        <strong>Rejected in the last 7 days ({data.recently_rejected.length})</strong>
        {data.recently_rejected.length === 0 && <p className="ld-form-hint">None.</p>}
        <ul style={{ listStyle: 'none', padding: 0, fontSize: '13px', display: 'grid', gap: '6px', marginTop: '6px' }}>
          {data.recently_rejected.map((r) => (
            <li key={`${r.order_code}-${r.updated_at}`} style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', gap: '6px' }}>
              <span>{r.order_code} · {r.store_name}{r.rejection_reason ? ` · ${r.rejection_reason}` : ''}</span>
              <span>{formatPaisaToINR(r.expected_amount_paisa)}</span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

// ---------------------------------------------------------------------------
// Traffic history
// ---------------------------------------------------------------------------
export function TrafficPanel({ client, onError }: DashProps) {
  const [days, setDays] = useState(7);
  const [data, setData] = useState<TrafficReport | null>(null);

  useEffect(() => {
    let active = true;
    traffic(client, days).then(
      (r) => { if (active) setData(r); },
      (err) => { if (active) onError(messageOf(err)); }
    );
    return () => { active = false; };
  }, [client, days, onError]);

  return (
    <section aria-label="Traffic" data-testid="admin-traffic">
      <DaysPicker days={days} onChange={setDays} />
      {!data ? (
        <p className="ld-form-hint" role="status">Loading…</p>
      ) : (
        <>
          <Grid>
            <Stat label="Visitors" value={data.totals.visitors} testId="traffic-visitors" />
            <Stat label="Page views" value={data.totals.page_views} />
            <Stat label="Visitors who had ordered before" value={data.totals.returning_buyer_visitors} />
          </Grid>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(260px, 1fr))', gap: '12px' }}>
            <div style={card}>
              <strong>Visitors per day</strong>
              <Bars rows={data.daily.map((d) => ({ label: d.date.slice(5), value: d.visitors }))} testId="traffic-daily" />
            </div>
            <div style={card}>
              <strong>Sources</strong>
              <Bars rows={data.by_source.map((s) => ({ label: s.source, value: s.visitors }))} />
            </div>
            <div style={card}>
              <strong>Devices</strong>
              <Bars rows={data.by_device.map((s) => ({ label: s.device, value: s.visitors }))} />
            </div>
            <div style={card}>
              <strong>Pages</strong>
              <Bars rows={data.by_page.map((s) => ({ label: s.page, value: s.views }))} />
            </div>
            <div style={card}>
              <strong>Most visited drops</strong>
              <Bars rows={data.top_drops.map((s) => ({ label: s.drop_slug, value: s.visitors }))} />
            </div>
          </div>
          <p className="ld-form-hint" style={{ fontSize: '12px', marginTop: '10px' }}>
            Anonymous counts only; visitors who opted out or use Do Not Track are not counted. Records older than 180 days are deleted.
          </p>
        </>
      )}
    </section>
  );
}
