// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

describe('ChatTools clock chevrons', () => {
  const src = readFileSync(
    join(__dirname, 'ChatTools.tsx'),
    'utf8',
  );

  it('gates Earlier/Later and the calendar on clockRunning, not realism alone', () => {
    expect(src).toContain('const clockRunning = t.time.clockRunning ?? t.realismEnabled');
    expect(src).toContain('disabled={!clockRunning}');
    expect(src).toContain('canEdit={clockRunning}');
    expect(src).toContain('Story clock is paused');
    expect(src).not.toContain(
      'Realism Mode is off, so the story clock is paused',
    );
  });
});
