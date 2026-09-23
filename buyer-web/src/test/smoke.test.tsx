import { describe, it, expect, vi, beforeEach } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import Home from '../app/page';
import * as supabaseClient from '../lib/supabase/client';

vi.mock('next/navigation', () => ({
  redirect: vi.fn(),
}));

describe('Buyer Web Smoke Test', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('renders the persistent luxury storefront when a live drop exists without redirecting', async () => {
    const mockClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          eq: vi.fn().mockReturnValue({
            order: vi.fn().mockReturnValue({
              limit: vi.fn().mockResolvedValue({
                data: [{ id: 'drop-01', slug: 'summer-flash-sale', status: 'live', title: 'Summer Silks' }],
                error: null,
              }),
            }),
          }),
        }),
      }),
    };
    vi.spyOn(supabaseClient, 'createBuyerClient').mockReturnValue(mockClient as unknown as SupabaseClient);

    const { redirect } = await import('next/navigation');
    const result = await Home();
    expect(redirect).not.toHaveBeenCalled();
    expect(result).toBeDefined();
  });

  it('renders the luxury storefront when no live drops are currently active', async () => {
    const mockClient = {
      from: vi.fn().mockReturnValue({
        select: vi.fn().mockImplementation(() => ({
          eq: vi.fn().mockReturnValue({
            order: vi.fn().mockReturnValue({
              limit: vi.fn().mockResolvedValue({
                data: [],
                error: null,
              }),
            }),
          }),
          order: vi.fn().mockReturnValue({
            limit: vi.fn().mockResolvedValue({
              data: [{ id: 'drop-prev', slug: 'previous-drop', title: 'Previous Flash Sale', status: 'closed' }],
              error: null,
            }),
          }),
        })),
      }),
    };
    vi.spyOn(supabaseClient, 'createBuyerClient').mockReturnValue(mockClient as unknown as SupabaseClient);

    const result = await Home();
    expect(result).toBeDefined();
  });
});
