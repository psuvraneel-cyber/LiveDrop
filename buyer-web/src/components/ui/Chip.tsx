import React from 'react';
import { motion, type HTMLMotionProps } from 'motion/react';

export interface ChipProps extends Omit<HTMLMotionProps<'button'>, 'children' | 'icon'> {
  selected?: boolean;
  icon?: React.ReactNode;
  children: React.ReactNode;
}

export function Chip({
  selected = false,
  icon,
  children,
  className = '',
  ...props
}: ChipProps) {
  return (
    <motion.button
      type="button"
      whileTap={{ scale: 0.96 }}
      className={`ld-chip inline-flex items-center gap-2 rounded-full border px-4 py-2 text-xs font-medium transition-colors cursor-pointer select-none focus-visible:outline-2 focus-visible:outline-[#f3c653] focus-visible:outline-offset-2 ${
        selected
          ? 'border-[#f3c653]/60 bg-gradient-to-r from-[#ffe18e] to-[#edae2f] font-bold text-black shadow-md'
          : 'border-white/10 bg-[#121512] text-[#f8f4ec] hover:border-white/25 hover:bg-white/5'
      } ${className}`.trim()}
      {...props}
    >
      {icon && <span aria-hidden="true">{icon}</span>}
      <span>{children}</span>
    </motion.button>
  );
}
