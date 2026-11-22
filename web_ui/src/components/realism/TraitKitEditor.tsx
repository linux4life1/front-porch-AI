// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of the desktop TraitKitEditor
// (lib/ui/widgets/trait_kit_editor.dart) — the card kit block from
// docs/design/boons-and-bogies.md §4. One row per entry: kind, text,
// starting tier, pin. The 6-entry cap (ruling 11) is enforced here; the
// parse layer truncates, but an author who hits the wall should see it.

import type { TraitKitEntry } from './realismTypes';
import { MAX_KIT_ENTRIES } from './realismTypes';

const KINDS = ['boon', 'bogey'] as const;
const TIERS = ['emerging', 'developing', 'established'] as const;
const TIER_LABEL: Record<string, string> = {
  emerging: 'Novice — starts faint',
  developing: 'Skilled — a known habit',
  established: 'Master-bound — core to them',
};

export function TraitKitEditor({
  values,
  onChange,
  helper,
}: {
  values: TraitKitEntry[];
  onChange: (v: TraitKitEntry[]) => void;
  helper?: string;
}) {
  const full = values.length >= MAX_KIT_ENTRIES;
  const bogeys = values.filter((e) => e.kind === 'bogey').length;

  const update = (i: number, patch: Partial<TraitKitEntry>) =>
    onChange(values.map((e, j) => (i === j ? { ...e, ...patch } : e)));

  return (
    <div className="realism-field" data-testid="trait-kit">
      <div style={{ display: 'flex', alignItems: 'baseline' }}>
        <span className="realism-head" style={{ margin: 0 }}>Boons &amp; Bogies</span>
        <span className="chiplist-count">{values.length} of {MAX_KIT_ENTRIES}</span>
      </div>
      {helper && <p className="muted small" style={{ margin: '4px 0 8px' }}>{helper}</p>}
      {values.map((e, i) => (
        <div
          key={i}
          className={`trait-kit-row${e.kind === 'bogey' ? ' bogey' : ''}`}
        >
          <select
            aria-label="Kind"
            value={e.kind}
            onChange={(ev) =>
              update(i, {
                kind: ev.target.value as (typeof KINDS)[number],
                // Kind decides the pin default on a fresh row: a bogey
                // arrives pinned unless the author says otherwise (§4).
                pinned: e.text === '' && ev.target.value === 'bogey' ? true : e.pinned,
              })
            }
          >
            {KINDS.map((k) => (
              <option key={k} value={k}>{k === 'boon' ? 'Boon' : 'Bogey'}</option>
            ))}
          </select>
          <input
            aria-label="Trait"
            value={e.text}
            maxLength={160}
            placeholder="e.g. reads a room in one breath"
            onChange={(ev) => update(i, { text: ev.target.value })}
          />
          <select
            aria-label="Starting tier"
            value={e.tier}
            onChange={(ev) => update(i, { tier: ev.target.value as TraitKitEntry['tier'] })}
          >
            {TIERS.map((t) => (
              <option key={t} value={t}>{TIER_LABEL[t]}</option>
            ))}
          </select>
          <button
            type="button"
            className={`trait-kit-pin${e.pinned ? ' on' : ''}`}
            title={e.pinned ? 'Pinned — a seeded flaw never fades. Tap to unpin.' : 'Pin so the seeded trait never fades'}
            onClick={() => update(i, { pinned: !e.pinned })}
          >
            📌
          </button>
          <button
            type="button"
            aria-label="Remove"
            onClick={() => onChange(values.filter((_, j) => j !== i))}
          >
            ×
          </button>
        </div>
      ))}
      <button
        type="button"
        className="ghost"
        disabled={full}
        onClick={() =>
          onChange([...values, { kind: 'boon', text: '', tier: 'emerging', pinned: false }])
        }
      >
        {full ? 'Kit is full — 6 of 6' : '+ Add trait'}
      </button>
      {bogeys > 3 && (
        <p className="muted small" style={{ margin: '4px 0 0', color: 'var(--bogey)' }}>
          A chat runs at most 3 active bogies — past the third, seeding drops the extras.
        </p>
      )}
    </div>
  );
}
