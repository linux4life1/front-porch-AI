// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A story's world on the web (docs/design/stories-in-worlds.md §5). Every
// word the screens show comes from the relay's `GET /api/stories/world`
// summary, so the PWA and the desktop read the same lines; this module only
// holds the shapes, the small pure rules, and the hook that asks.

import { useEffect, useState } from 'react';
import { api } from '../../../api/client';
import type { StoryLoreEntry, StoryProject, StoryScene } from '../../../storyTypes';

/** `GET /api/stories/world?place=…|session=…`. `ok: false` = no such place. */
export interface WorldSummary {
  ok: boolean;
  placeId: string;
  worldName: string;
  startName: string;
  atLarge: boolean;
  placeCount: number;
  factCount: number;
  constantCount: number;
  searchableCount: number;
  climate: string | null;
  /** "starts at The Conservatory · 3 places · 11 facts · Mediterranean" */
  detail: string;
  /** "World brief: 3 places · 0 always-on facts · 11 searchable facts" */
  briefLine: string;
  /** "Set in Greenhollow Estate · starts at The Conservatory" */
  setInLine: string;
  places: { id: string; name: string }[];
}

/** What New Story keeps once a world is picked. Twin of StoryWorldPick. */
export interface WorldPick {
  /** The place the story starts at. */
  placeId: string;
  worldName: string;
  detail: string;
  briefLine: string;
  /** Filled from the chat the story starts from, not picked by hand. */
  fromChat: boolean;
}

export function loadWorldSummary(by: { place?: string; session?: string }): Promise<WorldSummary> {
  const q = by.place ? `place=${encodeURIComponent(by.place)}` : `session=${encodeURIComponent(by.session ?? '')}`;
  return api.get<WorldSummary>(`/api/stories/world?${q}`);
}

export function pickFromSummary(s: WorldSummary, fromChat = false): WorldPick {
  return { placeId: s.placeId, worldName: s.worldName, detail: s.detail, briefLine: s.briefLine, fromChat };
}

/** The pick a saved story reopens with before the relay has answered: the name it stored, no detail yet. */
export function pickFromProject(p: StoryProject): WorldPick | null {
  if (!p.world_id) return null;
  return { placeId: p.world_id, worldName: p.world_name ?? '', detail: '', briefLine: '', fromChat: false };
}

/** The desktop's "no longer in the library" wording for a pick the relay does not know. */
export const WORLD_GONE = 'no longer in the library';

/** "Set in Greenhollow Estate · starts at The Conservatory", the stored name alone before the relay answers, or the gone note. */
export function worldLine(p: StoryProject, s: WorldSummary | null, gone: boolean): string | null {
  if (!p.world_id) return null;
  const name = p.world_name?.trim() || 'a world';
  if (gone) return `Set in ${name} (${WORLD_GONE})`;
  return s?.ok ? s.setInLine : `Set in ${name}`;
}

/** A scene the planner set somewhere the world does not have. Twin of storySceneIsNewPlace. */
export function sceneIsNewPlace(p: StoryProject, sc: StoryScene): boolean {
  return !!p.world_id && !sc.place_id && !!sc.location?.trim();
}

export const WORLD_PREFIX = 'world:';
export const PLACE_PREFIX = 'place:';

/** Entries copied from the story's world carry `world:<id>` in `related_to`. Twin of isWorldLore. */
export const isWorldLore = (l: StoryLoreEntry): boolean => (l.related_to ?? []).some((r) => r.startsWith(WORLD_PREFIX));

/** The ids of the places that own a copied entry. */
export const placeRefs = (l: StoryLoreEntry): string[] =>
  (l.related_to ?? []).filter((r) => r.startsWith(PLACE_PREFIX)).map((r) => r.slice(PLACE_PREFIX.length));

/** The relay's summary for the place a story starts at. `gone` once the relay said there is no such place. */
export function useStoryWorld(placeId: string | null | undefined): { summary: WorldSummary | null; gone: boolean } {
  const [summary, setSummary] = useState<WorldSummary | null>(null);
  const [gone, setGone] = useState(false);
  useEffect(() => {
    let live = true;
    setSummary(null);
    setGone(false);
    if (!placeId) return;
    loadWorldSummary({ place: placeId })
      .then((s) => {
        if (!live) return;
        if (s.ok) setSummary(s);
        else setGone(true);
      })
      .catch(() => { /* the stored name is shown instead */ });
    return () => { live = false; };
  }, [placeId]);
  return { summary, gone };
}
