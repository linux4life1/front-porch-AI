// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unofficial SuperGrok sign-in (desktop: lib/ui/settings/tabs/backend/
// super_grok_card.dart). The desktop runs the sign-in; this card shows the
// code, opens the approval link on this device, and polls until it lands.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';
import { StepUpFields, attachStepUp } from './StepUpFields';

export interface SuperGrokStatus {
  phase: 'signedOut' | 'waiting' | 'signedIn';
  signedIn: boolean;
  email?: string;
  userCode?: string;
  verificationUri?: string;
  error?: string;
  accessNote?: string;
}

/** Same words as the desktop card (kSuperGrokUnofficialWarning). */
export const SUPER_GROK_WARNING =
  'Unofficial. This signs in the same way xAI’s own Grok CLI does, so ' +
  'the approval screen will say “Grok CLI”. xAI has not approved Front ' +
  'Porch AI for this. xAI could block it at any time, and using it may ' +
  'go against xAI’s terms for your account. Use it at your own risk — ' +
  'an xAI API key is the official route.';

export function SuperGrokCard({
  onChange,
  onUseApiKey,
}: {
  /** Fires whenever the signed-in state may have changed. */
  onChange?: (status: SuperGrokStatus) => void;
  /** Reveals the xAI API key box — the fallback to signing in. */
  onUseApiKey?: () => void;
}) {
  const [status, setStatus] = useState<SuperGrokStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');
  const [password, setPassword] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [totpEnabled, setTotpEnabled] = useState(false);

  const apply = (next: SuperGrokStatus) => {
    setStatus(next);
    onChange?.(next);
  };

  const refresh = () =>
    api
      .get<SuperGrokStatus>('/api/backend/xai')
      .then(apply)
      .catch(() => {});

  useEffect(() => {
    void refresh();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // The desktop polls xAI; this only re-reads its status while waiting.
  useEffect(() => {
    if (status?.phase !== 'waiting') return;
    const timer = window.setInterval(() => void refresh(), 3000);
    return () => window.clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status?.phase]);

  const post = async (path: string, stepUp: boolean) => {
    setBusy(true);
    setErr('');
    try {
      const body: Record<string, unknown> = {};
      if (stepUp) attachStepUp(body, password, totpEnabled, totpCode);
      const next = await api.post<SuperGrokStatus>(path, body);
      apply(next);
      if (stepUp) {
        setPassword('');
        setTotpCode('');
      }
    } catch (e) {
      if (e instanceof ApiError && e.payload.totpRequired === true) {
        setTotpEnabled(true);
      }
      setErr(e instanceof ApiError ? e.message : 'Could not reach the desktop app');
    } finally {
      setBusy(false);
    }
  };


  if (!status) return null;

  const stepUp = (
    <StepUpFields
      password={password}
      onPassword={setPassword}
      totpEnabled={totpEnabled}
      totpCode={totpCode}
      onTotp={setTotpCode}
      reason={
        totpEnabled
          ? 'Changing which account pays for chat needs your web login password and a 2FA code.'
          : 'Changing which account pays for chat needs your web login password.'
      }
    />
  );

  return (
    <div className="sg-card" data-testid="super-grok-card">
      <div className="sg-head">
        <strong>SuperGrok sign-in</strong>
        <span className="sg-tag">UNOFFICIAL</span>
      </div>

      {status.phase === 'signedOut' && (
        <>
          <div className="cpu-warn">{SUPER_GROK_WARNING}</div>
          {stepUp}
          <button
            className="primary"
            data-testid="super-grok-sign-in"
            onClick={() => void post('/api/backend/xai/sign-in', true)}
            disabled={busy || !password}
          >
            {busy ? 'Starting…' : 'Sign in with SuperGrok'}
          </button>
          <p className="muted small">
            Uses your SuperGrok or X Premium+ allowance instead of paid API
            credits.
          </p>
          {onUseApiKey && (
            <button
              className="ghost"
              data-testid="super-grok-use-key"
              onClick={onUseApiKey}
            >
              Use an xAI API key instead
            </button>
          )}
        </>
      )}

      {status.phase === 'waiting' && (
        <>
          <p className="muted small">
            Tap Open xAI and approve Front Porch AI there. If it asks for a
            code, enter:
          </p>
          <div className="sg-code" data-testid="super-grok-code">
            {status.userCode}
          </div>
          <div className="sg-actions">
            {status.verificationUri && (
              <a
                className="btn-link"
                data-testid="super-grok-open"
                href={status.verificationUri}
                target="_blank"
                rel="noopener noreferrer"
              >
                Open xAI
              </a>
            )}
            <button
              className="ghost"
              onClick={() => void post('/api/backend/xai/cancel', false)}
              disabled={busy}
            >
              Cancel
            </button>
          </div>
          <p className="muted small">Waiting for you to approve…</p>
        </>
      )}

      {status.phase === 'signedIn' && (
        <>
          <p className="sg-signed-in" data-testid="super-grok-signed-in">
            ✓ {status.email ? `Signed in as ${status.email}` : 'Signed in with SuperGrok'}
          </p>
          <p className="muted small">
            xAI chat uses your subscription allowance, not API credits. Sign
            out to use an xAI API key instead.
          </p>
          {status.accessNote && <div className="cpu-warn">{status.accessNote}</div>}
          {stepUp}
          <div className="sg-actions">
            <button
              className="ghost"
              onClick={() => void post('/api/backend/xai/check', false)}
              disabled={busy}
            >
              Check access
            </button>
            <button
              className="ghost"
              data-testid="super-grok-sign-out"
              onClick={() => void post('/api/backend/xai/sign-out', true)}
              disabled={busy || !password}
            >
              Sign out
            </button>
          </div>
          <p className="sg-fine">Unofficial — xAI may block this sign-in at any time.</p>
        </>
      )}

      {(status.error || err) && <p className="error">{err || status.error}</p>}
    </div>
  );
}
