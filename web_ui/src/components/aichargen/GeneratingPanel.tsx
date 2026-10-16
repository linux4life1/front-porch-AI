// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's Generate screen while a run writes, as the desktop draws
// it: the turning sparkle, the latest status line, the amber progress bar
// (indeterminate: the relay reports steps, not a fraction), then every step
// so far, numbered. Writing the rest after the Profile step has a Stop (the
// profile then waits as it was); the first pass has none, as the relay
// cannot stop a create.

import { Sparkle, StopIcon } from './creatorIcons';

export function GeneratingPanel({ steps, onStop }: { steps: string[]; onStop?: () => void }) {
  const status = steps[steps.length - 1] ?? 'Generating…';
  return (
    <div className="cg-generating" data-testid="generating-panel">
      <span className="cg-gen-spark">
        <Sparkle />
      </span>
      <p className="cg-gen-status" aria-live="polite">
        {status}
      </p>
      <div
        className="cg-gen-bar"
        role="progressbar"
        aria-label="Writing the character"
        aria-valuetext={status}
      >
        <span />
      </div>
      {onStop && (
        <button type="button" className="cg-g-stop cg-gen-stop" onClick={onStop}>
          <StopIcon />
          Stop
        </button>
      )}
      {steps.length > 0 && (
        <ol className="chargen-steps">
          {steps.map((s, i) => (
            <li key={i} className={i === steps.length - 1 ? 'active' : 'done'}>
              {s}
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}
