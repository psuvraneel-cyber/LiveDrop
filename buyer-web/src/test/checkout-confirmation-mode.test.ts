/**
 * Checkout must work when the seller has not turned on advance payments: the server rejects an
 * 'advance' request with ADVANCE_CONFIRMATION_DISABLED, so checkout asks for 'full_payment'
 * (and falls back to it when the drop's settings were not loaded).
 */
import { describe, it, expect, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
import { confirmationModeFor } from '../lib/checkout/confirmation-mode';
import { createOrderWithReservation } from '../lib/data/buyer-catalog';
import type { CreateOrderRequest, PublicDropCatalog } from '../types/domain';

const REQ: CreateOrderRequest = {
  p_drop_id: 'd-1',
  p_product_ids: ['p-1'],
  p_buyer_name: 'Ananya Roy',
  p_buyer_phone: '9830045678',
  p_shipping_address: '14 Lansdowne Road, Kolkata',
  p_pincode: '700020',
  p_idempotency_key: 'k-1',
};
const OK = { success: true, order_id: 'o-1', order_token: 't', order_code: 'LD-ABC123', confirmation_mode: 'full_payment' };

function drop(dropSetting: boolean | null, sellerSetting: boolean): PublicDropCatalog {
  return { advance_confirmation_enabled: dropSetting, profiles: { advance_confirmation_enabled: sellerSetting } } as unknown as PublicDropCatalog;
}

describe('confirmationModeFor', () => {
  it('follows the drop setting, then the seller setting, like the server', () => {
    expect(confirmationModeFor(drop(null, false))).toBe('full_payment');
    expect(confirmationModeFor(drop(null, true))).toBe('advance');
    expect(confirmationModeFor(drop(false, true))).toBe('full_payment');
    expect(confirmationModeFor(drop(true, false))).toBe('advance');
    expect(confirmationModeFor(null)).toBeNull();
  });
});

describe('createOrderWithReservation advance fallback', () => {
  it('places the order as a full payment when advance is off for the drop', async () => {
    const rpc = vi.fn()
      .mockResolvedValueOnce({ data: { success: false, error: 'ADVANCE_CONFIRMATION_DISABLED' }, error: null })
      .mockResolvedValueOnce({ data: OK, error: null });
    const res = await createOrderWithReservation({ rpc } as unknown as SupabaseClient, REQ);
    expect(res.order_id).toBe('o-1');
    expect(rpc).toHaveBeenCalledTimes(2);
    expect(rpc.mock.calls[0][1].p_confirmation_mode).toBe('advance');
    expect(rpc.mock.calls[1][1].p_confirmation_mode).toBe('full_payment');
    expect(rpc.mock.calls[1][1].p_idempotency_key).toBe('k-1');
  });

  it('sends full_payment directly when checkout knows advance is off', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: OK, error: null });
    await createOrderWithReservation({ rpc } as unknown as SupabaseClient, { ...REQ, p_confirmation_mode: 'full_payment' });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc.mock.calls[0][1].p_confirmation_mode).toBe('full_payment');
  });

  it('does not retry other failures', async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { success: false, error: 'DROP_NOT_LIVE', message: 'closed' }, error: null });
    await expect(createOrderWithReservation({ rpc } as unknown as SupabaseClient, REQ)).rejects.toThrow();
    expect(rpc).toHaveBeenCalledTimes(1);
  });
});
