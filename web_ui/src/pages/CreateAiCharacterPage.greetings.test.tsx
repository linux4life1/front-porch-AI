// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// When a character is saved, the web creator moves straight onto its
// Greetings step (#370). The id used to come only from the URL, which the
// router updates as a transition, after the step change: one render could
// show the Greetings step with no character ("Generate a character first").
// Every node React adds while chargen_done lands is recorded, so a render
// that a later commit replaced is still caught.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { WsEvent } from '../api/ws';

const listeners: ((e: WsEvent) => void)[] = [];
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    constructor(cb: (e: WsEvent) => void) {
      listeners.push(cb);
    }
    connect() {}
    close() {}
  },
}));

vi.mock('../api/client', () => ({
  api: {
    get: async (path: string) => {
      if (path === '/api/chargen/status') return { available: true };
      if (path.includes('/detail')) return { firstMessage: '*The lamp turns.*', alternateGreetings: [] };
      return { writing: null };
    },
    post: async () => ({}),
  },
  ApiError: class ApiError extends Error {},
}));

const { CreateAiCharacterPage } = await import('./CreateAiCharacterPage');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  listeners.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root.render(
      createElement(
        MemoryRouter,
        { initialEntries: ['/create-ai'] },
        createElement(
          Routes,
          null,
          createElement(Route, { path: '/create-ai', element: createElement(CreateAiCharacterPage) }),
        ),
      ),
    );
  });
  await act(async () => {});
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

it('a saved character opens on its greetings, never on "Generate a character first"', async () => {
  const added: Node[] = [];
  const watch = new MutationObserver((records) => {
    for (const r of records) added.push(...Array.from(r.addedNodes));
  });
  watch.observe(container, { subtree: true, childList: true, characterData: true });

  await act(async () => {
    for (const l of listeners) l({ event: 'chargen_done', id: 7, name: 'Aria Vale' });
  });
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
  for (const r of watch.takeRecords()) added.push(...Array.from(r.addedNodes));
  watch.disconnect();

  const flashed = added.some((n) => (n.textContent ?? '').includes('Generate a character first'));
  expect(flashed, 'no render showed the step without its character').toBe(false);
  expect(container.querySelector('[data-testid="greetings-step"]')).not.toBeNull();
  expect(container.textContent).toContain('Open in editor');
});

it('a paused create opens on its profile; Next writes the rest, then the greetings', async () => {
  const added: Node[] = [];
  const watch = new MutationObserver((records) => {
    for (const r of records) added.push(...Array.from(r.addedNodes));
  });
  watch.observe(container, { subtree: true, childList: true, characterData: true });
  const said = (text: string) => added.some((n) => (n.textContent ?? '').includes(text));

  await act(async () => {
    for (const l of listeners) {
      l({
        event: 'chargen_profile',
        name: 'Aria Vale',
        description: '{{char}} keeps the light.',
        personality: 'Dry and patient.',
        scenario: 'A storm.',
        facts: { occupation: 'lighthouse keeper' },
      });
    }
  });
  expect(container.querySelector('[data-testid="profile-step"]')).not.toBeNull();
  expect(said('its profile opens here'), 'no render showed the step without its profile').toBe(false);

  const next = Array.from(container.querySelectorAll('button')).find((b) =>
    (b.textContent ?? '').includes('Next: Greetings'),
  )!;
  await act(async () => {
    next.click();
  });
  // The Generate screen again while the rest is written.
  expect(container.textContent).toContain('Generating…');
  expect(container.querySelector('[data-testid="profile-step"]')).toBeNull();

  await act(async () => {
    for (const l of listeners) l({ event: 'chargen_done', id: 7, name: 'Aria Vale' });
  });
  await act(async () => {
    await new Promise((r) => setTimeout(r, 0));
  });
  for (const r of watch.takeRecords()) added.push(...Array.from(r.addedNodes));
  watch.disconnect();
  expect(said('Generate a character first'), 'no render showed a step without its character').toBe(false);
  expect(container.querySelector('[data-testid="greetings-step"]')).not.toBeNull();
});
