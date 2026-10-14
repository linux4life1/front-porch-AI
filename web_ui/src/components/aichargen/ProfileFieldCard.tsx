// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One of the Profile step's three boxes (Description, Personality,
// Scenario): the editor's MacroField with the expand icon, or, while the
// profile is rewritten, the text coming in. The header says what the
// rewrite is doing to this box (docs/design/creator-ui-spec.md).

import { useState } from 'react';
import { MacroField } from '../MacroField';
import { useLayout } from '../../hooks/useBreakpoint';
import type { BoxState } from './profileApi';
import { ExpandIcon } from './creatorIcons';

const STATE_LABEL: Record<Exclude<BoxState, null>, string> = {
  writing: 'Writing…',
  waiting: 'Waiting for the description…',
  waitingShort: 'Waiting…',
  kept: 'Kept as it is',
  built: 'Kept as you built it',
};

export function ProfileFieldCard({
  title,
  subtitle,
  value,
  onChange,
  rewriting,
  state,
  streamed,
  scenario = false,
}: {
  title: string;
  /** Desktop only; the phone shows the rewrite's state alone. */
  subtitle: string;
  value: string;
  onChange: (v: string) => void;
  /** The profile is being rewritten: every box waits, read only. */
  rewriting: boolean;
  /** What the rewrite does to this box, or null when it is not touched. */
  state: BoxState;
  /** The text the rewrite has written into this box so far, when it has. */
  streamed: string | null;
  /** Scenario's box is capped lower on the phone. */
  scenario?: boolean;
}) {
  const { isPhone } = useLayout();
  const [full, setFull] = useState(false);
  const writing = state === 'writing';
  return (
    <section
      className={`cg-g-card${writing ? ' writing' : ''}`}
      aria-label={title}
      data-testid={`profile-card-${title.toLowerCase()}`}
    >
      <div className="cg-g-card-head">
        <h3>{title}</h3>
        {state ? (
          <span className={writing ? 'cg-g-writing' : 'cg-p-state'}>{STATE_LABEL[state]}</span>
        ) : (
          <span className="cg-g-sub">{subtitle}</span>
        )}
        <span className="cg-g-spacer" />
        <button
          type="button"
          className="cg-g-icon"
          aria-label={`Open ${title.toLowerCase()} in the full editor`}
          title="Open the full editor"
          disabled={rewriting}
          onClick={() => setFull(true)}
        >
          <ExpandIcon />
        </button>
      </div>
      {rewriting ? (
        <div
          className={`cg-g-stream${scenario ? ' cg-p-scenario' : ''}`}
          aria-live={writing ? 'polite' : undefined}
          data-testid={`profile-stream-${title.toLowerCase()}`}
        >
          {streamed ?? value}
          {writing && <span className="cg-g-caret" />}
        </div>
      ) : (
        <div className={scenario ? 'cg-p-scenario' : undefined}>
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
        </div>
      )}
    </section>
  );
}
