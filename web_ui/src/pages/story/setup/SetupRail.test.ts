// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// New story → "Your story so far" Shape line. The length label already names
// the form ("Novel · 80k"), so the line must not say "novel" a second time.
// Desktop twin: test/ui/story_setup/story_shape_summary_test.dart.

import { describe, expect, it } from 'vitest';
import { emptyDraft } from './draft';
import { shapeSummary } from './SetupRail';

describe('New Story Shape summary', () => {
  it('names a novel once, by its length', () => {
    expect(shapeSummary(emptyDraft())).toBe('Novel · 80k · third person, close');
  });

  it('still says audio drama', () => {
    const d = {
      ...emptyDraft(), proseLength: 'Short', storyFormat: 'audioDrama' as const, pov: 'First Person',
      genres: ['Fantasy'], moods: ['Dark'], writingStyle: 'Gothic',
    };
    expect(shapeSummary(d)).toBe('Novella · 30k · audio drama · first person · fantasy · dark · gothic');
  });
});
