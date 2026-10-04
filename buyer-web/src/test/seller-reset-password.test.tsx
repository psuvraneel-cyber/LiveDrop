/**
 * LiveDrop Buyer Webfront — /seller/reset-password (SA-AUTH-001)
 *
 * The seller app sends resetPasswordForEmail(email, redirectTo: '<BUYER_BASE_URL>/seller/reset-password').
 * The page establishes the recovery session from the e-mail link, lets the seller set a new
 * password and signs the browser session out. The Supabase client is mocked.
 */

import React from 'react';
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import type { SupabaseClient } from '@supabase/supabase-js';
import {
  SellerPasswordResetView,
  RESET_SUCCESS_MESSAGE,
  INVALID_LINK_MESSAGE,
  CODE_LINK_MESSAGE,
  MISSING_LINK_MESSAGE,
} from '../components/auth/SellerPasswordResetView';
import { parseRecoveryLink, validateNewPassword } from '../lib/auth/recovery-link';
import { metadata } from '../app/seller/reset-password/page';

const SESSION = { access_token: 'at', refresh_token: 'rt', user: { id: 'seller-1' } };
// Test-only value typed into the form; not a credential.
const TEST_NEW_PASSWORD = 'NewPassw0rd!'; // gitleaks:allow

function mockClient(overrides: Partial<Record<'verifyOtp' | 'exchangeCodeForSession' | 'setSession' | 'updateUser' | 'signOut', ReturnType<typeof vi.fn>>> = {}) {
  const auth = {
    verifyOtp: vi.fn().mockResolvedValue({ data: { session: SESSION, user: SESSION.user }, error: null }),
    exchangeCodeForSession: vi.fn().mockResolvedValue({ data: { session: SESSION, user: SESSION.user }, error: null }),
    setSession: vi.fn().mockResolvedValue({ data: { session: SESSION, user: SESSION.user }, error: null }),
    updateUser: vi.fn().mockResolvedValue({ data: { user: SESSION.user }, error: null }),
    signOut: vi.fn().mockResolvedValue({ error: null }),
    ...overrides,
  };
  return { client: { auth } as unknown as SupabaseClient, auth };
}

function openAt(url: string) {
  window.history.replaceState(null, '', url);
}

function fillAndSubmit(password: string, confirm: string) {
  fireEvent.change(screen.getByTestId('input-new-password'), { target: { value: password } });
  fireEvent.change(screen.getByTestId('input-confirm-password'), { target: { value: confirm } });
  fireEvent.click(screen.getByTestId('reset-submit'));
}

describe('parseRecoveryLink / validateNewPassword', () => {
  it('prefers token_hash, then code, then hash tokens; reports errors', () => {
    expect(parseRecoveryLink('?token_hash=abc&type=recovery', '')).toEqual({ kind: 'token_hash', tokenHash: 'abc' });
    expect(parseRecoveryLink('?token_hash=abc&type=signup', '')).toMatchObject({ kind: 'error' });
    expect(parseRecoveryLink('?code=xyz', '')).toEqual({ kind: 'code', code: 'xyz' });
    expect(parseRecoveryLink('', '#access_token=a&refresh_token=r&type=recovery')).toEqual({
      kind: 'session', accessToken: 'a', refreshToken: 'r',
    });
    expect(parseRecoveryLink('', '#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired'))
      .toEqual({ kind: 'error', errorCode: 'otp_expired', description: 'Email link is invalid or has expired' });
    expect(parseRecoveryLink('', '')).toEqual({ kind: 'none' });
  });

  it('requires 10+ characters (SA-AUTH-003) and matching confirmation', () => {
    expect(validateNewPassword('short', 'short')).toMatch(/at least 10/);
    expect(validateNewPassword('ninechars', 'ninechars')).toMatch(/at least 10/);
    expect(validateNewPassword('longenough1', 'longenough2')).toMatch(/do not match/);
    expect(validateNewPassword('x'.repeat(73), 'x'.repeat(73))).toMatch(/at most 72/);
    expect(validateNewPassword('longenough1', 'longenough1')).toBeNull();
  });
});

describe('SellerPasswordResetView', () => {
  beforeEach(() => {
    openAt('/seller/reset-password');
  });
  afterEach(() => {
    openAt('/');
  });

  it('token_hash link: verifies the recovery OTP, scrubs the URL and shows the form', async () => {
    openAt('/seller/reset-password?token_hash=pkce_abc123&type=recovery');
    const { client, auth } = mockClient();
    render(<SellerPasswordResetView clientFactory={() => client} />);

    expect(await screen.findByTestId('reset-form')).toBeInTheDocument();
    expect(auth.verifyOtp).toHaveBeenCalledTimes(1);
    expect(auth.verifyOtp).toHaveBeenCalledWith({ token_hash: 'pkce_abc123', type: 'recovery' });
    expect(window.location.search).toBe('');
    expect(window.location.hash).toBe('');
  });

  it('invalid or expired link: friendly message and no form', async () => {
    openAt('/seller/reset-password?token_hash=used&type=recovery');
    const { client } = mockClient({
      verifyOtp: vi.fn().mockResolvedValue({
        data: { session: null, user: null },
        error: { name: 'AuthApiError', message: 'Email link is invalid or has expired', status: 403, code: 'otp_expired' },
      }),
    });
    render(<SellerPasswordResetView clientFactory={() => client} />);

    expect(await screen.findByTestId('reset-invalid')).toHaveTextContent(INVALID_LINK_MESSAGE);
    expect(screen.queryByTestId('reset-form')).not.toBeInTheDocument();
  });

  it('Supabase error redirect (#error=...otp_expired) shows the expired-link message without calling Auth', async () => {
    openAt('/seller/reset-password#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired');
    const { client, auth } = mockClient();
    render(<SellerPasswordResetView clientFactory={() => client} />);

    expect(await screen.findByTestId('reset-invalid')).toHaveTextContent(INVALID_LINK_MESSAGE);
    expect(auth.verifyOtp).not.toHaveBeenCalled();
  });

  it('no token at all: asks the seller to use the e-mailed link', async () => {
    const { client } = mockClient();
    render(<SellerPasswordResetView clientFactory={() => client} />);
    expect(await screen.findByTestId('reset-invalid')).toHaveTextContent(MISSING_LINK_MESSAGE);
  });

  it('?code= link that cannot be exchanged (PKCE verifier lives in the app): asks for a new link', async () => {
    openAt('/seller/reset-password?code=abc');
    const { client, auth } = mockClient({
      exchangeCodeForSession: vi.fn().mockResolvedValue({
        data: { session: null, user: null },
        error: { name: 'AuthPKCECodeVerifierMissingError', message: 'PKCE code verifier not found in storage.', code: 'pkce_code_verifier_not_found' },
      }),
    });
    render(<SellerPasswordResetView clientFactory={() => client} />);

    expect(await screen.findByTestId('reset-invalid')).toHaveTextContent(CODE_LINK_MESSAGE);
    expect(auth.exchangeCodeForSession).toHaveBeenCalledWith('abc');
  });

  it('hash access_token link: establishes the session with setSession', async () => {
    openAt('/seller/reset-password#access_token=at1&refresh_token=rt1&type=recovery&expires_in=3600');
    const { client, auth } = mockClient();
    render(<SellerPasswordResetView clientFactory={() => client} />);

    expect(await screen.findByTestId('reset-form')).toBeInTheDocument();
    expect(auth.setSession).toHaveBeenCalledWith({ access_token: 'at1', refresh_token: 'rt1' });
  });

  it('rejects a too-short password and a mismatched confirmation without calling updateUser', async () => {
    openAt('/seller/reset-password?token_hash=abc&type=recovery');
    const { client, auth } = mockClient();
    render(<SellerPasswordResetView clientFactory={() => client} />);
    await screen.findByTestId('reset-form');

    fillAndSubmit('short', 'short');
    expect(screen.getByTestId('reset-form-error')).toHaveTextContent(/at least 10 characters/i);

    fillAndSubmit(TEST_NEW_PASSWORD, 'NewPassw0rd?');
    expect(screen.getByTestId('reset-form-error')).toHaveTextContent(/do not match/i);

    expect(auth.updateUser).not.toHaveBeenCalled();
  });

  it('show/hide toggles the password fields', async () => {
    openAt('/seller/reset-password?token_hash=abc&type=recovery');
    const { client } = mockClient();
    render(<SellerPasswordResetView clientFactory={() => client} />);
    await screen.findByTestId('reset-form');

    expect(screen.getByTestId('input-new-password')).toHaveAttribute('type', 'password');
    fireEvent.click(screen.getByTestId('toggle-show-password'));
    expect(screen.getByTestId('input-new-password')).toHaveAttribute('type', 'text');
    expect(screen.getByTestId('input-confirm-password')).toHaveAttribute('type', 'text');
  });

  it('updates the password, signs the browser session out and tells the seller to log in in the app', async () => {
    openAt('/seller/reset-password?token_hash=abc&type=recovery');
    const { client, auth } = mockClient();
    render(<SellerPasswordResetView clientFactory={() => client} />);
    await screen.findByTestId('reset-form');

    fillAndSubmit(TEST_NEW_PASSWORD, TEST_NEW_PASSWORD);

    expect(await screen.findByTestId('reset-success')).toHaveTextContent(RESET_SUCCESS_MESSAGE);
    expect(RESET_SUCCESS_MESSAGE).toBe('Password updated. Open the LiveDrop Seller app and log in with your new password.');
    expect(auth.updateUser).toHaveBeenCalledWith({ password: TEST_NEW_PASSWORD });
    await waitFor(() => expect(auth.signOut).toHaveBeenCalledWith({ scope: 'local' }));
    expect(screen.queryByTestId('reset-form')).not.toBeInTheDocument();
  });

  it('session expired while typing: shows the invalid-link message', async () => {
    openAt('/seller/reset-password?token_hash=abc&type=recovery');
    const { client } = mockClient({
      updateUser: vi.fn().mockResolvedValue({
        data: { user: null },
        error: { name: 'AuthApiError', message: 'Session not found', status: 403, code: 'session_not_found' },
      }),
    });
    render(<SellerPasswordResetView clientFactory={() => client} />);
    await screen.findByTestId('reset-form');

    fillAndSubmit(TEST_NEW_PASSWORD, TEST_NEW_PASSWORD);
    expect(await screen.findByTestId('reset-invalid')).toHaveTextContent(INVALID_LINK_MESSAGE);
  });

  it('same password as before: explains instead of failing silently', async () => {
    openAt('/seller/reset-password?token_hash=abc&type=recovery');
    const { client } = mockClient({
      updateUser: vi.fn().mockResolvedValue({
        data: { user: null },
        error: { name: 'AuthApiError', message: 'New password should be different from the old password.', status: 422, code: 'same_password' },
      }),
    });
    render(<SellerPasswordResetView clientFactory={() => client} />);
    await screen.findByTestId('reset-form');

    fillAndSubmit('OldPassw0rd!', 'OldPassw0rd!');
    expect(await screen.findByTestId('reset-form-error')).toHaveTextContent(/different from your current one/i);
  });
});

describe('/seller/reset-password metadata', () => {
  it('is not indexed and sends no referrer', () => {
    expect(metadata.robots).toMatchObject({ index: false, follow: false });
    expect(metadata.referrer).toBe('no-referrer');
  });
});
