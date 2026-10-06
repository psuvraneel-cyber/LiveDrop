'use client';

import React, { useEffect, useState } from 'react';
import { isAnalyticsAllowed, setAnalyticsOptOut } from '../../lib/analytics/visitor';

/** On /privacy: switch anonymous visit counting on or off for this browser. */
export function AnalyticsPreference() {
  const [allowed, setAllowed] = useState<boolean | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => setAllowed(isAnalyticsAllowed()), 0);
    return () => clearTimeout(timer);
  }, []);

  if (allowed === null) return null;

  return (
    <div data-testid="analytics-preference" style={{ display: 'flex', flexWrap: 'wrap', gap: '12px', alignItems: 'center' }}>
      <span>Anonymous visit counting is {allowed ? 'on' : 'off'} for this browser.</span>
      <button
        type="button"
        className="ld-copy-btn"
        data-testid="analytics-toggle"
        onClick={() => {
          setAnalyticsOptOut(allowed);
          setAllowed(isAnalyticsAllowed());
        }}
      >
        {allowed ? 'Turn off' : 'Turn on'}
      </button>
    </div>
  );
}
