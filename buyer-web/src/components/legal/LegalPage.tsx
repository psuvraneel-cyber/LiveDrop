import React, { ReactNode } from 'react';
import Link from 'next/link';
import { LEGAL } from '../../lib/legal/legal-config';

export const LEGAL_LINKS = [
  { href: '/privacy', label: 'Privacy Policy' },
  { href: '/terms', label: 'Terms of Use' },
  { href: '/refund-policy', label: 'Refunds & Returns' },
  { href: '/grievance', label: 'Grievances & Contact' },
] as const;

export function LegalPage({ title, children }: { title: string; children: ReactNode }) {
  return (
    <main className="ld-container" style={{ paddingTop: '40px', paddingBottom: '64px', maxWidth: '820px' }}>
      <nav aria-label="Legal pages" className="ld-form-hint" style={{ display: 'flex', flexWrap: 'wrap', gap: '14px', marginBottom: '24px' }}>
        <Link href="/">← LiveDrop</Link>
        {LEGAL_LINKS.map((l) => (
          <Link key={l.href} href={l.href}>
            {l.label}
          </Link>
        ))}
      </nav>
      <article className="ld-legal" data-testid="legal-page">
        <h1 className="ld-checkout-card-title" style={{ marginBottom: '6px' }}>
          {title}
        </h1>
        <p className="ld-form-hint" style={{ marginBottom: '24px' }}>
          Effective {LEGAL.effectiveDate}
        </p>
        <div className="ld-legal-body" style={{ display: 'grid', gap: '18px', lineHeight: 1.65, fontSize: '15px' }}>
          {children}
        </div>
      </article>
    </main>
  );
}

export function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section style={{ display: 'grid', gap: '8px' }}>
      <h2 style={{ fontSize: '18px', fontWeight: 600 }}>{title}</h2>
      {children}
    </section>
  );
}
