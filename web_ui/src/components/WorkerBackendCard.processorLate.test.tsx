// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Side jobs host picker greys KoboldCpp out on an Intel Mac host. The
// host only knows it is one once it has read its processor, a moment after
// it starts, so the picker follows every answer while it shows: an
// "unsupported" the host takes back gives KoboldCpp back, and one that comes
// late greys it out. It used to ask once and keep a "yes" for good.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get } = vi.hoisted(() => ({ get: vi.fn() }));
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: { get, post: async () => ({}) },
}));

import { WorkerBackendCard } from './WorkerBackendCard';

let container: HTMLDivElement;
let root: Root;
let unsupported: boolean;

async function open() {
  get.mockImplementation((path: string) =>
    Promise.resolve(
      path === '/api/backend/status' ? { localUnsupported: unsupported } : { models: [] },
    ),
  );
  await act(async () => {
    root.render(
      createElement(WorkerBackendCard, {
        s: {
          backend: 'openRouter',
          remoteApiUrl: 'https://openrouter.ai/api/v1',
          workerBackend: 'openRouter',
          workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
        },
        workerApiKey: '',
        onWorkerApiKey: () => {},
        onPatch: () => {},
      }),
    );
  });
}

const kobold = () =>
  container.querySelector(
    '[data-testid="side-jobs-host"] option[value="kobold"]',
  ) as HTMLOptionElement;
const sentence = () => container.querySelector('[data-testid="side-jobs-local-unsupported"]');
const later = async () => {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(5500);
  });
};

beforeEach(() => {
  vi.useFakeTimers();
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.useRealTimers();
});

describe('the Side jobs host picker while the host reads its processor', () => {
  it('an "unsupported" the host takes back gives KoboldCpp back', async () => {
    unsupported = true;
    await open();
    expect(kobold().disabled).toBe(true);

    unsupported = false;
    await later();

    expect(kobold().disabled).toBe(false);
    expect(sentence()).toBeNull();
  });

  it('an "unsupported" that comes late greys KoboldCpp out', async () => {
    unsupported = false;
    await open();
    expect(kobold().disabled).toBe(false);

    unsupported = true;
    await later();

    expect(kobold().disabled).toBe(true);
    expect(sentence()).not.toBeNull();
  });
});
