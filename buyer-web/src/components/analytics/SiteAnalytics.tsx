'use client';

/**
 * LiveDrop — anonymous live presence and page views (ADR-017)
 *
 * Mounted once for the whole website. On every page change it logs an anonymous page view
 * (log_page_view, migration 045) and updates this tab's presence on the Realtime channel that
 * /admin listens to. Nothing runs when counting is not allowed (see lib/analytics/visitor.ts).
 */

import { useEffect, useRef } from 'react';
import { usePathname } from 'next/navigation';
import type { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { getBuyerClient } from '../../lib/supabase/client';
import {
  PRESENCE_CHANNEL,
  buyerStatus,
  deviceFor,
  getVisitorId,
  isAnalyticsAllowed,
  pageFor,
  sourceFor,
  type PresencePayload,
} from '../../lib/analytics/visitor';

export interface SiteAnalyticsProps {
  /** Test seam; production uses the shared anonymous buyer client. */
  clientFactory?: () => SupabaseClient;
}

export function SiteAnalytics({ clientFactory = getBuyerClient }: SiteAnalyticsProps) {
  const pathname = usePathname() || '/';
  const channelRef = useRef<RealtimeChannel | null>(null);
  const joinedRef = useRef(false);
  const latestRef = useRef<PresencePayload | null>(null);

  // Leave the presence channel when the website is closed.
  useEffect(() => {
    return () => {
      const channel = channelRef.current;
      channelRef.current = null;
      joinedRef.current = false;
      if (channel) void channel.unsubscribe();
    };
  }, []);

  useEffect(() => {
    const page = pageFor(pathname);
    if (!page || !isAnalyticsAllowed()) {
      const channel = channelRef.current;
      if (channel) {
        void channel.untrack();
      }
      return;
    }

    let client: SupabaseClient;
    try {
      client = clientFactory();
    } catch {
      return; // Website misconfigured: shopping still works, counting is skipped.
    }

    const visitorId = getVisitorId();
    const { returning, activeOrder } = buyerStatus();
    const payload: PresencePayload = {
      page: page.kind,
      drop: page.drop,
      returning,
      activeOrder,
      source: sourceFor(document.referrer, window.location.search),
      device: deviceFor(window.innerWidth, navigator.userAgent),
      at: Date.now(),
    };
    latestRef.current = payload;

    void client
      .rpc('log_page_view', {
        p_visitor_id: visitorId,
        p_page_kind: payload.page,
        p_drop_slug: payload.drop,
        p_source: payload.source,
        p_device: payload.device,
        p_returning_buyer: payload.returning,
      })
      .then(
        () => undefined,
        () => undefined
      );

    if (!channelRef.current) {
      const channel = client.channel(PRESENCE_CHANNEL, { config: { presence: { key: visitorId } } });
      channelRef.current = channel;
      channel.subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          joinedRef.current = true;
          if (latestRef.current) void channel.track(latestRef.current);
        }
      });
    } else if (joinedRef.current) {
      void channelRef.current.track(payload);
    }
  }, [pathname, clientFactory]);

  return null;
}
