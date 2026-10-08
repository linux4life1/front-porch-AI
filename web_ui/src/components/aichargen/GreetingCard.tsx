// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One greeting on the creator's Greetings step: its text in the editor's
// MacroField, a one-line steer, Regenerate, and (alternates) Delete. While it
// is written it shows the incoming text and Stop. Drawn from the approved
// sketch (phone: "one greeting being written"; wide: the desktop step).

import { useState } from 'react';
import { MacroField } from '../MacroField';
import { useLayout } from '../../hooks/useBreakpoint';

const svg = {
  width: 18,
  height: 18,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
  'aria-hidden': true,
};

export const RefreshIcon = () => (
  <svg {...svg}>
    <path d="M20 11a8 8 0 1 0-2.3 5.7" />
    <path d="M20 4v7h-7" />
  </svg>
);

const TrashIcon = () => (
  <svg {...svg} width={20} height={20}>
    <path d="M5 7h14M10 7V4h4v3M7 7l1 13h8l1-13" />
  </svg>
);

const ExpandIcon = () => (
  <svg {...svg}>
    <path d="M15 4h5v5M9 20H4v-5M20 4l-6 6M4 20l6-6" />
  </svg>
);

export const PlusIcon = () => (
  <svg {...svg} strokeWidth={2.2}>
    <path d="M12 5v14M5 12h14" />
  </svg>
);

const StopIcon = () => (
  <svg width={14} height={14} viewBox="0 0 24 24" fill="currentColor" aria-hidden>
    <rect x="5" y="5" width="14" height="14" rx="2" />
  </svg>
);

export function GreetingCard({
  index,
  title,
  subtitle,
  value,
  onChange,
  steer,
  onSteer,
  writing,
  locked,
  error,
  onRegenerate,
  onStop,
  onDelete,
}: {
  index: number;
  title: string;
  subtitle?: string;
  /** Null while an alternate is being added: it has no text yet. */
  value: string | null;
  onChange: (v: string) => void;
  steer: string;
  onSteer: (v: string) => void;
  /** The incoming text while this greeting is written, else null. */
  writing: string | null;
  /** Another greeting is being written: this card's buttons wait. */
  locked: boolean;
  error?: string;
  onRegenerate: () => void;
  onStop: () => void;
  /** Absent for the first message, which cannot be deleted. */
  onDelete?: () => void;
}) {
  const { isPhone } = useLayout();
  const [full, setFull] = useState(false);
  const isWriting = writing !== null;
  return (
    <section
      className={`cg-g-card${isWriting ? ' writing' : ''}`}
      aria-label={title}
      data-testid={`greeting-card-${index}`}
    >
      <div className="cg-g-card-head">
        <h3>{title}</h3>
        {subtitle && <span className="cg-g-sub">{subtitle}</span>}
        {isWriting && <span className="cg-g-writing">Writing…</span>}
        <span className="cg-g-spacer" />
        {value !== null && !isWriting && (
          <button
            type="button"
            className="cg-g-icon"
            aria-label={`Open ${title.toLowerCase()} in the full editor`}
            title="Open the full editor"
            onClick={() => setFull(true)}
          >
            <ExpandIcon />
          </button>
        )}
        {onDelete && !isWriting && (
          <button
            type="button"
            className="cg-g-icon"
            aria-label={`Delete ${title.toLowerCase()}`}
            title={`Delete ${title.toLowerCase()}`}
            disabled={locked}
            onClick={onDelete}
          >
            <TrashIcon />
          </button>
        )}
      </div>
      {isWriting || value === null ? (
        <div className="cg-g-stream" aria-live="polite" data-testid="greeting-stream">
          {writing}
          <span className="cg-g-caret" />
        </div>
      ) : (
        <MacroField
          label={title}
          value={value}
          onChange={onChange}
          rows={isPhone ? 5 : 4}
          ariaLabel={`${title} text`}
          showHead={false}
          full={full}
          onFullChange={setFull}
        />
      )}
      {error && <p className="error cg-g-error">{error}</p>}
      <div className="cg-g-steer-row">
        <input
          className="cg-g-steer"
          aria-label="Steer the rewrite (optional)"
          placeholder={
            isPhone ? 'Steer it (optional)' : 'Steer it (optional), e.g. start at the harbor at dawn'
          }
          value={steer}
          disabled={isWriting}
          onChange={(e) => onSteer(e.target.value)}
        />
        {isWriting ? (
          <button type="button" className="cg-g-stop" onClick={onStop}>
            <StopIcon />
            Stop
          </button>
        ) : (
          <button
            type="button"
            className="cg-g-regen"
            disabled={locked || value === null}
            onClick={onRegenerate}
          >
            <RefreshIcon />
            Regenerate
          </button>
        )}
      </div>
    </section>
  );
}
