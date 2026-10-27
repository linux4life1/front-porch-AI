// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Did time pass?" (#629): the web twin of the desktop SkipConfirmDialog.
// Opens while /api/chat/state carries `pendingSkip` (the send is waiting on
// it) and answers via POST /api/chat/skip-confirm. The skips on offer come
// from the server, best guess first; "No skip" and "Other…" (read like
// `/skip 8h`) sit beside them. A bottom sheet on phones, a centred card on
// wide screens. Closing keeps the reader's guess.

import { useState } from 'react';

export interface PendingSkipChoice {
  label: string;
  minutes: number;
  until: string;
  slept: boolean;
}

export interface PendingSkip {
  line: string;
  reason: 'noReading' | 'noAmount' | 'disagrees' | 'long' | string;
  question: string;
  now: string;
  choices: PendingSkipChoice[];
}

/** What the sheet posts: an offered skip, none, typed text, or keep. */
export type SkipAnswer =
  | { choice: number }
  | { none: true }
  | { other: string }
  | Record<string, never>;

const NONE = -1;
const OTHER = -2;

/** The clock part of an offered label: "8 hours · 9:40 AM" → "9:40 AM". */
function landsAt(label: string): string {
  const at = label.split(' · ').pop() ?? label;
  return at.includes(', ') ? at.split(', ').pop()! : at;
}

export function SkipConfirmSheet({
  pending,
  onAnswer,
  error,
}: {
  pending: PendingSkip;
  onAnswer: (answer: SkipAnswer) => void;
  /** The server's word on a bad "Other…" answer. */
  error?: string | null;
}) {
  // Pick B: with no reading there is no guess to preselect.
  const [picked, setPicked] = useState<number | null>(
    pending.reason !== 'noReading' && pending.choices.length > 0 ? 0 : null,
  );
  const [other, setOther] = useState('');

  const chosen = picked !== null && picked >= 0 ? pending.choices[picked] : null;
  const action =
    picked === NONE
      ? 'Send without a skip'
      : picked === OTHER
        ? other.trim()
          ? `Skip ${other.trim()}`
          : 'Pick one'
        : chosen
          ? `Skip to ${landsAt(chosen.label)}`
          : 'Pick one';
  const ready = picked === NONE || (picked === OTHER ? !!other.trim() : !!chosen);

  const submit = () => {
    if (!ready || picked === null) return;
    if (picked === NONE) onAnswer({ none: true });
    else if (picked === OTHER) onAnswer({ other: other.trim() });
    else onAnswer({ choice: picked });
  };

  const chip = (value: number, label: string) => (
    <button
      key={value}
      type="button"
      className={`skip-chip${picked === value ? ' on' : ''}`}
      aria-pressed={picked === value}
      onClick={() => setPicked(value)}
    >
      {label}
    </button>
  );

  return (
    <div
      className="drawer-backdrop center skip-confirm-overlay"
      onClick={() => onAnswer({})}
    >
      <div
        className="modal skip-confirm-sheet"
        role="dialog"
        aria-label="Did time pass?"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="drawer-head">
          <span>🕰️ Did time pass?</span>
          <button className="link-btn" onClick={() => onAnswer({})}>
            Close
          </button>
        </div>
        <p className="muted small">{pending.question}</p>
        <p className="skip-confirm-line">“{pending.line}”</p>
        <div className="skip-chips">
          {pending.choices.map((c, i) => chip(i, c.label))}
          {chip(NONE, 'No skip')}
          {chip(OTHER, 'Other…')}
        </div>
        {picked === OTHER && (
          <input
            className="skip-other"
            aria-label="How far to skip"
            placeholder="8h, 2d, morning, 7:30 pm"
            value={other}
            autoFocus
            onChange={(e) => setOther(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && submit()}
          />
        )}
        {error && <p className="skip-confirm-error small">{error}</p>}
        {chosen?.slept && picked !== null && picked >= 0 && (
          <p className="muted small">Everyone wakes rested.</p>
        )}
        <div className="modal-actions">
          <button className="primary" disabled={!ready} onClick={submit}>
            {action}
          </button>
        </div>
      </div>
    </div>
  );
}
