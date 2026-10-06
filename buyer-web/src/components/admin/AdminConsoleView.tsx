'use client';

/**
 * LiveDrop — operator console (/admin, SA-OPS-002 / SA-ONB-001, ADR-016)
 *
 * Approve or suspend sellers and record refunds without the SQL editor. Access is decided by the
 * admin_* RPCs (migration 042); this page only shows what they return. Buyer phone numbers and
 * addresses are never requested.
 */

import React, { useCallback, useEffect, useRef, useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { Button } from '../ui/Button';
import { formatPaisaToINR } from '../../lib/utils/currency';
import {
  AdminError,
  createAdminClient,
  findOrder,
  isAdmin,
  listSellers,
  recordRefund,
  refundsDue,
  setSellerApproval,
  type AdminOrder,
  type AdminSeller,
  type SellerFilter,
} from '../../lib/admin/console';
import { LivePanel, PaymentsPanel, SalesPanel, TrafficPanel } from './AdminDashboardPanels';
import { missingLegalFields } from '../../lib/legal/legal-config';

const missingLegal = missingLegalFields();

export const NOT_ADMIN_MESSAGE = 'This account is not a LiveDrop administrator.';
const SETUP_MESSAGE = 'The admin console is not available right now. Please try again later.';

export interface AdminConsoleViewProps {
  /** Test seam; production uses the isolated in-memory admin client. */
  clientFactory?: () => SupabaseClient;
}

type Tab = 'live' | 'sales' | 'payments' | 'traffic' | 'sellers' | 'refunds';

const TABS: { id: Tab; label: string }[] = [
  { id: 'live', label: 'Live' },
  { id: 'sales', label: 'Sales' },
  { id: 'payments', label: 'Payments' },
  { id: 'traffic', label: 'Traffic' },
  { id: 'sellers', label: 'Sellers' },
  { id: 'refunds', label: 'Refunds' },
];

function messageOf(err: unknown): string {
  return err instanceof AdminError ? err.message : 'Something went wrong. Please try again.';
}

function formatDate(value: string | null): string {
  if (!value) return '—';
  return new Date(value).toLocaleString('en-IN', { dateStyle: 'medium', timeStyle: 'short' });
}

export function AdminConsoleView({ clientFactory = createAdminClient }: AdminConsoleViewProps) {
  const clientRef = useRef<SupabaseClient | null>(null);
  const [session, setSession] = useState<{ email: string; client: SupabaseClient } | null>(null);
  const signedInEmail = session?.email ?? null;
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [tab, setTab] = useState<Tab>('live');

  // Writes after 10 minutes need the password again; the action waits here meanwhile.
  const [reauthAction, setReauthAction] = useState<(() => Promise<void>) | null>(null);
  const [reauthPassword, setReauthPassword] = useState('');

  const client = useCallback((): SupabaseClient => {
    if (!clientRef.current) clientRef.current = clientFactory();
    return clientRef.current;
  }, [clientFactory]);

  const handleSignIn = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!email.trim() || !password) {
      setError('Enter your e-mail and password.');
      return;
    }
    setBusy(true);
    try {
      let c: SupabaseClient;
      try {
        c = client();
      } catch {
        setError(SETUP_MESSAGE);
        return;
      }
      const { error: authError } = await c.auth.signInWithPassword({ email: email.trim(), password });
      if (authError) {
        setError('Wrong e-mail or password.');
        return;
      }
      if (!(await isAdmin(c))) {
        await c.auth.signOut();
        setError(NOT_ADMIN_MESSAGE);
        return;
      }
      setSession({ email: email.trim(), client: c });
    } catch (err) {
      setError(messageOf(err));
    } finally {
      setPassword('');
      setBusy(false);
    }
  };

  const handleSignOut = async () => {
    try {
      await clientRef.current?.auth.signOut();
    } finally {
      setSession(null);
      setNotice(null);
      setError(null);
    }
  };

  /** Runs a write; on REAUTH_REQUIRED asks for the password and retries once it is entered. */
  const runWrite = useCallback(async (action: () => Promise<void>) => {
    setError(null);
    setNotice(null);
    try {
      await action();
    } catch (err) {
      if (err instanceof AdminError && err.code === 'REAUTH_REQUIRED') {
        setReauthAction(() => action);
        return;
      }
      setError(messageOf(err));
    }
  }, []);

  const handleReauth = async (e: React.FormEvent) => {
    e.preventDefault();
    const action = reauthAction;
    if (!action || !session) return;
    setBusy(true);
    try {
      const { error: authError } = await session.client.auth.signInWithPassword({ email: session.email, password: reauthPassword });
      if (authError) {
        setError('Wrong password.');
        return;
      }
      setReauthAction(null);
      await runWrite(action);
    } finally {
      setReauthPassword('');
      setBusy(false);
    }
  };

  if (!session) {
    return (
      <main className="ld-container" style={{ paddingTop: '48px', paddingBottom: '48px', maxWidth: '480px' }}>
        <section className="ld-checkout-section" aria-labelledby="admin-title" data-testid="admin-sign-in">
          <div className="ld-checkout-section-header">
            <h1 id="admin-title" className="ld-checkout-card-title">LiveDrop admin</h1>
            <p className="ld-checkout-card-subtitle">Approve sellers and record refunds</p>
          </div>
          <form className="ld-checkout-form-fields" onSubmit={handleSignIn} noValidate>
            <div className="ld-form-group">
              <label htmlFor="admin_email" className="ld-form-label">E-mail</label>
              <input id="admin_email" type="email" className="ld-form-input" value={email} autoComplete="username"
                disabled={busy} onChange={(e) => setEmail(e.target.value)} data-testid="admin-email" />
            </div>
            <div className="ld-form-group">
              <label htmlFor="admin_password" className="ld-form-label">Password</label>
              <input id="admin_password" type="password" className="ld-form-input" value={password}
                autoComplete="current-password" disabled={busy} onChange={(e) => setPassword(e.target.value)}
                data-testid="admin-password" />
            </div>
            {error && <p className="ld-field-error" role="alert" data-testid="admin-error"><span>{error}</span></p>}
            <button type="submit" className="ld-btn-submit-order" disabled={busy} data-testid="admin-sign-in-submit">
              {busy ? 'Signing in…' : 'Sign in'}
            </button>
          </form>
        </section>
      </main>
    );
  }

  return (
    <main className="ld-container" style={{ paddingTop: '32px', paddingBottom: '48px', maxWidth: '960px' }}>
      <header style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', alignItems: 'center', justifyContent: 'space-between', marginBottom: '20px' }}>
        <div>
          <h1 className="ld-checkout-card-title">LiveDrop admin</h1>
          <p className="ld-form-hint">Signed in as {signedInEmail}. Every action is logged.</p>
        </div>
        <Button variant="outline" size="sm" onClick={handleSignOut} data-testid="admin-sign-out">Sign out</Button>
      </header>

      {missingLegal.length > 0 && (
        <p className="ld-field-error" role="note" data-testid="admin-legal-missing" style={{ marginBottom: '12px' }}>
          <span>
            Legal pages are missing: {missingLegal.join(', ')}. Fill them in buyer-web/src/lib/legal/legal-config.ts before
            real customers use the site.
          </span>
        </p>
      )}

      <nav role="tablist" aria-label="Admin sections" style={{ display: 'flex', flexWrap: 'wrap', gap: '8px', marginBottom: '16px' }}>
        {TABS.map((t) => (
          <Button key={t.id} role="tab" aria-selected={tab === t.id} variant={tab === t.id ? 'gold' : 'outline'} size="sm"
            onClick={() => setTab(t.id)} data-testid={`admin-tab-${t.id}`}>
            {t.label}
          </Button>
        ))}
      </nav>

      {notice && <p className="ld-form-hint" role="status" data-testid="admin-notice">{notice}</p>}
      {error && <p className="ld-field-error" role="alert" data-testid="admin-error"><span>{error}</span></p>}

      {reauthAction && (
        <form className="ld-checkout-section" onSubmit={handleReauth} data-testid="admin-reauth">
          <p className="ld-form-hint">For your security, enter your password again to continue.</p>
          <div className="ld-form-group">
            <label htmlFor="admin_reauth" className="ld-form-label">Password</label>
            <input id="admin_reauth" type="password" className="ld-form-input" value={reauthPassword}
              autoComplete="current-password" disabled={busy} onChange={(e) => setReauthPassword(e.target.value)}
              data-testid="admin-reauth-password" />
          </div>
          <div style={{ display: 'flex', gap: '8px' }}>
            <Button type="submit" size="sm" disabled={busy || !reauthPassword} data-testid="admin-reauth-submit">Continue</Button>
            <Button type="button" variant="ghost" size="sm" onClick={() => setReauthAction(null)}>Cancel</Button>
          </div>
        </form>
      )}

      {tab === 'live' && <LivePanel client={session.client} onError={setError} />}
      {tab === 'sales' && <SalesPanel client={session.client} onError={setError} />}
      {tab === 'payments' && <PaymentsPanel client={session.client} onError={setError} />}
      {tab === 'traffic' && <TrafficPanel client={session.client} onError={setError} />}
      {tab === 'sellers' && <SellersPanel client={session.client} runWrite={runWrite} onNotice={setNotice} onError={setError} />}
      {tab === 'refunds' && <RefundsPanel client={session.client} runWrite={runWrite} onNotice={setNotice} onError={setError} />}
    </main>
  );
}

interface PanelProps {
  client: SupabaseClient;
  runWrite: (action: () => Promise<void>) => Promise<void>;
  onNotice: (message: string | null) => void;
  onError: (message: string | null) => void;
}

const FILTERS: { value: SellerFilter; label: string }[] = [
  { value: 'pending', label: 'Waiting for approval' },
  { value: 'approved', label: 'Approved' },
  { value: 'suspended', label: 'Suspended' },
  { value: 'all', label: 'All' },
];

function SellersPanel({ client, runWrite, onNotice, onError }: PanelProps) {
  const [filter, setFilter] = useState<SellerFilter>('pending');
  const [sellers, setSellers] = useState<AdminSeller[] | null>(null);
  const [suspending, setSuspending] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [reloadKey, setReloadKey] = useState(0);
  const load = () => setReloadKey((k) => k + 1);

  useEffect(() => {
    let active = true;
    listSellers(client, filter).then(
      (rows) => { if (active) setSellers(rows); },
      (err) => { if (active) { setSellers([]); onError(messageOf(err)); } }
    );
    return () => { active = false; };
  }, [client, filter, reloadKey, onError]);

  const approve = (s: AdminSeller) =>
    runWrite(async () => {
      onNotice(`${s.store_name}: ${await setSellerApproval(client, s.id, true)}`);
      load();
    });

  const suspend = (s: AdminSeller) =>
    runWrite(async () => {
      onNotice(`${s.store_name}: ${await setSellerApproval(client, s.id, false, reason)}`);
      setSuspending(null);
      setReason('');
      load();
    });

  return (
    <section aria-label="Sellers" data-testid="admin-sellers">
      <label className="ld-form-label" htmlFor="seller_filter">Show</label>
      <select id="seller_filter" className="ld-form-input" value={filter} style={{ maxWidth: '260px', marginBottom: '16px' }}
        onChange={(e) => setFilter(e.target.value as SellerFilter)} data-testid="admin-seller-filter">
        {FILTERS.map((f) => <option key={f.value} value={f.value}>{f.label}</option>)}
      </select>

      {sellers === null && <p className="ld-form-hint" role="status">Loading…</p>}
      {sellers?.length === 0 && <p className="ld-form-hint" data-testid="admin-sellers-empty">No sellers here.</p>}

      <ul style={{ display: 'grid', gap: '12px', listStyle: 'none', padding: 0 }}>
        {sellers?.map((s) => (
          <li key={s.id} className="ld-checkout-section" data-testid={`admin-seller-${s.store_slug}`}>
            <div style={{ display: 'flex', justifyContent: 'space-between', gap: '8px', flexWrap: 'wrap' }}>
              <strong>{s.store_name}</strong>
              <span className="ld-form-hint" data-testid="admin-seller-status">{s.status}</span>
            </div>
            <dl className="ld-form-hint" style={{ display: 'grid', gridTemplateColumns: 'max-content 1fr', gap: '2px 12px', margin: '8px 0' }}>
              <dt>Store link</dt><dd>/{s.store_slug}</dd>
              <dt>E-mail</dt><dd>{s.email ?? '—'} {s.email_confirmed ? '(confirmed)' : '(not confirmed)'}</dd>
              <dt>Phone</dt><dd>{s.phone_number ?? '—'}</dd>
              <dt>UPI</dt><dd>{s.upi_id ?? '—'}</dd>
              <dt>Onboarding fee UTR</dt><dd data-testid="admin-seller-utr">{s.onboarding_fee_utr ?? 'not given'}</dd>
              <dt>Signed up</dt><dd>{formatDate(s.created_at)}</dd>
              {s.last_suspension_reason && (<><dt>Last suspension</dt><dd>{s.last_suspension_reason}</dd></>)}
            </dl>
            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
              {s.status !== 'approved' && (
                <Button size="sm" onClick={() => approve(s)} data-testid="admin-approve">Approve</Button>
              )}
              {s.status !== 'suspended' && suspending !== s.id && (
                <Button size="sm" variant="outline" onClick={() => { setSuspending(s.id); setReason(''); }} data-testid="admin-suspend">
                  Suspend
                </Button>
              )}
            </div>
            {suspending === s.id && (
              <div style={{ marginTop: '12px' }}>
                <label className="ld-form-label" htmlFor={`reason_${s.id}`}>Reason (the seller&apos;s live drops close immediately)</label>
                <input id={`reason_${s.id}`} className="ld-form-input" value={reason} maxLength={500}
                  onChange={(e) => setReason(e.target.value)} data-testid="admin-suspend-reason" />
                <div style={{ display: 'flex', gap: '8px', marginTop: '8px' }}>
                  <Button size="sm" variant="danger" disabled={reason.trim().length < 3} onClick={() => suspend(s)}
                    data-testid="admin-suspend-confirm">Suspend seller</Button>
                  <Button size="sm" variant="ghost" onClick={() => setSuspending(null)}>Cancel</Button>
                </div>
              </div>
            )}
          </li>
        ))}
      </ul>
    </section>
  );
}

function RefundsPanel({ client, runWrite, onNotice, onError }: PanelProps) {
  const [orders, setOrders] = useState<AdminOrder[] | null>(null);
  const [code, setCode] = useState('');
  const [found, setFound] = useState<AdminOrder | null>(null);
  const [recording, setRecording] = useState<string | null>(null);
  const [reference, setReference] = useState('');
  const [note, setNote] = useState('');
  const [reloadKey, setReloadKey] = useState(0);
  const load = () => setReloadKey((k) => k + 1);

  useEffect(() => {
    let active = true;
    refundsDue(client).then(
      (rows) => { if (active) setOrders(rows); },
      (err) => { if (active) { setOrders([]); onError(messageOf(err)); } }
    );
    return () => { active = false; };
  }, [client, reloadKey, onError]);

  const search = async (e: React.FormEvent) => {
    e.preventDefault();
    onError(null);
    setFound(null);
    try {
      setFound(await findOrder(client, code));
    } catch (err) {
      onError(messageOf(err));
    }
  };

  const record = (o: AdminOrder) =>
    runWrite(async () => {
      onNotice(`${o.order_code}: ${await recordRefund(client, o.id, reference, note)}`);
      setRecording(null);
      setReference('');
      setNote('');
      if (found?.id === o.id) setFound(await findOrder(client, o.order_code));
      load();
    });

  const card = (o: AdminOrder) => (
    <li key={o.id} className="ld-checkout-section" data-testid={`admin-order-${o.order_code}`}>
      <div style={{ display: 'flex', justifyContent: 'space-between', gap: '8px', flexWrap: 'wrap' }}>
        <strong>{o.order_code}</strong>
        <span className="ld-form-hint">{o.store_name ?? ''} · order {o.status}</span>
      </div>
      <p className="ld-form-hint" style={{ margin: '6px 0' }}>
        Paid {formatPaisaToINR(o.total_paid_paisa)} of {formatPaisaToINR(o.total_paisa)}.{' '}
        {o.refund_status === 'required' && <>Refund owed: <strong>{formatPaisaToINR(o.refund_amount_paisa)}</strong>{o.refund_reason ? ` — ${o.refund_reason}` : ''}</>}
        {o.refund_status === 'refunded' && <>Refunded {formatPaisaToINR(o.refund_amount_paisa)} on {formatDate(o.refunded_at)} (ref {o.refund_reference}).</>}
        {o.refund_status === 'none' && <>No refund owed.</>}
      </p>
      {o.refund_status === 'required' && recording !== o.id && (
        <Button size="sm" onClick={() => { setRecording(o.id); setReference(''); setNote(''); }} data-testid="admin-record-refund">
          Record refund paid
        </Button>
      )}
      {recording === o.id && (
        <div style={{ display: 'grid', gap: '8px', marginTop: '8px' }}>
          <label className="ld-form-label" htmlFor={`ref_${o.id}`}>Refund UTR / reference</label>
          <input id={`ref_${o.id}`} className="ld-form-input" value={reference} maxLength={64}
            onChange={(e) => setReference(e.target.value)} data-testid="admin-refund-reference" />
          <label className="ld-form-label" htmlFor={`note_${o.id}`}>Note (optional)</label>
          <input id={`note_${o.id}`} className="ld-form-input" value={note} maxLength={500}
            onChange={(e) => setNote(e.target.value)} data-testid="admin-refund-note" />
          <div style={{ display: 'flex', gap: '8px' }}>
            <Button size="sm" disabled={reference.trim().length < 4} onClick={() => record(o)} data-testid="admin-refund-confirm">
              Save refund
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setRecording(null)}>Cancel</Button>
          </div>
        </div>
      )}
    </li>
  );

  return (
    <section aria-label="Refunds" data-testid="admin-refunds">
      <form onSubmit={search} style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'flex-end', marginBottom: '16px' }}>
        <div className="ld-form-group" style={{ flex: '1 1 200px' }}>
          <label htmlFor="order_code" className="ld-form-label">Find an order</label>
          <input id="order_code" className="ld-form-input" placeholder="LD-ABC123" value={code}
            onChange={(e) => setCode(e.target.value)} data-testid="admin-order-code" />
        </div>
        <Button type="submit" size="sm" variant="outline" disabled={!code.trim()} data-testid="admin-order-search">Find</Button>
      </form>
      {found && <ul style={{ listStyle: 'none', padding: 0, marginBottom: '20px' }}>{card(found)}</ul>}

      <h2 className="ld-form-label">Refunds owed</h2>
      {orders === null && <p className="ld-form-hint" role="status">Loading…</p>}
      {orders?.length === 0 && <p className="ld-form-hint" data-testid="admin-refunds-empty">No refunds owed.</p>}
      <ul style={{ display: 'grid', gap: '12px', listStyle: 'none', padding: 0 }}>{orders?.map(card)}</ul>
    </section>
  );
}
