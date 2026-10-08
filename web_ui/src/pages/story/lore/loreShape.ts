// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the Lore & continuity screen says: the count line, the ledger's order
// (live facts first, retired last), the "from 3.3" column and the Story so far
// blocks. The same words as the desktop's lore_section.dart. Presentation only.

import type { ContinuityFact, StoryLoreEntry, StoryProject } from '../../../storyTypes';
import { sceneIndexesInSequence, sceneLabel, sceneLabelById } from '../storyShape';
import { isRetired } from './continuity';

const plural = (n: number, one: string, many: string): string => (n === 1 ? one : many);

/** Lore entries that came from a dropped-in file carry `file:<name>` in `related_to`. */
export const FILE_PREFIX = 'file:';

export const fileRefs = (l: StoryLoreEntry): string[] => (l.related_to ?? []).filter((r) => r.startsWith(FILE_PREFIX));

export function loreFileCount(lore: StoryLoreEntry[]): number {
  return new Set(lore.flatMap(fileRefs)).size;
}

/** "38 facts · 12 lore entries · 3 files". */
export function loreSubtitle(p: StoryProject): string {
  const facts = (p.continuity ?? []).length;
  const files = loreFileCount(p.lore);
  return `${facts} ${plural(facts, 'fact', 'facts')} · ${p.lore.length} lore ${plural(p.lore.length, 'entry', 'entries')} · ${files} ${plural(files, 'file', 'files')}`;
}

export interface FactRow {
  fact: ContinuityFact;
  /** Its place in the project's list: what an edit, a retire and a forget act on. */
  index: number;
}

/** Live facts in recorded order, then the retired ones. */
export function factRows(facts: ContinuityFact[]): FactRow[] {
  const rows = facts.map((fact, index) => ({ fact, index }));
  return [...rows.filter((r) => !isRetired(r.fact)), ...rows.filter((r) => isRetired(r.fact))];
}

/** "from 3.3", "always", or for a retired fact "1.1 → 3.3". */
export function factWhen(p: StoryProject, f: ContinuityFact): string {
  const from = f.scene_id ? sceneLabelById(p, f.scene_id) : '';
  if (isRetired(f)) return `${from || 'always'} → ${sceneLabelById(p, f.retired_scene_id ?? '')}`;
  return from ? `from ${from}` : 'always';
}

/** "from act 2, scene 3": shown only for lore that starts later than the beginning. */
export const loreFrom = (l: StoryLoreEntry): string =>
  (l.valid_from_act > 1 || l.valid_from_scene > 1 ? `from act ${l.valid_from_act}, scene ${l.valid_from_scene}` : '');

export interface SoFarBlock {
  key: string;
  heading: string;
  summary: string;
  lines: string[];
}

/** One block per sequence that has a summary or any scene summaries. */
export function soFarBlocks(p: StoryProject): SoFarBlock[] {
  const blocks: SoFarBlock[] = [];
  for (const seq of p.sequences ?? []) {
    const found = p.acts.findIndex((a) => a.number === seq.act);
    const act = found >= 0 ? found : seq.act - 1;
    const lines = sceneIndexesInSequence(p, act, seq.number)
      .map((i) => ({ i, scene: p.scenes[String(act)][i] }))
      .filter(({ scene }) => !!scene.summary)
      .map(({ i, scene }) => `${sceneLabel(p, act, i)} ${scene.title}: ${scene.summary}`);
    if (!seq.summary && lines.length === 0) continue;
    blocks.push({
      key: `${seq.act}-${seq.number}`,
      heading: `Sequence ${seq.number}${seq.title ? ` · ${seq.title}` : ''}`,
      summary: seq.summary,
      lines,
    });
  }
  return blocks;
}
