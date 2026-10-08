// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The continuity ledger's edits, the web twin of the desktop's
// StoryContinuity.record / category and the Lore screen's own edits. A fact
// added by hand goes through `recordFact`, so it behaves like one the engine
// recorded: an active fact about the same subject is retired as of the new
// one's scene, and the same words twice are one fact. Pure: each function
// returns the new list, ready for `save({ continuity })`.

import type { ContinuityFact } from '../../../storyTypes';

/** The chips of the Add / Edit dialog. */
export const FACT_CATEGORIES = ['Body', 'Object', 'Promise', 'Place', 'Fact'] as const;

const norm = (s: string): string => s.trim().toLowerCase();

/** Models write categories loosely; fold them onto the fixed set ("Fact" has no home of its own: it is Knowledge). */
export function foldCategory(raw: string): string {
  const c = norm(raw);
  if (c.includes('appear') || c.includes('body') || c.includes('injur')) return 'Body';
  if (c.includes('object') || c.includes('item') || c.includes('invent')) return 'Object';
  if (c.includes('promise') || c.includes('agree') || c.includes('deadline')) return 'Promise';
  if (c.includes('place') || c.includes('locat') || c.includes('setting')) return 'Place';
  if (c.includes('opinion') || c.includes('suspic') || c.includes('belief')) return 'Opinion';
  return 'Knowledge';
}

export const isRetired = (f: ContinuityFact): boolean => !!f.retired_scene_id;

/** Add [fact]; an active fact about the same subject (key + entity) is retired as of the new fact's scene. */
export function recordFact(facts: ContinuityFact[], fact: ContinuityFact): ContinuityFact[] {
  if (!fact.key.trim() || !fact.value.trim()) return facts;
  const added = { ...fact, category: foldCategory(fact.category) };
  const next = facts.map((f) => ({ ...f }));
  for (const old of next) {
    if (isRetired(old)) continue;
    if (norm(old.key) !== norm(added.key) || norm(old.entity) !== norm(added.entity)) continue;
    if (norm(old.value) === norm(added.value)) return facts;
    if (old.scene_id === added.scene_id) {
      old.value = added.value;
      old.category = added.category;
      return next;
    }
    old.retired_scene_id = added.scene_id;
  }
  next.push(added);
  return next;
}

export interface FactFields {
  category: string;
  key: string;
  value: string;
  entity: string;
}

/** A fact written by hand has no scene: it is true from the start ("always"). */
export const newFact = (f: FactFields): ContinuityFact => ({
  category: f.category, key: f.key.trim(), value: f.value.trim(), entity: f.entity.trim(), scene_id: '',
});

/** Change what a fact says; where it was recorded and whether it is retired stay. */
export function editFact(facts: ContinuityFact[], index: number, f: FactFields): ContinuityFact[] {
  return facts.map((old, i) => (i === index
    ? { ...old, category: f.category, key: f.key.trim(), value: f.value.trim(), entity: f.entity.trim() }
    : old));
}

/** Retire a fact as of a scene: it was true until then, and the ledger keeps it struck through. */
export function retireFact(facts: ContinuityFact[], index: number, sceneId: string): ContinuityFact[] {
  return facts.map((old, i) => (i === index ? { ...old, retired_scene_id: sceneId } : old));
}

export const forgetFact = (facts: ContinuityFact[], index: number): ContinuityFact[] => facts.filter((_, i) => i !== index);
