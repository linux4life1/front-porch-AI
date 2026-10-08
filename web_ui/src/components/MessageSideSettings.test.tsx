// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "My messages on the right": the web switch saves the same setting the
// desktop uses and flips the chat layout at once, and the chat reads the
// saved value when it opens. Left is the default.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const post = vi.fn(async (_url?: string, _body?: unknown) => ({}));
let saved = false;

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: () => Promise.resolve({ realism: { userMessagesOnRight: saved } }),
    post: (url: string, body?: unknown) => post(url, body),
  },
}));

const { MessageSideSettings } = await import('./MessageSideSettings');
const { useUserMessageSide } = await import('../userMessageSide');

let container: HTMLDivElement;
let root: Root;

async function mount(node: ReturnType<typeof createElement>) {
  await act(async () => {
    root.render(node);
    await Promise.resolve();
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  post.mockClear();
  saved = false;
  delete document.documentElement.dataset.userSide;
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function Probe() {
  useUserMessageSide();
  return null;
}

describe('My messages on the right', () => {
  it('is off by default, and switching it on saves it and moves the chat', async () => {
    await mount(createElement(MessageSideSettings));
    const box = container.querySelector<HTMLInputElement>('input[aria-label="My messages on the right"]')!;
    expect(box.checked).toBe(false);

    await act(async () => { box.click(); });

    expect(post).toHaveBeenCalledWith('/api/settings', { realism: { userMessagesOnRight: true } });
    expect(document.documentElement.dataset.userSide).toBe('right');
  });

  it('a save that fails puts the switch and the chat back and says so', async () => {
    post.mockRejectedValueOnce(new Error('offline'));
    await mount(createElement(MessageSideSettings));
    const box = container.querySelector<HTMLInputElement>('input[aria-label="My messages on the right"]')!;

    await act(async () => { box.click(); await Promise.resolve(); });

    expect(box.checked).toBe(false);
    expect(document.documentElement.dataset.userSide).toBe('left');
    expect(container.querySelector('[role="alert"]')?.textContent).toContain('could not be saved');
  });

  it('the chat reads the saved side when it opens', async () => {
    saved = true;
    await mount(createElement(Probe));
    expect(document.documentElement.dataset.userSide).toBe('right');
  });

  it('the chat stays on the left when the setting is off', async () => {
    await mount(createElement(Probe));
    expect(document.documentElement.dataset.userSide).toBe('left');
  });
});
