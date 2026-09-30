// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Selection helpers for copying some of a character's lore into a place.
// Nothing here copies a whole book; callers pass the indexes the user ticked.

import type { LoreEntry } from './LoreEntriesEditor';

export interface NamedCard {
  name: string;
}

export function filterByName<T extends NamedCard>(items: T[], query: string): T[] {
  const q = query.trim().toLowerCase();
  if (!q) return items;
  return items.filter((item) => item.name.toLowerCase().includes(q));
}

export function loreEntryLabel(entry: LoreEntry): string {
  const name = entry.name.trim();
  if (name) return name;
  const key = entry.key.trim();
  if (key) return key;
  return 'Unnamed entry';
}

/** Indexes whose name, keywords, or content contain [query]. */
export function matchingEntryIndexes(entries: LoreEntry[], query: string): number[] {
  const q = query.trim().toLowerCase();
  const all = entries.map((_, i) => i);
  if (!q) return all;
  return all.filter((i) => {
    const entry = entries[i];
    return `${loreEntryLabel(entry)}\n${entry.key}\n${entry.content}`
      .toLowerCase()
      .includes(q);
  });
}

/** The entries at [checked], in list order. Unchecked entries are dropped. */
export function tickedEntries(entries: LoreEntry[], checked: Iterable<number>): LoreEntry[] {
  const want = new Set(checked);
  return entries.filter((_, i) => want.has(i)).map((entry) => ({ ...entry }));
}
