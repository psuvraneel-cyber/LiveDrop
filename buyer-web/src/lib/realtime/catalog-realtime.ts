/**
 * LiveDrop Buyer Webfront — Realtime Catalog Subscription Manager & Delta Polling Fallback
 *
 * Implements ephemeral low-latency catalog stock updates per docs/14-realtime-contract.md.
 * Defense against out-of-order delivery via monotonic entity versioning.
 * Includes automatic 3-second HTTP stock-delta polling fallback when WebSocket is disconnected.
 * PostgreSQL remains the sole authoritative source of truth.
 */

import { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { ProductStatus, PublicProductView } from '../../types/domain';
import { getPublicProductsForDrop } from '../data/buyer-catalog';

export interface RealtimeProductEvent {
  eventType: 'INSERT' | 'UPDATE' | 'DELETE';
  new: Partial<PublicProductView> & { id: string; version?: number };
  old: Partial<PublicProductView> & { id?: string; version?: number };
}

export type CatalogSubscriptionStatus =
  | 'SUBSCRIBED'
  | 'TIMED_OUT'
  | 'CLOSED'
  | 'CHANNEL_ERROR'
  | 'POLLING';

export interface CatalogRealtimeOptions {
  dropId: string;
  onProductChange: (product: PublicProductView) => void;
  onStatusChange?: (status: CatalogSubscriptionStatus) => void;
  onReconnectRequired?: () => void;
  enablePollingFallback?: boolean;
  pollingIntervalMs?: number;
}

export class CatalogRealtimeSubscription {
  private channel: RealtimeChannel | null = null;
  private readonly localVersions = new Map<string, number>();
  private readonly options: CatalogRealtimeOptions;
  private isSubscribed = false;
  private pollingTimer: ReturnType<typeof setInterval> | null = null;
  private isPolling = false;

  constructor(
    private readonly client: SupabaseClient,
    options: CatalogRealtimeOptions
  ) {
    this.options = {
      enablePollingFallback: true,
      pollingIntervalMs: 3000,
      ...options,
    };
  }

  /**
   * Initializes known product versions from an authoritative initial snapshot.
   */
  public seedVersions(products: PublicProductView[]): void {
    for (const p of products) {
      this.localVersions.set(p.id, p.version);
    }
  }

  /**
   * Subscribes to the live drop product channel (`drop:{dropId}:products`).
   * Automatically engages 3-second HTTP stock-delta polling if the WebSocket drops.
   */
  public subscribe(): RealtimeChannel {
    if (this.channel) {
      return this.channel;
    }

    const channelName = `drop:${this.options.dropId}:products`;

    this.channel = this.client
      .channel(channelName)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'products',
          filter: `drop_id=eq.${this.options.dropId}`,
        },
        (payload: { [key: string]: unknown }) => {
          this.handleIncomingPayload(payload as unknown as RealtimeProductEvent);
        }
      )
      .subscribe((status: string) => {
        if (status === 'SUBSCRIBED') {
          this.stopPollingFallback();
          this.isSubscribed = true;
          this.options.onStatusChange?.('SUBSCRIBED');
        } else if (status === 'CLOSED') {
          this.isSubscribed = false;
          this.options.onStatusChange?.('CLOSED');
          this.triggerFallbackIfNeeded();
        } else if (status === 'TIMED_OUT') {
          this.isSubscribed = false;
          this.options.onStatusChange?.('TIMED_OUT');
          this.triggerFallbackIfNeeded();
          this.options.onReconnectRequired?.();
        } else if (status === 'CHANNEL_ERROR') {
          this.isSubscribed = false;
          this.options.onStatusChange?.('CHANNEL_ERROR');
          this.triggerFallbackIfNeeded();
          this.options.onReconnectRequired?.();
        }
      });

    return this.channel;
  }

  /**
   * Starts periodic HTTP delta polling when WebSocket connection fails.
   */
  private triggerFallbackIfNeeded(): void {
    if (this.options.enablePollingFallback && !this.isPolling) {
      this.startPollingFallback();
    }
  }

  /**
   * Engages 3-second HTTP stock-delta polling.
   */
  public startPollingFallback(): void {
    if (this.isPolling) return;
    this.isPolling = true;
    this.options.onStatusChange?.('POLLING');

    const poll = async () => {
      try {
        const products = await getPublicProductsForDrop(this.client, this.options.dropId);
        for (const p of products) {
          const curVersion = this.localVersions.get(p.id);
          // If product version advanced or is brand new, emit update
          if (curVersion === undefined || p.version > curVersion) {
            this.localVersions.set(p.id, p.version);
            this.options.onProductChange(p);
          }
        }
      } catch {
        // Polling network error handled silently; retries on next tick
      }
    };

    // Immediate initial poll followed by interval
    void poll();
    this.pollingTimer = setInterval(poll, this.options.pollingIntervalMs ?? 3000);
  }

  /**
   * Stops HTTP polling when WebSocket connection recovers.
   */
  public stopPollingFallback(): void {
    if (this.pollingTimer) {
      clearInterval(this.pollingTimer);
      this.pollingTimer = null;
    }
    this.isPolling = false;
  }

  /**
   * Evaluates an incoming postgres_changes payload against the monotonic version gate.
   * Returns true if applied, false if discarded as stale.
   */
  public handleIncomingPayload(payload: RealtimeProductEvent): boolean {
    const incoming = payload.new;
    if (!incoming || !incoming.id) {
      return false;
    }

    const incomingVersion = typeof incoming.version === 'number' ? incoming.version : 0;
    const currentVersion = this.localVersions.get(incoming.id);

    // Out-of-order defense: discard if incoming version <= known local version
    if (currentVersion !== undefined && incomingVersion <= currentVersion) {
      return false;
    }

    // Record monotonic version advance
    this.localVersions.set(incoming.id, incomingVersion);

    // Sanitize product view (mask internal reservation fields)
    const productView: PublicProductView = {
      id: incoming.id,
      code: incoming.code || '',
      title: incoming.title || '',
      price_paisa: incoming.price_paisa || 0,
      size: incoming.size || '',
      image_url: incoming.image_url || '',
      status: (incoming.status as ProductStatus) || 'available',
      reserved_at: incoming.reserved_at || null,
      version: incomingVersion,
    };

    this.options.onProductChange(productView);
    return true;
  }

  /**
   * Gracefully unsubscribes from the realtime channel, stops polling, and clears listeners.
   */
  public async unsubscribe(): Promise<void> {
    this.stopPollingFallback();
    if (this.channel) {
      await this.client.removeChannel(this.channel);
      this.channel = null;
      this.isSubscribed = false;
    }
  }

  public get active(): boolean {
    return this.isSubscribed || this.isPolling;
  }

  public get pollingActive(): boolean {
    return this.isPolling;
  }
}
