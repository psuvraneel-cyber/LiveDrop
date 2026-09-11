/**
 * LiveDrop Buyer Webfront — Realtime Catalog Subscription Manager
 *
 * Implements ephemeral low-latency catalog stock updates per docs/14-realtime-contract.md.
 * Defense against out-of-order delivery via monotonic entity versioning.
 * PostgreSQL remains the sole authoritative source of truth.
 */

import { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import { ProductStatus, PublicProductView } from '../../types/domain';

export interface RealtimeProductEvent {
  eventType: 'INSERT' | 'UPDATE' | 'DELETE';
  new: Partial<PublicProductView> & { id: string; version?: number };
  old: Partial<PublicProductView> & { id?: string; version?: number };
}

export interface CatalogRealtimeOptions {
  dropId: string;
  onProductChange: (product: PublicProductView) => void;
  onStatusChange?: (status: 'SUBSCRIBED' | 'TIMED_OUT' | 'CLOSED' | 'CHANNEL_ERROR') => void;
  onReconnectRequired?: () => void;
}

export class CatalogRealtimeSubscription {
  private channel: RealtimeChannel | null = null;
  private readonly localVersions = new Map<string, number>();
  private readonly options: CatalogRealtimeOptions;
  private isSubscribed = false;

  constructor(
    private readonly client: SupabaseClient,
    options: CatalogRealtimeOptions
  ) {
    this.options = options;
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
          this.isSubscribed = true;
          this.options.onStatusChange?.('SUBSCRIBED');
        } else if (status === 'CLOSED') {
          this.isSubscribed = false;
          this.options.onStatusChange?.('CLOSED');
        } else if (status === 'TIMED_OUT') {
          this.isSubscribed = false;
          this.options.onStatusChange?.('TIMED_OUT');
          this.options.onReconnectRequired?.();
        } else if (status === 'CHANNEL_ERROR') {
          this.isSubscribed = false;
          this.options.onStatusChange?.('CHANNEL_ERROR');
          this.options.onReconnectRequired?.();
        }
      });

    return this.channel;
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
   * Gracefully unsubscribes from the realtime channel and clears listeners.
   */
  public async unsubscribe(): Promise<void> {
    if (this.channel) {
      await this.client.removeChannel(this.channel);
      this.channel = null;
      this.isSubscribed = false;
    }
  }

  public get active(): boolean {
    return this.isSubscribed;
  }
}
