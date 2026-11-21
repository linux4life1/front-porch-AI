// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { describe, expect, it, vi } from 'vitest';
import { api, isTimeout } from './client';

// A POST that opts into a bound gives up as a timeout instead of hanging
// (persona saves); POSTs that do not (journal regen, growth passes) keep
// waiting as before.
describe('api.post timeoutMs', () => {
  const stalledFetch = () =>
    vi.fn((_path: string, init?: RequestInit) =>
      new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener('abort', () => reject(init.signal!.reason));
      }),
    );

  it('rejects with a timeout the caller can tell apart', async () => {
    const fetchMock = stalledFetch();
    vi.stubGlobal('fetch', fetchMock);
    try {
      const err = await api.post('/api/personas/create', { name: 'x' }, { timeoutMs: 20 }).catch((e) => e);
      expect(isTimeout(err)).toBe(true);
    } finally {
      vi.unstubAllGlobals();
    }
  });
});
