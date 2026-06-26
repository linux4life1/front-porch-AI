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

export function AccountPage() {
  const [sessions, setSessions] = useState<SessionInfo[]>([]);
  const [enroll, setEnroll] = useState<{ otpauthUri: string; secret: string } | null>(null);
  const [code, setCode] = useState('');
  const [recovery, setRecovery] = useState<string[] | null>(null);
  const [error, setError] = useState('');

  const loadSessions = () =>
    api
      .get<{ sessions: SessionInfo[] }>('/api/auth/sessions')
      .then((r) => setSessions(r.sessions))
      .catch(() => {});

  useEffect(() => {
    void loadSessions();
  }, []);

  const begin = async () => {
    setError('');
    setRecovery(null);
    try {
      const r = await api.post<{ otpauthUri: string; secret: string }>('/api/auth/2fa/begin');
      setEnroll(r);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Could not start 2FA setup');
    }
  };

  const confirm = async () => {
    setError('');
    try {
      const r = await api.post<{ recoveryCodes: string[] }>('/api/auth/2fa/confirm', { code });
      setRecovery(r.recoveryCodes);
      setEnroll(null);
      setCode('');
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Invalid code');
    }
  };

  const revokeAll = async () => {
    await api.post('/api/auth/sessions/revoke', { all: true });
    await loadSessions();
  };

  return (
    <div className="page">
      <h2>Account &amp; security</h2>

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
    </div>
  );
}
