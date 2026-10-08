// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The speed test on the phone's Local model card in auto mode, as the
// desktop's KoboldSpeedTestButton shows it: the button, why it cannot run
// now, and how the last test of this model ended, in the host's words. While
// a test runs the button opens it again, and the other two wait. It is not
// greyed while the question is on its way (a greyed button loses focus, which
// the overlay gives back to it when it closes); a second tap is ignored.

import { useId } from 'react';
import type { SpeedTestCard } from './types';
import type { SpeedTest } from './useSpeedTest';

export function SpeedTestButton({ card, speed }: { card: SpeedTestCard; speed: SpeedTest }) {
  const whyId = useId();
  const why = speed.running ? null : card.unavailable || null;
  const line = speed.running ? null : card.line || null;
  return (
    <div className="kc-speed">
      <button
        type="button"
        className="kc-btn amber kc-speed-btn"
        data-testid="speed-test-button"
        disabled={why !== null}
        aria-describedby={why === null ? undefined : whyId}
        onClick={() => void speed.open()}
      >
        {speed.running ? 'Testing speed settings…' : 'Find the fastest settings for this computer'}
      </button>
      {why !== null && (
        <p id={whyId} className="kc-speed-why" data-testid="speed-test-unavailable">
          {why}
        </p>
      )}
      {line !== null && (
        <p className="kc-speed-line" data-testid="speed-test-card-line">
          {line}
        </p>
      )}
    </div>
  );
}
