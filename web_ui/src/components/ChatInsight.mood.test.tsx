// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// Mood with bite (docs/design/mood-with-bite.md): the phone shows the same
// one-line row the desktop does — label, intensity, cause and hold word —
// and falls back to the older `mood` string from a desktop that predates it.
describe('ChatInsight mood row', () => {
  const src = readFileSync(join(__dirname, 'ChatInsight.tsx'), 'utf8');
  const types = readFileSync(join(__dirname, 'chatTypes.ts'), 'utf8');

  it('renders moodLine before the older mood string', () => {
    const line = src.indexOf('realism.moodLine || realism.mood');
    expect(line).toBeGreaterThan(-1);
    const row = src.slice(src.lastIndexOf('<span>Mood</span>', line), line);
    expect(row).toContain('Mood');
  });

  it('types the three additive fields as optional', () => {
    expect(types).toMatch(/emotionCause\?: string/);
    expect(types).toMatch(/emotionHeld\?: number/);
    expect(types).toMatch(/moodLine\?: string/);
  });
});
