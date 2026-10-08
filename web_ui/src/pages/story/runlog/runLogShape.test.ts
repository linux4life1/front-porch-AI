// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import type { StoryRunEntry } from '../../../storyTypes';
import { bothText, callsLine, clock, isFailure, roleTone, rowStats, stageLabel, verdictTone } from './runLogShape';

const entry = (patch: Partial<StoryRunEntry> = {}): StoryRunEntry => ({
  at: '2026-10-02T14:02:11', stage: 'Writing 1.1 · beat 3', role: 'prose', backend: 'KoboldCpp', attempt: 1, verdict: '',
  note: '', millis: 1234, tokens: 410, prompt: 'p', response: 'r', ...patch,
});

describe('Run log words (sketch U)', () => {
  it('tones a verdict: PASS and OK teal, FAIL and ERROR bad, INVALID and FIXED honey, the rest plain', () => {
    expect(['PASS', 'OK'].map(verdictTone)).toEqual(['teal', 'teal']);
    expect(['FAIL', 'ERROR'].map(verdictTone)).toEqual(['bad', 'bad']);
    expect(['INVALID', 'FIXED'].map(verdictTone)).toEqual(['honey', 'honey']);
    expect(verdictTone('')).toBe('');
    expect(verdictTone('SKIPPED')).toBe('');
  });

  it('counts FAIL, ERROR and INVALID as failures, and nothing else', () => {
    expect(['FAIL', 'ERROR', 'INVALID'].every((v) => isFailure(entry({ verdict: v })))).toBe(true);
    expect(['PASS', 'OK', 'FIXED', ''].some((v) => isFailure(entry({ verdict: v })))).toBe(false);
  });

  it('colours the role: prose terracotta, planning honey, review plain', () => {
    expect([roleTone('prose'), roleTone('planning'), roleTone('review')]).toEqual(['terra', 'honey', '']);
  });

  it('shows the stage, with the try number from the second try on', () => {
    expect(stageLabel(entry())).toBe('Writing 1.1 · beat 3');
    expect(stageLabel(entry({ stage: 'Review: beats', attempt: 2 }))).toBe('Review: beats · try 2');
    expect(stageLabel(entry({ stage: '' }))).toBe('Model call');
  });

  it('shows seconds and tokens', () => {
    expect(rowStats(entry())).toBe('1.2s · 410 tok');
    expect(rowStats(entry({ millis: 26000, tokens: 1410 }))).toBe('26.0s · 1410 tok');
  });

  it('draws a 24-hour clock with two digits each, and a dash for a time it cannot read', () => {
    expect(clock('2026-10-02T09:05:03')).toBe('09:05:03');
    expect(clock('2026-10-02T21:36:54.123456')).toBe('21:36:54');
    expect(clock('not a time')).toBe('—');
  });

  it('counts the calls, or says there are none yet', () => {
    expect(callsLine(0)).toBe('No model calls yet. Every call this story makes is listed here.');
    expect(callsLine(1)).toBe('1 call · newest first');
    expect(callsLine(22)).toBe('22 calls · newest first');
  });

  it('copies both sides under their own headings', () => {
    expect(bothText(entry({ prompt: 'Write.', response: 'Done.' }))).toBe('### Prompt\nWrite.\n\n### Reply\nDone.');
  });
});
