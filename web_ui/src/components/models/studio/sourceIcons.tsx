// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where a Recent picture came from: the sources the shelf's chips sort by,
// in the desktop's order and words, and the line icon for each (the desktop
// draws the matching Material outline icons).

export type SourceKey = 'studio' | 'edit' | 'creator' | 'chat' | 'guest' | 'story';

export const SOURCES: { key: SourceKey; label: string }[] = [
  { key: 'studio', label: 'Studio' },
  { key: 'edit', label: 'Edits' },
  { key: 'creator', label: 'Character creator' },
  { key: 'chat', label: 'Chat' },
  { key: 'guest', label: 'Guests' },
  { key: 'story', label: 'Story Studio' },
];

/** The source a picture carries; an older computer sends none, so the mode decides. */
export function sourceOf(entry: { source?: string; mode?: string }): SourceKey {
  const known = SOURCES.find((s) => s.key === entry.source);
  if (known) return known.key;
  return entry.mode === 'edit' ? 'edit' : 'studio';
}

export function sourceLabel(key: SourceKey): string {
  return SOURCES.find((s) => s.key === key)?.label ?? 'Studio';
}

export function SourceIcon({ source, size = 12 }: { source: SourceKey; size?: number }) {
  return (
    <svg viewBox="0 0 24 24" width={size} height={size} fill="none" stroke="currentColor"
      strokeWidth={2.2} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      {source === 'studio' ? <path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z" /> : null}
      {source === 'edit' ? <path d="M4 20h4L19 9l-4-4L4 16z" /> : null}
      {source === 'creator' ? (
        <>
          <circle cx="9" cy="8" r="3.5" />
          <path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6" />
          <path d="M19 7v6M16 10h6" />
        </>
      ) : null}
      {source === 'chat' ? <path d="M4 5h16v11H9l-5 4z" /> : null}
      {source === 'guest' ? (
        <>
          <path d="M6 3h12v18H6z" />
          <path d="M14 12h.01" />
        </>
      ) : null}
      {source === 'story' ? (
        <>
          <path d="M4 5c3-1 6-1 8 1c2-2 5-2 8-1v14c-3-1-6-1-8 1c-2-2-5-2-8-1z" />
          <path d="M12 6v14" />
        </>
      ) : null}
    </svg>
  );
}
