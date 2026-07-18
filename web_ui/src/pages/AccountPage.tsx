// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { api, ApiError } from '../api/client';

interface SessionInfo {
  id: string;
  lastSeenAt: number;
  userAgent: string | null;
  ip: string | null;
}

interface AuthState {
  setupRequired: boolean;
  authenticated: boolean;
  username?: string;
  totpEnabled?: boolean;
}

function errText(e: unknown, fallback: string): string {
  return e instanceof ApiError ? e.message : fallback;
}

export function AccountPage() {
  const [state, setState] = useState<AuthState | null>(null);
  const [sessions, setSessions] = useState<SessionInfo[]>([]);

  const loadState = () =>
    api
      .get<AuthState>('/api/auth/state')
      .then(setState)
      .catch(() => {});

  const loadSessions = () =>
    api
      .get<{ sessions: SessionInfo[] }>('/api/auth/sessions')
      .then((r) => setSessions(r.sessions))
      .catch(() => {});

  useEffect(() => {
    void loadState();
    void loadSessions();
  }, []);

  const revokeAll = async () => {
    await api.post('/api/auth/sessions/revoke', { all: true });
    await loadSessions();
  };

  return (
    <div className="page">
      <h2>Account &amp; security</h2>

      <CredentialsCard
        state={state}
        onChanged={() => {
          void loadState();
          void loadSessions();
        }}
      />

      <TwoFactorCard state={state} onChanged={() => void loadState()} />

      <section className="card">
        <h3>Signed-in devices</h3>
        {sessions.length === 0 ? (
          <p className="muted">No active sessions.</p>
        ) : (
          <ul className="session-list">
            {sessions.map((s) => (
              <li key={s.id}>
                <span>{s.userAgent ?? 'Unknown device'}</span>
                <span className="muted">{s.ip ?? ''}</span>
              </li>
            ))}
          </ul>
        )}
        <button onClick={revokeAll}>Sign out all devices</button>
      </section>

      <section className="card">
        <h3>Forgot your password?</h3>
        <p className="muted">
          The desktop app is the recovery key: Settings → Web Server → “Reset web
          login” erases this account so the browser shows first-run setup again.
          There is deliberately no network-based reset.
        </p>
      </section>
    </div>
  );
}

/** Change username / password. Always re-authenticates with the current
 *  password (+ a current 2FA code when enabled) so a stolen device with a
 *  live session can't take over the account. A password change signs out
 *  every other device. */
function CredentialsCard({
  state,
  onChanged,
}: {
  state: AuthState | null;
  onChanged: () => void;
}) {
  const [username, setUsername] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [currentPassword, setCurrentPassword] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    if (state?.username) setUsername(state.username);
  }, [state?.username]);

  const dirty =
    (!!username.trim() && username.trim() !== (state?.username ?? '')) ||
    !!newPassword;

  const save = async () => {
    setNote('');
    setError('');
    if (newPassword && newPassword.length < 8) {
      return setError('New password must be at least 8 characters.');
    }
    if (newPassword && newPassword !== confirm) {
      return setError('New passwords don’t match.');
    }
    if (!currentPassword) {
      return setError('Enter your current password to confirm the change.');
    }
    setBusy(true);
    try {
      await api.post('/api/auth/change-credentials', {
        currentPassword,
        ...(state?.totpEnabled ? { totpCode: totpCode.trim() } : {}),
        ...(username.trim() !== (state?.username ?? '')
          ? { newUsername: username.trim() }
          : {}),
        ...(newPassword ? { newPassword } : {}),
      });
      setNote(
        newPassword
          ? 'Saved. Other devices were signed out; this one stays signed in.'
          : 'Saved.',
      );
      setNewPassword('');
      setConfirm('');
      setCurrentPassword('');
      setTotpCode('');
      onChanged();
    } catch (e) {
      setError(errText(e, 'Couldn’t save the change.'));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="card">
      <h3>Login credentials</h3>
      <label>
        Username
        <input
          autoComplete="username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
      </label>
      <label>
        New password <span className="muted">(leave blank to keep it)</span>
        <input
          type="password"
          autoComplete="new-password"
          value={newPassword}
          onChange={(e) => setNewPassword(e.target.value)}
        />
      </label>
      {newPassword && (
        <label>
          Confirm new password
          <input
            type="password"
            autoComplete="new-password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
          />
        </label>
      )}
      <label>
        Current password <span className="muted">(required to save)</span>
        <input
          type="password"
          autoComplete="current-password"
          value={currentPassword}
          onChange={(e) => setCurrentPassword(e.target.value)}
        />
      </label>
      {state?.totpEnabled && (
        <label>
          Two-factor code
          <input
            inputMode="numeric"
            placeholder="123456"
            value={totpCode}
            onChange={(e) => setTotpCode(e.target.value)}
          />
        </label>
      )}
      {note && <p className="auth-note">{note}</p>}
      {error && <p className="error">{error}</p>}
      <button className="primary" disabled={busy || !dirty} onClick={save}>
        {busy ? 'Saving…' : 'Save changes'}
      </button>
    </section>
  );
}

/** 2FA enroll (QR + confirm) and — new — a re-authenticated disable flow:
 *  turning 2FA off requires the current password AND a current code, so a
 *  hijacked session can't silently strip the second factor. */
function TwoFactorCard({
  state,
  onChanged,
}: {
  state: AuthState | null;
  onChanged: () => void;
}) {
  const [enroll, setEnroll] = useState<{ otpauthUri: string; secret: string } | null>(null);
  const [code, setCode] = useState('');
  const [password, setPassword] = useState('');
  const [recovery, setRecovery] = useState<string[] | null>(null);
  const [error, setError] = useState('');

  const begin = async () => {
    setError('');
    setRecovery(null);
    try {
      const r = await api.post<{ otpauthUri: string; secret: string }>('/api/auth/2fa/begin');
      setEnroll(r);
    } catch (e) {
      setError(errText(e, 'Could not start 2FA setup'));
    }
  };

  const confirm = async () => {
    setError('');
    try {
      const r = await api.post<{ recoveryCodes: string[] }>('/api/auth/2fa/confirm', { code });
      setRecovery(r.recoveryCodes);
      setEnroll(null);
      setCode('');
      onChanged();
    } catch (e) {
      setError(errText(e, 'Invalid code'));
    }
  };

  const disable = async () => {
    setError('');
    try {
      await api.post('/api/auth/2fa/disable', {
        currentPassword: password,
        totpCode: code.trim(),
      });
      setPassword('');
      setCode('');
      onChanged();
    } catch (e) {
      setError(errText(e, 'Couldn’t turn off 2FA'));
    }
  };

  return (
    <section className="card">
      <h3>Two-factor authentication</h3>
      {recovery ? (
        <>
          <p>Save these one-time recovery codes somewhere safe:</p>
          <ul className="recovery">
            {recovery.map((c) => (
              <li key={c}>
                <code>{c}</code>
              </li>
            ))}
          </ul>
        </>
      ) : state?.totpEnabled ? (
        <>
          <p className="muted">
            2FA is on. To turn it off, confirm your password and a current code.
          </p>
          <label>
            Current password
            <input
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>
          <label>
            Two-factor code
            <input
              inputMode="numeric"
              placeholder="123456"
              value={code}
              onChange={(e) => setCode(e.target.value)}
            />
          </label>
          <button disabled={!password || !code.trim()} onClick={disable}>
            Turn off 2FA
          </button>
        </>
      ) : enroll ? (
        <>
          <p className="muted">Scan with an authenticator app, then enter the 6-digit code.</p>
          <div className="qr">
            <QRCodeSVG value={enroll.otpauthUri} size={180} />
          </div>
          <p className="muted">Secret: <code>{enroll.secret}</code></p>
          <label>
            Code
            <input
              inputMode="numeric"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              placeholder="123456"
            />
          </label>
          <button className="primary" onClick={confirm}>
            Confirm &amp; enable
          </button>
        </>
      ) : (
        <button className="primary" onClick={begin}>
          Set up 2FA
        </button>
      )}
      {error && <p className="error">{error}</p>}
    </section>
  );
}
