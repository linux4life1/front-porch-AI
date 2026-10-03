// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { SceneRef } from '../storyShape';
import {
  parsePhraseList, phrasesSummary, projectLenses, rewriteWithNoteLabel, sceneFileName, sceneMarkdown,
  sceneNeighbours, sceneSubtitle, withCustomLens,
} from './writeShape';

const refs = [
  { act: 0, index: 0 }, { act: 0, index: 1 }, { act: 1, index: 0 },
] as SceneRef[];

describe('write shape', () => {
  it('walks scenes in story order and stops at the ends', () => {
    expect(sceneNeighbours(refs, 0, 0)).toEqual({ prev: undefined, next: refs[1] });
    expect(sceneNeighbours(refs, 0, 1)).toEqual({ prev: refs[0], next: refs[2] });
    expect(sceneNeighbours(refs, 1, 0)).toEqual({ prev: refs[1], next: undefined });
    expect(sceneNeighbours(refs, 5, 5)).toEqual({ prev: undefined, next: undefined });
  });

  it('words the header subtitle like the desktop', () => {
    expect(sceneSubtitle({ beats: 0, written: 0 })).toBe('No beats yet');
    expect(sceneSubtitle({ beats: 14, written: 5, lens: 'Kinetic action', location: 'Caravan yard' }))
      .toBe('Beat 6 of 14 · Kinetic action · Caravan yard');
    expect(sceneSubtitle({ beats: 3, written: 3, location: '' })).toBe('Beat 3 of 3');
  });

  it('names the last written beat on the bottom bar', () => {
    expect(rewriteWithNoteLabel(0, 3)).toBe('Rewrite beat 1 with a note…');
    expect(rewriteWithNoteLabel(2, 3)).toBe('Rewrite beat 2 with a note…');
    expect(rewriteWithNoteLabel(9, 3)).toBe('Rewrite beat 3 with a note…');
    expect(rewriteWithNoteLabel(0, 0)).toBe('Rewrite beat 1 with a note…');
  });

  it("says which phrases the engine noticed and which are the writer's own", () => {
    expect(phrasesSummary([], [])).toBe('');
    expect(phrasesSummary(['a'], ['b', 'c']))
      .toBe('2 of these were noticed by the engine in the last chapter; the rest are yours and stay for the whole story');
    expect(phrasesSummary([], ['b'])).toBe('1 of these was noticed by the engine in the last chapter');
    expect(phrasesSummary(['a'], [])).toBe('These are yours and stay for the whole story');
  });

  it("lists built-in lenses first and the story's own after, an own lens replacing a built-in of the same id", () => {
    const builtIn = [
      { id: 'BASELINE_NEUTRAL', name: 'Balanced', context: 'default', glyph: '◐' },
      { id: 'KINETIC_ACTION', name: 'Kinetic action', context: 'chases', glyph: '⚡' },
    ];
    const own = { id: 'KINETIC_ACTION', name: 'My action', context: 'mine', prompt: 'short' };
    expect(projectLenses(builtIn, [own]).map((l) => [l.id, l.name, l.glyph])).toEqual([
      ['BASELINE_NEUTRAL', 'Balanced', '◐'],
      ['KINETIC_ACTION', 'My action', '✎'],
    ]);
  });

  it('adds a lens under its normalised name and replaces one of the same id', () => {
    const first = withCustomLens([], { name: 'Slow dusk', context: 'quiet', prompt: 'long sentences' });
    expect(first.id).toBe('SLOW_DUSK');
    expect(first.lenses).toEqual([{ id: 'SLOW_DUSK', name: 'Slow dusk', context: 'quiet', prompt: 'long sentences' }]);
    const again = withCustomLens(first.lenses, { name: 'slow dusk', context: 'calm', prompt: 'x' });
    expect(again.lenses).toHaveLength(1);
    expect(again.lenses[0].context).toBe('calm');
  });

  it('reads a phrase list one per line', () => {
    expect(parsePhraseList(' the weight of it \n\n jaw tightened\n')).toEqual(['the weight of it', 'jaw tightened']);
  });

  it('exports a scene as markdown with a title heading', () => {
    expect(sceneMarkdown('The wagon fire', 'Smoke.')).toBe('# The wagon fire\n\nSmoke.');
    expect(sceneFileName('3.3', 'The wagon fire')).toBe('3.3_The_wagon_fire.md');
  });
});
