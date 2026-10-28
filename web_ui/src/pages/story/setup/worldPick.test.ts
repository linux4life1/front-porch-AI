// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The pure rules of a story's world on the web (docs/design/stories-in-worlds.md
// §5): the lines the Overview and Lore header read, the "new place" rule, and
// the lore tags. Twins of the desktop's story_world_lookup.dart tests.

import { describe, expect, it } from 'vitest';
import type { StoryProject, StoryScene } from '../../../storyTypes';
import { isWorldLore, pickFromProject, pickFromSummary, placeRefs, sceneIsNewPlace, worldLine, type WorldSummary } from './worldPick';

const summary: WorldSummary = {
  ok: true, placeId: 'conservatory', worldName: 'Greenhollow Estate', startName: 'The Conservatory', atLarge: false,
  placeCount: 3, factCount: 11, constantCount: 0, searchableCount: 11, climate: 'Mediterranean',
  detail: 'starts at The Conservatory · 3 places · 11 facts · Mediterranean',
  briefLine: 'World brief: 3 places · 0 always-on facts · 11 searchable facts',
  setInLine: 'Set in Greenhollow Estate · starts at The Conservatory',
  places: [{ id: 'conservatory', name: 'The Conservatory' }, { id: 'kitchens', name: 'The Kitchens' }],
};
const withWorld = { world_id: 'conservatory', world_name: 'Greenhollow Estate' } as unknown as StoryProject;
const noWorld = {} as unknown as StoryProject;

describe('a story\'s world on the web', () => {
  it('worldLine: the relay\'s line, the stored name before it answers, the gone note', () => {
    expect(worldLine(withWorld, summary, false)).toBe('Set in Greenhollow Estate · starts at The Conservatory');
    expect(worldLine(withWorld, null, false)).toBe('Set in Greenhollow Estate');
    expect(worldLine(withWorld, null, true)).toBe('Set in Greenhollow Estate (no longer in the library)');
    expect(worldLine(noWorld, summary, false)).toBeNull();
  });

  it('a scene with a location but no place is a new place, only in a story with a world', () => {
    const gate = { location: 'the Gatehouse — dusk' } as StoryScene;
    const kitchen = { location: 'x', place_id: 'kitchens' } as StoryScene;
    expect(sceneIsNewPlace(withWorld, gate)).toBe(true);
    expect(sceneIsNewPlace(withWorld, kitchen)).toBe(false);
    expect(sceneIsNewPlace(withWorld, { location: '' } as StoryScene)).toBe(false);
    expect(sceneIsNewPlace(noWorld, gate)).toBe(false);
  });

  it('lore tags: copied entries carry world: and place:', () => {
    const copied = { topic: 'The bell', detail: 'x', related_to: ['world:g', 'place:kitchens'], valid_from_act: 1, valid_from_scene: 1 };
    const grown = { topic: 'The key', detail: 'x', related_to: [], valid_from_act: 1, valid_from_scene: 1 };
    expect(isWorldLore(copied)).toBe(true);
    expect(placeRefs(copied)).toEqual(['kitchens']);
    expect(isWorldLore(grown)).toBe(false);
    expect(placeRefs(grown)).toEqual([]);
  });

  it('picks: from the relay with its lines, from a saved project with the name alone', () => {
    expect(pickFromSummary(summary, true)).toEqual({
      placeId: 'conservatory', worldName: 'Greenhollow Estate', detail: summary.detail, briefLine: summary.briefLine, fromChat: true,
    });
    expect(pickFromProject(withWorld)).toEqual({ placeId: 'conservatory', worldName: 'Greenhollow Estate', detail: '', briefLine: '', fromChat: false });
    expect(pickFromProject(noWorld)).toBeNull();
  });
});
