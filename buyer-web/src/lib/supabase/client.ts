/**
 * LiveDrop Buyer Webfront — Safe Anonymous Supabase Client
 *
 * Configured specifically for unauthenticated public buyers:
 * - Uses anon public API key only
 * - Session persistence disabled (unauthenticated buyer browsing)
 * - Prohibits direct mutations on orders/order_items (enforced by RLS & RPCs)
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';
import { validateBuyerEnv } from './env';

let cachedClient: SupabaseClient | null = null;

export interface BuyerClientOptions {
  supabaseUrl?: string;
  supabaseAnonKey?: string;
}

/**
 * Creates a browser-safe Supabase client.
 * If credentials are not explicitly supplied, retrieves them from validated environment variables.
 */
export function createBuyerClient(options?: BuyerClientOptions): SupabaseClient {
  const url = options?.supabaseUrl || validateBuyerEnv().supabaseUrl;
  const anonKey = options?.supabaseAnonKey || validateBuyerEnv().supabaseAnonKey;

  return createClient(url, anonKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}

/**
 * Returns a cached singleton Supabase client for buyer web.
 */
export function getBuyerClient(): SupabaseClient {
  if (!cachedClient) {
    cachedClient = createBuyerClient();
  }
  return cachedClient;
}
