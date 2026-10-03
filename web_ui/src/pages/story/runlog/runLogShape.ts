// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What a run-log row says (sketch U): the clock, the stage with its try number,
// the chip tones for role and verdict, seconds and tokens, and what counts as a
// failure for the Failures filter. The same rules as the desktop's
// RunLogSection. Presentation only.

import type { StoryRunEntry } from '../../../storyTypes';

/** PASS / OK are teal, FAIL / ERROR bad, INVALID / FIXED honey, anything else plain. */
export function verdictTone(verdict: string): 'teal' | 'bad' | 'honey' | '' {
  if (verdict === 'PASS' || verdict === 'OK') return 'teal';
  if (verdict === 'FAIL' || verdict === 'ERROR') return 'bad';
  if (verdict === 'INVALID' || verdict === 'FIXED') return 'honey';
  return '';
}

/** The Failures filter: FAIL, ERROR and INVALID. */
export const isFailure = (e: StoryRunEntry): boolean => verdictTone(e.verdict) === 'bad' || e.verdict === 'INVALID';

/** Prose is terracotta, planning honey, the reviewer plain. */
export function roleTone(role: string): 'terra' | 'honey' | '' {
  return role === 'prose' ? 'terra' : role === 'planning' ? 'honey' : '';
}

const two = (n: number): string => String(n).padStart(2, '0');

/** 24-hour local clock, "14:02:11". An entry with no readable time shows a dash. */
export function clock(at: string): string {
  const t = new Date(typeof at === 'string' ? at.replace(/(\.\d{3})\d+/, '$1') : at);
  return Number.isNaN(t.getTime()) ? '—' : `${two(t.getHours())}:${two(t.getMinutes())}:${two(t.getSeconds())}`;
}

export const stageLabel = (e: StoryRunEntry): string => {
  const stage = e.stage || 'Model call';
  return e.attempt > 1 ? `${stage} · try ${e.attempt}` : stage;
};

export const seconds = (millis: number): string => (millis / 1000).toFixed(1);

/** "1.2s · 410 tok". */
export const rowStats = (e: StoryRunEntry): string => `${seconds(e.millis)}s · ${e.tokens} tok`;

/** "148 calls · newest first", or the empty line. */
export function callsLine(n: number): string {
  return n === 0
    ? 'No model calls yet. Every call this story makes is listed here.'
    : `${n} call${n === 1 ? '' : 's'} · newest first`;
}

/** What "Copy both" puts on the clipboard. */
export const bothText = (e: StoryRunEntry): string => `### Prompt\n${e.prompt}\n\n### Reply\n${e.response}`;
