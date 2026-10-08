// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "just now", "12m ago", "3h ago", "yesterday", "4 days ago", "Aug 12" (the
// year is appended when it is not this year). Same wording as the desktop
// shelf: lib/utils/relative_time.dart.

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MS_MINUTE = 60_000;
const MS_HOUR = 3_600_000;
const MS_DAY = 86_400_000;

/** Whole calendar days from [from] to [to], ignoring the time of day (and DST). */
function calendarDays(from: Date, to: Date): number {
  const a = Date.UTC(from.getFullYear(), from.getMonth(), from.getDate());
  const b = Date.UTC(to.getFullYear(), to.getMonth(), to.getDate());
  return Math.round((b - a) / MS_DAY);
}

export function formatRelativeTime(at: Date | string | number, now: Date = new Date()): string {
  // Dart writes microseconds (".123456"); trim to the millisecond ECMAScript defines.
  const when = at instanceof Date ? at : new Date(typeof at === 'string' ? at.replace(/(\.\d{3})\d+/, '$1') : at);
  if (Number.isNaN(when.getTime())) return '';
  const diff = now.getTime() - when.getTime();
  const minutes = Math.trunc(diff / MS_MINUTE);
  const hours = Math.trunc(diff / MS_HOUR);
  if (minutes < 1) return 'just now';
  if (hours < 1) return `${minutes}m ago`;
  if (hours < 24 && when.getDate() === now.getDate()) return `${hours}h ago`;
  const days = calendarDays(when, now);
  if (days <= 1) return 'yesterday';
  if (days < 7) return `${days} days ago`;
  const year = when.getFullYear() === now.getFullYear() ? '' : ` ${when.getFullYear()}`;
  return `${MONTHS[when.getMonth()]} ${when.getDate()}${year}`;
}
