// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's existing-chats question (desktop parity: Porch Life's
// Afterglow switch). Turning Afterglow on asks about the chats that have it
// off; Done changes nothing unless its switch was flipped.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posts: { path: string; body: unknown }[] = [];
let count = 2;

vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    get: async (path: string) =>
      path.startsWith('/api/settings/existing-chats')
        ? { count }
        : { realism: { realismDefault: true, adultThemesEnabled: true, nsfwCooldownDefault: false } },
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
  count = 2;
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

const flush = () =>
  act(async () => {
    for (let i = 0; i < 5; i++) await Promise.resolve();
  });

async function turnAfterglowOn() {
  const sw = container.querySelector<HTMLInputElement>('input[aria-label="Afterglow"]')!;
  await act(async () => {
    sw.click();
  });
  await flush();
}

const dialog = () => container.querySelector('[role="dialog"][aria-label="Afterglow is on"]');
const done = () =>
  [...container.querySelectorAll<HTMLButtonElement>('[role="dialog"] button')].find((b) => b.textContent === 'Done')!;

it('asks about the chats that have Afterglow off, and Done with its switch on turns it on in them', async () => {
  await turnAfterglowOn();
  expect(dialog()).not.toBeNull();
  expect(dialog()!.textContent).toContain('Turn it on in those 2 chats too');

  const offerSwitch = dialog()!.querySelector<HTMLInputElement>('input[type="checkbox"]')!;
  expect(offerSwitch.checked, 'starts off').toBe(false);
  await act(async () => {
    offerSwitch.click();
  });
  await act(async () => {
    done().click();
  });
  await flush();
  expect(posts.filter((p) => p.path === '/api/settings/existing-chats')).toEqual([
    { path: '/api/settings/existing-chats', body: { feature: 'afterglow' } },
  ]);
  expect(dialog(), 'Done closes it').toBeNull();
});

it('Done with the switch left off changes nothing', async () => {
  await turnAfterglowOn();
  await act(async () => {
    done().click();
  });
  await flush();
  expect(posts.filter((p) => p.path === '/api/settings/existing-chats')).toHaveLength(0);
  expect(dialog()).toBeNull();
});

it('asks nothing when every chat already has it on', async () => {
  count = 0;
  await turnAfterglowOn();
  expect(dialog()).toBeNull();
});
