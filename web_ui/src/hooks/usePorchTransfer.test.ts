// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { importCardMenu } from '../components/library/cardMenus';
import { porchSummary, type PorchImportReport } from './usePorchTransfer';

const report = (r: Partial<PorchImportReport>): PorchImportReport => ({
  imported: [],
  skipped: [],
  refused: [],
  chats: 0,
  message: '',
  ...r,
});

describe('porchSummary', () => {
  it('adds every file up and names what was skipped, like the desktop', () => {
    const lines = porchSummary(
      [
        report({ imported: ['Cora Lind'], skipped: ['Aria Vale'], chats: 2 }),
        report({ skipped: ['Bram Elder'], refused: ['“odd.porch” couldn’t be opened.'] }),
      ],
      ['That file is too large to send from here.'],
    ).split('\n');
    expect(lines).toEqual([
      'Imported 1 character with 2 chats.',
      'Skipped 2 you already have: Aria Vale, Bram Elder.',
      '“odd.porch” couldn’t be opened.',
      'That file is too large to send from here.',
    ]);
  });

  it('says so when the files held no characters', () => {
    expect(porchSummary([report({})], [])).toBe('Those files held no characters.');
  });
});

describe('importCardMenu', () => {
  it('offers .porch / .porchpack when the page wires it', () => {
    const labels = importCardMenu({
      onImportCards: () => {},
      onImportFolder: () => {},
      onImportByaf: () => {},
      onImportPorch: () => {},
    }).map((i) => i.label);
    expect(labels).toContain('Import .porch / .porchpack…');
  });
});
