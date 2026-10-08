// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it, vi } from 'vitest';
import type { StoryProject } from '../../storyTypes';
import { orderedScenes } from './storyShape';
import { bookTocEntries, scrollTocEntries } from './tocEntries';

const project = {
  acts: [{ number: 1, title: 'Arrival' }, { number: 2, title: 'Flight' }],
  scenes: {
    '0': [{ number: 1, title: 'The yard' }, { number: 2, title: '' }],
    '1': [{ number: 1, title: 'The road' }],
  },
  beats: { '0-0': [{}], '0-1': [{}], '1-0': [{}] },
  prose: { '0-0-0': { final: 'Smoke.' }, '0-1-0': { final: 'Ash.' } },
} as unknown as StoryProject;

describe('contents entries', () => {
  it('Book: lists the title page, acts and written scenes with their pages', () => {
    const goTo = vi.fn();
    const anchors = { title: 0, 'act:0': 1, 'scene:0-0': 2, 'scene:0-1': 3, 'act:1': 4 };
    const entries = bookTocEntries(project, anchors, 3, goTo);
    expect(entries.map((e) => [e.label, e.num])).toEqual([
      ['Title Page', 1], ['Act 1: Arrival', 2], ['The yard', 3], ['Scene 2', 4], ['Act 2: Flight', 5],
    ]);
    expect(entries.filter((e) => e.current).map((e) => e.label)).toEqual(['Scene 2']);
    entries[2].onPick?.();
    expect(goTo).toHaveBeenCalledWith(2);
  });

  it('Scroll: chapters are the scenes with prose; an act without any cannot be tapped', () => {
    const goToChapter = vi.fn();
    const toTop = vi.fn();
    const chapters = orderedScenes(project).filter((r) => r.act === 0);
    const entries = scrollTocEntries(project, chapters, 1, goToChapter, toTop);
    expect(entries.map((e) => [e.label, e.num])).toEqual([
      ['Title Page', ''], ['Act 1: Arrival', ''], ['The yard', 1], ['Scene 2', 2], ['Act 2: Flight', ''],
    ]);
    expect(entries.filter((e) => e.current).map((e) => e.label)).toEqual(['Scene 2']);
    expect(entries[4].onPick).toBeNull();
    entries[1].onPick?.();
    expect(goToChapter).toHaveBeenCalledWith(0);
    entries[0].onPick?.();
    expect(toTop).toHaveBeenCalled();
  });
});
