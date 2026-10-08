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

// ── Time by job (twin of lib/services/story/story_run_summary.dart) ──

export interface JobTime {
  role: string;
  calls: number;
  millis: number;
  models: string[];
}

const JOB_ORDER = ['planning', 'prose', 'review'];

/** "48s" under a minute and a half, else whole minutes. */
export function duration(millis: number): string {
  const s = millis / 1000;
  return s < 90 ? `${Math.round(s)}s` : `${Math.round(s / 60)} min`;
}

const average = (j: JobTime): number => (j.calls === 0 ? 0 : j.millis / j.calls / 1000);

/** Time per job, in the order planning, prose, review, then anything else. */
export function jobTimes(entries: StoryRunEntry[]): JobTime[] {
  const byRole = new Map<string, JobTime>();
  for (const e of entries) {
    const job = byRole.get(e.role) ?? { role: e.role, calls: 0, millis: 0, models: [] };
    job.calls += 1;
    job.millis += e.millis;
    if (e.model && !job.models.includes(e.model)) job.models.push(e.model);
    byRole.set(e.role, job);
  }
  const rank = (role: string) => (JOB_ORDER.includes(role) ? JOB_ORDER.indexOf(role) : JOB_ORDER.length);
  return [...byRole.values()].sort((a, b) => rank(a.role) - rank(b.role));
}

/** "Review · 28 calls · 34 min · 74s each · grok-4.7" */
export function jobTimeLine(j: JobTime): string {
  const name = j.role ? j.role[0].toUpperCase() + j.role.slice(1) : 'Other';
  return [
    name,
    `${j.calls} call${j.calls === 1 ? '' : 's'}`,
    duration(j.millis),
    `${Math.round(average(j))}s each`,
    ...(j.models.length ? [j.models.join(', ')] : []),
  ].join(' · ');
}

/** Plain words when checking takes far longer than writing; null until there is enough to judge. */
export function slowChecksNote(entries: StoryRunEntry[]): string | null {
  const jobs = jobTimes(entries);
  const review = jobs.find((j) => j.role === 'review');
  const prose = jobs.find((j) => j.role === 'prose');
  if (!review || !prose || review.calls < 3 || prose.calls < 3) return null;
  if (average(review) < 20 || average(review) < average(prose) * 3) return null;
  return `Checks average ${Math.round(average(review))}s each; writing averages ${Math.round(average(prose))}s. `
    + 'A check runs after every beat, so a faster Review model (Setup, Engine step) would speed this story up.';
}
