// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// The mood moved off the insight panel: the Mood chip under each reply says
// what they feel and why (ChipsRow), so the panel no longer repeats it, the
// same as the desktop sidebar. The realism payload keeps its mood fields.
describe('ChatInsight mood row', () => {
  const src = readFileSync(join(__dirname, 'ChatInsight.tsx'), 'utf8');
  const types = readFileSync(join(__dirname, 'chatTypes.ts'), 'utf8');

  it('has no Mood row', () => {
    expect(src).not.toContain('<span>Mood</span>');
    expect(src).not.toContain('realism.moodLine');
  });

  it('types the three additive fields as optional', () => {
    expect(types).toMatch(/emotionCause\?: string/);
    expect(types).toMatch(/emotionHeld\?: number/);
    expect(types).toMatch(/moodLine\?: string/);
  });
});
