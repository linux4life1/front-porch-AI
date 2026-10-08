// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// How the Relationships screen reads and edits the ledger. `shiftRelationship`
// is the web twin of the desktop's StoryContinuity.shift: it creates the row
// when the pair is new, appends a history step only when the feeling actually
// changed, and never clears a note or an unspoken line by saving it empty.
// Pure: each edit returns the new list, ready for `save({ relationships })`.

import type { StoryProject, StoryRelationship } from '../../../storyTypes';
import { sceneLabelById, trustTone } from '../storyShape';

const norm = (s: string): string => s.trim().toLowerCase();

export interface Pair {
  from: string;
  to: string;
}

export interface Shift extends Pair {
  feeling: string;
  note?: string;
  subtext?: string;
  trust?: number;
  sceneId?: string;
  reason?: string;
}

/** The people the grid is drawn for: the cast, in order. */
export function relationshipNames(p: StoryProject): string[] {
  return [...new Set(p.cast.map((m) => m.name))];
}

export function findPair(rels: StoryRelationship[], from: string, to: string): StoryRelationship | undefined {
  return rels.find((r) => r.from === from && r.to === to);
}

/** Record that [from] now feels [feeling] about [to]. Returns the list unchanged when it makes no sense (same person, no feeling). */
export function shiftRelationship(rels: StoryRelationship[], s: Shift): StoryRelationship[] {
  const feeling = s.feeling.trim();
  if (!feeling || s.from === s.to) return rels;
  const next = rels.map((r) => ({ ...r, history: [...r.history] }));
  let rel = findPair(next, s.from, s.to);
  if (!rel) {
    rel = { from: s.from, to: s.to, feeling: '', note: '', subtext: '', trust: 5, history: [] };
    next.push(rel);
  }
  if (norm(rel.feeling) !== norm(feeling)) {
    rel.history.push({ scene_id: s.sceneId ?? '', from: rel.feeling || '—', to: feeling, reason: (s.reason ?? '').trim() });
    rel.feeling = feeling;
  }
  if (s.note?.trim()) rel.note = s.note.trim();
  if (s.subtext?.trim()) rel.subtext = s.subtext.trim();
  if (s.trust !== undefined) rel.trust = Math.min(Math.max(Math.round(s.trust), 0), 10);
  return next;
}

export function removePair(rels: StoryRelationship[], from: string, to: string): StoryRelationship[] {
  return rels.filter((r) => !(r.from === from && r.to === to));
}

/** The chip and cell colour for a pair: warm trust is teal, low trust bad, the rest honey. */
export function feelingTone(r: StoryRelationship): 'teal' | 'bad' | 'honey' {
  const tone = trustTone(r.trust);
  return tone === 'warm' ? 'teal' : tone === 'hot' ? 'bad' : 'honey';
}

/** "After scene 3.2": the last recorded move that happened in a scene (not one made by hand). */
export function recordedAfter(p: StoryProject): string {
  const moves = (p.relationships ?? []).flatMap((r) => r.history).filter((h) => h.scene_id);
  const latest = moves[moves.length - 1];
  return latest ? `After scene ${sceneLabelById(p, latest.scene_id)}` : 'Nothing recorded yet';
}
