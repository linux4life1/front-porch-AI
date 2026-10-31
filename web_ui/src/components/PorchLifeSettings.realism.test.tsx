// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Porch Life's Realism Engine row is the permission (desktop parity: the
// Porch Life engine card). "Start every new chat with Realism" sits under it
// and keeps the old realismDefault switch. Turning the engine back on asks
// the existing-chats question; Needs and Afterglow grey out under it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posts: { path: string; body: unknown }[] = [];
const gets: string[] = [];
let realism: Record<string, unknown> = {};

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: async (path: string) =>
      gets.push(path) && path.startsWith('/api/settings/existing-chats') ? { count: 3 } : { realism },
    post: async (path: string, body: unknown) => {
      posts.push({ path, body });
      return {};
    },
  },
}));

const { PorchLifeSettings } = await import('./PorchLifeSettings');

let container: HTMLDivElement;
let root: Root;

async function mount() {
  await act(async () => {
    root.render(createElement(PorchLifeSettings));
    await Promise.resolve();
  });
}

async function flush() {
  await act(async () => {
    for (let i = 0; i < 5; i++) await Promise.resolve();
  });
}

const input = (label: string) => container.querySelector<HTMLInputElement>(`input[aria-label="${label}"]`);

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  gets.length = 0;
  realism = {};
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('an older desktop that sends no permission reads as allowed: the engine is on and Needs is live', async () => {
  realism = { realismDefault: false, needsSimDefault: true };
  await mount();
  expect(input('Realism Engine')!.checked).toBe(true);
  expect(input('Needs')!.disabled).toBe(false);
  expect(input('Start every new chat with Realism')!.checked).toBe(false);
});

it('"Start every new chat with Realism" writes the old default, not the permission', async () => {
  realism = { realismAllowed: true, realismDefault: false };
  await mount();
  await act(async () => {
    input('Start every new chat with Realism')!.click();
  });
  expect(posts).toEqual([{ path: '/api/settings', body: { realism: { realismDefault: true } } }]);
});

it('blocked: Needs greys out under the engine, and turning it on asks nothing about Needs', async () => {
  realism = { realismAllowed: false, needsSimDefault: false };
  await mount();
  expect(input('Needs')!.disabled).toBe(true);
  expect(input('Start every new chat with Realism')).toBeNull();
});

it('turning the engine back on asks about the chats that have Realism off, and Done with its switch on turns them on', async () => {
  realism = { realismAllowed: false, realismDefault: false };
  await mount();
  await act(async () => {
    input('Realism Engine')!.click();
  });
  await flush();
  expect(posts[0]).toEqual({ path: '/api/settings', body: { realism: { realismAllowed: true } } });
  expect(gets).toContain('/api/settings/existing-chats?feature=realism');
  const dialog = container.querySelector('[role="dialog"][aria-label="Realism is on"]');
  expect(dialog).not.toBeNull();
  expect(dialog!.textContent).toContain('Turn it on in those 3 chats too');
  expect(dialog!.textContent).toContain('Start every new chat with Realism');
  await act(async () => {
    dialog!.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click();
  });
  await act(async () => {
    [...dialog!.querySelectorAll('button')].find((b) => b.textContent === 'Done')!.click();
  });
  expect(posts.filter((p) => p.path === '/api/settings/existing-chats')).toEqual([
    { path: '/api/settings/existing-chats', body: { feature: 'realism' } },
  ]);
});

it('turning the engine off asks nothing', async () => {
  realism = { realismAllowed: true };
  await mount();
  await act(async () => {
    input('Realism Engine')!.click();
  });
  await flush();
  expect(posts).toEqual([{ path: '/api/settings', body: { realism: { realismAllowed: false } } }]);
  expect(gets.filter((g) => g.startsWith('/api/settings/existing-chats'))).toEqual([]);
});
