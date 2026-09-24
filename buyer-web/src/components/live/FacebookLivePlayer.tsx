'use client';

import React, { useState } from 'react';

export interface FacebookLivePlayerProps {
  streamUrl?: string | null;
  dropTitle?: string;
  storeName?: string;
  isLive?: boolean;
}

/**
 * Validates and encodes a Facebook Live URL for official iframe embedding.
 */
export function getFacebookEmbedUrl(url: string, muted: boolean = true): string | null {
  if (!url || typeof url !== 'string') return null;
  const trimmed = url.trim();
  if (!/^https?:\/\//i.test(trimmed)) return null;

  const encodedHref = encodeURIComponent(trimmed);
  const muteParam = muted ? '1' : '0';
  return `https://www.facebook.com/plugins/video.php?href=${encodedHref}&show_text=false&autoplay=true&mute=${muteParam}&show_captions=false`;
}

export function FacebookLivePlayer({
  streamUrl,
  dropTitle = 'Exclusive Runway Drop',
  storeName = 'LiveDrop Atelier',
  isLive = true,
}: FacebookLivePlayerProps) {
  const [isMuted, setIsMuted] = useState(true);
  const [hasUnmuted, setHasUnmuted] = useState(false);

  const embedUrl = streamUrl ? getFacebookEmbedUrl(streamUrl, isMuted) : null;

  const handleToggleAudio = () => {
    setIsMuted((prev) => !prev);
    setHasUnmuted(true);
  };

  return (
    <div
      className="ld-fb-live-player-container relative w-full h-full bg-[#08080A] overflow-hidden select-none"
      data-testid="facebook-live-player"
    >
      {embedUrl ? (
        <>
          {/* Official Facebook Video Embed Player */}
          <iframe
            key={`fb-player-${isMuted ? 'muted' : 'unmuted'}`}
            src={embedUrl}
            title={`${storeName} — ${dropTitle} Live Broadcast`}
            className="w-full h-full border-0 absolute inset-0 object-cover pointer-events-auto"
            allow="autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share; fullscreen"
            allowFullScreen
            loading="eager"
            data-testid="facebook-live-iframe"
          />

          {/* Luxury Unmute Overlay Indicator */}
          {!hasUnmuted && isMuted && (
            <button
              type="button"
              onClick={handleToggleAudio}
              className="absolute top-16 right-4 z-20 flex items-center gap-2 px-3 py-1.5 rounded-full bg-black/70 backdrop-blur-md border border-[rgba(212,175,55,0.4)] text-[#FBFBFB] text-xs font-medium tracking-wide shadow-lg hover:bg-black/90 transition-all cursor-pointer"
              aria-label="Tap to unmute live audio"
              data-testid="unmute-button"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                <line x1="23" y1="9" x2="17" y2="15" />
                <line x1="17" y1="9" x2="23" y2="15" />
              </svg>
              <span>Tap for Audio</span>
            </button>
          )}

          {/* Facebook App External Launcher Pill */}
          <a
            href={streamUrl!}
            target="_blank"
            rel="noopener noreferrer"
            className="absolute top-16 left-4 z-20 flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-white/80 hover:text-white text-[11px] font-sans transition-colors"
            title="Open in Facebook App"
          >
            <svg width="12" height="12" viewBox="0 0 24 24" fill="#1877F2">
              <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
            </svg>
            <span>Facebook Live</span>
          </a>
        </>
      ) : (
        /* Graceful Luxury Ambient Fallback when streamUrl is absent or offline */
        <div
          className="w-full h-full relative flex flex-col items-center justify-center p-6 text-center"
          style={{
            background: 'radial-gradient(ellipse at 50% 35%, rgba(61, 12, 25, 0.45) 0%, rgba(8, 8, 10, 0.95) 75%), #08080A',
          }}
          data-testid="fallback-ambient-player"
        >
          {/* Subtle Ambient Shimmer Rings */}
          <div className="absolute w-72 h-72 rounded-full border border-[rgba(212,175,55,0.12)] animate-pulse pointer-events-none" />
          <div className="absolute w-96 h-96 rounded-full border border-[rgba(212,175,55,0.06)] pointer-events-none" />

          {/* Runway Model Silhouette Graphic / Emblem */}
          <div className="relative z-10 mb-4 w-16 h-16 rounded-full bg-[rgba(212,175,55,0.1)] border border-[rgba(212,175,55,0.3)] flex items-center justify-center shadow-[0_0_24px_rgba(212,175,55,0.2)]">
            <span className="text-2xl text-[#D4AF37] font-serif select-none">✦</span>
          </div>

          <div className="relative z-10 max-w-xs space-y-2">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[rgba(212,175,55,0.12)] border border-[rgba(212,175,55,0.25)] text-[#D4AF37] text-[11px] font-semibold tracking-widest uppercase">
              <span className="w-1.5 h-1.5 rounded-full bg-[#D4AF37] animate-ping" />
              {isLive ? 'Atelier Stream Connecting' : 'Atelier Stream Concluded'}
            </div>
            <h2 className="text-xl font-serif text-[#FBFBFB] tracking-wide pt-1">
              {dropTitle}
            </h2>
            <p className="text-xs text-[#FBFBFB]/70 font-sans leading-relaxed">
              Broadcast will stream live from {storeName}. Reserve spotlighted pieces below in real-time.
            </p>
          </div>
        </div>
      )}
    </div>
  );
}
