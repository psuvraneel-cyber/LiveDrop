/**
 * LiveDrop Buyer Webfront — Environment Variables Validation
 *
 * Enforces client-safe Supabase configuration.
 * Under no circumstances may a service-role key or private secret exist in the client environment.
 */

export interface BuyerEnvConfig {
  supabaseUrl: string;
  supabaseAnonKey: string;
  appEnv: 'development' | 'staging' | 'production';
  appBaseUrl: string;
}

export function validateBuyerEnv(): BuyerEnvConfig {
  // Prohibit service role key presence anywhere in accessible env
  const envObj = typeof process !== 'undefined' ? process.env : {};

  for (const key of Object.keys(envObj)) {
    if (key.toUpperCase().includes('SERVICE_ROLE') || key.toUpperCase().includes('SERVICE_KEY')) {
      throw new Error(
        `[SECURITY VIOLATION] Secret key '${key}' detected in buyer-web client environment. Service-role credentials must NEVER be accessible to the buyer client.`
      );
    }
  }

  const sanitize = (val?: string) => (val || '').replace(/^\uFEFF/, '').trim();

  const supabaseUrl = sanitize(process.env.NEXT_PUBLIC_SUPABASE_URL);
  const supabaseAnonKey = sanitize(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
  const appEnv = (sanitize(process.env.NEXT_PUBLIC_APP_ENV) || 'development') as 'development' | 'staging' | 'production';
  const appBaseUrl = sanitize(process.env.NEXT_PUBLIC_APP_BASE_URL) || 'http://localhost:3000';

  if (!supabaseUrl || supabaseUrl.trim() === '') {
    throw new Error(
      '[ENV CONFIG ERROR] Missing required environment variable: NEXT_PUBLIC_SUPABASE_URL. ' +
      'Please check your .env.local or environment configuration.'
    );
  }

  try {
    const parsed = new URL(supabaseUrl);
    if (!['http:', 'https:'].includes(parsed.protocol)) {
      throw new Error(`Invalid protocol '${parsed.protocol}'. Expected 'https:' or 'http:'.`);
    }
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(
      `[ENV CONFIG ERROR] NEXT_PUBLIC_SUPABASE_URL is not a valid URL ('${supabaseUrl}'): ${msg}`
    );
  }

  if (!supabaseAnonKey || supabaseAnonKey.trim() === '') {
    throw new Error(
      '[ENV CONFIG ERROR] Missing required environment variable: NEXT_PUBLIC_SUPABASE_ANON_KEY. ' +
      'Please check your .env.local or environment configuration.'
    );
  }

  return {
    supabaseUrl,
    supabaseAnonKey,
    appEnv,
    appBaseUrl,
  };
}
