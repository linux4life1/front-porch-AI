// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Sign in / create account for The Stoop. Mirrors the desktop auth view:
// email + password, a TOTP step revealed when the server demands it, and
// signup requiring display name + date of birth with a local 18+ check
// (the server independently enforces it).

import { useState, type FormEvent } from 'react';
import { stoop, StoopError, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';

function ageInYears(dob: Date, now: Date): number {
  let age = now.getFullYear() - dob.getFullYear();
  const beforeBirthday =
    now.getMonth() < dob.getMonth() ||
    (now.getMonth() === dob.getMonth() && now.getDate() < dob.getDate());
  if (beforeBirthday) age -= 1;
  return age;
}

export function StoopAuthView() {
  const { applyAuthResult } = useStoop();
  const [mode, setMode] = useState<'login' | 'signup'>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [dob, setDob] = useState('');
  const [totp, setTotp] = useState('');
  const [totpNeeded, setTotpNeeded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    if (!email.includes('@')) return setError('Enter a valid email address.');
    if (password.length < 8) return setError('Password must be at least 8 characters.');
    if (mode === 'signup') {
      if (!displayName.trim()) return setError('Pick a display name.');
      const parsed = dob ? new Date(dob) : null;
      if (!parsed || Number.isNaN(parsed.getTime())) {
        return setError('Enter your date of birth.');
      }
      if (ageInYears(parsed, new Date()) < 18) {
        return setError('You must be 18 or older to use The Stoop.');
      }
    }
    setBusy(true);
    try {
      const r =
        mode === 'login'
          ? await stoop.login(email.trim(), password, totpNeeded ? totp.trim() : undefined)
          : await stoop.signup(
              email.trim(),
              password,
              displayName.trim(),
              new Date(dob).toISOString(),
            );
      applyAuthResult(r.user, r.policyVersion);
    } catch (err) {
      if (err instanceof StoopError && err.code === 'two_factor_required') {
        setTotpNeeded(true);
        setError(totp ? stoopErrorText(err) : 'Enter your two-factor code to finish signing in.');
      } else {
        setError(stoopErrorText(err));
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="page stoop-page">
      <div className="stoop-auth card">
        <h2>The Stoop</h2>
        <p className="muted">
          The community hub for sharing character cards — browse, download, upvote and
          follow creators. Strictly 18+; a free account is required. Your sign-in is
          saved on this device.
        </p>
        <form onSubmit={submit}>
          <label>
            Email
            <input
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </label>
          <label>
            Password
            <input
              type="password"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>
          {mode === 'signup' && (
            <>
              <label>
                Display name
                <input value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
              </label>
              <label>
                Date of birth
                <input type="date" value={dob} onChange={(e) => setDob(e.target.value)} />
              </label>
            </>
          )}
          {mode === 'login' && totpNeeded && (
            <label>
              Two-factor code
              <input
                inputMode="numeric"
                placeholder="123456"
                value={totp}
                onChange={(e) => setTotp(e.target.value)}
              />
            </label>
          )}
          {error && <p className="error">{error}</p>}
          <button className="primary" type="submit" disabled={busy}>
            {busy ? 'Working…' : mode === 'login' ? 'Sign in' : 'Create account'}
          </button>
        </form>
        <button
          className="link-btn"
          onClick={() => {
            setMode(mode === 'login' ? 'signup' : 'login');
            setError('');
            setTotpNeeded(false);
          }}
        >
          {mode === 'login' ? 'New here? Create an account' : 'Have an account? Sign in'}
        </button>
      </div>
    </div>
  );
}
