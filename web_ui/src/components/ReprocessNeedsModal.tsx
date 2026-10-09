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

// The Feelings choice. Desktop twin: reprocess_needs_dialog.dart constants.
export const CHOICE_PROMPT = 'What should be redone?';
export const CHOICE_NEEDS = 'Needs';
export const CHOICE_FEELINGS = 'Feelings (bond, trust, mood)';
export const FEELINGS_BUTTON = 'Score again';
export const feelingsIntro = (name: string) =>
  `Ask the model again how ${name} feels about your last message. This reply's bond, trust and mood are replaced, not added on top. The reply itself stays as it is.`;

export function ReprocessNeedsModal({
  enabledNeeds,
  speaker,
  speakerName,
  feelingsSpeaker,
  onSubmit,
  onSubmitFeelings,
  onClose,
}: {
  /** Enabled keys from the facade resolver — never re-derived here. */
  enabledNeeds: string[];
  speaker?: string;
  speakerName?: string;
  /** Set when the facade resolver offers a Feelings re-score; absent hides it. */
  feelingsSpeaker?: string;
  /** Resolves on success (the parent then unmounts this modal); throws on failure. */
  onSubmit: (critique: string, onlyNeeds: string[]) => Promise<void>;
  /** Same contract as onSubmit, for the Feelings re-score. */
  onSubmitFeelings?: () => Promise<void>;
  onClose: () => void;
}) {
  const [critique, setCritique] = useState('');
  const [onlyNeeds, setOnlyNeeds] = useState<string[]>([]);
  const [picked, setPicked] = useState<'needs' | 'feelings' | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const name = (speakerName || speaker || '').trim();
  const oneEnabled = enabledNeeds.length === 1;
  const needsOk = enabledNeeds.length > 0;
  const feelingsOk = feelingsSpeaker !== undefined && !!onSubmitFeelings;
  const choice =
    picked === 'needs' && needsOk ? 'needs'
      : picked === 'feelings' && feelingsOk ? 'feelings'
        : needsOk ? 'needs'
          : feelingsOk ? 'feelings'
            : null;
  const zeroEnabled = choice === null;
  const feelings = choice === 'feelings';

  const submitFeelings = async () => {
    if (!onSubmitFeelings) return;
    setBusy(true);
    setError('');
    try {
      await onSubmitFeelings();
    } catch (e) {
      setError(e instanceof ApiError ? e.message : 'Reprocess failed');
      setBusy(false);
    }
  };

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
        : onlyNeeds.filter((need) => enabledNeeds.includes(need));
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
          <span>{feelings ? 'Reprocess Feelings' : 'Reprocess Needs'}</span>
          {!zeroEnabled && (
            <button className="link-btn" onClick={onClose} disabled={busy}>Close</button>
          )}
        </div>
        {needsOk && feelingsOk && (
          <>
            <p className="reprocess-scope-title">{CHOICE_PROMPT}</p>
            <div className="reprocess-needs" role="radiogroup">
              {(['needs', 'feelings'] as const).map((c) => (
                <button
                  key={c}
                  type="button"
                  role="radio"
                  className={`need-chip${choice === c ? ' on' : ''}`}
                  aria-checked={choice === c}
                  onClick={() => setPicked(c)}
                  disabled={busy}
                >
                  {c === 'needs' ? CHOICE_NEEDS : CHOICE_FEELINGS}
                </button>
              ))}
            </div>
          </>
        )}
        {zeroEnabled ? (
          <p className="muted small">{NOTHING}</p>
        ) : feelings ? (
          <p className="muted small">{feelingsIntro(feelingsSpeaker || name || 'them')}</p>
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
                Only {needTitle(enabledNeeds[0])} is on for {name}, so only {needTitle(enabledNeeds[0])} is re-evaluated.
              </p>
            ) : (
              <>
                <p className="reprocess-scope-title">Limit to these needs</p>
                <p className="muted small">
                  {onlyNeeds.length === 0 ? EMPTY_HELPER : SOME_HELPER}
                </p>
                <div className="reprocess-needs">
                  {enabledNeeds.map((need) => (
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
              {feelings ? (
                <button className="primary" onClick={submitFeelings} disabled={busy}>
                  {busy ? 'Scoring…' : FEELINGS_BUTTON}
                </button>
              ) : (
                <button className="primary" onClick={submit} disabled={busy || !critique.trim()}>
                  {busy ? 'Reprocessing…' : 'Reprocess'}
                </button>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}
