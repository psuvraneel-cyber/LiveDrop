import React from 'react';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'gold' | 'outline' | 'ghost' | 'danger';
  size?: 'sm' | 'md' | 'lg';
  fullWidth?: boolean;
  children: React.ReactNode;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = 'gold',
    size = 'md',
    fullWidth = false,
    className = '',
    children,
    disabled,
    ...props
  },
  ref
) {
  const baseClasses =
    'inline-flex items-center justify-center gap-2 rounded-full font-semibold transition-all duration-200 select-none focus-visible:outline-2 focus-visible:outline-[#f3c653] focus-visible:outline-offset-2 active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed disabled:active:scale-100';

  const sizeClasses = {
    sm: 'text-xs px-3.5 py-1.5 min-h-[36px]',
    md: 'text-xs sm:text-sm px-5 py-2.5 min-h-[44px]',
    lg: 'text-sm sm:text-base px-6 py-3 min-h-[48px]',
  }[size];

  const variantClasses = {
    gold: 'bg-gradient-to-r from-[#ffe18e] via-[#f3c653] to-[#d89f2a] text-[#08080a] shadow-[0_4px_20px_rgba(243,198,83,0.25)] hover:shadow-[0_6px_24px_rgba(243,198,83,0.35)] hover:brightness-105',
    outline: 'border border-white/15 bg-white/5 text-[#f8f4ec] hover:bg-white/10 hover:border-white/25',
    ghost: 'text-[#b7b0a4] hover:text-[#f8f4ec] hover:bg-white/5',
    danger: 'bg-[#ff375f] text-white hover:bg-[#ff1f4b] shadow-lg shadow-red-950/40',
  }[variant];

  const widthClass = fullWidth ? 'w-full' : '';

  return (
    <button
      ref={ref}
      disabled={disabled}
      className={`${baseClasses} ${sizeClasses} ${variantClasses} ${widthClass} ${className}`.trim()}
      {...props}
    >
      {children}
    </button>
  );
});
