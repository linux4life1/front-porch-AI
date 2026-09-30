// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { filterByName, matchingEntryIndexes, tickedEntries } from './importCharacterLore';
import type { LoreEntry } from './LoreEntriesEditor';

const entries: LoreEntry[] = [
  { name: 'Harbor bell', key: 'harbor', content: 'Rings at dusk.', enabled: true, constant: false, stickyDepth: 4 },
  { name: 'Market day', key: 'market', content: 'Stalls at dawn.', enabled: true, constant: false, stickyDepth: 2 },
];

describe('place lore picked from a character', () => {
  it('filters characters by name and entries by any field', () => {
    expect(filterByName([{ name: 'Pier Keeper' }, { name: 'Quiet Extra' }], 'pier')).toEqual([
      { name: 'Pier Keeper' },
    ]);
    expect(matchingEntryIndexes(entries, 'dawn')).toEqual([1]);
    expect(matchingEntryIndexes(entries, '')).toEqual([0, 1]);
  });

  it('returns only the ticked entries', () => {
    expect(tickedEntries(entries, [0]).map((e) => e.name)).toEqual(['Harbor bell']);
    expect(tickedEntries(entries, []).length).toBe(0);
  });
});
