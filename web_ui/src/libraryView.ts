// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Characters-screen sort and search scope. Desktop stores the sort in
// SharedPreferences (uiSettings.sortMode / sort_mode). The web settings API
// does not read or write that pref, so the PWA keeps its own copy on this
// device. Unknown values and storage failures fall back to the defaults.
// The free-text search box is not stored.

const SORT_KEY = 'fpai.lib.sort';
const SCOPE_KEY = 'fpai.lib.scope';

export const LIBRARY_SORTS = ['name', 'recent', 'messages', 'importDate'] as const;
export type LibrarySort = (typeof LIBRARY_SORTS)[number];

export const LIBRARY_SCOPES = ['currentFolder', 'folderRecursive', 'allCharacters'] as const;
export type LibraryScope = (typeof LIBRARY_SCOPES)[number];

function readEnum<T extends string>(key: string, allowed: readonly T[], fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    if (raw != null && (allowed as readonly string[]).includes(raw)) return raw as T;
  } catch {
    /* private mode / blocked storage */
  }
  return fallback;
}

function writeEnum(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* storage full / disabled — the choice just won't survive a relaunch */
  }
}

export function loadLibrarySort(): LibrarySort {
  return readEnum(SORT_KEY, LIBRARY_SORTS, 'name');
}

export function saveLibrarySort(value: string): LibrarySort {
  const next = readEnumValue(value, LIBRARY_SORTS, 'name');
  writeEnum(SORT_KEY, next);
  return next;
}

export function loadLibraryScope(): LibraryScope {
  return readEnum(SCOPE_KEY, LIBRARY_SCOPES, 'currentFolder');
}

export function saveLibraryScope(value: string): LibraryScope {
  const next = readEnumValue(value, LIBRARY_SCOPES, 'currentFolder');
  writeEnum(SCOPE_KEY, next);
  return next;
}

function readEnumValue<T extends string>(value: string, allowed: readonly T[], fallback: T): T {
  return (allowed as readonly string[]).includes(value) ? (value as T) : fallback;
}
