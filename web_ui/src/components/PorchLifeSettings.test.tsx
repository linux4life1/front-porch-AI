// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The browser must never receive the stored Tavily key, and typing a
// replacement must not persist partial secrets one keystroke at a time.
//
// Guard proven red before passing: the old onChange writer POSTed immediately.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async (_url?: string, _body?: unknown) => ({}));

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () =>
      Promise.resolve({
        realism: { webSearchDefault: true, hasSearchApiKey: false },
      }),
    post: (url: string, body?: unknown) => post(url, body),
  },
}));

const { PorchLifeSettings } = await import('./PorchLifeSettings');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean })
    .IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  post.mockClear();
  await act(async () => {
    root.render(createElement(PorchLifeSettings));
    await Promise.resolve();
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Porch Life web-search key', () => {
  it('persists the complete key only when Save is pressed', async () => {
    const input = container.querySelector(
      'input[placeholder="Paste key"]',
    ) as HTMLInputElement;
    expect(input).toBeTruthy();
    act(() => {
      const setter = Object.getOwnPropertyDescriptor(
        HTMLInputElement.prototype,
        'value',
      )!.set!;
      setter.call(input, 'tavily-complete-key');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(post).not.toHaveBeenCalled();

    const save = [...container.querySelectorAll('button')].find(
      (button) => button.textContent === 'Save key',
    );
    expect(save).toBeTruthy();
    await act(async () => {
      save!.click();
      await Promise.resolve();
    });

    expect(post).toHaveBeenCalledTimes(1);
    expect(post).toHaveBeenCalledWith('/api/settings', {
      realism: { searchApiKey: 'tavily-complete-key' },
    });
    expect(container.textContent).toContain('Tavily key saved securely.');
  });
});
