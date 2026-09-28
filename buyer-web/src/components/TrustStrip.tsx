'use client';

import React from 'react';

export function TrustStrip() {
  return (
    <section
      className="py-4 px-4 rounded-xl bg-[#121211] border border-white/5 text-center shadow-sm"
      aria-label="Buyer Trust Assurances"
    >
      <div className="flex flex-wrap items-center justify-center gap-x-4 gap-y-1.5 text-xs text-[#AAA49A]">
        <span className="text-[#C79A45] font-medium tracking-wide">Direct UPI</span>
        <span className="text-white/20" aria-hidden="true">•</span>
        <span className="text-[#C79A45] font-medium tracking-wide">Instant Reservation</span>
        <span className="text-white/20" aria-hidden="true">•</span>
        <span className="text-[#C79A45] font-medium tracking-wide">Independent Boutiques</span>
      </div>
    </section>
  );
}
