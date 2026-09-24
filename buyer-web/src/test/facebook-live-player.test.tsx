/**
 * LiveDrop Buyer Webfront — FacebookLivePlayer Unit Tests
 *
 * Verifies:
 * 1. Safe parsing and official iframe URL formatting
 * 2. Proper initial muted autoplay handling
 * 3. Graceful luxury fallback when stream_url is missing
 * 4. Tap-for-audio interaction
 */

import React from 'react';
import { describe, it, expect } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { FacebookLivePlayer, getFacebookEmbedUrl } from '../components/live/FacebookLivePlayer';

describe('FacebookLivePlayer Component & URL Helper Tests', () => {
  it('correctly constructs official Facebook video embed plugin URL', () => {
    const rawUrl = 'https://www.facebook.com/zara/videos/123456789/';
    const embedUrl = getFacebookEmbedUrl(rawUrl, true);

    expect(embedUrl).toContain('https://www.facebook.com/plugins/video.php?href=');
    expect(embedUrl).toContain(encodeURIComponent(rawUrl));
    expect(embedUrl).toContain('autoplay=true');
    expect(embedUrl).toContain('mute=1');
  });

  it('handles unmuted URL generation', () => {
    const rawUrl = 'https://www.facebook.com/watch/live/?v=987654321';
    const embedUrl = getFacebookEmbedUrl(rawUrl, false);

    expect(embedUrl).toContain('mute=0');
  });

  it('returns null for invalid or non-http URLs', () => {
    expect(getFacebookEmbedUrl('')).toBeNull();
    expect(getFacebookEmbedUrl('javascript:alert(1)')).toBeNull();
    expect(getFacebookEmbedUrl('not-a-url')).toBeNull();
  });

  it('renders official iframe player when valid streamUrl is provided', () => {
    render(
      <FacebookLivePlayer
        streamUrl="https://www.facebook.com/boutique/videos/10101010/"
        dropTitle="Kanjivaram Festive Drop"
        storeName="Suhani Silks"
      />
    );

    const iframe = screen.getByTestId('facebook-live-iframe');
    expect(iframe).toBeInTheDocument();
    expect(iframe).toHaveAttribute('src', expect.stringContaining('facebook.com/plugins/video.php'));

    // Verify unmute helper button is present initially
    const unmuteBtn = screen.getByTestId('unmute-button');
    expect(unmuteBtn).toBeInTheDocument();

    // Clicking unmute updates mute state and dismisses prompt
    fireEvent.click(unmuteBtn);
    expect(screen.queryByTestId('unmute-button')).not.toBeInTheDocument();
  });

  it('renders graceful luxury fallback when streamUrl is null or empty', () => {
    render(
      <FacebookLivePlayer
        streamUrl={null}
        dropTitle="Royal Banarasi Runway"
        storeName="Varanasi Heritage"
      />
    );

    expect(screen.queryByTestId('facebook-live-iframe')).not.toBeInTheDocument();
    expect(screen.getByTestId('fallback-ambient-player')).toBeInTheDocument();
    expect(screen.getByText('Royal Banarasi Runway')).toBeInTheDocument();
    expect(screen.getByText(/Varanasi Heritage/i)).toBeInTheDocument();
  });
});
