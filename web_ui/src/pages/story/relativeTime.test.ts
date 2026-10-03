// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { formatRelativeTime } from './relativeTime';

// Local-time dates, like the desktop helper (DateTime.now()).
const now = new Date(2026, 9, 2, 15, 0, 0); // Oct 2 2026, 15:00

const ago = (ms: number) => new Date(now.getTime() - ms);
const MIN = 60_000;
const HOUR = 60 * MIN;

describe('formatRelativeTime', () => {
  it('says "just now" inside the first minute, and for a time in the future', () => {
    expect(formatRelativeTime(ago(20_000), now)).toBe('just now');
    expect(formatRelativeTime(ago(-5 * MIN), now)).toBe('just now');
  });

  it('counts minutes then hours within the same day', () => {
    expect(formatRelativeTime(ago(12 * MIN), now)).toBe('12m ago');
    expect(formatRelativeTime(ago(3 * HOUR), now)).toBe('3h ago');
  });

  it('says "yesterday" across midnight, even when it is under 24 hours ago', () => {
    expect(formatRelativeTime(new Date(2026, 9, 1, 23, 0), now)).toBe('yesterday');
    expect(formatRelativeTime(new Date(2026, 9, 1, 9, 0), now)).toBe('yesterday');
  });

  it('counts days under a week, then names the date', () => {
    expect(formatRelativeTime(new Date(2026, 8, 28, 9, 0), now)).toBe('4 days ago');
    expect(formatRelativeTime(new Date(2026, 8, 25, 9, 0), now)).toBe('Sep 25');
    expect(formatRelativeTime(new Date(2026, 7, 12, 9, 0), now)).toBe('Aug 12');
  });

  it('appends the year when it is not this year', () => {
    expect(formatRelativeTime(new Date(2025, 7, 12, 9, 0), now)).toBe('Aug 12 2025');
  });

  it('reads ISO strings the relay sends', () => {
    expect(formatRelativeTime(new Date(now.getTime() - 5 * MIN).toISOString(), now)).toBe('5m ago');
    // Dart's toIso8601String() carries microseconds and no zone for local times.
    const local = new Date(now.getTime() - 3 * HOUR);
    const pad = (n: number) => String(n).padStart(2, '0');
    const dartLocal = `${local.getFullYear()}-${pad(local.getMonth() + 1)}-${pad(local.getDate())}T${pad(local.getHours())}:${pad(local.getMinutes())}:${pad(local.getSeconds())}.000456`;
    expect(formatRelativeTime(dartLocal, now)).toBe('3h ago');
    expect(formatRelativeTime('not a date', now)).toBe('');
  });
});
