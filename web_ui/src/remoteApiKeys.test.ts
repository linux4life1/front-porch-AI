// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it } from 'vitest';
import { isLmStudioUrl, urlHasStoredApiKey } from './remoteApiKeys';

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

  it('treats trailing slash and host case as the same slot', () => {
    expect(
      urlHasStoredApiKey('https://OpenRouter.ai/api/v1/', [
        'https://openrouter.ai/api/v1',
      ]),
    ).toBe(true);
  });
});

describe('isLmStudioUrl', () => {
  it('matches localhost and 127.0.0.1 on port 1234', () => {
    expect(isLmStudioUrl('http://localhost:1234/v1')).toBe(true);
    expect(isLmStudioUrl('http://127.0.0.1:1234/v1/')).toBe(true);
    expect(isLmStudioUrl('http://localhost:8000/v1')).toBe(false);
    expect(isLmStudioUrl('https://openrouter.ai/api/v1')).toBe(false);
  });
});
