// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { useState } from 'react';
import { api, ApiError } from '../api/client';
import { useAuth } from '../auth/AuthContext';

export function LoginPage() {
  const { refresh } = useAuth();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [totp, setTotp] = useState('');
  const [needTotp, setNeedTotp] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      await api.post('/api/auth/login', {
        username,
        password,
        totpCode: totp || undefined,
      });
      await refresh();
    } catch (err) {
      if (err instanceof ApiError && err.payload.totpRequired) {
        setNeedTotp(true);
        setError(totp ? 'Invalid code, try again.' : '');
      } else {
        setError(err instanceof ApiError ? err.message : 'Login failed.');
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="auth-screen">
      <form className="card auth-card" onSubmit={submit}>
        <h1>Sign in</h1>
        <label>
          Username
          <input value={username} onChange={(e) => setUsername(e.target.value)} autoFocus required />
        </label>
        <label>
          Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </label>
        {needTotp && (
          <label>
            Two-factor code
            <input
              inputMode="numeric"
              autoComplete="one-time-code"
              value={totp}
              onChange={(e) => setTotp(e.target.value)}
              placeholder="123456 or recovery code"
              autoFocus
            />
          </label>
        )}
        {error && <p className="error">{error}</p>}
        <button className="primary" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
