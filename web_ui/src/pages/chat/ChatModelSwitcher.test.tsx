// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// In-chat model chip: shows the current model (or the backend, when there is
// no model list), saves through POST /api/settings like Settings, and the
// sheet closes on Escape, the phone back gesture, and Close.

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

interface Snap {
  backend: string;
  remoteApiUrl: string;
  remoteModelName: string;
  loadedModel?: string;
  remoteApiUrlsWithKeys?: string[];
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
    ...over,
  };
}

const models = {
  models: [{ id: 'glm-5', name: 'GLM 5', pricing: '', free: true }],
};

async function flushHistory() {
  for (let i = 0; i < 4; i++) {
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
  }
}

async function renderSwitcher() {
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(ChatModelSwitcher)));
  });
  await act(async () => {
    await Promise.resolve();
  });
}

function chip(): HTMLButtonElement {
  return container.querySelector('.model-switch-chip') as HTMLButtonElement;
}

function dialog(): HTMLElement | null {
  return container.querySelector('[role="dialog"]');
}

async function openSheet() {
  await act(async () => {
    chip().click();
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  get.mockReset();
  post.mockReset();
  get.mockResolvedValue(snap());
  post.mockImplementation(async (path: string, body?: unknown) => {
    if (path === '/api/backend/remote-models') return models;
    const name = (body as { remoteModelName?: string } | undefined)?.remoteModelName ?? '';
    return snap({ remoteModelName: name });
  });
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(async () => {
  await act(async () => root.unmount());
  await flushHistory();
  container.remove();
  vi.restoreAllMocks();
});

describe('ChatModelSwitcher', () => {
  it('shows the current model and saves it through POST /api/settings', async () => {
    await renderSwitcher();
    expect(chip().textContent).toContain('alpha-model');

    await openSheet();
    await act(async () => {
      await new Promise((r) => setTimeout(r, 500));
    });
    await act(async () => {
      (container.querySelector('.model-picker-trigger') as HTMLButtonElement).click();
    });
    const option = [...container.querySelectorAll('.mp-option')].find((el) =>
      el.textContent?.includes('GLM 5'),
    ) as HTMLButtonElement;
    expect(option).toBeTruthy();

    await act(async () => {
      option.click();
      await new Promise((r) => setTimeout(r, 0));
    });

    expect(post).toHaveBeenCalledWith('/api/settings', { remoteModelName: 'glm-5' });
    expect(dialog()).toBeNull();
    expect(chip().textContent).toContain('glm-5');
  });

  it('links to Settings when the backend has no model picker', async () => {
    get.mockResolvedValue(snap({ backend: 'kobold', remoteModelName: '', loadedModel: 'mistral.gguf' }));
    await renderSwitcher();
    expect(chip().textContent).toContain('KoboldCpp');
    expect(chip().textContent).not.toContain('mistral.gguf');

    await openSheet();
    expect(container.querySelector('.model-picker')).toBeNull();
    const link = container.querySelector('a.model-switch-settings') as HTMLAnchorElement;
    expect(link).toBeTruthy();
    expect(link.getAttribute('href')).toBe('/settings');
    expect(link.textContent).toContain('Open Settings');
  });

  it('tells the user and links to Settings when saving needs a step-up', async () => {
    post.mockImplementation(async (path: string) => {
      if (path === '/api/backend/remote-models') return models;
      throw new ApiError(401, 'Password required', { totpRequired: true });
    });
    await renderSwitcher();
    await openSheet();
    await act(async () => {
      await new Promise((r) => setTimeout(r, 500));
    });
    await act(async () => {
      (container.querySelector('.model-picker-trigger') as HTMLButtonElement).click();
    });
    const option = container.querySelector('.mp-option') as HTMLButtonElement;
    await act(async () => {
      option.click();
      await new Promise((r) => setTimeout(r, 0));
    });

    expect(dialog()).not.toBeNull();
    expect(container.querySelector('[role="alert"]')?.textContent).toContain('web login');
    expect(container.querySelector('[role="alert"] a')?.getAttribute('href')).toBe('/settings');
  });

  it('closes on Escape, popstate, and Close', async () => {
    await renderSwitcher();
    await openSheet();
    expect(window.history.state.fpModelSwitch).toBe('open');

    await act(async () => {
      window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape' }));
    });
    await flushHistory();
    expect(dialog()).toBeNull();

    await openSheet();
    await act(async () => {
      window.history.back();
    });
    await flushHistory();
    expect(dialog()).toBeNull();

    await openSheet();
    const close = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Close');
    await act(async () => {
      close!.click();
    });
    await flushHistory();
    expect(dialog()).toBeNull();
    expect(window.history.state?.fpModelSwitch).not.toBe('open');
  });

  it('pins the phone sheet with safe-area padding, not a 100dvh box', () => {
    const css = readFileSync(join(__dirname, '../../styles/chat.css'), 'utf8').replace(
      /\/\*[\s\S]*?\*\//g,
      '',
    );
    expect(css).not.toMatch(/model-switch[\w-]*[^{]*\{[^}]*100dvh/);
    expect(css).toMatch(
      /\[data-layout="phone"\]\s+\.drawer-backdrop\.model-switch-overlay\s*\{[^}]*align-items:\s*flex-start/,
    );
    expect(css).toMatch(/height:\s*var\(--fp-vvh,\s*100%\)/);
    expect(css).toMatch(/var\(--fp-safe-top,\s*env\(safe-area-inset-top\)\)/);
    expect(css).toMatch(/var\(--fp-safe-bottom,\s*env\(safe-area-inset-bottom\)\)/);
    expect(css).toMatch(/var\(--fp-safe-left,\s*env\(safe-area-inset-left\)\)/);
    expect(css).toMatch(/var\(--fp-safe-right,\s*env\(safe-area-inset-right\)\)/);
  });

  it('switches provider with the password step-up and saves the new model', async () => {
    get.mockResolvedValue(
      snap({ remoteApiUrlsWithKeys: ['https://nano-gpt.com/api/v1'] }),
    );
    await renderSwitcher();
    await openSheet();
    const select = container.querySelector('.model-switch-provider select') as HTMLSelectElement;
    expect(select.value).toBe('openrouter');
    await act(async () => {
      select.value = 'nanogpt';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    const pw = container.querySelector('input[type="password"]') as HTMLInputElement;
    expect(pw).toBeTruthy();
    await act(async () => {
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      setter.call(pw, 'hunter2');
      pw.dispatchEvent(new Event('input', { bubbles: true }));
    });
    await act(async () => {
      await new Promise((r) => setTimeout(r, 500));
    });
    expect(post).toHaveBeenCalledWith(
      '/api/backend/remote-models',
      expect.objectContaining({ apiUrl: 'https://nano-gpt.com/api/v1', currentPassword: 'hunter2' }),
    );
    await act(async () => {
      (container.querySelector('.model-picker-trigger') as HTMLButtonElement).click();
    });
    await act(async () => {
      (container.querySelector('.mp-option') as HTMLButtonElement).click();
      await new Promise((r) => setTimeout(r, 0));
    });
    expect(post).toHaveBeenCalledWith('/api/settings', {
      remoteModelName: 'glm-5',
      backend: 'openRouter',
      remoteApiUrl: 'https://nano-gpt.com/api/v1',
      currentPassword: 'hunter2',
    });
    expect(dialog()).toBeNull();
  });

  it('switches to KoboldCpp without a password', async () => {
    await renderSwitcher();
    await openSheet();
    const select = container.querySelector('.model-switch-provider select') as HTMLSelectElement;
    await act(async () => {
      select.value = 'kobold';
      select.dispatchEvent(new Event('change', { bubbles: true }));
    });
    expect(container.querySelector('input[type="password"]')).toBeNull();
    const btn = [...container.querySelectorAll('button')].find((b) =>
      b.textContent?.includes('Switch to KoboldCpp'),
    ) as HTMLButtonElement;
    await act(async () => {
      btn.click();
      await new Promise((r) => setTimeout(r, 0));
    });
    expect(post).toHaveBeenCalledWith('/api/settings', { backend: 'kobold' });
  });

  it('lays the model list out inside the sheet, not as a clipped dropdown', () => {
    const css = readFileSync(join(__dirname, '../../styles/chat.css'), 'utf8').replace(
      /\/\*[\s\S]*?\*\//g,
      '',
    );
    expect(css).toMatch(/\.model-switch-body\s+\.model-picker-menu\s*\{[^}]*position:\s*static/);
    expect(css).toMatch(/\.model-switch-body\s*\{[^}]*flex:\s*1/);
  });

  it('lists the current provider from its saved URL (localhost previews are refused)', async () => {
    get.mockResolvedValue(snap({ remoteApiUrl: 'http://127.0.0.1:1234/v1' }));
    await renderSwitcher();
    await openSheet();
    await act(async () => {
      await new Promise((r) => setTimeout(r, 500));
    });
    const call = post.mock.calls.find(([path]) => path === '/api/backend/remote-models');
    expect(call).toBeTruthy();
    expect(call![1]).toEqual({});
    expect(container.querySelector('input[type="password"]')).toBeNull();
  });
});
