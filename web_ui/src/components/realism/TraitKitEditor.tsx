// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web mirror of the desktop TraitKitEditor
// (lib/ui/widgets/trait_kit_editor.dart) — the card kit block from
// docs/design/boons-and-bogies.md §4. One row per entry: kind, text,
// starting tier, pin. The 6-entry cap (ruling 11) is enforced here; the
// parse layer truncates, but an author who hits the wall should see it.

import { Fragment } from 'react';

import type { TraitKitEntry } from './realismTypes';
import { MAX_KIT_ENTRIES, SEED_TIER_NAMES } from './realismTypes';

/** The kit's scope hint under the bogey rows (#763) — the desktop's words. */
export const BOGEY_SCOPE_HINT =
  'Write flaws that can show up anywhere — one tied to a single place or object only shows near it.';

/** The pin default (ruling, 2026-11-21): a Skilled bogey arrives pinned. */
const defaultPin = (kind: string, tier: string) => kind === 'bogey' && tier === 'developing';

/**
 * A kind or tier change — the desktop's `_reshape`. The pin follows the
 * default while it still IS the default for the row as it was (typing first,
 * then flipping a Skilled row to Bogey now pins it, #763); a pin that
 * differs is the author's and stays. A boon carries no boon link.
 */
export function reshape(
  e: TraitKitEntry,
  next: { kind?: TraitKitEntry['kind']; tier?: TraitKitEntry['tier'] },
): Partial<TraitKitEntry> {
  const kind = next.kind ?? e.kind;
  const tier = next.tier ?? e.tier;
  return {
    kind,
    tier,
    pinned: e.pinned === defaultPin(e.kind, e.tier) ? defaultPin(kind, tier) : e.pinned,
    linkedTo: kind === 'bogey' ? e.linkedTo : undefined,
  };
}

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
  const boons = values
    .filter((e) => e.kind === 'boon' && e.text.trim() !== '')
    .map((e) => e.text.trim());

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
        <Fragment key={i}>
        <div className={`trait-kit-row${e.kind === 'bogey' ? ' bogey' : ''}`}>
          <select
            aria-label="Kind"
            value={e.kind}
            onChange={(ev) =>
              update(i, reshape(e, { kind: ev.target.value as (typeof KINDS)[number] }))
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
            onChange={(ev) =>
              update(i, reshape(e, { tier: ev.target.value as TraitKitEntry['tier'] }))
            }
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
        {e.kind === 'bogey' && boons.length > 0 && (
          // A bogey's boon link (#763; phase 7's roll bias reads it).
          <label className="trait-kit-link">
            <span>Pushes against</span>
            <select
              aria-label="Boon link"
              value={e.linkedTo && boons.includes(e.linkedTo) ? e.linkedTo : ''}
              onChange={(ev) => update(i, { linkedTo: ev.target.value || undefined })}
            >
              <option value="">No boon</option>
              {boons.map((b) => (
                <option key={b} value={b}>{b}</option>
              ))}
            </select>
          </label>
        )}
        </Fragment>
      ))}
      {bogeys > 0 && <p className="muted small" style={{ margin: '0 0 4px' }}>{BOGEY_SCOPE_HINT}</p>}
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
