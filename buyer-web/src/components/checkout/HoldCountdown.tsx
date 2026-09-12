'use client';

import React, { useEffect, useState } from 'react';

export interface HoldCountdownProps {
  expiresAt: string | null;
}

/**
 * Presentation-only countdown timer for active garment holds.
 *
 * CRITICAL RULE: This timer is strictly informational.
 * Authoritative expiration is determined exclusively by the database engine.
 */
export function HoldCountdown({ expiresAt }: HoldCountdownProps) {
  const [secondsRemaining, setSecondsRemaining] = useState<number | null>(() => {
    if (!expiresAt) return null;
    const diff = Math.floor((new Date(expiresAt).getTime() - Date.now()) / 1000);
    return Math.max(0, diff);
  });

  useEffect(() => {
    if (!expiresAt) return;

    const interval = setInterval(() => {
      const diff = Math.floor((new Date(expiresAt).getTime() - Date.now()) / 1000);
      setSecondsRemaining(Math.max(0, diff));
      if (diff <= 0) {
        clearInterval(interval);
      }
    }, 1000);

    return () => clearInterval(interval);
  }, [expiresAt]);

  if (secondsRemaining === null) {
    return null;
  }

  if (secondsRemaining <= 0) {
    return (
      <div className="ld-hold-timer-pill expired" data-testid="hold-countdown-expired">
        <span className="ld-hold-timer-icon" aria-hidden="true">⏱️</span>
        <span>Hold period has expired</span>
      </div>
    );
  }

  const minutes = Math.floor(secondsRemaining / 60);
  const seconds = secondsRemaining % 60;
  const formatted = `${minutes}:${seconds.toString().padStart(2, '0')}`;

  return (
    <div className="ld-hold-timer-pill" data-testid="hold-countdown">
      <span className="ld-hold-timer-icon" aria-hidden="true">⏱️</span>
      <span>
        Hold expires in <strong className="ld-countdown-clock">{formatted}</strong>
      </span>
    </div>
  );
}
