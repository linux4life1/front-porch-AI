// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

describe('ChatInsight Needs vs Realism', () => {
  const src = readFileSync(join(__dirname, 'ChatInsight.tsx'), 'utf8');

  it('renders Needs outside the realism-off paragraph', () => {
    const realismOff = src.indexOf('realism.realismEnabled === false');
    const needsBlock = src.indexOf(
      'realism.needsEnabled && Object.keys(realism.needs).length > 0',
    );
    expect(realismOff).toBeGreaterThan(-1);
    expect(needsBlock).toBeGreaterThan(realismOff);
    const between = src.slice(realismOff, needsBlock);
    expect(between).toContain('</>');
    expect(between).toContain(')}');
    expect(src).not.toContain(
      'needs, and scene time for this character.',
    );
  });
});
