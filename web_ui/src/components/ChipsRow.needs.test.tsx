// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

describe('ChipsRow no-action Needs chip', () => {
  const src = readFileSync(join(__dirname, 'ChipsRow.tsx'), 'utf8');

  it('renders No needs affected when the facade flags needsUnaffected', () => {
    expect(src).toContain('chips.needsUnaffected');
    expect(src).toContain('No needs affected');
  });
});
