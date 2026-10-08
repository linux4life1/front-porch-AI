// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The needs bands for a sidebar bar (docs/design/needs-on-the-clock.md,
// "Bands"): amber from 40 down, red from 25 down, calm above.

import { describe, expect, it } from 'vitest';
import { NEED_CRITICAL_AT, NEED_URGENT_AT, needTone } from './needTone';

describe('needTone', () => {
  it('uses the spec numbers', () => {
    expect(NEED_URGENT_AT).toBe(40);
    expect(NEED_CRITICAL_AT).toBe(25);
  });

  it('is calm above 40, amber from 40, red from 25', () => {
    expect(needTone(100)).toBe('ok');
    expect(needTone(41)).toBe('ok');
    expect(needTone(40)).toBe('warn');
    expect(needTone(26)).toBe('warn');
    expect(needTone(25)).toBe('danger');
    expect(needTone(1)).toBe('danger');
    expect(needTone(0)).toBe('danger');
  });

  it('follows the cutoffs the server sends when they differ from the defaults', () => {
    // The engine owns the bands; a future change there must move the phone too.
    expect(needTone(45, 50, 30)).toBe('warn');
    expect(needTone(30, 50, 30)).toBe('danger');
    expect(needTone(51, 50, 30)).toBe('ok');
    expect(needTone(40, undefined, undefined)).toBe('warn');
  });
});
