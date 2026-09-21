// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { workerPairAllowed } from './workerBackend';

describe('workerPairAllowed', () => {
  it('allows API+API, including the same host', () => {
    expect(
      workerPairAllowed(
        'openRouter',
        'https://nano-gpt.com/api/v1',
        'openRouter',
        'https://nano-gpt.com/api/v1',
      ),
    ).toBe(true);
    expect(
      workerPairAllowed(
        'openRouter',
        'https://openrouter.ai/api/v1',
        'openRouter',
        'https://nano-gpt.com/api/v1',
      ),
    ).toBe(true);
  });

  it('allows API+local and local+API', () => {
    expect(
      workerPairAllowed(
        'openRouter',
        'https://nano-gpt.com/api/v1',
        'omlx',
        'http://localhost:8000/v1',
      ),
    ).toBe(true);
    expect(
      workerPairAllowed(
        'kobold',
        '',
        'openRouter',
        'https://openrouter.ai/api/v1',
      ),
    ).toBe(true);
  });

  it('refuses local+local and allows an empty worker', () => {
    expect(
      workerPairAllowed('kobold', '', 'omlx', 'http://localhost:8000/v1'),
    ).toBe(false);
    expect(workerPairAllowed('kobold', '', '', '')).toBe(true);
  });
});
