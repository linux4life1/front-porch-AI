// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import {
  autopilotCopy, deleteSceneCopy, deleteStoryCopy, regenerateBibleCopy, rewriteSceneCopy,
} from './confirmCopy';
import { studioStory } from './storyFixture';

describe('confirm copy (sketch V)', () => {
  it('Autopilot writes what is left and promises not to touch the rest', () => {
    // 1.1 is written; two scenes are left.
    expect(autopilotCopy(studioStory())).toEqual({
      title: 'Write the whole story?',
      body: "Autopilot writes the 2 scenes that are left, one after another, with reviews on. It will not touch the 1 already written or the bible. You can stop at any time and keep what's done.",
      confirmLabel: 'Start',
    });
  });

  it('Autopilot with nothing planned builds the structure too, and drops "reviews on" when they are off', () => {
    const none = studioStory({ scenes: {}, beats: {}, prose: {}, review_enabled: false });
    expect(autopilotCopy(none).body).toBe(
      "Autopilot builds the acts, outlines every sequence and writes every scene, one after another. You can stop at any time and keep what's done.",
    );
  });

  it('Autopilot with one scene left says "is", not "are", and skips "0 already written"', () => {
    const p = studioStory({ scenes: { '0': [{ number: 1, id: 'a', title: 'One', sequence: 1 }] }, beats: {}, prose: {} });
    expect(autopilotCopy(p).body).toBe(
      "Autopilot writes the 1 scene that is left, one after another, with reviews on. It will not touch the bible. You can stop at any time and keep what's done.",
    );
  });

  it('Regenerate the bible says how many written scenes stay', () => {
    expect(regenerateBibleCopy(studioStory())).toEqual({
      title: 'Regenerate the bible?',
      body: 'This rewrites the cast, themes, threads and lore from your idea. Your 1 written scene stays but may no longer match. Interviews and portraits are kept.',
      confirmLabel: 'Regenerate',
      destructive: true,
    });
    const none = studioStory({ prose: {} });
    expect(regenerateBibleCopy(none).body).toBe('This rewrites the cast, themes, threads and lore from your idea. Interviews and portraits are kept.');
  });

  it('Delete story names the title and the words that go with it', () => {
    const p = studioStory();
    expect(deleteStoryCopy(p, 41200)).toEqual({
      title: 'Delete The Salt Road?',
      body: '41,200 words, its bible and its run log will be removed. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    });
    expect(deleteStoryCopy(p, 0).body).toBe('Its setup and bible will be removed. This cannot be undone.');
  });

  it('Rewrite names the scene and its words, and counts the facts it retires', () => {
    const p = studioStory({
      continuity: [
        { category: 'item', key: 'a', value: '', entity: '', scene_id: 'a' },
        { category: 'item', key: 'b', value: '', entity: '', scene_id: 'a' },
        { category: 'item', key: 'c', value: '', entity: '', scene_id: 'b' },
      ],
    });
    expect(rewriteSceneCopy(p, 0, 0)).toEqual({
      title: 'Rewrite 1.1 · The ledger?',
      body: 'Its 5 words will be replaced. The beats stay. 2 continuity facts recorded from this scene are retired first.',
      confirmLabel: 'Rewrite',
      destructive: true,
    });
  });

  it('Delete scene says what goes with it: prose when there is some, only beats when there is none', () => {
    const p = studioStory();
    expect(deleteSceneCopy(p, 0, 0).body).toBe('Its prose, beats and the continuity facts it recorded are removed. Later scenes renumber.');
    expect(deleteSceneCopy(p, 0, 1)).toEqual({
      title: 'Delete 1.2 · The knock?',
      body: 'Its beats are removed. Later scenes renumber.',
      confirmLabel: 'Delete',
      destructive: true,
    });
  });
});
