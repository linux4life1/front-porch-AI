// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { splitParagraphs } from './paragraphs';

describe('splitParagraphs', () => {
  it('breaks on blank lines only and trims each paragraph', () => {
    expect(splitParagraphs('One.\nStill one.\n\n\n  Two.  \n \nThree.')).toEqual(['One.\nStill one.', 'Two.', 'Three.']);
  });

  it('gives nothing for blank text', () => {
    expect(splitParagraphs(' \n\n ')).toEqual([]);
  });
});
