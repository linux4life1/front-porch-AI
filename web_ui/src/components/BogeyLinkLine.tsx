// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A bogey's boon link on its card — the web twin of the desktop
// `BogeyLinkLine` (lib/ui/chat_components/sidebar/journal_memory/
// bogey_link_line.dart; docs/design/boons-and-bogies.md phase 7, maintainer
// rulings 2026-11-26). "Held back by Stealth (Skilled)" with Change, or
// "Not linked to a boon" with Link when the owner has boons to pick. The
// picker posts the growth action `link` ({ringId, boonId|null}).

import { useState } from 'react';
import type { GrowthRing } from './GrowthPanel';

const TIER_NAME: Record<string, string> = {
  novice: 'Novice',
  skilled: 'Skilled',
  master: 'Master',
};

const tierName = (t?: string | null) => TIER_NAME[t ?? ''] ?? 'Novice';

export function BogeyLinkLine({
  ring,
  boons,
  act,
}: {
  ring: GrowthRing;
  boons: GrowthRing[];
  act?: (action: string, body?: Record<string, unknown>) => void;
}) {
  const [picking, setPicking] = useState(false);
  const linked = ring.linkedBoon ?? null;
  if (!linked && boons.length === 0) return null;
  const label = linked
    ? `Held back by ${linked.content} (${tierName(linked.tier)})`
    : 'Not linked to a boon';
  const choose = (boonId: string | null) => {
    setPicking(false);
    if (boonId === (linked?.id ?? null)) return;
    act?.('link', { ringId: ring.id, boonId });
  };
  return (
    <div className={`bogey-link${linked ? ' linked' : ''}`}>
      <span className="bogey-link-icon" aria-hidden="true">{linked ? '🛡️' : '🔗'}</span>
      <span className="bogey-link-text">{label}</span>
      {act && boons.length > 0 && (
        <button className="link-btn bogey-link-btn" onClick={() => setPicking(true)}>
          {linked ? 'Change' : 'Link'}
        </button>
      )}
      {picking && (
        <div className="drawer-backdrop center" onClick={() => setPicking(false)}>
          <div
            className="modal bogey-link-modal"
            role="dialog"
            aria-label="Which boon holds this back?"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="drawer-head">
              <span>Which boon holds this back?</span>
            </div>
            <p className="muted small">&ldquo;{ring.content}&rdquo;</p>
            <div className="bogey-link-options">
              {boons.map((b) => (
                <button
                  key={b.id}
                  className={`bogey-link-option${linked?.id === b.id ? ' selected' : ''}`}
                  onClick={() => choose(b.id)}
                >
                  <span aria-hidden="true">{linked?.id === b.id ? '◉' : '○'}</span>
                  {b.content} ({tierName(b.bbTier)})
                </button>
              ))}
              <button
                className={`bogey-link-option${linked ? '' : ' selected'}`}
                onClick={() => choose(null)}
              >
                <span aria-hidden="true">{linked ? '○' : '◉'}</span>
                No boon
              </button>
            </div>
            <div className="modal-actions">
              <button className="link-btn" onClick={() => setPicking(false)}>
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
