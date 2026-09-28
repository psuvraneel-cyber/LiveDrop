import React from 'react';

export interface BadgeProps extends React.HTMLAttributes<HTMLSpanElement> {
  variant?: 'live' | 'available' | 'reserved' | 'sold' | 'gold' | 'flash' | 'neutral';
  children?: React.ReactNode;
}

export function Badge({
  variant = 'neutral',
  className = '',
  children,
  ...props
}: BadgeProps) {
  const baseClasses =
    'inline-flex items-center gap-1.5 rounded-full font-mono text-[10px] uppercase font-bold tracking-wider select-none';

  const variantClasses = {
    live: 'bg-[#ff375f]/15 border border-[#ff375f]/40 text-[#ff375f] px-2.5 py-0.5',
    available: 'bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 px-2 py-0.5',
    reserved: 'bg-amber-500/15 border border-amber-500/30 text-amber-400 px-2 py-0.5',
    sold: 'bg-zinc-800/80 border border-zinc-700 text-zinc-400 px-2 py-0.5',
    gold: 'bg-[#f3c653]/15 border border-[#f3c653]/35 text-[#f3c653] px-2.5 py-0.5',
    flash: 'bg-black/75 border border-white/15 text-[#f8f4ec] font-bold px-2 py-0.5 backdrop-blur-md',
    neutral: 'bg-white/5 border border-white/10 text-[#b7b0a4] px-2 py-0.5',
  }[variant];

  return (
    <span className={`${baseClasses} ${variantClasses} ${className}`.trim()} {...props}>
      {variant === 'live' && (
        <span className="h-1.5 w-1.5 rounded-full bg-[#ff375f] animate-pulse" aria-hidden="true" />
      )}
      {children}
    </span>
  );
}
