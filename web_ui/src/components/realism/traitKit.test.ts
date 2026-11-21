// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web half of the kit contract (docs/design/boons-and-bogies.md §4).
//
// CharacterEditPage sends `...rv` wholesale, so `realismFromDetail` is the
// gate: a kit part it does not carry is a kit part every web save drops —
// the inventory lesson (realismTypes.test.ts) applied to the new field.
// These mirror the Dart reader's rules so the two ends of one bridge can
// not drift into disagreeing about what a card means.

import { describe, expect, it } from 'vitest';

import {
  MAX_KIT_ENTRIES,
  MAX_KIT_TEXT_CHARS,
  realismFromDetail,
  traitKitFromDetail,
} from './realismTypes';

describe('traitKitFromDetail — one reader, two ends', () => {
  it('keeps a good kit untouched', () => {
    const kit = traitKitFromDetail([
      { kind: 'boon', text: 'reads a room in one breath', tier: 'established' },
      { kind: 'bogey', text: 'bad temper', tier: 'developing', pinned: false },
    ]);
    expect(kit).toHaveLength(2);
    expect(kit[0].pinned).toBe(false); // boons default unpinned
    expect(kit[1].pinned).toBe(false); // explicit false beats the bogey default
  });

  it('defaults a bogey pinned and a boon not (§4)', () => {
    const kit = traitKitFromDetail([
      { kind: 'bogey', text: 'bad temper' },
      { kind: 'boon', text: 'steady hands' },
    ]);
    expect(kit[0].pinned).toBe(true);
    expect(kit[1].pinned).toBe(false);
  });

  it('drops unknown kinds and blank text, falls back bad tiers', () => {
    const kit = traitKitFromDetail([
      { kind: 'power', text: 'flight' },
      { kind: 'boon', text: '   ' },
      { kind: 'boon', text: 'steady hands', tier: 'royal' },
      'junk',
      null,
    ]);
    expect(kit).toHaveLength(1);
    expect(kit[0].tier).toBe('emerging');
  });

  it('truncates long text and caps the count, never throws', () => {
    const kit = traitKitFromDetail([
      { kind: 'boon', text: 'x'.repeat(200) },
      ...Array.from({ length: 9 }, (_, i) => ({ kind: 'boon', text: `t ${i}` })),
    ]);
    expect(kit).toHaveLength(MAX_KIT_ENTRIES);
    expect(kit[0].text).toHaveLength(MAX_KIT_TEXT_CHARS);
  });

  it('yields empty for junk shapes', () => {
    for (const junk of [undefined, null, 'kit', 7, {}, [42]]) {
      expect(traitKitFromDetail(junk)).toEqual([]);
    }
  });

  it('carries linkedTo only when it says something', () => {
    const kit = traitKitFromDetail([
      { kind: 'bogey', text: 'a', linkedTo: 'reads a room' },
      { kind: 'bogey', text: 'b', linkedTo: '  ' },
    ]);
    expect(kit[0].linkedTo).toBe('reads a room');
    expect(kit[1].linkedTo).toBeUndefined();
  });
});

describe('realismFromDetail carries the kit like the Dart bridge does', () => {
  it('parses a realism block that has one', () => {
    const rv = realismFromDetail({
      traitKit: [{ kind: 'bogey', text: 'bad temper', tier: 'established' }],
    });
    expect(rv.traitKit).toHaveLength(1);
    expect(rv.traitKit[0].pinned).toBe(true);
  });

  it('defaults to an empty kit — a web save never invents entries', () => {
    expect(realismFromDetail({}).traitKit).toEqual([]);
    expect(realismFromDetail(null).traitKit).toEqual([]);
  });

  it('truncates past the budget instead of trusting the payload', () => {
    const rv = realismFromDetail({
      traitKit: Array.from({ length: 9 }, (_, i) => ({
        kind: 'boon',
        text: `t ${i}`,
      })),
    });
    expect(rv.traitKit).toHaveLength(MAX_KIT_ENTRIES);
  });
});
