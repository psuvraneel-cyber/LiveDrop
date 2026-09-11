/**
 * LiveDrop Buyer Webfront — Realtime Subscription & Out-of-Order Defense Tests
 *
 * Validates:
 * 1. Monotonic entity version defense against out-of-order WebSocket arrivals
 * 2. Realtime channel setup with drop-specific filtering
 * 3. Graceful cleanup and unsubscription
 * 4. Stale event suppression
 */

import { describe, it, expect, vi } from 'vitest';
import { RealtimeChannel, SupabaseClient } from '@supabase/supabase-js';
import {
  CatalogRealtimeSubscription,
  RealtimeProductEvent,
} from '../lib/realtime/catalog-realtime';
import { PublicProductView } from '../types/domain';

describe('TASK-1.4: Realtime Catalog Foundation & Version Defense', () => {
  it('discards stale out-of-order events using monotonic version checking', () => {
    const changes: PublicProductView[] = [];
    const onProductChange = vi.fn((p: PublicProductView) => {
      changes.push(p);
    });

    const mockClient = {
      channel: vi.fn(),
      removeChannel: vi.fn(),
    } as unknown as SupabaseClient;

    const sub = new CatalogRealtimeSubscription(mockClient, {
      dropId: 'drop-1',
      onProductChange,
    });

    // Seed initial product version 1
    sub.seedVersions([
      {
        id: 'prod-1',
        code: '#A01',
        title: 'Silk Saree',
        price_paisa: 185000,
        size: 'Free Size',
        image_url: 'url-1',
        status: 'available',
        reserved_at: null,
        version: 1,
      },
    ]);

    // 1. Arrives in order: version 2 (e.g. reserved)
    const eventV2: RealtimeProductEvent = {
      eventType: 'UPDATE',
      new: {
        id: 'prod-1',
        code: '#A01',
        title: 'Silk Saree',
        price_paisa: 185000,
        status: 'reserved',
        version: 2,
      },
      old: { id: 'prod-1', status: 'available', version: 1 },
    };

    const appliedV2 = sub.handleIncomingPayload(eventV2);
    expect(appliedV2).toBe(true);
    expect(changes.length).toBe(1);
    expect(changes[0].status).toBe('reserved');
    expect(changes[0].version).toBe(2);

    // 2. Delayed/out-of-order event arrives: version 1 (stale network packet)
    const staleEventV1: RealtimeProductEvent = {
      eventType: 'UPDATE',
      new: {
        id: 'prod-1',
        code: '#A01',
        title: 'Silk Saree',
        price_paisa: 185000,
        status: 'available',
        version: 1,
      },
      old: { id: 'prod-1' },
    };

    const appliedStaleV1 = sub.handleIncomingPayload(staleEventV1);
    expect(appliedStaleV1).toBe(false);
    expect(changes.length).toBe(1); // Stale event was discarded, count remains 1

    // 3. Duplicate event arrives: version 2 (duplicate delivery)
    const duplicateEventV2: RealtimeProductEvent = {
      eventType: 'UPDATE',
      new: {
        id: 'prod-1',
        status: 'reserved',
        version: 2,
      },
      old: { id: 'prod-1' },
    };

    const appliedDupV2 = sub.handleIncomingPayload(duplicateEventV2);
    expect(appliedDupV2).toBe(false);
    expect(changes.length).toBe(1);

    // 4. Future event arrives: version 3 (e.g. sold)
    const eventV3: RealtimeProductEvent = {
      eventType: 'UPDATE',
      new: {
        id: 'prod-1',
        status: 'sold',
        version: 3,
      },
      old: { id: 'prod-1' },
    };

    const appliedV3 = sub.handleIncomingPayload(eventV3);
    expect(appliedV3).toBe(true);
    expect(changes.length).toBe(2);
    expect(changes[1].status).toBe('sold');
    expect(changes[1].version).toBe(3);
  });

  it('subscribes with correct channel name and filter', () => {
    const state: {
      capturedFilter: Record<string, unknown> | null;
      subscribeCallback: ((status: string) => void) | null;
    } = {
      capturedFilter: null,
      subscribeCallback: null,
    };

    const mockChannel = {
      on: vi.fn((_type: string, filter: Record<string, unknown>) => {
        state.capturedFilter = filter;
        return mockChannel;
      }),
      subscribe: vi.fn((cb: (status: string) => void) => {
        state.subscribeCallback = cb;
        return mockChannel;
      }),
    };

    const mockClient = {
      channel: vi.fn().mockReturnValue(mockChannel),
      removeChannel: vi.fn().mockResolvedValue('ok'),
    } as unknown as SupabaseClient;

    const onStatusChange = vi.fn();
    const sub = new CatalogRealtimeSubscription(mockClient, {
      dropId: 'drop-test-abc',
      onProductChange: vi.fn(),
      onStatusChange,
    });

    sub.subscribe();

    expect(mockClient.channel).toHaveBeenCalledWith('drop:drop-test-abc:products');
    expect(state.capturedFilter?.table).toBe('products');
    expect(state.capturedFilter?.filter).toBe('drop_id=eq.drop-test-abc');

    // Simulate status transition to SUBSCRIBED
    state.subscribeCallback?.('SUBSCRIBED');
    expect(onStatusChange).toHaveBeenCalledWith('SUBSCRIBED');
    expect(sub.active).toBe(true);
  });

  it('unsubscribes and cleans up channel gracefully', async () => {
    const mockChannel = {
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn((cb: (status: string) => void) => {
        cb('SUBSCRIBED');
        return mockChannel;
      }),
    } as unknown as RealtimeChannel;

    const mockClient = {
      channel: vi.fn().mockReturnValue(mockChannel),
      removeChannel: vi.fn().mockResolvedValue('ok'),
    } as unknown as SupabaseClient;

    const sub = new CatalogRealtimeSubscription(mockClient, {
      dropId: 'drop-1',
      onProductChange: vi.fn(),
    });

    sub.subscribe();
    expect(sub.active).toBe(true);

    await sub.unsubscribe();
    expect(mockClient.removeChannel).toHaveBeenCalledWith(mockChannel);
    expect(sub.active).toBe(false);
  });
});
