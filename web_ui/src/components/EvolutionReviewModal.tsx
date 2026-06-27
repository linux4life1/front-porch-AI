// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Character-evolution review/reset modal — the web mirror of the desktop
// _showEvolutionReview / _showResetEvolutionConfirm. Shows the read-only
// original personality + scenario beside the editable evolved versions, the
// evolution count, and Save / Reset actions. Group-aware: the backend scopes
// every read/write to the focused participant, so a member's review is identical
// to a 1:1 review (parity). Mirrors the chat_page group dialog's fallback of
// showing the original text when no evolved override exists yet.

import { useEffect, useState } from 'react';
import { api, ApiError } from '../api/client';

interface EvolutionData {
  name: string;
  originalPersonality: string;
  originalScenario: string;
  evolvedPersonality: string;
  evolvedScenario: string;
  count: number;
}

export function EvolutionReviewModal({
  focusedId,
  onClose,
  onSaved,
}: {
  focusedId?: string | null;
  onClose: () => void;
  /** Called after a successful save/reset so the parent can refresh the count. */
  onSaved?: () => void;
}) {
  const q = focusedId ? `?participant=${encodeURIComponent(focusedId)}` : '';
  const [data, setData] = useState<EvolutionData | null>(null);
  const [personality, setPersonality] = useState('');
  const [scenario, setScenario] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    api
      .get<EvolutionData>(`/api/chat/tools/evolution${q}`)
      .then((d) => {
        setData(d);
        setPersonality(d.evolvedPersonality || d.originalPersonality);
        setScenario(d.evolvedScenario || d.originalScenario);
      })
      .catch((e) => setError(e instanceof ApiError ? e.message : 'Failed to load evolution'));
  }, [q]);

  const save = async () => {
    setBusy(true);
    setError('');
    try {
      await api.post(`/api/chat/tools/evolution${q}`, { action: 'save', personality, scenario });
      onSaved?.();
      onClose();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Save failed');
      setBusy(false);
    }
  };

  const reset = async () => {
    if (
      !window.confirm(
        "This will reset the character's personality and scenario back to the original card values. " +
          'The evolution count will also reset to 0. This cannot be undone.',
      )
    )
      return;
    setBusy(true);
    setError('');
    try {
      await api.post(`/api/chat/tools/evolution${q}`, { action: 'reset' });
      onSaved?.();
      onClose();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Reset failed');
      setBusy(false);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={() => !busy && onClose()}>
      <div className="modal evolution-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>{data?.name ? `${data.name} — Evolution` : 'Evolution'}</span>
          <button className="link-btn" onClick={onClose} disabled={busy}>Close</button>
        </div>
        {!data && !error && (
          <div className="centered"><div className="spinner" /></div>
        )}
        {data && (
          <>
            <p className="muted small">
              {data.count > 0
                ? `Evolved ${data.count} time${data.count > 1 ? 's' : ''}`
                : 'Not yet evolved'}
            </p>

            <span className="muted small">Original Personality</span>
            <div className="evo-original">{data.originalPersonality || '—'}</div>
            <label>
              Evolved Personality
              <textarea rows={4} value={personality} onChange={(e) => setPersonality(e.target.value)} />
            </label>

            <span className="muted small">Original Scenario</span>
            <div className="evo-original">{data.originalScenario || '—'}</div>
            <label>
              Evolved Scenario
              <textarea rows={4} value={scenario} onChange={(e) => setScenario(e.target.value)} />
            </label>

            {error && <p className="error">{error}</p>}
            <div className="modal-actions">
              <button className="danger" onClick={reset} disabled={busy}>Reset to original</button>
              <button onClick={onClose} disabled={busy}>Cancel</button>
              <button className="primary" onClick={save} disabled={busy}>
                {busy ? 'Saving…' : 'Save Changes'}
              </button>
            </div>
          </>
        )}
        {error && !data && <p className="error">{error}</p>}
      </div>
    </div>
  );
}
