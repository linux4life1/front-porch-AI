// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Passage of Time is the only clock driver. The leftover standalone
// sub-switch must not come back on the web Porch Life card.

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

describe('Porch Life Passage of Time', () => {
  const src = readFileSync(
    join(__dirname, 'PorchLifeSettings.tsx'),
    'utf8',
  );

  it('is the new-chat default and does not nest a standalone switch', () => {
    expect(src).toContain('default for new chats');
    expect(src).toContain('Automatic Passage of Time');
    expect(src).not.toContain('Keep the clock running without the engine');
    expect(src).not.toContain("set('standaloneClockEnabled'");
  });
});
