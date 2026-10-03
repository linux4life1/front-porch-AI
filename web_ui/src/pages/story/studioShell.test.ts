// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { navCount } from './StudioShell';
import { studioStory } from './storyFixture';
import { headerSubtitle } from './useShelfState';

describe('sidebar counts', () => {
  it('shows scenes written of planned, the cast size and the continuity facts, only when there are some', () => {
    const p = studioStory({ continuity: [{ scene_id: 'a' }, { scene_id: 'b' }, { scene_id: 'b' }] });
    expect(navCount(p, 'structure')).toBe('1/3');
    expect(navCount(p, 'cast')).toBe('2');
    expect(navCount(p, 'lore')).toBe('3');
    expect(navCount(p, 'overview')).toBeNull();
    expect(navCount(p, 'log')).toBeNull();
    const bare = studioStory({ cast: [], scenes: {}, beats: {}, prose: {}, continuity: [] });
    expect(navCount(bare, 'structure')).toBeNull();
    expect(navCount(bare, 'cast')).toBeNull();
    expect(navCount(bare, 'lore')).toBeNull();
  });
});

describe('header subtitle', () => {
  const shelf = (status: string) => ({ status, fraction: 0.5, done: false, setup: false });

  it('gives the shelf line the unit it has no room for', () => {
    expect(headerSubtitle(shelf('Act II · 41,200 / 80,000'), false, studioStory())).toBe('Act II · 41,200 / 80,000 words');
    expect(headerSubtitle(shelf('Structure ready · nothing written'), false, studioStory())).toBe('Structure ready · nothing written');
    expect(headerSubtitle(shelf('Finished · 31,400 words'), false, studioStory())).toBe('Finished · 31,400 words');
  });

  it('says the bible is being built while a run is on and there are no acts yet', () => {
    const bare = studioStory({ acts: [] });
    expect(headerSubtitle(shelf('Bible ready · nothing written'), true, bare)).toBe('Building the bible…');
    expect(headerSubtitle(shelf('Act I · 10 / 80,000'), true, studioStory())).toBe('Act I · 10 / 80,000 words');
  });

  it('is blank until the shelf has answered', () => {
    expect(headerSubtitle(null, false, studioStory())).toBe('');
  });
});
