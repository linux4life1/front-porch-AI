// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Up next": where the story is and the one thing to do about it. The card the
// Overview opens with, selected (amber ring). Web twin of _upNextCard.

import { Chip } from '../StudioShell';
import { CardHead } from './CardHead';
import type { UpNext } from './upNext';

export function UpNextCard({ up, running, onAction, onAutopilot }: {
  up: UpNext;
  running: boolean;
  onAction: () => void;
  onAutopilot: () => void;
}) {
  const primaryTestId = {
    continue: 'story-continue', acts: 'story-build-acts', bible: 'story-build-bible', read: 'story-read',
  }[up.action];
  return (
    <section className="s-card sel" data-testid="studio-up-next">
      <CardHead label="Up next">{up.sequence && <Chip>{up.sequence}</Chip>}</CardHead>
      <div className="s-upnext">
        <div className="s-upnext-text">
          <div className="s-bold">{up.title}</div>
          <div className="s-muted s-small">{up.detail}</div>
        </div>
        {up.autopilot && (
          <button type="button" className="s-btn-quiet" data-testid="story-autopilot" disabled={running || up.autopilotIdle}
            onClick={onAutopilot}>Autopilot…</button>
        )}
        <button type="button" className="s-btn-primary" data-testid={primaryTestId} disabled={running && up.action !== 'read'}
          onClick={onAction}>{up.label}</button>
      </div>
    </section>
  );
}
