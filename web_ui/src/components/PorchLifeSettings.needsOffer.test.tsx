// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Turning Porch Life's Needs on asks the same existing-chats question as
// Afterglow (desktop parity: the Porch Life engine card's Needs row).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posts: { path: string; body: unknown }[] = [];
const gets: string[] = [];

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: async (path: string) =>
      gets.push(path) && path.startsWith('/api/settings/existing-chats')
        ? { count: 4 }
        : { realism: { realismDefault: true, needsSimDefault: false } },
    post: async (path: string, body: unknown) => {
      posts.push({ path, body });
      return {};
    },
  },
}));

const { PorchLifeSettings } = await import('./PorchLifeSettings');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  gets.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(createElement(PorchLifeSettings));
    await Promise.resolve();
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('turning Needs on asks about the chats that have it off, and Done with its switch on turns them on', async () => {
  const sw = container.querySelector<HTMLInputElement>('input[aria-label="Needs"]')!;
  await act(async () => {
    sw.click();
  });
  await act(async () => {
    for (let i = 0; i < 5; i++) await Promise.resolve();
  });
  expect(gets).toContain('/api/settings/existing-chats?feature=needs');
  const dialog = container.querySelector('[role="dialog"][aria-label="Needs is on"]');
  expect(dialog).not.toBeNull();
  expect(dialog!.textContent).toContain('Turn it on in those 4 chats too');
  await act(async () => {
    dialog!.querySelector<HTMLInputElement>('input[type="checkbox"]')!.click();
  });
  await act(async () => {
    [...dialog!.querySelectorAll('button')].find((b) => b.textContent === 'Done')!.click();
  });
  expect(posts.filter((p) => p.path === '/api/settings/existing-chats')).toEqual([
    { path: '/api/settings/existing-chats', body: { feature: 'needs' } },
  ]);
});
