// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { ContinuityFact, StoryLoreEntry } from '../../../storyTypes';
import { studioStory } from '../storyFixture';
import { factRows, factWhen, loreFileCount, loreFrom, loreSubtitle, soFarBlocks } from './loreShape';

const fact = (patch: Partial<ContinuityFact> = {}): ContinuityFact => ({
  category: 'Object', key: 'The ledger', value: 'soot on the cover', entity: 'Mara', scene_id: '', ...patch,
});

const lore = (patch: Partial<StoryLoreEntry> = {}): StoryLoreEntry => ({
  topic: 'The salt road', detail: 'A caravan route.', related_to: [], valid_from_act: 1, valid_from_scene: 1, ...patch,
});

describe('Lore & continuity words (sketch T)', () => {
  it('counts facts, lore entries and the distinct files they came from', () => {
    const p = studioStory({
      continuity: [fact(), fact({ key: 'b' })],
      lore: [lore({ related_to: ['file:world.md', 'Mara'] }), lore({ related_to: ['file:world.md'] }), lore({ related_to: ['file:cities.txt'] })],
    });
    expect(loreFileCount(p.lore)).toBe(2);
    expect(loreSubtitle(p)).toBe('2 facts · 3 lore entries · 2 files');
  });

  it('uses the singular for one of each and zero files for none', () => {
    expect(loreSubtitle(studioStory({ continuity: [fact()], lore: [lore()] }))).toBe('1 fact · 1 lore entry · 0 files');
    expect(loreSubtitle(studioStory({ lore: [lore({ related_to: ['file:a.md'] })] }))).toBe('0 facts · 1 lore entry · 1 file');
  });

  it('lists live facts first and retired ones last, each keeping its place in the list', () => {
    const rows = factRows([fact({ key: 'old', retired_scene_id: 'b' }), fact({ key: 'live 1' }), fact({ key: 'live 2' })]);
    expect(rows.map((r) => [r.fact.key, r.index])).toEqual([['live 1', 1], ['live 2', 2], ['old', 0]]);
  });

  it('says where a fact holds: from a scene, always, or from one scene to another', () => {
    const p = studioStory();
    expect(factWhen(p, fact({ scene_id: 'b' }))).toBe('from 1.2');
    expect(factWhen(p, fact())).toBe('always');
    expect(factWhen(p, fact({ scene_id: 'a', retired_scene_id: 'c' }))).toBe('1.1 → 1.3');
    expect(factWhen(p, fact({ scene_id: 'gone' }))).toBe('always');
  });

  it('shows "from act, scene" only for lore that starts after the beginning', () => {
    expect(loreFrom(lore())).toBe('');
    expect(loreFrom(lore({ valid_from_act: 2, valid_from_scene: 3 }))).toBe('from act 2, scene 3');
    expect(loreFrom(lore({ valid_from_scene: 2 }))).toBe('from act 1, scene 2');
  });

  it('makes a Story so far block per sequence with something to say, summary first, then its scene lines', () => {
    const p = studioStory({
      sequences: [
        { number: 1, act: 1, title: 'The Ledger', summary: 'Mara hides the debt.' },
        { number: 2, act: 1, title: 'Empty', summary: '' },
      ],
    });
    p.scenes['0'][0].summary = 'She counts forty silver.';
    p.scenes['0'][1].summary = '';
    expect(soFarBlocks(p)).toEqual([{
      key: '1-1',
      heading: 'Sequence 1 · The Ledger',
      summary: 'Mara hides the debt.',
      lines: ['1.1 The ledger: She counts forty silver.'],
    }]);
  });

  it('has nothing to show before any summary exists', () => {
    expect(soFarBlocks(studioStory())).toEqual([]);
  });
});
