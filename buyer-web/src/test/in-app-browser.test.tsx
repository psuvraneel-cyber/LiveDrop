import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import React from 'react';
import {
  detectInAppBrowser,
  getExternalBrowserIntentUrl,
} from '../lib/utils/in-app-browser';
import { InAppBrowserBanner } from '../components/InAppBrowserBanner';

describe('SPRINT 3: Social In-App Browser (IAB) Detection & Routing', () => {
  describe('detectInAppBrowser', () => {
    it('detects Instagram on iOS', () => {
      const ua =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 280.0.0.18.114';
      const result = detectInAppBrowser(ua);

      expect(result.isInApp).toBe(true);
      expect(result.browserType).toBe('instagram');
      expect(result.browserDisplayName).toBe('Instagram');
      expect(result.os).toBe('ios');
    });

    it('detects Instagram on Android', () => {
      const ua =
        'Mozilla/5.0 (Linux; Android 13; SM-S908B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/112.0.0.0 Mobile Safari/537.36 Instagram 275.0.0.27.98 Android';
      const result = detectInAppBrowser(ua);

      expect(result.isInApp).toBe(true);
      expect(result.browserType).toBe('instagram');
      expect(result.browserDisplayName).toBe('Instagram');
      expect(result.os).toBe('android');
    });

    it('detects Facebook app on iOS', () => {
      const ua =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/20F66 [FBAN/FBIOS;FBDV/iPhone14,2;FBMD/iPhone;FBSN/iOS;FBSV/16.5;FBSS/3;FBID/phone;FBLC/en_US;FBOP/5]';
      const result = detectInAppBrowser(ua);

      expect(result.isInApp).toBe(true);
      expect(result.browserType).toBe('facebook');
      expect(result.browserDisplayName).toBe('Facebook');
      expect(result.os).toBe('ios');
    });

    it('detects WhatsApp on Android', () => {
      const ua =
        'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.4951.41 Mobile Safari/537.36 WhatsApp/2.22.10.73 A';
      const result = detectInAppBrowser(ua);

      expect(result.isInApp).toBe(true);
      expect(result.browserType).toBe('whatsapp');
      expect(result.browserDisplayName).toBe('WhatsApp');
      expect(result.os).toBe('android');
    });

    it('returns isInApp = false for standard Mobile Safari on iOS', () => {
      const ua =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
      const result = detectInAppBrowser(ua);

      expect(result.isInApp).toBe(false);
      expect(result.os).toBe('ios');
    });

    it('returns isInApp = false for standard Chrome on Android', () => {
      const ua =
        'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
      const result = detectInAppBrowser(ua);

      expect(result.isInApp).toBe(false);
      expect(result.os).toBe('android');
    });
  });

  describe('getExternalBrowserIntentUrl', () => {
    it('creates a Chrome intent URL on Android', () => {
      const rawUrl = 'https://livedrop.store/drop/vintage-summer';
      const intentUrl = getExternalBrowserIntentUrl(rawUrl, 'android');

      expect(intentUrl).toBe(
        'intent://livedrop.store/drop/vintage-summer#Intent;scheme=https;package=com.android.chrome;end;'
      );
    });

    it('returns standard URL on iOS', () => {
      const rawUrl = 'https://livedrop.store/drop/vintage-summer';
      const intentUrl = getExternalBrowserIntentUrl(rawUrl, 'ios');

      expect(intentUrl).toBe(rawUrl);
    });
  });

  describe('InAppBrowserBanner Component', () => {
    beforeEach(() => {
      sessionStorage.clear();
      vi.restoreAllMocks();
    });

    it('renders banner when Instagram user agent is detected', () => {
      vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5) Instagram 280.0.0.18.114'
      );

      render(<InAppBrowserBanner />);

      expect(screen.getByTestId('iab-banner')).toBeInTheDocument();
      expect(screen.getByText(/Instagram In-App Browser Detected/i)).toBeInTheDocument();
      expect(screen.getByTestId('iab-open-btn')).toHaveTextContent('Open in Safari');
    });

    it('does not render banner on standard browser', () => {
      vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36'
      );

      render(<InAppBrowserBanner />);

      expect(screen.queryByTestId('iab-banner')).not.toBeInTheDocument();
    });

    it('dismisses banner and persists to sessionStorage on close click', () => {
      vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(
        'Mozilla/5.0 (Linux; Android 13) Instagram 275.0'
      );

      render(<InAppBrowserBanner />);

      expect(screen.getByTestId('iab-banner')).toBeInTheDocument();

      const dismissBtn = screen.getByTestId('iab-dismiss-btn');
      fireEvent.click(dismissBtn);

      expect(screen.queryByTestId('iab-banner')).not.toBeInTheDocument();
      expect(sessionStorage.getItem('ld_dismiss_iab_banner')).toBe('1');
    });

    it('opens iOS modal instructions when Open in Safari is tapped on iOS', () => {
      vi.spyOn(navigator, 'userAgent', 'get').mockReturnValue(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_5) Instagram 280.0'
      );

      render(<InAppBrowserBanner />);

      const openBtn = screen.getByTestId('iab-open-btn');
      fireEvent.click(openBtn);

      expect(screen.getByTestId('iab-ios-guide-modal')).toBeInTheDocument();
      expect(screen.getByText(/Tap the/i)).toBeInTheDocument();
    });
  });
});
