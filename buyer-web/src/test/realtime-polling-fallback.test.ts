import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { CatalogRealtimeSubscription } from '../lib/realtime/catalog-realtime';
import { PublicProductView } from '../types/domain';
import * as buyerCatalog from '../lib/data/buyer-catalog';

describe('SPRINT 3: Realtime Graceful Fallback to 3-Second HTTP Stock-Delta Polling', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
  });

  const mockClient: any = {
    channel: vi.fn().mockReturnValue({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn((cb: (status: string) => void) => {
        // Will be triggered manually in tests
        return { unsubscribe: vi.fn() };
      }),
    }),
    removeChannel: vi.fn().mockResolvedValue('ok'),
  };

  const initialProducts: PublicProductView[] = [
    {
      id: 'prod-1',
      code: 'A01',
      title: 'Silk Blouse',
      price_paisa: 120000,
      size: 'M',
      image_url: 'https://example.com/a01.jpg',
      status: 'available',
      reserved_at: null,
      version: 1,
    },
    {
      id: 'prod-2',
      code: 'A02',
      title: 'Denim Jacket',
      price_paisa: 250000,
      size: 'L',
      image_url: 'https://example.com/a02.jpg',
      status: 'available',
      reserved_at: null,
      version: 1,
    },
  ];

  it('engages 3-second HTTP stock delta polling when channel disconnects with TIMED_OUT or CHANNEL_ERROR', async () => {
    const onProductChange = vi.fn();
    const onStatusChange = vi.fn();

    let channelSubscribeCallback: (status: string) => void = () => {};

    mockClient.channel = vi.fn().mockReturnValue({
      on: vi.fn().mockReturnThis(),
      subscribe: vi.fn((cb: (status: string) => void) => {
        channelSubscribeCallback = cb;
        return { unsubscribe: vi.fn() };
      }),
    });

    const sub = new CatalogRealtimeSubscription(mockClient, {
      dropId: 'drop-100',
      onProductChange,
      onStatusChange,
      pollingIntervalMs: 3000,
    });

    sub.seedVersions(initialProducts);
    sub.subscribe();

    // 1. Simulate WebSocket connecting successfully
    channelSubscribeCallback('SUBSCRIBED');
    expect(onStatusChange).toHaveBeenCalledWith('SUBSCRIBED');
    expect(sub.pollingActive).toBe(false);

    // 2. Mock getPublicProductsForDrop returning updated delta
    const updatedProducts: PublicProductView[] = [
      {
        ...initialProducts[0],
        status: 'reserved',
        version: 2, // version advanced
      },
      {
        ...initialProducts[1],
        version: 1, // unchanged version
      },
    ];

    const getProductsSpy = vi
      .spyOn(buyerCatalog, 'getPublicProductsForDrop')
      .mockResolvedValue(updatedProducts);

    // 3. Simulate connection drop / timeout
    channelSubscribeCallback('TIMED_OUT');
    expect(onStatusChange).toHaveBeenCalledWith('TIMED_OUT');
    expect(onStatusChange).toHaveBeenCalledWith('POLLING');
    expect(sub.pollingActive).toBe(true);

    // Initial immediate poll executed
    await vi.advanceTimersByTimeAsync(10);
    expect(getProductsSpy).toHaveBeenCalledWith(mockClient, 'drop-100');

    // Only prod-1 should be emitted because its version advanced from 1 to 2
    expect(onProductChange).toHaveBeenCalledTimes(1);
    expect(onProductChange).toHaveBeenCalledWith(
      expect.objectContaining({
        id: 'prod-1',
        status: 'reserved',
        version: 2,
      })
    );

    // 4. Advance time by 3 seconds for next polling interval tick
    onProductChange.mockClear();

    const furtherUpdatedProducts: PublicProductView[] = [
      {
        ...updatedProducts[0],
        status: 'sold',
        version: 3,
      },
      updatedProducts[1],
    ];
    getProductsSpy.mockResolvedValue(furtherUpdatedProducts);

    await vi.advanceTimersByTimeAsync(3000);
    expect(onProductChange).toHaveBeenCalledTimes(1);
    expect(onProductChange).toHaveBeenCalledWith(
      expect.objectContaining({
        id: 'prod-1',
        status: 'sold',
        version: 3,
      })
    );

    // 5. Simulate WebSocket reconnecting
    channelSubscribeCallback('SUBSCRIBED');
    expect(onStatusChange).toHaveBeenCalledWith('SUBSCRIBED');
    expect(sub.pollingActive).toBe(false);

    // Further timer ticks should NOT poll
    getProductsSpy.mockClear();
    await vi.advanceTimersByTimeAsync(3000);
    expect(getProductsSpy).not.toHaveBeenCalled();

    // 6. Cleanup
    await sub.unsubscribe();
  });

  it('discards stale polling payloads with version <= known local version', async () => {
    const onProductChange = vi.fn();

    const sub = new CatalogRealtimeSubscription(mockClient, {
      dropId: 'drop-100',
      onProductChange,
    });

    sub.seedVersions([
      {
        ...initialProducts[0],
        version: 5, // locally known at version 5
      },
    ]);

    const staleProducts: PublicProductView[] = [
      {
        ...initialProducts[0],
        status: 'sold',
        version: 4, // stale version from lagged cache
      },
    ];

    vi.spyOn(buyerCatalog, 'getPublicProductsForDrop').mockResolvedValue(staleProducts);

    sub.startPollingFallback();
    await vi.advanceTimersByTimeAsync(10);

    // Stale version must be discarded
    expect(onProductChange).not.toHaveBeenCalled();

    await sub.unsubscribe();
  });
});
