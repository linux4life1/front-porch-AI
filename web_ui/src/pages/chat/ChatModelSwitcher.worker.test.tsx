// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Model sheet's Realism evals lane (docs/design/one-chat-ux.md PR 6):
// the worker card mounts with the desktop's compact sentence and host chips
// (xAI included), live-saves through POST /api/settings with worker keys
// only, and holds credential-grade picks (a new helper URL) until the web
// login password is entered — the gate settings_routes.dart enforces.
// The save is one debounced scheduler: a keystroke burst posts once with
// the final values (the login limiter must not see partial passwords), and
// a pick landing while a save is in flight survives to save next.

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
const { ApiError } = await import('../../api/client');

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

/** Beyond the lane's 350 ms save debounce. */
async function settle(ms = 450) {
  await act(async () => {
    await new Promise((r) => setTimeout(r, ms));
  });
}

async function flush() {
  for (let i = 0; i < 4; i++) {
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
  }
  await settle();
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

function pwInput(): HTMLInputElement | null {
  const label = [...container.querySelectorAll('label')].find((l) =>
    l.textContent?.includes('Web login password'),
  );
  return (label?.querySelector('input[type="password"]') as HTMLInputElement) ?? null;
}

async function typeInto(input: HTMLInputElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  await act(async () => {
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function typePassword(value: string) {
  const pw = pwInput();
  expect(pw).toBeTruthy();
  await typeInto(pw!, value);
  await settle();
}

function settingsBodies(): Record<string, unknown>[] {
  return post.mock.calls
    .filter(([path]) => path === '/api/settings')
    .map(([, body]) => body as Record<string, unknown>);
}

function lastSettingsPost(): Record<string, unknown> | null {
  return settingsBodies().pop() ?? null;
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
  vi.useRealTimers();
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
    expect(pwInput()).toBeTruthy();
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

  it('types the password key by key and posts once, with the whole password', async () => {
    // The login limiter doubles on every failed password: a POST per
    // keystroke would lock the account out mid-typing (review of PR 6).
    vi.useFakeTimers();
    const later = async (ms = 80) => {
      await act(async () => {
        await vi.advanceTimersByTimeAsync(ms);
      });
    };
    await act(async () => {
      root.render(createElement(MemoryRouter, null, createElement(ChatModelSwitcher)));
    });
    await later();
    await act(async () => {
      (container.querySelector('.model-switch-chip') as HTMLButtonElement).click();
    });
    await later();
    clickTestId('[data-testid="side-jobs-different-host"]');
    clickTestId('[data-testid="side-jobs-host"] [data-testid="provider-chip-nanogpt"]');
    await later();
    const pw = pwInput();
    expect(pw).toBeTruthy();
    for (const ch of 'hunter2') {
      await typeInto(pw!, pw.value + ch);
      await later(60); // each key restarts the debounce; none may post
      expect(settingsBodies()).toHaveLength(0);
    }
    await later(600);
    const bodies = settingsBodies();
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).toMatchObject({
      workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
      currentPassword: 'hunter2',
    });
  });

  it('keeps a pick made during an in-flight save and saves it on a second confirm', async () => {
    await renderSwitcher();
    await openSheet();
    clickTestId('[data-testid="side-jobs-different-host"]');
    clickTestId('[data-testid="side-jobs-host"] [data-testid="provider-chip-nanogpt"]');
    // Hold the first settings POST open, like a slow server.
    let resolveFirst: ((v: unknown) => void) | undefined;
    const base = post.getMockImplementation()!;
    let hold = true;
    post.mockImplementation((path: string, body?: unknown) => {
      if (path === '/api/settings' && hold) {
        hold = false;
        return new Promise((res) => {
          resolveFirst = res;
        });
      }
      return base(path, body) as Promise<unknown>;
    });
    await typePassword('hunter2'); // the held POST is now in flight
    expect(resolveFirst).toBeTruthy();
    // Switch the helper host while that save is in flight.
    clickTestId('[data-testid="side-jobs-host"] [data-testid="provider-chip-xai"]');
    await act(async () => {
      resolveFirst?.(
        snap({
          workerBackend: 'openRouter',
          workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
          workerRemoteModelName: 'glm-5',
        }),
      );
    });
    await settle();
    // The xAI pick is credential-grade and the password was consumed by the
    // first save: step-up asks again, and the pick survived the flight.
    expect(pwInput()).toBeTruthy();
    await typePassword('hunter3');
    const xaiPost = settingsBodies().find(
      (b) => b.workerRemoteApiUrl === 'https://api.x.ai/v1',
    );
    // Only the delta needs re-sending: workerBackend was persisted by the
    // first save, so the second POST carries the URL change and password.
    expect(xaiPost).toMatchObject({
      workerRemoteApiUrl: 'https://api.x.ai/v1',
      currentPassword: 'hunter3',
    });
  });

  it('a failed save stops: the same payload never re-sends itself unasked', async () => {
    // The login limiter counts every failed step-up; a retry loop over the
    // same wrong password would lock the account out in seconds.
    post.mockImplementation(async (path: string, body?: unknown) => {
      if (path === '/api/backend/remote-models') {
        return { models: [{ id: 'glm-5', name: 'GLM 5', pricing: '', free: true }] };
      }
      throw new ApiError(401, 'Current password is incorrect');
    });
    await renderSwitcher();
    await openSheet();
    clickTestId('[data-testid="side-jobs-different-host"]');
    clickTestId('[data-testid="side-jobs-host"] [data-testid="provider-chip-nanogpt"]');
    await typePassword('wrong1');
    // Well past the debounce: a retry loop would have fired several by now.
    await settle(900);
    const bodies = settingsBodies();
    expect(bodies).toHaveLength(1);
    expect(bodies[0]).toMatchObject({ currentPassword: 'wrong1' });
    expect(container.textContent).toContain('Current password is incorrect');
    expect(container.textContent).toContain('Retry');
    // An edit moves it again: the corrected password posts once more.
    await typeInto(pwInput()!, 'right1');
    await settle();
    const after = settingsBodies();
    expect(after).toHaveLength(2);
    expect(after[1]).toMatchObject({ currentPassword: 'right1' });
  });

  it('a two-factor challenge takes the typed code and posts it with the login', async () => {
    let first = true;
    post.mockImplementation(async (path: string, body?: unknown) => {
      if (path === '/api/backend/remote-models') {
        return { models: [{ id: 'glm-5', name: 'GLM 5', pricing: '', free: true }] };
      }
      if (path === '/api/settings' && first) {
        first = false;
        throw new ApiError(401, 'Two-factor code required', { totpRequired: true });
      }
      return snap({ ...(body as Partial<Snap>) });
    });
    await renderSwitcher();
    await openSheet();
    clickTestId('[data-testid="side-jobs-different-host"]');
    clickTestId('[data-testid="side-jobs-host"] [data-testid="provider-chip-nanogpt"]');
    await typePassword('hunter2');
    // The 401 asks for the code; typing it must arm a send (it is part of
    // the payload the scheduler compares against the failed one).
    const totp = container.querySelector('input[inputmode="numeric"]') as HTMLInputElement;
    expect(totp).toBeTruthy();
    await typeInto(totp, '123456');
    await settle();
    const bodies = settingsBodies();
    expect(bodies).toHaveLength(2);
    expect(bodies[1]).toMatchObject({
      workerRemoteApiUrl: 'https://nano-gpt.com/api/v1',
      currentPassword: 'hunter2',
      totpCode: '123456',
    });
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
    await settle();
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
