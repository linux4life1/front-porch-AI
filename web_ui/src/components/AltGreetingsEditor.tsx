// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Shared alternate-greetings list editor used by the character create wizard
// and the character edit page so both author and revise the greeting cycler
// identically. The chat greeting picker cycles through firstMessage + these.
// Each alt can carry a sparse Realism/Needs opening overlay.

import { GreetingSeedForm } from './GreetingSeedForm';
import { type GreetingSeed } from './realism/realismTypes';

export function AltGreetingsEditor({
  greetings,
  onChange,
  seeds = [],
  onSeedsChange,
  showNeeds = true,
  clockOn,
}: {
  greetings: string[];
  onChange: (next: string[]) => void;
  seeds?: (GreetingSeed | null)[];
  onSeedsChange?: (next: (GreetingSeed | null)[]) => void;
  showNeeds?: boolean;
  /** Porch Life's Passage of Time, for the Needs block's clock-off line. */
  clockOn: boolean;
}) {
  const aligned = align(seeds, greetings.length);
  const setSeeds = (next: (GreetingSeed | null)[]) => onSeedsChange?.(align(next, greetings.length));
  return (
    <>
      <div className="row-label">
        <span>Alternate greetings</span>
        <button
          className="ghost"
          onClick={() => {
            onChange([...greetings, '']);
            setSeeds([...aligned, null]);
          }}
        >
          + Add
        </button>
      </div>
      {greetings.length === 0 && (
        <p className="muted small">
          None. Add openings the reader can cycle through on the first message.
          Each one can carry its own mood, bond, clock and needs.
        </p>
      )}
      {greetings.map((g, i) => (
        <div className="tool-col" key={i}>
          <div className="tool-row">
            <textarea
              rows={3}
              value={g}
              onChange={(e) => {
                const next = [...greetings];
                next[i] = e.target.value;
                onChange(next);
              }}
            />
            <button
              className="icon-btn"
              title="Remove"
              onClick={() => {
                onChange(greetings.filter((_, j) => j !== i));
                setSeeds(aligned.filter((_, j) => j !== i));
              }}
            >
              🗑
            </button>
          </div>
          {onSeedsChange && (
            <GreetingSeedForm
              seed={aligned[i] ?? null}
              showNeeds={showNeeds}
              clockOn={clockOn}
              showInventory
              onChange={(next) => {
                const copy = [...aligned];
                copy[i] = next;
                setSeeds(copy);
              }}
            />
          )}
        </div>
      ))}
    </>
  );
}

function align(seeds: (GreetingSeed | null)[], n: number): (GreetingSeed | null)[] {
  if (n <= 0) return [];
  if (seeds.length === n) return seeds;
  if (seeds.length > n) return seeds.slice(0, n);
  return [...seeds, ...Array<GreetingSeed | null>(n - seeds.length).fill(null)];
}
