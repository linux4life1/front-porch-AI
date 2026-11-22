// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of the desktop TraitKitEditor
// (lib/ui/widgets/trait_kit_editor.dart) — the card kit block from
// docs/design/boons-and-bogies.md §4. One row per entry: kind, text,
// starting tier, pin. The 6-entry cap (ruling 11) is enforced here; the
// parse layer truncates, but an author who hits the wall should see it.

import type { TraitKitEntry } from './realismTypes';
import { MAX_KIT_ENTRIES, SEED_TIER_NAMES } from './realismTypes';

const KINDS = ['boon', 'bogey'] as const;
// Seed cap (ruling 8, amended 2026-11-21): the editor offers Novice and
// Skilled only. Master is milestone ground; a card that claims it (the old
// `established` wire value) reads back as Skilled after the reader clamps.
const TIERS = ['emerging', 'developing'] as const;
// Ladder name (SEED_TIER_NAMES, ruling 2) + what the seed buys the trait.
const TIER_SUFFIX: Record<string, string> = {
  emerging: 'starts faint',
  developing: 'a known habit',
  established: 'a known habit',
};
const TIER_LABEL: Record<string, string> = Object.fromEntries(
  TIERS.map((t) => [t, `${SEED_TIER_NAMES[t]} — ${TIER_SUFFIX[t]}`]),
);

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
        {/* Beta marker for nightly ships. Remove together with the
            settings copy when phase 5 lands — tracked in issue #763. */}
        <span
          className="trait-kit-beta"
          title="Beta: shipping ahead of the full ruleset. Milestones (Master, overcome) arrive in a later update; until then growth stops one step below Master."
        >
          BETA
        </span>
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
                // Kind decides the pin default on a fresh row, and so
                // does tier (ruling, 2026-11-21): a fresh Skilled bogey
                // arrives pinned, a fresh Novice one stays fragile until
                // the story says otherwise (§4).
                pinned:
                  e.text === '' &&
                  ev.target.value === 'bogey' &&
                  e.tier === 'developing'
                    ? true
                    : e.pinned,
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
