/**
 * LiveDrop Buyer Webfront — In-App Browser (IAB) Detection & Deep Link Routing
 *
 * Boutique drops receive ~80%+ traffic directly from Instagram Stories, Reels, FB, and WhatsApp.
 * Social IABs sandbox cookies and block external UPI deep links (upi://pay / Google Pay / PhonePe).
 * This utility detects IAB user agents and helps buyers switch to native Safari / Chrome.
 */

export type InAppBrowserType =
  | 'instagram'
  | 'facebook'
  | 'whatsapp'
  | 'tiktok'
  | 'twitter'
  | 'line'
  | 'other';

export interface InAppBrowserInfo {
  isInApp: boolean;
  browserType?: InAppBrowserType;
  browserDisplayName?: string;
  os: 'ios' | 'android' | 'other';
}

export function detectInAppBrowser(customUserAgent?: string): InAppBrowserInfo {
  const ua =
    customUserAgent ??
    (typeof navigator !== 'undefined' ? navigator.userAgent || navigator.vendor || '' : '');

  if (!ua) {
    return { isInApp: false, os: 'other' };
  }

  // OS Detection
  const isIOS = /iPhone|iPad|iPod/i.test(ua);
  const isAndroid = /Android/i.test(ua);
  const os: 'ios' | 'android' | 'other' = isIOS ? 'ios' : isAndroid ? 'android' : 'other';

  // IAB Signature Matching
  if (/Instagram/i.test(ua)) {
    return {
      isInApp: true,
      browserType: 'instagram',
      browserDisplayName: 'Instagram',
      os,
    };
  }

  if (/FBAN|FBAV|FB_IAB|FB4A|FBIOS/i.test(ua)) {
    return {
      isInApp: true,
      browserType: 'facebook',
      browserDisplayName: 'Facebook',
      os,
    };
  }

  if (/WhatsApp/i.test(ua)) {
    return {
      isInApp: true,
      browserType: 'whatsapp',
      browserDisplayName: 'WhatsApp',
      os,
    };
  }

  if (/musical_ly|ByteLocale|ByteFullConfig|TikTok/i.test(ua)) {
    return {
      isInApp: true,
      browserType: 'tiktok',
      browserDisplayName: 'TikTok',
      os,
    };
  }

  if (/Twitter/i.test(ua)) {
    return {
      isInApp: true,
      browserType: 'twitter',
      browserDisplayName: 'Twitter/X',
      os,
    };
  }

  if (/Line/i.test(ua)) {
    return {
      isInApp: true,
      browserType: 'line',
      browserDisplayName: 'LINE',
      os,
    };
  }

  return { isInApp: false, os };
}

/**
 * Builds an intent link or standard URL to trigger external browser launch.
 */
export function getExternalBrowserIntentUrl(currentUrl: string, os: 'ios' | 'android' | 'other'): string {
  if (os === 'android') {
    const rawTarget = currentUrl.replace(/^https?:\/\//, '');
    return `intent://${rawTarget}#Intent;scheme=https;package=com.android.chrome;end;`;
  }
  return currentUrl;
}
