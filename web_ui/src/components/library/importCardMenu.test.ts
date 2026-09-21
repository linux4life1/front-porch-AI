// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { importCardMenu } from './cardMenus';

describe('importCardMenu', () => {
  it('offers Backyard AI .byaf next to PNG/JSON and folder import', () => {
    const labels = importCardMenu({
      onImportCards: () => {},
      onImportFolder: () => {},
      onImportByaf: () => {},
    }).map((i) => i.label);
    expect(labels).toContain('Import cards…');
    expect(labels).toContain('Import a folder…');
    expect(labels).toContain('Import Backyard AI (.byaf)…');
    expect(labels.indexOf('Import Backyard AI (.byaf)…')).toBe(
      labels.indexOf('Import a folder…') + 1,
    );
  });
});
