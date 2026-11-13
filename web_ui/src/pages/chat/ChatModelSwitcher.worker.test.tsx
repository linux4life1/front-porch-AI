// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Model sheet's Realism evals lane (docs/design/one-chat-ux.md PR 6):
// the worker card mounts with the desktop's compact sentence and host chips
// (xAI included), live-saves through POST /api/settings with worker keys
// only, and holds credential-grade picks (a new helper URL) until the web
// login password is entered — the gate settings_routes.dart enforces.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

interface Snap {
  backend: string;
  remoteApiUrl: string;
  remoteModelName: string;
  remoteApiUrlsWithKeys?: string[];
  workerBackend?: string;
  workerRemoteApiUrl?: string;
  workerRemoteModelName?: string;
}

const get = vi.fn<(path: string) => Promise<unknown>>();
const post = vi.fn<(path: string, body?: unknown) => Promise<unknown>>();

vi.mock('../../api/client', () => ({
  api: {
    get: (path: string) => get(path),
    post: (path: string, body?: unknown) => post(path, body),
  },
  ApiError: class ApiError extends Error {
    status: number;
    payload: Record<string, unknown>;
    constructor(status: number, message: string, payload: Record<string, unknown> = {}) {
      super(message);
      this.status = status;
      this.payload = payload;
    }
  },
}));

const { ChatModelSwitcher } = await import('./ChatModelSwitcher');

let container: HTMLDivElement;
let root: Root;

function snap(over: Partial<Snap> = {}): Snap {
  return {
    backend: 'openRouter',
    remoteApiUrl: 'https://openrouter.ai/api/v1',
    remoteModelName: 'alpha-model',
    workerBackend: '',
    workerRemoteApiUrl: '',
    workerRemoteModelName: '',
    ...over,
  };
}

async function flush() {
  for (let i = 0; i < 5; i++) {
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
  }
}

async function renderSwitcher() {
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(ChatModelSwitcher)));
  });
  await flush();
}

async function openSheet() {
  await act(async () => {
    (container.querySelector('.model-switch-chip') as HTMLButtonElement).click();
  });
  await flush();
}

function clickTestId(selector: string) {
  const el = container.querySelector(selector) as HTMLButtonElement;
  act(() => {
    el.click();
  });
}

async function typePassword(value: string) {
  const label = [...container.querySelectorAll('label')].find((l) =>
    l.textContent?.includes('Web login password'),
  );
  const pw = label?.querySelector('input[type="password"]') as HTMLInputElement;
  expect(pw).toBeTruthy();
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(pw, value);
    pw.dispatchEvent(new Event('input', { bubbles: true }));
  });
  await flush();
}

/** The worker keys of the last POST to /api/settings, or null. */
function lastSettingsPost(): Record<string, unknown> | null {
  const call = post.mock.calls
    .filter(([path]) => path === '/api/settings')
    .pop();
  return (call?.[1] as Record<string, unknown>) ?? null;
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  get.mockReset();
  post.mockReset();
  get.mockResolvedValue(snap());
  post.mockImplementation(async (path: string, body?: unknown) => {
    if (path === '/api/backend/remote-models') {
      return { models: [{ id: 'glm-5', name: 'GLM 5', pricing: '', free: true }] };
    }
    const applied = (body ?? {}) as Partial<Snap>;
    return snap({
      ...applied,
      backend: applied.backend ?? 'openRouter',
      remoteApiUrl: applied.remoteApiUrl ?? 'https://openrouter.ai/api/v1',
      remoteModelName: applied.remoteModelName ?? 'alpha-model',
    });
  });
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => root.unmount());
  await flush();
  container.remove();
  vi.restoreAllMocks();
});

describe('ChatModelSwitcher worker lane', () => {
  it('mounts the Realism evals section with the compact sentence and xAI chip', async () => {
    await renderSwitcher();
    await openSheet();
    expect(container.querySelector('[data-testid="side-jobs-card"]')).not.toBeNull();
    expect(container.textContent).toContain(
      'Feelings, wiki/web, journal, and growth can use another host. Chat speech stays above.',
    );
    expect(container.textContent).not.toContain('Two local engines');
    clickTestId('[data-testid="side-jobs-different-host"]');
    const labels = [
      ...container.querySelectorAll('[data-testid="side-jobs-host"] .provider-chip'),
    ].map((b) => b.textContent);
    expect(labels).toContain('xAI');
    expect(labels).toContain('Nano-GPT');
  });

  it('holds a new helper host until the web login password, then saves worker keys only', async () => {
    await renderSwitcher();
    await openSheet();
    clickTestId('[data-testid="side-jobs-different-host"]');
    clickTestId(
      '[data-testid="side-jobs-host"] [data-testid="provider-chip-nanogpt"]',
    );
    // Credential-grade (helper URL changed): nothing posted yet, step-up shown.
    expect(lastSettingsPost()).toBeNull();
    await typePassword('hunter2');
    const body = lastSettingsPost();
    expect(body).toMatchObject({
      workerBackend: 'openRouter',
      workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
      currentPassword: 'hunter2',
    });
    // Worker keys only: the chat lane fields stay out of the POST.
    expect(body && 'remoteModelName' in body).toBe(false);
    expect(body && 'remoteApiUrl' in body).toBe(false);
    // The sheet stays open for the model pick.
    expect(container.querySelector('[role="dialog"]')).not.toBeNull();
  });

  it('saves Same as chat without a password', async () => {
    get.mockResolvedValue(
      snap({
        workerBackend: 'openRouter',
        workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
        workerRemoteModelName: 'glm-5',
      }),
    );
    await renderSwitcher();
    await openSheet();
    clickTestId('[data-testid="side-jobs-same-as-chat"]');
    expect(lastSettingsPost()).toMatchObject({ workerBackend: '' });
    expect(container.querySelector('[role="dialog"]')).not.toBeNull();
  });

  it('uses the saved xAI key: no second key field, the saved-key hint instead', async () => {
    get.mockResolvedValue(
      snap({
        workerBackend: 'openRouter',
        workerRemoteApiUrl: 'https://api.x.ai/v1',
        workerRemoteModelName: 'grok-4',
        remoteApiUrlsWithKeys: ['https://api.x.ai/v1'],
      }),
    );
    await renderSwitcher();
    await openSheet();
    expect(container.querySelector('[data-testid="side-jobs-worker-key"]')).toBeNull();
    expect(container.querySelector('[data-testid="side-jobs-saved-key-hint"]')?.textContent)
      .toContain('saved key');
  });
});
