/**
 * LiveDrop — Seller password-recovery Supabase client
 *
 * Used only by /seller/reset-password. It is deliberately separate from the buyer client
 * (getBuyerClient): a recovery session belongs to a seller account and must never be attached
 * to buyer requests made from the same tab.
 *
 * - anon key only (validateBuyerEnv rejects any service-role key in the environment)
 * - session kept in memory only, never persisted and never auto-refreshed
 * - URL detection off: the page reads the link itself and scrubs the tokens from the address bar
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { validateBuyerEnv } from './env';

export function createSellerRecoveryClient(): SupabaseClient {
  const { supabaseUrl, supabaseAnonKey } = validateBuyerEnv();
  return createClient(supabaseUrl, supabaseAnonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
      storageKey: 'livedrop-seller-recovery',
    },
  });
}
