'use client';

import React from 'react';
import Link from 'next/link';

export interface SectionTitleProps {
  title: string;
  subtitle?: string;
  actionHref?: string;
  actionLabel?: string;
  actionTestId?: string;
}

export function SectionTitle({
  title,
  subtitle,
  actionHref,
  actionLabel,
  actionTestId,
}: SectionTitleProps) {
  return (
    <div className="flex items-center justify-between border-b border-white/10 pb-3">
      <div>
        <h2 className="text-xl sm:text-2xl font-serif text-[#F4F1EA] tracking-wide">
          {title}
        </h2>
        {subtitle && (
          <span className="text-xs text-[#AAA49A] block mt-0.5">
            {subtitle}
          </span>
        )}
      </div>
      {actionHref && actionLabel && (
        <Link
          href={actionHref}
          className="text-xs sm:text-sm text-[#C79A45] hover:text-[#E2C27A] font-sans font-medium transition-colors focus-visible:outline-2 focus-visible:outline-[#C79A45] focus-visible:outline-offset-2"
          data-testid={actionTestId}
        >
          {actionLabel}
        </Link>
      )}
    </div>
  );
}
