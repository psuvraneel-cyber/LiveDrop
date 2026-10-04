'use client';

/**
 * LiveDrop — Seller password reset (/seller/reset-password)
 *
 * Landing page for the Supabase "Reset password" e-mail sent by the LiveDrop Seller app.
 * It establishes a short-lived recovery session from the link, lets the seller choose a new
 * password, then signs that browser session out. No buyer data is read or written here.
 */

import React, { useEffect, useRef, useState } from 'react';
import type { SupabaseClient } from '@supabase/supabase-js';
import { createSellerRecoveryClient } from '../../lib/supabase/recovery-client';
import {
  MIN_PASSWORD_LENGTH,
  parseRecoveryLink,
  validateNewPassword,
} from '../../lib/auth/recovery-link';

type ViewState =
  | { step: 'checking' }
  | { step: 'invalid'; message: string }
  | { step: 'ready' }
  | { step: 'done' };

export const RESET_SUCCESS_MESSAGE =
  'Password updated. Open the LiveDrop Seller app and log in with your new password.';

const REQUEST_NEW_LINK =
  'Request a new link from the LiveDrop Seller app (Login → Forgot password?).';

export const INVALID_LINK_MESSAGE =
  `This password reset link is invalid or has expired. Reset links can be used once and expire after a short time. ${REQUEST_NEW_LINK}`;

export const MISSING_LINK_MESSAGE =
  `Open this page from the link in your password reset e-mail. ${REQUEST_NEW_LINK}`;

export const CODE_LINK_MESSAGE =
  `This reset link can only be completed in the app or browser that requested it, so it cannot be used here. ${REQUEST_NEW_LINK}`;

const SETUP_MESSAGE =
  'Password reset is not available right now. Please try again later or contact LiveDrop support.';

export interface SellerPasswordResetViewProps {
  /** Test seam; production uses the isolated in-memory recovery client. */
  clientFactory?: () => SupabaseClient;
}

function errorCode(err: unknown): string {
  if (err && typeof err === 'object' && 'code' in err && typeof (err as { code?: unknown }).code === 'string') {
    return (err as { code: string }).code;
  }
  return '';
}

function errorStatus(err: unknown): number | undefined {
  if (err && typeof err === 'object' && 'status' in err && typeof (err as { status?: unknown }).status === 'number') {
    return (err as { status: number }).status;
  }
  return undefined;
}

function errorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err && typeof (err as { message?: unknown }).message === 'string') {
    return (err as { message: string }).message;
  }
  return '';
}

export function SellerPasswordResetView({ clientFactory = createSellerRecoveryClient }: SellerPasswordResetViewProps) {
  const [state, setState] = useState<ViewState>({ step: 'checking' });
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const clientRef = useRef<SupabaseClient | null>(null);
  const startedRef = useRef(false);

  useEffect(() => {
    // Recovery tokens are single-use: never run the exchange twice (React strict mode re-runs effects).
    if (startedRef.current) return;
    startedRef.current = true;

    const link = parseRecoveryLink(window.location.search, window.location.hash);

    // Keep the one-time tokens out of the address bar, history and any later Referer header.
    if (link.kind !== 'none') {
      try {
        window.history.replaceState(null, '', window.location.pathname);
      } catch {
        // Non-fatal: the page still works with the tokens left in the URL.
      }
    }

    const establish = async () => {
      if (link.kind === 'none') {
        setState({ step: 'invalid', message: MISSING_LINK_MESSAGE });
        return;
      }
      if (link.kind === 'error') {
        setState({ step: 'invalid', message: INVALID_LINK_MESSAGE });
        return;
      }

      let client: SupabaseClient;
      try {
        client = clientFactory();
      } catch {
        setState({ step: 'invalid', message: SETUP_MESSAGE });
        return;
      }
      clientRef.current = client;

      try {
        if (link.kind === 'token_hash') {
          const { data, error } = await client.auth.verifyOtp({ token_hash: link.tokenHash, type: 'recovery' });
          if (error || !data?.session) {
            setState({ step: 'invalid', message: INVALID_LINK_MESSAGE });
            return;
          }
        } else if (link.kind === 'code') {
          const { data, error } = await client.auth.exchangeCodeForSession(link.code);
          if (error || !data?.session) {
            setState({ step: 'invalid', message: CODE_LINK_MESSAGE });
            return;
          }
        } else {
          const { data, error } = await client.auth.setSession({
            access_token: link.accessToken,
            refresh_token: link.refreshToken,
          });
          if (error || !data?.session) {
            setState({ step: 'invalid', message: INVALID_LINK_MESSAGE });
            return;
          }
        }
        setState({ step: 'ready' });
      } catch {
        setState({
          step: 'invalid',
          message: link.kind === 'code' ? CODE_LINK_MESSAGE : INVALID_LINK_MESSAGE,
        });
      }
    };

    void establish();
  }, [clientFactory]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (isSubmitting) return;

    const validation = validateNewPassword(password, confirm);
    if (validation) {
      setFormError(validation);
      return;
    }

    const client = clientRef.current;
    if (!client) {
      setState({ step: 'invalid', message: INVALID_LINK_MESSAGE });
      return;
    }

    setFormError(null);
    setIsSubmitting(true);
    try {
      const { error } = await client.auth.updateUser({ password });
      if (error) {
        const code = errorCode(error);
        const status = errorStatus(error);
        if (code === 'same_password') {
          setFormError('Choose a password that is different from your current one.');
        } else if (code === 'weak_password') {
          setFormError(errorMessage(error) || 'This password is too weak. Choose a longer or less common one.');
        } else if (
          code === 'session_not_found' ||
          code === 'session_expired' ||
          code === 'bad_jwt' ||
          status === 401 ||
          status === 403
        ) {
          setState({ step: 'invalid', message: INVALID_LINK_MESSAGE });
        } else {
          setFormError('Your password could not be updated. Please try again.');
        }
        return;
      }

      // Done: end this browser's recovery session only (the seller logs in again in the app).
      try {
        await client.auth.signOut({ scope: 'local' });
      } catch {
        // The in-memory session is discarded with the page anyway.
      }
      clientRef.current = null;
      setPassword('');
      setConfirm('');
      setState({ step: 'done' });
    } catch {
      setFormError('Your password could not be updated. Please check your connection and try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <main className="ld-container" style={{ paddingTop: '48px', paddingBottom: '48px', maxWidth: '480px' }}>
      <section className="ld-checkout-section" aria-labelledby="reset-title" data-testid="seller-reset-password">
        <div className="ld-checkout-section-header">
          <h1 id="reset-title" className="ld-checkout-card-title">
            Reset your seller password
          </h1>
          <p className="ld-checkout-card-subtitle">LiveDrop Seller account</p>
        </div>

        {state.step === 'checking' && (
          <p className="ld-form-hint" role="status" data-testid="reset-checking">
            Checking your reset link…
          </p>
        )}

        {state.step === 'invalid' && (
          <p className="ld-field-error" role="alert" data-testid="reset-invalid">
            <span>{state.message}</span>
          </p>
        )}

        {state.step === 'done' && (
          <p className="ld-form-hint" role="status" data-testid="reset-success">
            {RESET_SUCCESS_MESSAGE}
          </p>
        )}

        {state.step === 'ready' && (
          <form className="ld-checkout-form-fields" onSubmit={handleSubmit} noValidate data-testid="reset-form">
            <div className="ld-form-group">
              <label htmlFor="new_password" className="ld-form-label">
                New password
              </label>
              <input
                id="new_password"
                name="new_password"
                type={showPassword ? 'text' : 'password'}
                className={`ld-form-input ${formError ? 'invalid' : ''}`}
                value={password}
                disabled={isSubmitting}
                autoComplete="new-password"
                minLength={MIN_PASSWORD_LENGTH}
                aria-required="true"
                aria-invalid={Boolean(formError)}
                aria-describedby="new_password_hint"
                onChange={(e) => setPassword(e.target.value)}
                data-testid="input-new-password"
              />
              <p id="new_password_hint" className="ld-form-hint">
                At least {MIN_PASSWORD_LENGTH} characters.
              </p>
            </div>

            <div className="ld-form-group">
              <label htmlFor="confirm_password" className="ld-form-label">
                Confirm new password
              </label>
              <input
                id="confirm_password"
                name="confirm_password"
                type={showPassword ? 'text' : 'password'}
                className={`ld-form-input ${formError ? 'invalid' : ''}`}
                value={confirm}
                disabled={isSubmitting}
                autoComplete="new-password"
                aria-required="true"
                aria-invalid={Boolean(formError)}
                onChange={(e) => setConfirm(e.target.value)}
                data-testid="input-confirm-password"
              />
            </div>

            <label className="ld-form-hint" style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
              <input
                type="checkbox"
                checked={showPassword}
                onChange={(e) => setShowPassword(e.target.checked)}
                data-testid="toggle-show-password"
              />
              Show passwords
            </label>

            {formError && (
              <p className="ld-field-error" role="alert" data-testid="reset-form-error">
                <span>{formError}</span>
              </p>
            )}

            <button type="submit" className="ld-btn-submit-order" disabled={isSubmitting} data-testid="reset-submit">
              {isSubmitting ? 'Updating…' : 'Update password'}
            </button>
          </form>
        )}
      </section>
    </main>
  );
}
