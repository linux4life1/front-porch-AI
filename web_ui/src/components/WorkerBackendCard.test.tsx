// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  kWorkerDualLocalMessage,
  workerHostMatchesChat,
  workerShowsApiKeyField,
} from '../workerBackend';

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () => Promise.resolve({}),
    post: async () => ({ models: [{ id: 'z-ai/glm-5.3', name: 'GLM', pricing: '', free: true }] }),
  },
}));

const { WorkerBackendCard } = await import('./WorkerBackendCard');
type WorkerBackendFields = import('./WorkerBackendCard').WorkerBackendFields;

let container: HTMLDivElement;
let root: Root;
let latest: WorkerBackendFields;

function render(s: WorkerBackendFields, workerApiKey = '') {
  latest = { ...s };
  const onPatch = (p: Partial<WorkerBackendFields>) => {
    latest = { ...latest, ...p };
    act(() => {
      root.render(
        createElement(WorkerBackendCard, {
          s: latest,
          workerApiKey,
          onWorkerApiKey: () => {},
          onPatch,
        }),
      );
    });
  };
  act(() => {
    root.render(
      createElement(WorkerBackendCard, {
        s,
        workerApiKey,
        onWorkerApiKey: () => {},
        onPatch,
      }),
    );
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean })
    .IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('WorkerBackendCard', () => {
  it('H2 defaults to Same as chat with zero extra fields', () => {
    render({ backend: 'openRouter', remoteApiUrl: 'https://nano-gpt.com/api/v1' });
    expect(container.textContent).toContain('Realism evals');
    expect(container.textContent).not.toContain('Worker backend');
    expect(container.querySelector('[data-testid="side-jobs-same-as-chat"]')?.getAttribute('aria-pressed')).toBe('true');
    expect(container.querySelector('[data-testid="side-jobs-host"]')).toBeNull();
    expect(container.querySelector('[data-testid="side-jobs-worker-key"]')).toBeNull();
    expect(container.querySelector('[data-testid="side-jobs-worker-url"]')).toBeNull();
    expect(container.querySelector('.model-picker')).toBeNull();
    expect(container.textContent).not.toContain('Browse models');
    expect(container.querySelector('[data-testid="worker-dual-local-banner"]')).toBeNull();
  });

  it('H3 same host shows the chat model picker only', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      workerBackend: 'openRouter',
      workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
      workerRemoteModelName: 'z-ai/glm-5.3',
    });
    expect(container.querySelector('.model-picker')).not.toBeNull();
    expect(container.querySelector('[data-testid="side-jobs-worker-key"]')).toBeNull();
    expect(container.querySelector('[data-testid="side-jobs-worker-url"]')).toBeNull();
    expect(container.textContent).not.toContain('Browse models');
    expect(container.querySelector('input[type="password"]')).toBeNull();
  });

  it('H4 different host shows a key only when the vault is empty', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      workerBackend: 'openRouter',
      workerRemoteApiUrl: 'https://openrouter.ai/api/v1',
    });
    expect(container.querySelector('[data-testid="side-jobs-worker-key"]')).not.toBeNull();
    expect(container.querySelector('.model-picker')).not.toBeNull();
    expect(container.querySelector('[data-testid="side-jobs-worker-url"]')).toBeNull();
  });

  it('H4 different host with a saved key hides the second key field', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      workerBackend: 'openRouter',
      workerRemoteApiUrl: 'https://openrouter.ai/api/v1',
      remoteApiUrlsWithKeys: ['https://openrouter.ai/api/v1'],
    });
    expect(container.querySelector('[data-testid="side-jobs-worker-key"]')).toBeNull();
    expect(container.querySelector('[data-testid="side-jobs-saved-key-hint"]')?.textContent)
      .toContain('saved key');
  });

  it('H5 shows the GPU warning when chat is Kobold and worker is oMLX', () => {
    render({
      backend: 'kobold',
      remoteApiUrl: '',
      workerBackend: 'omlx',
      workerRemoteApiUrl: 'http://localhost:8000/v1',
      omlxAvailable: true,
    });
    const banner = container.querySelector('[data-testid="worker-dual-local-banner"]');
    expect(banner?.textContent).toContain('fight over the GPU');
    expect(banner?.textContent).toBe(kWorkerDualLocalMessage);
  });

  it('lists compact host families without an Off row when Different host', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      omlxAvailable: true,
    });
    const different = container.querySelector('[data-testid="side-jobs-different-host"]') as HTMLButtonElement;
    act(() => different.click());
    const labels = [...container.querySelectorAll('[data-testid="side-jobs-host"] option')].map((o) => o.textContent);
    expect(labels).toEqual([
      'Choose a host…',
      'KoboldCpp',
      'OpenRouter',
      'Nano-GPT',
      'LM Studio',
      'oMLX',
      'Custom',
    ]);
    expect(labels).not.toContain('Off — same as chat');
  });

  it('hides oMLX when the host does not offer it', () => {
    render({
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      omlxAvailable: false,
    });
    const different = container.querySelector('[data-testid="side-jobs-different-host"]') as HTMLButtonElement;
    act(() => different.click());
    const labels = [...container.querySelectorAll('[data-testid="side-jobs-host"] option')].map((o) => o.textContent);
    expect(labels).not.toContain('oMLX');
    expect(labels).toContain('KoboldCpp');
    expect(labels).toContain('Custom');
  });
});

describe('workerHostMatchesChat / workerShowsApiKeyField', () => {
  it('treats Nano + Nano as the same host', () => {
    expect(workerHostMatchesChat(
      'openRouter',
      'https://nano-gpt.com/api/v1',
      'openRouter',
      'https://nano-gpt.com/api/v1',
    )).toBe(true);
    expect(workerHostMatchesChat(
      'openRouter',
      'https://nano-gpt.com/api/v1',
      'openRouter',
      'https://openrouter.ai/api/v1',
    )).toBe(false);
  });

  it('hides the second key on the same host', () => {
    expect(workerShowsApiKeyField({
      sameHost: true,
      needsKey: true,
      vaultHasKey: false,
    })).toBe(false);
    expect(workerShowsApiKeyField({
      sameHost: false,
      needsKey: true,
      vaultHasKey: false,
    })).toBe(true);
  });
});
