// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Other words" on a reply — web parity with the desktop
// TokenAlternativesDialog (KoboldCpp only). Lists the places where the model
// nearly wrote something else; picking a word rewrites the last reply from
// there as a new swipe.

import { useEffect, useState } from 'react';
import { api } from '../api/client';

interface Place {
  token: string;
  p: number;
  leadIn: string;
  alts: { token: string; p: number }[];
}
interface TokenAlts {
  canPick: boolean;
  refusal?: string;
  places: Place[];
}

const pct = (p: number) => `${Math.round(p * 100)}%`;

export function TokenAlternativesModal({
  messageIndex,
  onClose,
}: {
  messageIndex: number;
  onClose: () => void;
}) {
  const [data, setData] = useState<TokenAlts | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api
      .get<TokenAlts>(`/api/chat/token-alts?index=${messageIndex}`)
      .then(setData)
      .catch(() => setError('Couldn’t load the words — try again.'));
  }, [messageIndex]);

  const pick = async (place: number, word: string) => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await api.post('/api/chat/token-alts/pick', { index: messageIndex, place, word });
      onClose();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Couldn’t rewrite the reply.');
      setBusy(false);
    }
  };

  const canPick = !!data?.canPick && !busy;

  return (
    <div className="drawer-backdrop center" onClick={onClose}>
      <div
        className="modal ctxb-modal"
        role="dialog"
        aria-label="Other words it weighed"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="drawer-head">
          <div>🔀 Other words it weighed</div>
          <button className="link-btn" onClick={onClose}>Close</button>
        </div>
        {data && (
          <p className="muted small">
            {data.refusal ??
              'Pick a word to rewrite the reply from there. The words before it stay; the new take is added as a swipe.'}
          </p>
        )}
        {error && <p className="muted">{error}</p>}
        {!data && !error && <div className="centered"><div className="spinner" /></div>}
        {data?.places.map((place, i) => (
          <div key={i} className="tokalt-place">
            <div>
              <span className="muted">{place.leadIn}</span>
              <strong>{place.token}</strong>
              <span className="muted"> {pct(place.p)}</span>
            </div>
            <div className="tokalt-words">
              {place.alts.map((alt) => (
                <button
                  key={alt.token}
                  className="chip tokalt-word"
                  disabled={!canPick}
                  onClick={() => void pick(i, alt.token)}
                >
                  {alt.token.trim()} {pct(alt.p)}
                </button>
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
