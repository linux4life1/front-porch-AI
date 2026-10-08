// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Side jobs host picker on an Intel Mac. KoboldCpp cannot run there, so
// the desktop greys it out in its Realism evals host bar
// (worker_backend_section.dart, koboldEnabled: !intelMac). The phone offered
// it as any other host. Now it is greyed out the same way, with the
// desktop's sentence, when the host's status says local models cannot run.

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
import { INTEL_MAC_LOCAL_UNSUPPORTED } from '../backendOptions';

let container: HTMLDivElement;
let root: Root;

async function open(status: Record<string, unknown>) {
  get.mockImplementation((path: string) =>
    Promise.resolve(path === '/api/backend/status' ? status : { models: [] }),
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
  ) as HTMLOptionElement | null;
const sentence = () =>
  container.querySelector('[data-testid="side-jobs-local-unsupported"]');

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the Side jobs host picker on an Intel Mac', () => {
  it('greys KoboldCpp out and says why, in the desktop\'s words', async () => {
    await open({ localUnsupported: true });

    expect(kobold()).not.toBeNull();
    expect(kobold()!.disabled).toBe(true);
    expect(sentence()?.textContent).toBe(INTEL_MAC_LOCAL_UNSUPPORTED);
  });

  it('elsewhere, and from an app too old to say, KoboldCpp is a host as before', async () => {
    for (const status of [{ localUnsupported: false }, {}]) {
      await open(status);

      expect(kobold()!.disabled).toBe(false);
      expect(sentence()).toBeNull();
    }
  });
});
