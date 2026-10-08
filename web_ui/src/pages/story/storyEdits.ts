// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Structural edits that keep the index-keyed maps honest: `beats` is keyed
// "act-scene" and `prose` "act-scene-beat", so inserting or removing a scene
// re-keys everything after it. Web twin of the desktop's StoryStructure
// (lib/services/story/story_structure.dart) and the scene half of
// StoryContinuity.forgetScene. Every function is pure: it returns the slices
// of the project it changed, ready to hand to `save`.

import type { BeatProse, StoryProject, StoryScene } from '../../storyTypes';

/** The project slices a structural edit may rewrite. */
export type StructurePatch = Pick<StoryProject, 'scenes' | 'beats' | 'prose' | 'continuity' | 'relationships'>;

const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value)) as T;

/** A fresh id for a scene (same shape as the desktop's newStoryId). */
export function newStoryId(prefix = 's'): string {
  return `${prefix}${Date.now().toString(36)}${Math.floor(Math.random() * (1 << 20)).toString(36)}`;
}

function slices(p: StoryProject): StructurePatch {
  return clone({
    scenes: p.scenes,
    beats: p.beats,
    prose: p.prose,
    continuity: p.continuity ?? [],
    relationships: p.relationships ?? [],
  });
}

/** Re-key every scene of [act] so the maps follow [order]: order[newIndex] = oldIndex, or -1 for a new, empty scene. */
function rekeyAct(next: StructurePatch, act: number, order: number[], oldLength: number): void {
  const lifted = Array.from({ length: oldLength }, (_, scene) => {
    const key = `${act}-${scene}`;
    const beats = next.beats[key];
    delete next.beats[key];
    const prose: Record<number, BeatProse> = {};
    const prefix = `${key}-`;
    for (const k of Object.keys(next.prose)) {
      if (!k.startsWith(prefix)) continue;
      const beat = k.slice(prefix.length);
      if (/^\d+$/.test(beat)) prose[Number(beat)] = next.prose[k];
      delete next.prose[k];
    }
    return { beats, prose };
  });
  order.forEach((from, scene) => {
    if (from < 0) return;
    const key = `${act}-${scene}`;
    const { beats, prose } = lifted[from];
    if (beats) next.beats[key] = beats;
    for (const [beat, value] of Object.entries(prose)) next.prose[`${key}-${beat}`] = value;
  });
}

function renumber(list: StoryScene[]): void {
  list.forEach((scene, i) => { scene.number = i + 1; });
}

/** Forget everything a scene established: its facts go, facts it retired come back, relationship moves it caused are undone. */
function forgetScene(next: StructurePatch, sceneId: string): void {
  if (!sceneId) return;
  const facts = (next.continuity ?? []).filter((f) => f.scene_id !== sceneId);
  for (const f of facts) if (f.retired_scene_id === sceneId) f.retired_scene_id = '';
  next.continuity = facts;
  for (const r of next.relationships ?? []) {
    const undone = r.history.filter((h) => h.scene_id === sceneId);
    if (undone.length === 0) continue;
    r.history = r.history.filter((h) => h.scene_id !== sceneId);
    r.feeling = r.history.length > 0 ? r.history[r.history.length - 1].to : undone[0].from;
  }
}

/** Insert [scene] at [index] of the act (clamped), shifting later scenes, their beats and prose. */
export function insertScene(p: StoryProject, act: number, index: number, scene: StoryScene): StructurePatch {
  const next = slices(p);
  const list = next.scenes[String(act)] ?? [];
  next.scenes[String(act)] = list;
  const at = Math.min(Math.max(index, 0), list.length);
  const oldLength = list.length;
  list.splice(at, 0, { ...scene, id: scene.id || newStoryId() });
  rekeyAct(next, act, list.map((_, i) => (i < at ? i : i === at ? -1 : i - 1)), oldLength);
  renumber(list);
  return next;
}

/** Remove the scene with its beats, prose, facts and relationship moves; later scenes renumber. */
export function removeScene(p: StoryProject, act: number, index: number): StructurePatch {
  const next = slices(p);
  const list = next.scenes[String(act)];
  if (!list || index < 0 || index >= list.length) return next;
  const oldLength = list.length;
  const [removed] = list.splice(index, 1);
  rekeyAct(next, act, list.map((_, i) => (i < index ? i : i + 1)), oldLength);
  forgetScene(next, removed.id ?? '');
  renumber(list);
  return next;
}

/** Throw a scene's prose away (for a rewrite) along with everything the archivist learned from it. */
export function clearSceneProse(p: StoryProject, act: number, scene: number): StructurePatch {
  const next = slices(p);
  const prefix = `${act}-${scene}-`;
  for (const k of Object.keys(next.prose)) if (k.startsWith(prefix)) delete next.prose[k];
  const target = next.scenes[String(act)]?.[scene];
  if (target) {
    target.summary = '';
    forgetScene(next, target.id ?? '');
  }
  return next;
}

/** A blank scene for "Insert scene after…": it joins the sequence of the scene before it. */
export function blankScene(title: string, description: string, sequence: number): StoryScene {
  return {
    number: 0,
    title,
    description,
    location: '',
    cast_names: [],
    valence: 0,
    id: newStoryId(),
    sequence,
  };
}
