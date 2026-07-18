// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The AUP gate — shown whenever the server's live policy version moves past
// what the account accepted (including first sign-in). The text comes from
// GET /api/stoop/aup, which serves the same bundled document the desktop gate
// renders, so the two can never drift apart.

import { useEffect, useState } from 'react';
import { stoop, stoopErrorText } from '../../stoop/stoopApi';
import { useStoop } from '../../stoop/StoopContext';
import type { StoopAup } from '../../stoop/stoopTypes';

export function StoopPolicyGate() {
  const { policyVersion, applyAuthResult, signOut } = useStoop();
  const [aup, setAup] = useState<StoopAup | null>(null);
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    stoop.aup().then(setAup).catch(() => setError('Couldn’t load the policy text.'));
  }, []);

  const accept = async () => {
    setBusy(true);
    setError('');
    try {
      const r = await stoop.acceptPolicy(policyVersion);
      applyAuthResult(r.user, r.policyVersion);
    } catch (e) {
      setError(stoopErrorText(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="page stoop-page">
      <div className="card stoop-gate">
        <h2>Before you come in</h2>
        {aup ? (
          <div className="stoop-gate-text">
            <p>{aup.intro}</p>
            {aup.sections.map((s) => (
              <section key={s.title}>
                <h4>{s.title}</h4>
                <p>{s.body}</p>
              </section>
            ))}
            <p className="muted">Policy revision {aup.id}</p>
          </div>
        ) : (
          <div className="spinner" aria-label="Loading" />
        )}
        <label className="stoop-gate-agree">
          <input
            type="checkbox"
            checked={agreed}
            onChange={(e) => setAgreed(e.target.checked)}
          />
          I am 18 or older and I have read and agree to the policy above.
        </label>
        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          <button onClick={() => void signOut()}>Decline &amp; sign out</button>
          <button className="primary" disabled={!agreed || busy} onClick={accept}>
            {busy ? 'Working…' : 'Agree & continue'}
          </button>
        </div>
      </div>
    </div>
  );
}
