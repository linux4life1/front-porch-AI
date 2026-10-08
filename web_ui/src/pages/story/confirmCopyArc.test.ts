// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryProject } from '../../storyTypes';
import { rewriteArcCopy } from './confirmCopy';

const project = (over: Partial<StoryProject>) =>
  ({ acts: [], scenes: {}, beats: {}, prose: {}, ...over }) as unknown as StoryProject;

describe('rewriteArcCopy', () => {
  it('says what is rewritten and what is kept', () => {
    const copy = rewriteArcCopy(project({}));
    expect(copy.title).toBe('Rewrite the arc?');
    expect(copy.body).toContain('inciting incident, themes, twists and threads');
    expect(copy.body).toContain('The world, cast and interviews stay as they are.');
    expect(copy.body).not.toContain('may no longer match');
    expect(copy.destructive).toBeUndefined();
  });

  it('warns that planned acts may no longer match', () => {
    const copy = rewriteArcCopy(project({ acts: [{ number: 1 }] as unknown as StoryProject['acts'] }));
    expect(copy.body).toContain('Your acts stay but may no longer match.');
  });
});
