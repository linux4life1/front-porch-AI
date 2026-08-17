// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Voice (perspective + tense) must ride the shared output-settings payload
// so the Dart generator sees the same choice the web wizard made.

import { describe, it, expect } from 'vitest';
import { DEFAULT_FORM, buildPayload, type ChargenForm } from './chargenForm';

const form = (over: Partial<ChargenForm>): ChargenForm => ({ ...DEFAULT_FORM, ...over });

describe('buildPayload — narrative voice', () => {
  it('defaults to first-person present and forwards sex on Quick', () => {
    const p = buildPayload(form({
      mode: 'quick', name: 'Nina', quickConcept: 'a baker', sex: 'Female',
    }));
    expect(p.narrativePerspective).toBe('first');
    expect(p.narrativeTense).toBe('present');
    expect(p.sex).toBe('Female');
  });

  it('forwards third + past on every mode', () => {
    for (const mode of ['quick', 'guided', 'automated'] as const) {
      const p = buildPayload(form({
        mode, name: 'Nina',
        quickConcept: 'c', vision: 'c', aConcept: 'c',
        narrativePerspective: 'third', narrativeTense: 'past', sex: 'Male',
      }));
      expect(p.narrativePerspective, mode).toBe('third');
      expect(p.narrativeTense, mode).toBe('past');
    }
  });
});
