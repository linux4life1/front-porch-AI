// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { workerPairAllowed } from './workerBackend';

describe('workerPairAllowed V2 swap flag', () => {
  it('allows dual-local when swap is available', () => {
    expect(
      workerPairAllowed(
        'kobold',
        '',
        'omlx',
        'http://localhost:8000/v1',
        true,
      ),
    ).toBe(true);
  });

  it('keeps refusing dual-local when swap is not available', () => {
    expect(
      workerPairAllowed('kobold', '', 'omlx', 'http://localhost:8000/v1'),
    ).toBe(false);
  });
});
