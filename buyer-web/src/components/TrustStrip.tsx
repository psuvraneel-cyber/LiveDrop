'use client';

import React from 'react';
import { QrCode, Timer, Store } from 'lucide-react';

const ASSURANCES = [
  {
    icon: QrCode,
    label: 'Direct UPI',
    detail: 'Pay the boutique directly from any UPI app.',
  },
  {
    icon: Timer,
    label: 'Instant Reservation',
    detail: 'Your piece is held for you the moment you check out.',
  },
  {
    icon: Store,
    label: 'Independent Boutiques',
    detail: 'Single-piece originals from approved Indian ateliers.',
  },
];

export function TrustStrip() {
  return (
    <section
      className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4"
      aria-label="Buyer Trust Assurances"
    >
      {ASSURANCES.map(({ icon: Icon, label, detail }) => (
        <div
          key={label}
          className="ld-trust-tile flex items-start gap-3 p-4 rounded-xl border border-white/5"
        >
          <span
            className="flex-shrink-0 w-10 h-10 rounded-full flex items-center justify-center bg-[#C79A45]/10 border border-[#C79A45]/30 text-[#D4AF37]"
            aria-hidden="true"
          >
            <Icon size={18} strokeWidth={1.75} />
          </span>
          <div className="min-w-0">
            <span className="block text-sm text-[#E2C27A] font-semibold tracking-wide">{label}</span>
            <span className="block mt-0.5 text-xs text-[#AAA49A] leading-relaxed">{detail}</span>
          </div>
        </div>
      ))}
    </section>
  );
}
