'use client';

import React, { useState, useEffect } from 'react';
import { detectInAppBrowser, getExternalBrowserIntentUrl, InAppBrowserInfo } from '../lib/utils/in-app-browser';

export function InAppBrowserBanner() {
  const [iabInfo, setIabInfo] = useState<InAppBrowserInfo | null>(null);
  const [isDismissed, setIsDismissed] = useState(true);
  const [showIosGuide, setShowIosGuide] = useState(false);
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    const info = detectInAppBrowser();
    if (info.isInApp) {
      try {
        const dismissed = sessionStorage.getItem('ld_dismiss_iab_banner');
        if (!dismissed) {
          setIabInfo(info);
          setIsDismissed(false);
        }
      } catch {
        setIabInfo(info);
        setIsDismissed(false);
      }
    }
  }, []);

  if (isDismissed || !iabInfo || !iabInfo.isInApp) {
    return null;
  }

  const handleDismiss = () => {
    setIsDismissed(true);
    try {
      sessionStorage.setItem('ld_dismiss_iab_banner', '1');
    } catch {
      // Ignored
    }
  };

  const handleOpenBrowser = () => {
    if (typeof window === 'undefined') return;
    const currentUrl = window.location.href;

    if (iabInfo.os === 'android') {
      const intentUrl = getExternalBrowserIntentUrl(currentUrl, 'android');
      window.location.href = intentUrl;
    } else {
      setShowIosGuide(true);
    }
  };

  const handleCopyLink = async () => {
    if (typeof window === 'undefined') return;
    try {
      await navigator.clipboard.writeText(window.location.href);
      setCopied(true);
      setTimeout(() => setCopied(false), 2500);
    } catch {
      // Fallback
    }
  };

  const targetBrowserName = iabInfo.os === 'ios' ? 'Safari' : 'Chrome';

  return (
    <>
      <aside
        className="ld-iab-banner"
        role="alert"
        aria-label="In-app browser recommendation"
        data-testid="iab-banner"
        style={{
          backgroundColor: '#1E1E24',
          borderBottom: '1px solid #F59E0B',
          padding: '10px 16px',
          color: '#FFFFFF',
          fontSize: '13px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          gap: '12px',
          zIndex: 100,
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flex: 1 }}>
          <span style={{ fontSize: '16px' }} aria-hidden="true">
            ⚡
          </span>
          <div>
            <span style={{ fontWeight: 600, color: '#F59E0B' }}>
              {iabInfo.browserDisplayName || 'Social'} In-App Browser Detected
            </span>
            <span style={{ color: '#D1D5DB', marginLeft: '6px' }}>
              For 1-tap UPI app payments and faster flash checkout, open in {targetBrowserName}.
            </span>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: '8px', flexShrink: 0 }}>
          <button
            type="button"
            onClick={handleOpenBrowser}
            data-testid="iab-open-btn"
            style={{
              backgroundColor: '#F59E0B',
              color: '#000000',
              fontWeight: 700,
              fontSize: '12px',
              padding: '6px 12px',
              borderRadius: '6px',
              border: 'none',
              cursor: 'pointer',
            }}
          >
            Open in {targetBrowserName}
          </button>
          <button
            type="button"
            onClick={handleDismiss}
            data-testid="iab-dismiss-btn"
            aria-label="Dismiss banner"
            style={{
              background: 'transparent',
              border: 'none',
              color: '#9CA3AF',
              fontSize: '18px',
              cursor: 'pointer',
              padding: '4px',
              lineHeight: 1,
            }}
          >
            ×
          </button>
        </div>
      </aside>

      {/* iOS Step-by-Step Guide Modal */}
      {showIosGuide && (
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="iab-modal-title"
          data-testid="iab-ios-guide-modal"
          style={{
            position: 'fixed',
            inset: 0,
            backgroundColor: 'rgba(0, 0, 0, 0.75)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000,
            padding: '20px',
          }}
        >
          <div
            style={{
              backgroundColor: '#1E1E24',
              borderRadius: '16px',
              border: '1px solid rgba(255, 255, 255, 0.1)',
              padding: '24px',
              maxWidth: '380px',
              width: '100%',
              color: '#FFFFFF',
            }}
          >
            <h3 id="iab-modal-title" style={{ fontSize: '18px', fontWeight: 700, margin: '0 0 12px 0' }}>
              Open in Safari
            </h3>
            <p style={{ fontSize: '13px', color: '#9CA3AF', margin: '0 0 16px 0', lineHeight: 1.5 }}>
              Instagram and Facebook limit opening UPI apps directly. Follow these 2 quick steps:
            </p>
            <ol style={{ fontSize: '13px', color: '#E5E7EB', paddingLeft: '20px', margin: '0 0 20px 0', lineHeight: 1.6 }}>
              <li>
                Tap the <strong>•••</strong> (three dots) or <strong>Share</strong> icon in the corner of your screen.
              </li>
              <li>
                Select <strong>&quot;Open in Safari&quot;</strong> (or &quot;Open in System Browser&quot;).
              </li>
            </ol>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <button
                type="button"
                onClick={handleCopyLink}
                style={{
                  backgroundColor: '#2A2A32',
                  color: '#FFFFFF',
                  border: '1px solid rgba(255, 255, 255, 0.1)',
                  padding: '10px',
                  borderRadius: '8px',
                  fontWeight: 600,
                  fontSize: '13px',
                  cursor: 'pointer',
                }}
              >
                {copied ? '✓ Link Copied to Clipboard!' : 'Copy Drop Link to Paste in Safari'}
              </button>
              <button
                type="button"
                onClick={() => setShowIosGuide(false)}
                style={{
                  backgroundColor: '#F59E0B',
                  color: '#000000',
                  border: 'none',
                  padding: '10px',
                  borderRadius: '8px',
                  fontWeight: 700,
                  fontSize: '13px',
                  cursor: 'pointer',
                }}
              >
                Got It, Continue Here
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
