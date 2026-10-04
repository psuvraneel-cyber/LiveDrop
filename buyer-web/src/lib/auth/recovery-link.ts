/**
 * LiveDrop — parse a Supabase password-recovery link (seller accounts)
 *
 * Supported shapes, in order of preference:
 *   1. ?token_hash=...&type=recovery          (e-mail template link; verified with verifyOtp)
 *   2. ?code=...                              (PKCE redirect; only works in the browser that
 *                                              requested the reset, so it usually fails here)
 *   3. #access_token=...&refresh_token=...&type=recovery   (implicit-flow redirect)
 * Supabase reports a failed or expired link as ?error=... or #error=... with error_code and
 * error_description.
 */

export type RecoveryLink =
  | { kind: 'token_hash'; tokenHash: string }
  | { kind: 'code'; code: string }
  | { kind: 'session'; accessToken: string; refreshToken: string }
  | { kind: 'error'; errorCode: string; description: string }
  | { kind: 'none' };

function params(raw: string, prefix: string): URLSearchParams {
  const trimmed = raw.startsWith(prefix) ? raw.slice(prefix.length) : raw;
  return new URLSearchParams(trimmed);
}

export function parseRecoveryLink(search: string, hash: string): RecoveryLink {
  const query = params(search || '', '?');
  const fragment = params(hash || '', '#');

  const errorSource = query.get('error') || query.get('error_code') ? query
    : fragment.get('error') || fragment.get('error_code') ? fragment
    : null;
  if (errorSource) {
    return {
      kind: 'error',
      errorCode: errorSource.get('error_code') || errorSource.get('error') || 'unknown',
      description: errorSource.get('error_description') || '',
    };
  }

  const tokenHash = query.get('token_hash');
  const queryType = query.get('type');
  if (tokenHash) {
    if (queryType && queryType !== 'recovery') {
      return { kind: 'error', errorCode: 'wrong_link_type', description: '' };
    }
    return { kind: 'token_hash', tokenHash };
  }

  const code = query.get('code');
  if (code) {
    return { kind: 'code', code };
  }

  const accessToken = fragment.get('access_token');
  const refreshToken = fragment.get('refresh_token');
  if (accessToken && refreshToken) {
    if (fragment.get('type') !== 'recovery') {
      return { kind: 'error', errorCode: 'wrong_link_type', description: '' };
    }
    return { kind: 'session', accessToken, refreshToken };
  }

  return { kind: 'none' };
}

export const MIN_PASSWORD_LENGTH = 8;
/** Supabase Auth (bcrypt) ignores bytes beyond 72; refuse instead of silently truncating. */
export const MAX_PASSWORD_LENGTH = 72;

export function validateNewPassword(password: string, confirm: string): string | null {
  if (password.length < MIN_PASSWORD_LENGTH) {
    return `Use at least ${MIN_PASSWORD_LENGTH} characters.`;
  }
  if (new TextEncoder().encode(password).length > MAX_PASSWORD_LENGTH) {
    return `Use at most ${MAX_PASSWORD_LENGTH} characters.`;
  }
  if (password !== confirm) {
    return 'The two passwords do not match.';
  }
  return null;
}
