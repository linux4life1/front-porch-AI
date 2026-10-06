// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { importCardMenu } from '../components/library/cardMenus';
import { exportNotice, porchOutcome, type PorchImportReport } from './usePorchTransfer';

const report = (r: Partial<PorchImportReport>): PorchImportReport => ({
  imported: [],
  skipped: [],
  refused: [],
  chats: 0,
  message: '',
  ...r,
});

describe('porchOutcome', () => {
  it('adds every file up; imports and skips are a notice, refusals the error', () => {
    const out = porchOutcome(
      [
        report({ imported: ['Cora Lind'], skipped: ['Aria Vale'], chats: 2 }),
        report({ skipped: ['Bram Elder'], refused: ['“odd.porch” couldn’t be opened.'] }),
      ],
      ['That file is too large to send from here.'],
    );
    expect(out.notice.split('\n')).toEqual([
      'Imported 1 character with 2 chats.',
      'Skipped 2 you already have: Aria Vale, Bram Elder.',
    ]);
    expect(out.error.split('\n')).toEqual([
      '“odd.porch” couldn’t be opened.',
      'That file is too large to send from here.',
    ]);
  });

  it('a skip alone is not an error', () => {
    expect(porchOutcome([report({ skipped: ['Aria Vale'] })], [])).toEqual({
      notice: 'Skipped 1 you already have: Aria Vale.',
      error: '',
    });
  });

  it('says so when the files held no characters', () => {
    expect(porchOutcome([report({})], [])).toEqual({
      notice: 'Those files held no characters.',
      error: '',
    });
  });
});

describe('exportNotice', () => {
  it('names the file, as the desktop does', () => {
    expect(exportNotice(2, 'Front Porch characters (2).porchpack', 0)).toBe(
      'Saved 2 characters to Front Porch characters (2).porchpack.',
    );
  });

  it('says groups were left out when the selection had groups', () => {
    expect(exportNotice(1, 'Aria Vale.porch', 2)).toBe(
      'Saved 1 character to Aria Vale.porch. Groups were left out.',
    );
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
