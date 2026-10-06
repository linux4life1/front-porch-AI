// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The speed test's overlay on the phone, the desktop's warm dialog
// (showKoboldSpeedTest): the question with how long it takes, then the test
// as it runs (progress, the step, the time left and what it does, with
// Cancel), then the one line it ended with. Every sentence is the host's;
// the labels are the desktop's own.

import { useEffect, useId, useRef } from 'react';
import type { SpeedTestRun } from './types';
import { SPEED_TEST_STARTING, type SpeedTest } from './useSpeedTest';

export function SpeedTestOverlay({ speed }: { speed: SpeedTest }) {
  return speed.view.kind === 'closed' ? null : <SpeedTestDialog speed={speed} />;
}

/** "about 3 minutes" → "About 3 minutes left", as the desktop says it. */
const leftWords = (left: string) => `${left.charAt(0).toUpperCase()}${left.slice(1)} left`;

function SpeedTestDialog({ speed }: { speed: SpeedTest }) {
  const { view, closable, close } = speed;
  const titleId = useId();
  const bodyId = useId();
  const box = useRef<HTMLDivElement>(null);
  const run = speed.run ?? SPEED_TEST_STARTING;
  // Following the test: its progress while it runs, then how it ended.
  const shows = view.kind === 'watch' ? (speed.running ? 'progress' : 'ended') : view.kind;

  // Focus goes back where it was when the overlay closes (this runs first,
  // so it keeps what had focus before the overlay took it)…
  useEffect(() => {
    const before = document.activeElement;
    return () => {
      if (before instanceof HTMLElement) before.focus();
    };
  }, []);
  // …and comes into the overlay as it opens and each time it says something
  // new: the button that had focus may be gone.
  useEffect(() => box.current?.focus(), [shows]);

  useEffect(() => {
    if (!closable) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [closable, close]);

  return (
    <div className="drawer-backdrop center kc-speed-overlay" onClick={() => closable && close()}>
      <div
        ref={box}
        className="modal kc-speed-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        aria-describedby={bodyId}
        tabIndex={-1}
        data-testid="speed-test-overlay"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 id={titleId} className="kc-speed-title">
          Find the fastest settings
        </h2>
        {view.kind === 'ask' && (
          <>
            <p id={bodyId} className="kc-speed-text" data-testid="speed-test-ask">
              {view.words}
            </p>
            <div className="modal-actions">
              <button type="button" className="kc-btn" data-testid="speed-test-not-now" disabled={speed.busy} onClick={close}>
                Not now
              </button>
              <button
                type="button"
                className="kc-btn solid"
                data-testid="speed-test-run"
                disabled={speed.busy}
                onClick={() => void speed.start()}
              >
                Run it
              </button>
            </div>
          </>
        )}
        {view.kind === 'refused' && (
          <>
            <p id={bodyId} className="kc-speed-text" data-testid="speed-test-refused">
              {view.words}
            </p>
            <div className="modal-actions">
              <button type="button" className="kc-btn" data-testid="speed-test-close" onClick={close}>
                Close
              </button>
            </div>
          </>
        )}
        {shows === 'progress' && (
          <>
            <Progress run={run} labelId={titleId} bodyId={bodyId} />
            {speed.problem && (
              <div className="kc-verdict bad" role="alert" data-testid="speed-test-problem">
                <span className="kc-mark" aria-hidden="true" />
                <p>{speed.problem}</p>
              </div>
            )}
            <div className="modal-actions">
              <button
                type="button"
                className="kc-btn"
                data-testid="speed-test-cancel"
                disabled={run.state === 'stopping' || speed.busy}
                onClick={() => void speed.cancel()}
              >
                Cancel
              </button>
            </div>
          </>
        )}
        {shows === 'ended' && (
          <>
            <p id={bodyId} className="kc-speed-text kc-speed-result" data-testid="speed-test-line">
              {run.line ?? ''}
            </p>
            <div className="modal-actions">
              <button type="button" className="kc-btn solid" data-testid="speed-test-done" onClick={close}>
                Done
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}

/** The test as it runs: the bar counts finished steps, as the desktop's does. */
function Progress({ run, labelId, bodyId }: { run: SpeedTestRun; labelId: string; bodyId: string }) {
  const { step, steps } = run;
  const done = Math.min(Math.max(step - 1, 0), steps);
  const stepWords = steps === 0 ? 'Getting ready' : `Step ${step} of ${steps}`;
  return (
    <>
      <div
        className={steps === 0 ? 'kc-progress waiting' : 'kc-progress'}
        role="progressbar"
        aria-labelledby={labelId}
        aria-valuemin={0}
        aria-valuemax={steps === 0 ? undefined : steps}
        aria-valuenow={steps === 0 ? undefined : done}
        aria-valuetext={steps === 0 ? undefined : stepWords}
        data-testid="speed-test-progress"
      >
        <span className="kc-progress-fill" style={steps === 0 ? undefined : { width: `${(done / steps) * 100}%` }} />
      </div>
      <div className="kc-speed-steps">
        <span className="kc-speed-step" data-testid="speed-test-step">
          {stepWords}
        </span>
        {steps > 0 && run.left && (
          <span className="kc-speed-left" data-testid="speed-test-left">
            {leftWords(run.left)}
          </span>
        )}
      </div>
      <p id={bodyId} className="kc-speed-text" aria-live="polite" data-testid="speed-test-doing">
        {run.doing}
      </p>
    </>
  );
}
