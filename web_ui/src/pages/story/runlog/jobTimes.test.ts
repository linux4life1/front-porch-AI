// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryRunEntry } from '../../../storyTypes';
import { jobTimeLine, jobTimes, slowChecksNote } from './runLogShape';

const e = (role: string, seconds: number, model?: string): StoryRunEntry => ({
  at: '2026-10-03T15:00:00.000', stage: 'x', role, backend: 'Remote API', model, attempt: 1,
  verdict: '', note: '', millis: seconds * 1000, tokens: 0, prompt: '', response: '',
});

describe('time by job', () => {
  it('totals per job in planning, prose, review order', () => {
    const jobs = jobTimes([e('review', 80, 'slow-thinker'), e('prose', 6, 'quick'), e('review', 100, 'slow-thinker'), e('planning', 120)]);
    expect(jobs.map((j) => j.role)).toEqual(['planning', 'prose', 'review']);
    expect(jobTimeLine(jobs[2])).toBe('Review · 2 calls · 3 min · 90s each · slow-thinker');
    expect(jobTimeLine(jobs[1])).toBe('Prose · 1 call · 6s · 6s each · quick');
    expect(jobTimeLine(jobs[0])).toBe('Planning · 1 call · 2 min · 120s each');
  });

  it('calls out slow checks once there is enough to judge', () => {
    const slow = [0, 1, 2].flatMap(() => [e('prose', 6), e('review', 82)]);
    expect(slowChecksNote(slow)).toContain('Checks average 82s each; writing averages 6s.');
    expect(slowChecksNote(slow.slice(0, 4))).toBeNull();
    expect(slowChecksNote([0, 1, 2].flatMap(() => [e('prose', 6), e('review', 8)]))).toBeNull();
    expect(slowChecksNote([0, 1, 2].flatMap(() => [e('prose', 60), e('review', 70)]))).toBeNull();
  });
});
