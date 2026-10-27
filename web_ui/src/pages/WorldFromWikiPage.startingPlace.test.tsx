// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from Wiki / World from Character must give the minted world the
// place its chats start in (web twin of the desktop Review card). With
// Lorebooks off the wizard goes straight to Review with no written places:
// Mint stays off until a starting place is named, and the mint carries it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post, avatarUrl: (p: string) => p },
  ApiError: class extends Error {},
}));
vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

import { WorldFromWikiPage } from './WorldFromWikiPage';

let container: HTMLDivElement;
let root: Root;

const STATUS = {
  available: true,
  toolsAdvertised: true,
  toolsGate: 'ready',
  savedWikis: [],
  depth: 0,
  sources: ['wiki', 'character'],
};

const byId = (id: string) => container.querySelector<HTMLElement>(`[data-testid="${id}"]`);
const buttonLike = (re: RegExp) =>
  Array.from(container.querySelectorAll('button')).find((b) => re.test(b.textContent ?? ''))!;

function type(selector: string, value: string) {
  const el = container.querySelector(selector) as HTMLInputElement;
  act(() => {
    Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set?.call(el, value);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  get.mockImplementation((url: string) => {
    if (url.startsWith('/api/worlds/from-wiki/status')) return Promise.resolve(STATUS);
    if (url === '/api/characters') return Promise.resolve([{ id: 'c1', name: 'Ines Calder', hasAvatar: false }]);
    if (url === '/api/stories/chat-sources') return Promise.resolve({ chats: [] });
    return Promise.resolve({ worlds: [] });
  });
  await act(async () => {
    root.render(
      createElement(MemoryRouter, null, createElement(WorldFromWikiPage, { source: 'character' })),
    );
  });
  await act(async () => {
    await Promise.resolve();
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('Where chats start in World from Character', () => {
  it('Mint waits for a starting place, and the mint carries it', async () => {
    await act(async () => byId('world-character-pick-c1')!.click());
    const lorebooks = Array.from(container.querySelectorAll('label'))
      .find((l) => (l.textContent ?? '').includes('Lorebooks'))!
      .querySelector('input') as HTMLInputElement;
    await act(async () => lorebooks.click());
    await act(async () => buttonLike(/Next: Review/).click());

    expect(byId('world-starting-place')).not.toBeNull();
    const mint = byId('world-from-wiki-mint') as HTMLButtonElement;
    type('.cg-config label input', 'Calder Isle');
    expect(mint.disabled).toBe(true);
    expect(byId('world-starting-place')?.textContent).toContain(
      'Name the place where chats in this world start.',
    );

    type('input[aria-label="Starting place"]', 'The Clinic');
    expect((byId('world-from-wiki-mint') as HTMLButtonElement).disabled).toBe(false);

    post.mockResolvedValue({ worlds: [] });
    await act(async () => (byId('world-from-wiki-mint') as HTMLButtonElement).click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({
        name: 'Calder Isle',
        create: true,
        startingPlace: { name: 'The Clinic', description: '' },
      }),
    );
  });
});
