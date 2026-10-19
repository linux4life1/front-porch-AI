// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Client side of ⌘F find-in-chat. Counts, navigation AND the highlighted
// ranges all come from the server scan (`GET /api/chat/search`, the Dart
// engine in lib/services/chat/chat_search_engine.dart). Leaves never
// re-match the query: each one paints the slice of the engine's ranges that
// falls inside it, by its offset into the message text. Re-matching per
// leaf lit `^.` at the start of every colored run and could not light a hit
// that crosses from *action* into "dialogue".

import { createContext, createElement, useContext, type ReactNode } from 'react';

export type FindRange = [number, number];

/** One message's hits, as offsets into its text (body) and sender name. */
export type FindMessageHits = { body: FindRange[]; sender: FindRange[] };

/** What mounted bubbles read to paint highlights. */
export type FindSurface = {
  byMessage: Map<number, FindMessageHits>;
  active: { messageIndex: number; region: 'body' | 'sender'; start: number } | null;
};

export const FindSurfaceContext = createContext<FindSurface | null>(null);
export const useFindSurface = () => useContext(FindSurfaceContext);

/**
 * Paint the parts of [ranges] that fall inside one rendered run. [offset] is
 * where [plain] starts in the region string the ranges index into; a hit
 * split across runs paints each piece, and every piece of the hit starting
 * at [activeStart] is the active one.
 */
export function markRanges(
  plain: string,
  offset: number,
  ranges: readonly FindRange[],
  activeStart: number | null,
  key: string,
): ReactNode {
  const end = offset + plain.length;
  const nodes: ReactNode[] = [];
  let pos = 0;
  for (const [s, e] of ranges) {
    if (e <= offset || s >= end) continue;
    const from = Math.max(s - offset, 0);
    const to = Math.min(e - offset, plain.length);
    if (from > pos) nodes.push(plain.slice(pos, from));
    nodes.push(
      createElement(
        'mark',
        { key: `${key}-f${s}`, className: s === activeStart ? 'find-hit active' : 'find-hit' },
        plain.slice(from, to),
      ),
    );
    pos = to;
  }
  if (!nodes.length) return plain;
  if (pos < plain.length) nodes.push(plain.slice(pos));
  return nodes;
}
