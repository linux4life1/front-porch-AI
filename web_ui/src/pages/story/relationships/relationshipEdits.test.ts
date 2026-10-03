// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryRelationship } from '../../../storyTypes';
import { studioStory } from '../storyFixture';
import {
  feelingTone, findPair, recordedAfter, relationshipNames, removePair, shiftRelationship,
} from './relationshipEdits';

const rel = (patch: Partial<StoryRelationship> = {}): StoryRelationship => ({
  from: 'Mara', to: 'Joss', feeling: 'Wary', note: 'owes him', subtext: 'she lied', trust: 4, history: [], ...patch,
});

describe('shiftRelationship (the desktop StoryContinuity.shift)', () => {
  it('creates a pair that is new, with a first history step from a dash', () => {
    const out = shiftRelationship([], { from: 'Mara', to: 'Joss', feeling: ' Drawn to ', note: 'trusts', subtext: 'misreads', trust: 7, reason: 'Edited by hand.' });
    expect(out).toEqual([{
      from: 'Mara', to: 'Joss', feeling: 'Drawn to', note: 'trusts', subtext: 'misreads', trust: 7,
      history: [{ scene_id: '', from: '—', to: 'Drawn to', reason: 'Edited by hand.' }],
    }]);
  });

  it('adds a history step only when the feeling really changed (case and padding do not count)', () => {
    const before = [rel()];
    const same = shiftRelationship(before, { from: 'Mara', to: 'Joss', feeling: ' wary ', trust: 9, reason: 'Edited by hand.' });
    expect(same[0].history).toEqual([]);
    expect(same[0].trust).toBe(9);
    const moved = shiftRelationship(before, { from: 'Mara', to: 'Joss', feeling: 'Resentful', reason: 'Edited by hand.' });
    expect(moved[0]).toMatchObject({ feeling: 'Resentful', history: [{ scene_id: '', from: 'Wary', to: 'Resentful', reason: 'Edited by hand.' }] });
  });

  it('never clears a note or an unspoken line by saving it empty', () => {
    const out = shiftRelationship([rel()], { from: 'Mara', to: 'Joss', feeling: 'Wary', note: '  ', subtext: '' });
    expect(out[0]).toMatchObject({ note: 'owes him', subtext: 'she lied' });
  });

  it('clamps trust to 0 to 10 and leaves it alone when none is given', () => {
    expect(shiftRelationship([rel()], { from: 'Mara', to: 'Joss', feeling: 'Wary', trust: 14 })[0].trust).toBe(10);
    expect(shiftRelationship([rel()], { from: 'Mara', to: 'Joss', feeling: 'Wary', trust: -3 })[0].trust).toBe(0);
    expect(shiftRelationship([rel()], { from: 'Mara', to: 'Joss', feeling: 'Wary' })[0].trust).toBe(4);
  });

  it('ignores a pair with no feeling, or a person about themselves, and does not touch the list it was given', () => {
    const before = [rel()];
    expect(shiftRelationship(before, { from: 'Mara', to: 'Joss', feeling: '  ' })).toBe(before);
    expect(shiftRelationship(before, { from: 'Mara', to: 'Mara', feeling: 'Proud' })).toBe(before);
    shiftRelationship(before, { from: 'Mara', to: 'Joss', feeling: 'Resentful' });
    expect(before[0].history).toEqual([]);
    expect(before[0].feeling).toBe('Wary');
  });

  it('keeps A to B and B to A as separate rows', () => {
    const out = shiftRelationship([rel()], { from: 'Joss', to: 'Mara', feeling: 'Protective' });
    expect(out.map((r) => `${r.from}>${r.to}:${r.feeling}`)).toEqual(['Mara>Joss:Wary', 'Joss>Mara:Protective']);
  });
});

describe('Relationships screen reads', () => {
  it('removes just the pair named', () => {
    const list = [rel(), rel({ from: 'Joss', to: 'Mara' })];
    expect(removePair(list, 'Mara', 'Joss').map((r) => r.from)).toEqual(['Joss']);
    expect(findPair(list, 'Joss', 'Mara')?.from).toBe('Joss');
    expect(findPair(list, 'Mara', 'Teodor')).toBeUndefined();
  });

  it('colours a feeling by trust: warm teal, low red, the rest honey', () => {
    expect(feelingTone(rel({ trust: 7 }))).toBe('teal');
    expect(feelingTone(rel({ trust: 3 }))).toBe('bad');
    expect(feelingTone(rel({ trust: 5 }))).toBe('honey');
  });

  it('draws the grid for the cast, once each', () => {
    expect(relationshipNames(studioStory())).toEqual(['Mara', 'Joss']);
    expect(relationshipNames(studioStory({ cast: [{ name: 'A' }, { name: 'A' }, { name: 'B' }] }))).toEqual(['A', 'B']);
  });

  it('says "After scene 1.2" from the last move made in a scene, ignoring moves made by hand', () => {
    const moves = [
      rel({ history: [{ scene_id: 'a', from: '—', to: 'Wary', reason: '' }, { scene_id: '', from: 'Wary', to: 'Fond', reason: 'Edited by hand.' }] }),
      rel({ from: 'Joss', to: 'Mara', history: [{ scene_id: 'b', from: '—', to: 'Protective', reason: '' }] }),
    ];
    expect(recordedAfter(studioStory({ relationships: moves }))).toBe('After scene 1.2');
    expect(recordedAfter(studioStory({ relationships: [rel({ history: [{ scene_id: '', from: '—', to: 'Fond', reason: '' }] })] }))).toBe('Nothing recorded yet');
    expect(recordedAfter(studioStory())).toBe('Nothing recorded yet');
  });
});
