// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web/mobile Chance Time (chaos) "accept your fate" modal — the reveal-card
// counterpart to the desktop spinning-wheel overlay. When a chaos event fires,
// the engine parks the send until the user accepts; a phone can't reach the
// desktop wheel, so this pops instead. Two beats: tease → reveal → accept. It's
// centered + blocking on purpose: the paused reply can't continue until the user
// commits, exactly like the desktop dialog.

export function ChanceTimeModal({
  event,
  revealed,
  onReveal,
  onAccept,
}: {
  event: string;
  revealed: boolean;
  onReveal: () => void;
  onAccept: () => void;
}) {
  return (
    <div className="chance-overlay" role="dialog" aria-modal="true" aria-label="Chance Time">
      <div className="chance-card">
        <div className="chance-title">🎲 Chance Time</div>
        {!revealed ? (
          <>
            <p className="chance-sub">Fate has something in store for you…</p>
            <button type="button" className="chance-btn" onClick={onReveal}>
              🎲 Reveal Fate
            </button>
          </>
        ) : (
          <>
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
