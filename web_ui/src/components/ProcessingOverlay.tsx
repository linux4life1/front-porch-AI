// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Realism / Objective "engine is thinking" overlay — the web mirror of the
// desktop realism_processing_overlay + objective_check_overlay. Shows the live
// eval stream while the Realism Engine evaluates, and a status panel while the
// Objective Engine checks task completion. Driven by the `processing` WS event.

import { useEffect, useRef } from 'react';

export interface Processing {
  active: boolean;
  realism: boolean;
  objective: boolean;
  greeting: boolean;
  verifying: boolean;
  text: string;
}

export const NO_PROCESSING: Processing = {
  active: false,
  realism: false,
  objective: false,
  greeting: false,
  verifying: false,
  text: '',
};

export function ProcessingOverlay({ p, onCancel }: { p: Processing; onCancel: () => void }) {
  const streamRef = useRef<HTMLPreElement>(null);
  // Keep the live stream scrolled to the newest text.
  useEffect(() => {
    if (streamRef.current) streamRef.current.scrollTop = streamRef.current.scrollHeight;
  }, [p.text]);

  if (!p.active) return null;

  const realismMode = p.realism;
  const title = p.greeting
    ? 'Reading the room…'
    : p.verifying
      ? '🕵️ Verifying Realism output'
      : realismMode
        ? 'Realism Engine'
        : 'Objective Engine';
  const subtitle = p.greeting
    ? 'Capturing emotional baseline from the opening message'
    : p.verifying
      ? 'Checking deltas & latent context; applying corrections as needed'
      : realismMode
        ? 'Evaluating relationship, mood & scene state'
        : 'Evaluating objective & task completion';
  const stages = realismMode
    ? [...(p.objective ? ['Objective'] : []), 'Relationship', 'Emotion', 'Scene', 'Trust']
    : ['Objective', 'Progress', 'Completion'];

  return (
    <div className="proc-overlay" role="status" aria-live="polite">
      <div className="proc-card">
        <div className="proc-head">
          <span className="proc-spinner" aria-hidden />
          <div className="proc-headtext">
            <div className="proc-title">{title}</div>
            <div className="proc-sub muted small">{subtitle}</div>
          </div>
        </div>

        <div className="proc-stages">
          {stages.map((s) => (
            <span key={s} className="proc-pill">{s}</span>
          ))}
        </div>

        {realismMode && p.text ? (
          <div className="proc-stream">
            <div className="proc-stream-head"><span className="proc-dot" aria-hidden /> LIVE EVAL STREAM</div>
            <pre className="proc-stream-body" ref={streamRef}>{p.text}</pre>
          </div>
        ) : !realismMode ? (
          <p className="muted small proc-objtext">
            Reviewing recent conversation to determine if objectives or tasks have been fulfilled…
          </p>
        ) : null}

        {realismMode && (
          <button type="button" className="proc-cancel" onClick={onCancel}>Cancel Realism</button>
        )}
      </div>
    </div>
  );
}
