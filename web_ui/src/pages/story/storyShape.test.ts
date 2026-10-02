// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryProject } from '../../storyTypes';
import {
  beatsWritten, nextUnfinished, sceneLabel, sceneLabelById, sequencesInAct,
  tensionBars, trustTone, wordCount,
} from './storyShape';

const project = {
  acts: [{ number: 1, title: 'A' }, { number: 2, title: 'B' }],
  sequences: [
    { number: 1, act: 1 }, { number: 2, act: 1 }, { number: 3, act: 2 },
  ],
  scenes: {
    '0': [
      { id: 'a', title: 'one', sequence: 1 },
      { id: 'b', title: 'two', sequence: 1 },
      { id: 'c', title: 'three', sequence: 2 },
    ],
    '1': [{ id: 'd', title: 'four', sequence: 3 }],
  },
  beats: { '0-0': [{ number: 1 }, { number: 2 }], '0-1': [{ number: 1 }] },
  prose: { '0-0-0': { final: 'one two three' }, '0-0-1': { final: 'four' } },
} as unknown as StoryProject;

describe('storyShape', () => {
  it('labels scenes by sequence and position, like the desktop', () => {
    expect(sceneLabel(project, 0, 1)).toBe('1.2');
    expect(sceneLabel(project, 0, 2)).toBe('2.1');
    expect(sceneLabel(project, 1, 0)).toBe('3.1');
    expect(sceneLabelById(project, 'c')).toBe('2.1');
    expect(sequencesInAct(project, 0).map((s) => s.number)).toEqual([1, 2]);
  });

  it('counts what is written and finds the next unfinished scene', () => {
    expect(beatsWritten(project, 0, 0)).toBe(2);
    expect(wordCount(project)).toBe(4);
    expect(nextUnfinished(project)?.scene.id).toBe('b');
  });

  it('maps tension and trust the same way as the desktop', () => {
    expect([-2, -1, 0, 1, 2].map(tensionBars)).toEqual([1, 2, 2, 3, 4]);
    expect([8, 5, 2].map(trustTone)).toEqual(['warm', 'mid', 'hot']);
  });
});
