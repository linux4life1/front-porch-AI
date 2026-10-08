// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryProject } from '../../storyTypes';
import { blankScene, clearSceneProse, insertScene, removeScene } from './storyEdits';

function project(): StoryProject {
  return {
    acts: [{ number: 1, title: 'A' }, { number: 2, title: 'B' }],
    scenes: {
      '0': [
        { number: 1, id: 'a', title: 'one', sequence: 1, summary: 'one happened' },
        { number: 2, id: 'b', title: 'two', sequence: 1, summary: 'two happened' },
        { number: 3, id: 'c', title: 'three', sequence: 1 },
      ],
      '1': [{ number: 1, id: 'd', title: 'four', sequence: 2 }],
    },
    beats: {
      '0-0': [{ number: 1 }],
      '0-1': [{ number: 1 }, { number: 2 }],
      '0-2': [{ number: 1 }],
      '1-0': [{ number: 1 }],
    },
    prose: {
      '0-0-0': { final: 'alpha' },
      '0-1-0': { final: 'bravo' },
      '0-1-1': { final: 'charlie' },
      '0-2-0': { final: 'delta' },
      '1-0-0': { final: 'echo' },
    },
    continuity: [
      { category: 'item', key: 'lamp', value: 'lit', entity: 'Mara', scene_id: 'b' },
      { category: 'item', key: 'coat', value: 'torn', entity: 'Joss', scene_id: 'a', retired_scene_id: 'b' },
    ],
    relationships: [{
      from: 'Mara', to: 'Joss', feeling: 'wary', note: '', subtext: '', trust: 4,
      history: [
        { scene_id: 'a', from: 'neutral', to: 'curious', reason: '' },
        { scene_id: 'b', from: 'curious', to: 'wary', reason: '' },
      ],
    }],
  } as unknown as StoryProject;
}

describe('insertScene', () => {
  it('shifts the later scenes together with their beats and prose, and renumbers', () => {
    const p = project();
    const next = insertScene(p, 0, 1, blankScene('new', 'between', 1));
    expect(next.scenes['0'].map((s) => s.title)).toEqual(['one', 'new', 'two', 'three']);
    expect(next.scenes['0'].map((s) => s.number)).toEqual([1, 2, 3, 4]);
    expect(next.scenes['0'][1].id).toBeTruthy();
    expect(next.beats['0-0']).toHaveLength(1);
    expect(next.beats['0-1']).toBeUndefined();
    expect(next.beats['0-2']).toHaveLength(2);
    expect(next.beats['0-3']).toHaveLength(1);
    expect(next.prose['0-0-0'].final).toBe('alpha');
    expect(next.prose['0-1-0']).toBeUndefined();
    expect(next.prose['0-2-0'].final).toBe('bravo');
    expect(next.prose['0-2-1'].final).toBe('charlie');
    expect(next.prose['0-3-0'].final).toBe('delta');
    expect(next.prose['1-0-0'].final).toBe('echo');
    // The project the caller holds is untouched until the patch is saved.
    expect(p.scenes['0']).toHaveLength(3);
  });
});

describe('removeScene', () => {
  it('drops the scene, its beats, prose and facts, and closes the gap', () => {
    const next = removeScene(project(), 0, 1);
    expect(next.scenes['0'].map((s) => s.title)).toEqual(['one', 'three']);
    expect(next.scenes['0'].map((s) => s.number)).toEqual([1, 2]);
    expect(next.beats['0-1']).toHaveLength(1);
    expect(next.beats['0-2']).toBeUndefined();
    expect(next.prose['0-1-0'].final).toBe('delta');
    expect(Object.keys(next.prose).sort()).toEqual(['0-0-0', '0-1-0', '1-0-0']);
    expect(next.continuity.map((f) => f.key)).toEqual(['coat']);
    expect(next.continuity[0].retired_scene_id).toBe('');
    expect(next.relationships![0].history.map((h) => h.scene_id)).toEqual(['a']);
    expect(next.relationships![0].feeling).toBe('curious');
  });

  it('leaves the other acts alone and ignores an index that is not there', () => {
    const p = project();
    const next = removeScene(p, 0, 9);
    expect(next.scenes['0']).toHaveLength(3);
    expect(next.prose['1-0-0'].final).toBe('echo');
  });
});

describe('clearSceneProse', () => {
  it('clears one scene for a rewrite: prose, summary and what it recorded; beats stay', () => {
    const next = clearSceneProse(project(), 0, 1);
    expect(next.prose['0-1-0']).toBeUndefined();
    expect(next.prose['0-1-1']).toBeUndefined();
    expect(next.prose['0-0-0'].final).toBe('alpha');
    expect(next.beats['0-1']).toHaveLength(2);
    expect(next.scenes['0'][1].summary).toBe('');
    expect(next.scenes['0'][0].summary).toBe('one happened');
    expect(next.continuity.map((f) => f.key)).toEqual(['coat']);
  });

  it('does not match a prose key of another scene that merely starts with the same digits', () => {
    const p = project();
    p.prose['0-10-0'] = { final: 'far away' };
    const next = clearSceneProse(p, 0, 1);
    expect(next.prose['0-10-0'].final).toBe('far away');
  });
});
