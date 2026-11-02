// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web/mobile Chance Time (chaos) "accept your fate" modal, the twin of
// the desktop wheel overlay. When a chaos event fires, the engine parks the
// send until the user accepts; the event is already picked (it comes in
// pre-resolved), so the wheel's spin is solved to land on a slot for it:
// outcome first, the wheel only dresses it. Three beats: SPIN → the wheel
// lands and settles → the card, then Accept. Centered and blocking on
// purpose: the paused reply can't continue until the user commits, exactly
// like the desktop dialog.

import { useEffect, useMemo, useState } from 'react';

import { CHANCE_WHEEL_SLOTS, chanceRevealEffectFor, fnv1a32 } from '../theme/chanceSpin';
import { ChanceTimeWheel } from './ChanceTimeWheel';

export function prefersReducedMotion(): boolean {
  return typeof window !== 'undefined' && typeof window.matchMedia === 'function'
    ? window.matchMedia('(prefers-reduced-motion: reduce)').matches
    : false;
}

export function ChanceTimeModal({
  event,
  revealed,
  kind,
  label,
  emoji,
  onReveal,
  onAccept,
}: {
  event: string;
  /** True once the user has pressed Spin. */
  revealed: boolean;
  kind?: string;
  label?: string;
  emoji?: string;
  onReveal: () => void;
  onAccept: () => void;
}) {
  // The spin is a function of the event: the same event spins the same
  // way on every device that shows it, and a reconnect replays it.
  const seed = useMemo(() => fnv1a32(event), [event]);
  const slot = seed % CHANCE_WHEEL_SLOTS;
  const effect = chanceRevealEffectFor(kind);
  const [landed, setLanded] = useState(false);
  const [settled, setSettled] = useState(false);
  const reduce = prefersReducedMotion();
  useEffect(() => {
    if (!revealed) {
      setLanded(false);
      setSettled(false);
    }
  }, [revealed, event]);

  return (
    <div className="chance-overlay" role="dialog" aria-modal="true" aria-label="Chance Time">
      <div className={`chance-card chance-card-wheel${landed ? ' landed' : ''}`}>
        <div className="chance-title">🎲 Chance Time</div>
        <ChanceTimeWheel
          seed={seed}
          slot={slot}
          effect={effect}
          spinning={revealed}
          reduceMotion={reduce}
          onLanded={() => setLanded(true)}
          onSettled={() => setSettled(true)}
          size={landed ? 200 : 280}
        />
        {!revealed ? (
          <button type="button" className="chance-btn spin" onClick={onReveal}>
            SPIN
          </button>
        ) : !settled ? (
          <p className="chance-sub" aria-live="polite">
            {landed ? 'Settling…' : 'Spinning…'}
          </p>
        ) : (
          <>
            <div className={`chance-kind tone-${effect}`} data-testid="chance-kind">
              {emoji ?? '🔮'} {label ?? 'Wild Card'}
            </div>
            <div className="chance-event">{event}</div>
            <button type="button" className="chance-btn accept" onClick={onAccept}>
              Accept Your Fate 🎲
            </button>
          </>
        )}
      </div>
    </div>
  );
}
