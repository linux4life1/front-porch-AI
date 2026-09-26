// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Director-redo modal: reprocess a message's Needs deltas with a written
// critique. Extracted from ChatPage (which keeps only the target message index)
// so the page stays under the file-size cap; owns its own draft/busy/error state.

import { useState } from 'react';
import { ApiError } from '../api/client';
import { NEED_LABELS } from './chatTypes';

const INTRO =
  'Enter your critique to correct the Needs Simulation deltas. The Realism Director will re-evaluate the scene based on this input.';
const PLACEHOLDER =
  'e.g., They rested on the sofa — energy should have improved.';
const EMPTY_HELPER =
  'Nothing selected — every need shown here is re-evaluated.';
const SOME_HELPER =
  'Only the selected needs change. The others keep their current deltas.';

function needTitle(need: string): string {
  return NEED_LABELS[need] ?? `${need.charAt(0).toUpperCase()}${need.slice(1)}`;
}

const NOTHING = "There's nothing to reprocess for this message.";

export function ReprocessNeedsModal({
  enabledNeeds,
  speaker,
  speakerName,
  onSubmit,
  onClose,
}: {
  /** Enabled keys from the facade resolver — never re-derived here. */
  enabledNeeds: string[];
  speaker?: string;
  speakerName?: string;
  /** Resolves on success (the parent then unmounts this modal); throws on failure. */
  onSubmit: (critique: string, onlyNeeds: string[]) => Promise<void>;
  onClose: () => void;
}) {
  const [critique, setCritique] = useState('');
  const [onlyNeeds, setOnlyNeeds] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const name = (speakerName || speaker || '').trim() || 'this character';
  const visible = enabledNeeds.filter((need) => need in NEED_LABELS || need.length > 0);
  const oneEnabled = visible.length === 1;
  const zeroEnabled = visible.length === 0;

  const toggleNeed = (need: string) =>
    setOnlyNeeds((prev) =>
      prev.includes(need) ? prev.filter((n) => n !== need) : [...prev, need],
    );

  const submit = async () => {
    const c = critique.trim();
    if (!c || zeroEnabled) return;
    setBusy(true);
    setError('');
    try {
      const scope = oneEnabled
        ? []
        : onlyNeeds.filter((need) => visible.includes(need));
      await onSubmit(c, scope);
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Reprocess failed');
      setBusy(false);
    }
  };

  return (
    <div className="drawer-backdrop center" onClick={() => !busy && onClose()}>
      <div className="modal reprocess-modal" onClick={(e) => e.stopPropagation()}>
        <div className="drawer-head">
          <span>Reprocess Needs</span>
          {!zeroEnabled && (
            <button className="link-btn" onClick={onClose} disabled={busy}>Close</button>
          )}
        </div>
        {zeroEnabled ? (
          <p className="muted small">{NOTHING}</p>
        ) : (
          <>
            <p className="muted small">{INTRO}</p>
            <textarea
              value={critique}
              onChange={(e) => setCritique(e.target.value)}
              rows={4}
              placeholder={PLACEHOLDER}
              autoFocus
            />
            {oneEnabled ? (
              <p className="muted small">
                Only {needTitle(visible[0])} is on for {name}, so only {needTitle(visible[0])} is re-evaluated.
              </p>
            ) : (
              <>
                <p className="reprocess-scope-title">Limit to these needs</p>
                <p className="muted small">
                  {onlyNeeds.length === 0 ? EMPTY_HELPER : SOME_HELPER}
                </p>
                <div className="reprocess-needs">
                  {visible.map((need) => (
                    <button
                      key={need}
                      type="button"
                      className={`need-chip${onlyNeeds.includes(need) ? ' on' : ''}`}
                      aria-pressed={onlyNeeds.includes(need)}
                      onClick={() => toggleNeed(need)}
                      disabled={busy}
                    >
                      {needTitle(need)}
                    </button>
                  ))}
                </div>
              </>
            )}
          </>
        )}
        {error && <p className="error">{error}</p>}
        <div className="modal-actions">
          {zeroEnabled ? (
            <button onClick={onClose} disabled={busy}>Close</button>
          ) : (
            <>
              <button onClick={onClose} disabled={busy}>Cancel</button>
              <button className="primary" onClick={submit} disabled={busy || !critique.trim()}>
                {busy ? 'Reprocessing…' : 'Reprocess'}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
