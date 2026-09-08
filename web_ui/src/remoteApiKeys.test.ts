// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { urlHasStoredApiKey } from './remoteApiKeys';

describe('urlHasStoredApiKey', () => {
  it('is false when this host has no saved key', () => {
    expect(
      urlHasStoredApiKey('https://nano-gpt.com/api/v1', [
        'https://openrouter.ai/api/v1',
      ]),
    ).toBe(false);
  });

  it('is true only for the matching host', () => {
    expect(
      urlHasStoredApiKey('https://openrouter.ai/api/v1', [
        'https://openrouter.ai/api/v1',
      ]),
    ).toBe(true);
  });
});
