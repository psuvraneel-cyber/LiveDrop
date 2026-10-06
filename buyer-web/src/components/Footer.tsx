'use client';

import React from 'react';
import Link from 'next/link';
import { LEGAL_LINKS } from './legal/LegalPage';
import { LEGAL } from '../lib/legal/legal-config';

export function Footer() {
  return (
    <footer className="w-full border-t border-white/10 bg-[#090909] py-8 sm:py-10 px-4 sm:px-6 lg:px-8 text-center text-xs text-[#AAA49A]">
      <div className="max-w-7xl mx-auto space-y-4">
        {/* Responsive Navigation Links */}
        <nav className="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 text-xs font-medium tracking-wide" aria-label="Footer Navigation">
          <Link href="/" className="text-[#F4F1EA]/80 hover:text-[#D4AF37] transition-colors min-h-[36px] inline-flex items-center">
            Home
          </Link>
          <Link href="/shop" className="text-[#F4F1EA]/80 hover:text-[#D4AF37] transition-colors min-h-[36px] inline-flex items-center">
            Shop All
          </Link>
          <Link href="/#live-drops" className="text-[#F4F1EA]/80 hover:text-[#D4AF37] transition-colors min-h-[36px] inline-flex items-center">
            Live Drops
          </Link>
          <Link href="/#boutiques" className="text-[#F4F1EA]/80 hover:text-[#D4AF37] transition-colors min-h-[36px] inline-flex items-center">
            Boutiques
          </Link>
          <Link href="/order" className="text-[#F4F1EA]/80 hover:text-[#D4AF37] transition-colors min-h-[36px] inline-flex items-center">
            Orders
          </Link>
        </nav>

        <nav className="flex flex-wrap items-center justify-center gap-x-5 gap-y-1 text-[11px]" aria-label="Legal" data-testid="footer-legal-links">
          {LEGAL_LINKS.map((l) => (
            <Link key={l.href} href={l.href} className="text-[#AAA49A] hover:text-[#D4AF37] transition-colors min-h-[32px] inline-flex items-center">
              {l.label}
            </Link>
          ))}
        </nav>

        <div className="space-y-1 pt-1">
          <p className="font-serif text-sm text-[#F4F1EA] tracking-wider">LiveDrop</p>
          <p className="text-[11px] text-[#AAA49A]/80">Haute-couture live commerce for independent Indian fashion boutiques.</p>
        </div>

        <p className="font-mono text-[10px] text-white/30 pt-1">
          © {new Date().getFullYear()} {LEGAL.operatorName ?? 'LiveDrop'}. All rights reserved.
        </p>
      </div>
    </footer>
  );
}
