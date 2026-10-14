// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One review rewrite card (Example dialogue, Lorebook): its content, a
// one-line steer and the rewrite button, which is Stop while this card is
// written. Locked while something else is written.

import { useState, type ReactNode } from 'react';
import { RewriteIcon, StopIcon } from './creatorIcons';

export function ReviewRewriteCard({
  title,
  subtitle,
  headAction,
  children,
  placeholder,
  button,
  caption,
  writing,
  locked,
  error,
  onRewrite,
  onStop,
}: {
  title: string;
  subtitle: string;
  /** A text button at the right of the header (Open the lorebook editor). */
  headAction?: ReactNode;
  children: ReactNode;
  placeholder: string;
  button: string;
  caption?: string;
  writing: boolean;
  locked: boolean;
  error?: string;
  onRewrite: (direction: string) => void;
  onStop: () => void;
}) {
  const [steer, setSteer] = useState('');
  return (
    <section
      className={`cg-g-card${writing ? ' writing' : ''}`}
      aria-label={title}
      data-testid={`review-${title.toLowerCase().replace(/\s+/g, '-')}`}
    >
      <div className="cg-g-card-head">
        <h3>{title}</h3>
        {writing ? <span className="cg-g-writing">Writing…</span> : <span className="cg-g-sub cg-r-sub">{subtitle}</span>}
        <span className="cg-g-spacer" />
        {headAction}
      </div>
      {children}
      {error && <p className="error cg-g-error">{error}</p>}
      <div className="cg-g-steer-row">
        <input
          className="cg-g-steer"
          aria-label={`Steer the ${title.toLowerCase()} (optional)`}
          placeholder={placeholder}
          value={steer}
          disabled={writing}
          onChange={(e) => setSteer(e.target.value)}
        />
        {writing ? (
          <button type="button" className="cg-g-stop" onClick={onStop}>
            <StopIcon />
            Stop
          </button>
        ) : (
          <button type="button" className="cg-g-regen" disabled={locked} onClick={() => onRewrite(steer)}>
            <RewriteIcon />
            {button}
          </button>
        )}
      </div>
      {caption && <p className="cg-p-caption">{caption}</p>}
    </section>
  );
}
