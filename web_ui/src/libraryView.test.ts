// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Sort / search-scope persistence. Junk and a storage exception both fall
// back to the desktop defaults (name, this folder). The hook test covers
// restore-after-remount.

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  loadLibraryScope,
  loadLibrarySort,
  saveLibraryScope,
  saveLibrarySort,
} from './libraryView';

afterEach(() => {
  localStorage.clear();
  vi.restoreAllMocks();
});

describe('library view persistence', () => {
  it('rejects unknown stored values', () => {
    localStorage.setItem('fpai.lib.sort', 'garbage');
    localStorage.setItem('fpai.lib.scope', 'nope');
    expect(loadLibrarySort()).toBe('name');
    expect(loadLibraryScope()).toBe('currentFolder');
  });

  it('falls back when storage throws', () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('denied');
    });
    expect(loadLibrarySort()).toBe('name');
    expect(loadLibraryScope()).toBe('currentFolder');

    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('full');
    });
    expect(() => saveLibrarySort('recent')).not.toThrow();
    expect(() => saveLibraryScope('allCharacters')).not.toThrow();
  });

  it('writes only a known sort', () => {
    expect(saveLibrarySort('recent')).toBe('recent');
    expect(localStorage.getItem('fpai.lib.sort')).toBe('recent');
    expect(saveLibrarySort('sideways')).toBe('name');
    expect(localStorage.getItem('fpai.lib.sort')).toBe('name');
  });
});
