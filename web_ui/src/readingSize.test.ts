// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for web-local reading size load/save/apply. jsdom provides
// localStorage + document.

import { describe, it, expect, beforeEach } from 'vitest';
import {
  READING_SIZE_DEFAULT,
  applyReadingSize,
  loadReadingSize,
  saveReadingSize,
} from './readingSize';

beforeEach(() => {
  localStorage.clear();
  document.documentElement.removeAttribute('style');
});

describe('readingSize', () => {
  it('returns the default when nothing is saved', () => {
    expect(loadReadingSize()).toBe(READING_SIZE_DEFAULT);
  });

  it('persists a value in the allowed range', () => {
    saveReadingSize(1.5);
    expect(loadReadingSize()).toBe(1.5);
  });

  it('clamps out-of-range values', () => {
    saveReadingSize(0.2);
    expect(loadReadingSize()).toBe(0.7);
    saveReadingSize(9);
    expect(loadReadingSize()).toBe(2);
  });

  it('falls back to default on corrupt storage', () => {
    localStorage.setItem('fpai.readingSize', 'nope');
    expect(loadReadingSize()).toBe(READING_SIZE_DEFAULT);
  });

  it('applies --reading-size on :root', () => {
    applyReadingSize(1.5);
    expect(document.documentElement.style.getPropertyValue('--reading-size')).toBe('1.5');
  });
});
