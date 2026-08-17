// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Payload pin: /api/chargen/enhance must carry the Create voice when the
// client has it. Default first/present is omitted so the existing payload
// shape test stays unchanged.

import { describe, it, expect } from 'vitest';
import { buildEnhancePayload, DEFAULT_ENHANCE_SELECTION } from './enhanceForm';

describe('buildEnhancePayload — narrative voice', () => {
  it('omits voice keys when the client did not pass them', () => {
    const p = buildEnhancePayload('char-1', 'sess-1', DEFAULT_ENHANCE_SELECTION, true);
    expect(p).not.toHaveProperty('narrativePerspective');
    expect(p).not.toHaveProperty('narrativeTense');
    expect(p).not.toHaveProperty('sex');
  });

  it('carries third + past + Female when the card had that voice', () => {
    const p = buildEnhancePayload(
      'char-1',
      'sess-1',
      DEFAULT_ENHANCE_SELECTION,
      false,
      '',
      { narrativePerspective: 'third', narrativeTense: 'past', sex: 'Female' },
    );
    expect(p.narrativePerspective).toBe('third');
    expect(p.narrativeTense).toBe('past');
    expect(p.sex).toBe('Female');
  });
});
