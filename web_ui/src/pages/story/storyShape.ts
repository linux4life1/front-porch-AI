// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Presentation-side readers of the story's shape — the same questions the
// desktop's StoryProjectShape extension answers (scene labels, sequence
// grouping, what is written), so the two surfaces label things identically.
// No engine logic lives here.

import type { StoryProject, StoryScene, StorySequence } from '../../storyTypes';

export interface SceneRef {
  act: number;
  index: number;
  scene: StoryScene;
}

export function sequencesInAct(p: StoryProject, act: number): StorySequence[] {
  const number = p.acts[act]?.number;
  if (number === undefined) return [];
  return (p.sequences ?? [])
    .filter((s) => s.act === number)
    .sort((a, b) => a.number - b.number);
}

export function sceneIndexesInSequence(p: StoryProject, act: number, number: number): number[] {
  const list = p.scenes[String(act)] ?? [];
  return list.map((s, i) => (s.sequence === number ? i : -1)).filter((i) => i >= 0);
}

export function orderedScenes(p: StoryProject): SceneRef[] {
  const out: SceneRef[] = [];
  p.acts.forEach((_, act) => {
    (p.scenes[String(act)] ?? []).forEach((scene, index) => out.push({ act, index, scene }));
  });
  return out;
}

export function findScene(p: StoryProject, id: string): SceneRef | undefined {
  if (!id) return undefined;
  return orderedScenes(p).find((r) => r.scene.id === id);
}

/** "3.2" — sequence number, then the scene's place inside that sequence. */
export function sceneLabel(p: StoryProject, act: number, index: number): string {
  const list = p.scenes[String(act)] ?? [];
  const scene = list[index];
  if (!scene) return '';
  const seq = scene.sequence ?? act + 1;
  let n = 0;
  for (let i = 0; i <= index; i++) if ((list[i].sequence ?? act + 1) === seq) n++;
  return `${seq}.${n}`;
}

export function sceneLabelById(p: StoryProject, id: string): string {
  const ref = findScene(p, id);
  return ref ? sceneLabel(p, ref.act, ref.index) : '';
}

export function beatText(p: StoryProject, act: number, index: number, beat: number): string {
  const pr = p.prose[`${act}-${index}-${beat}`];
  return pr?.final ?? '';
}

export function sceneText(p: StoryProject, act: number, index: number): string {
  const beats = p.beats[`${act}-${index}`] ?? [];
  return beats.map((_, b) => beatText(p, act, index, b)).filter(Boolean).join('\n\n');
}

export function beatsWritten(p: StoryProject, act: number, index: number): number {
  const beats = p.beats[`${act}-${index}`] ?? [];
  return beats.filter((_, b) => beatText(p, act, index, b)).length;
}

export function sceneHasProse(p: StoryProject, act: number, index: number): boolean {
  return beatsWritten(p, act, index) > 0;
}

export function countWords(text: string): number {
  const t = text.trim();
  return t ? t.split(/\s+/).length : 0;
}

export function wordCount(p: StoryProject): number {
  return Object.values(p.prose).reduce((n, pr) => n + countWords(pr.final ?? ''), 0);
}

/** The next scene with unwritten beats (or no beats), in story order. */
export function nextUnfinished(p: StoryProject): SceneRef | undefined {
  return orderedScenes(p).find((r) => {
    const count = (p.beats[`${r.act}-${r.index}`] ?? []).length;
    return count === 0 || beatsWritten(p, r.act, r.index) < count;
  });
}

/**
 * Whether Continue writing still has something to outline before it can
 * write: a Studio sequence with no scenes, or a Quick act with none. The
 * engine outlines that first, so "the whole story is written" needs this
 * false as well as no unfinished scene. Twin of `hasUnoutlined` in
 * story_project.shape.dart.
 */
export function hasUnoutlined(p: StoryProject): boolean {
  if (p.engine_mode === 'studio') {
    return (p.sequences ?? []).some((s) => {
      const act = p.acts.findIndex((a) => a.number === s.act);
      return sceneIndexesInSequence(p, act, s.number).length === 0;
    });
  }
  return p.acts.some((_, act) => (p.scenes[String(act)] ?? []).length === 0);
}

export const ROMAN = ['', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

/** "II" for act 2; the desktop's romanAct stops at V. */
export function romanAct(n: number): string {
  return ROMAN[Math.min(Math.max(n, 1), 5)];
}

/** Scenes with at least one finished beat: the count behind "24 of 51 scenes written". */
export function scenesWritten(p: StoryProject): number {
  return orderedScenes(p).filter((r) => beatsWritten(p, r.act, r.index) > 0).length;
}

/** Models write lens ids loosely ("kinetic action"); this is the stored form. */
export function normalizeLensId(raw: string): string {
  const id = raw.trim().toUpperCase().replace(/[^A-Z0-9]+/g, '_');
  return id === '' ? 'BASELINE_NEUTRAL' : id;
}

export function groupThousands(n: number): string {
  return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** Filled bars (1–4) for the tension meter, same mapping as the desktop. */
export function tensionBars(tension: number): number {
  if (tension <= -2) return 1;
  if (tension <= 0) return 2;
  if (tension === 1) return 3;
  return 4;
}

/** Cell colour class for a relationship by trust, same bands as the desktop. */
export function trustTone(trust: number): 'warm' | 'mid' | 'hot' {
  return trust >= 7 ? 'warm' : trust <= 3 ? 'hot' : 'mid';
}

export function timeAgo(iso: string): string {
  const ms = Date.now() - new Date(iso).getTime();
  const min = Math.floor(ms / 60000);
  if (min < 1) return 'just now';
  if (min < 60) return `${min} min ago`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h} h ago`;
  const d = Math.floor(h / 24);
  return `${d} day${d === 1 ? '' : 's'} ago`;
}
