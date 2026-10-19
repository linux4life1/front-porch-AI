// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Client side of ⌘F find-in-chat. Counts and navigation come from the
// server scan (`GET /api/chat/search`, the Dart engine in
// lib/services/chat/chat_search_engine.dart — the single semantic truth).
// This mirror exists only so leaves can self-highlight the strings they
// actually render: plain substring, word-anchored glob (`*dog` → bulldog,
// never dogwood), or raw regex — `Aa` toggling case-sensitivity, `\*`
// escaping a literal star. Word boundaries are checked manually, matching
// the Dart engine exactly.

import { createContext, useContext } from 'react';

export type FindSpec = {
  bad: boolean;
  mode: 'plain' | 'pattern';
  needle: string;
  re?: RegExp;
  wordBounded: boolean;
  caseSensitive: boolean;
};

const IMAGE_SPAN = /!\[[^\]]*\]\((?:https?:\/\/[^)]+)\)/g;
const WORD_CHAR = /[\p{L}\p{N}_]/u;
const META = /[.*+?^${}()|[\]\\]/g;
const SENT = '\uE000';

export function compileFindQuery(
  raw: string,
  opts: { regex?: boolean; caseSensitive?: boolean } = {},
): FindSpec {
  const query = raw.trim();
  const caseSensitive = !!opts.caseSensitive;
  if (opts.regex) {
    if (!query) return { bad: false, mode: 'plain', needle: '', wordBounded: false, caseSensitive };
    try {
      const re = new RegExp(query, 'gu' + (caseSensitive ? '' : 'i'));
      return { bad: false, mode: 'pattern', needle: '', re, wordBounded: false, caseSensitive };
    } catch {
      return { bad: true, mode: 'plain', needle: '', wordBounded: false, caseSensitive };
    }
  }
  const folded = (caseSensitive ? query : query.toLowerCase()).split('\\*').join(SENT);
  if (!folded.includes('*')) {
    return {
      bad: false,
      mode: 'plain',
      needle: folded.split(SENT).join('*'),
      wordBounded: false,
      caseSensitive,
    };
  }
  const parts = folded
    .split('*')
    .map((p) => p.replace(META, '\\$&').split(SENT).join('\\*'));
  const re = new RegExp(parts.join('[\\p{L}\\p{N}_]*'), 'gu' + (caseSensitive ? '' : 'i'));
  return { bad: false, mode: 'pattern', needle: '', re, wordBounded: true, caseSensitive };
}

export type FindRange = [number, number];

/** Ranges of [spec] in one string — image spans excluded, glob matches
 * word-anchored manually (no lookbehind, mirroring the Dart engine). */
export function findRanges(text: string, spec: FindSpec): FindRange[] {
  const out: FindRange[] = [];
  if (spec.mode === 'plain' && !spec.needle) return out;
  const images: FindRange[] = [];
  IMAGE_SPAN.lastIndex = 0;
  let im: RegExpExecArray | null;
  while ((im = IMAGE_SPAN.exec(text)) !== null) images.push([im.index, im.index + im[0].length]);
  const inImage = (start: number, end: number) =>
    images.some(([s, e]) => start < e && end > s);

  if (spec.mode === 'plain') {
    const hay = spec.caseSensitive ? text : text.toLowerCase();
    let idx = hay.indexOf(spec.needle);
    while (idx !== -1) {
      const end = idx + spec.needle.length;
      if (!inImage(idx, end)) out.push([idx, end]);
      idx = hay.indexOf(spec.needle, idx + 1);
    }
    return out;
  }
  const re = spec.re;
  if (!re) return out;
  re.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    if (m[0].length === 0) {
      re.lastIndex += 1;
      continue;
    }
    const start = m.index;
    const end = m.index + m[0].length;
    if (spec.wordBounded) {
      if (start > 0 && WORD_CHAR.test(text[start - 1])) continue;
      if (end < text.length && WORD_CHAR.test(text[end])) continue;
    }
    if (inImage(start, end)) continue;
    out.push([start, end]);
  }
  return out;
}

/** What mounted bubbles read to paint highlights: the compiled query plus
 * the active hit's message/region/occurrence (from the server scan). */
export type FindSurface = {
  spec: FindSpec;
  activeMessageIndex: number | null;
  activeRegion: 'body' | 'sender';
  activeOccurrence: number;
};

export const FindSurfaceContext = createContext<FindSurface | null>(null);
export const useFindSurface = () => useContext(FindSurfaceContext);
