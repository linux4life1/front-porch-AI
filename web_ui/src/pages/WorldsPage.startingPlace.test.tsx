// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Where chats in a world start, chosen in the Worlds menu (web twin of the
// desktop library star and editor section):
//   - a place inside a world shows ☆; tapping it posts the star and the
//     world's card says "Chats start at <place>"; the starred place stays
//     starred when tapped (every world keeps one);
//   - a world with places but no start asks for one on its card;
//   - a new top-level world cannot be saved without naming its starting
//     place, and the save carries it;
//   - editing a world picks among its places, preselected from the relay.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post },
  ApiError: class extends Error {},
}));
vi.mock('../components/ClimateSeasonEditor', () => ({ ClimateSeasonEditor: () => null }));
vi.mock('../components/LoreEntriesEditor', () => ({ LoreEntriesEditor: () => null }));
vi.mock('../components/ImportCharacterLoreButton', () => ({
  ImportCharacterLoreButton: () => null,
}));

import { WorldsPage } from './WorldsPage';

let container: HTMLDivElement;
let root: Root;

const TOWN = {
  id: 'town-1',
  name: 'Bletchfield',
  description: 'A town',
  entryCount: 1,
  climateEnabled: true,
  biomeId: 'temperate',
};
const TEA = {
  id: 'tea-1',
  name: 'Tea Rooms',
  description: 'Steam and gossip',
  entryCount: 0,
  climateEnabled: false,
  parentWorldId: 'town-1',
};
const HALL = {
  id: 'hall-1',
  name: 'Town Hall',
  description: 'Records',
  entryCount: 0,
  climateEnabled: false,
  parentWorldId: 'town-1',
};

const starOf = (name: string) =>
  container.querySelector(
    `button[aria-label="Start chats at ${name}"], button[aria-label="Chats start at ${name}"]`,
  ) as HTMLButtonElement | null;

// A world's places sit in a panel under its card, closed until opened.
const openPlaces = async () =>
  act(async () =>
    (container.querySelector('[data-testid="world-places-toggle"]') as HTMLButtonElement).click(),
  );

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find(
    (b) => b.textContent?.trim() === label,
  )!;

function type(selector: string, value: string) {
  const el = container.querySelector(selector) as
    | HTMLInputElement
    | HTMLSelectElement
    | HTMLTextAreaElement;
  act(() => {
    const proto =
      el instanceof HTMLSelectElement
        ? window.HTMLSelectElement
        : el instanceof HTMLTextAreaElement
          ? window.HTMLTextAreaElement
          : window.HTMLInputElement;
    Object.getOwnPropertyDescriptor(proto.prototype, 'value')?.set?.call(el, value);
    el.dispatchEvent(
      new Event(el instanceof HTMLSelectElement ? 'change' : 'input', { bubbles: true }),
    );
  });
}

async function mount(rows: unknown[]) {
  get.mockImplementation((url: string) => {
    if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
    if (url.startsWith('/api/worlds/parent-candidates')) return Promise.resolve({ candidates: [] });
    if (url.includes('/detail'))
      return Promise.resolve({
        ...TOWN,
        entries: [],
        atmosphere: 'breathable',
        gravity: 'earth',
        defaultPlaceId: 'tea-1',
      });
    return Promise.resolve({ worlds: rows });
  });
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the starting-place star', () => {
  it('stars a place inside a world and names it on the world card', async () => {
    await mount([TOWN, TEA, HALL]);
    await openPlaces();
    expect(starOf('Bletchfield')).toBeNull();
    expect(
      container.querySelector('[data-testid="world-starts-at-missing"]'),
      'a world with places and no start asks for one',
    ).not.toBeNull();
    const star = starOf('Tea Rooms')!;
    expect(star.textContent).toBe('☆');

    post.mockResolvedValueOnce({
      worlds: [{ ...TOWN, defaultPlaceId: 'tea-1' }, TEA, HALL],
    });
    await act(async () => star.click());

    expect(post).toHaveBeenCalledWith('/api/worlds/default-place', {
      worldId: 'town-1',
      placeId: 'tea-1',
    });
    expect(container.querySelector('[data-testid="world-starts-at"]')?.textContent).toContain(
      'Chats start at Tea Rooms',
    );
    expect(container.querySelector('[data-testid="world-starts-at-missing"]')).toBeNull();
    expect(starOf('Tea Rooms')!.textContent).toBe('★');
    expect(starOf('Town Hall')!.textContent).toBe('☆');
  });

  it('the starred place stays starred when tapped: a world always keeps one', async () => {
    await mount([{ ...TOWN, defaultPlaceId: 'tea-1' }, TEA, HALL]);
    await openPlaces();
    await act(async () => starOf('Tea Rooms')!.click());
    expect(post).not.toHaveBeenCalled();
    expect(starOf('Tea Rooms')!.textContent).toBe('★');
  });
});

describe('Where chats start in the editor', () => {
  it('a new world cannot be saved until it names its starting place', async () => {
    await mount([]);
    await act(async () => button('＋ New place').click());
    type('.world-edit label input', 'Harbor Town');
    await act(async () => button('Save place').click());
    expect(post).not.toHaveBeenCalled();
    expect(container.querySelector('[data-testid="world-starting-place"] [role="alert"]')?.textContent).toBe(
      'Name the place where chats in this world start.',
    );

    type('input[aria-label="Starting place"]', 'The Quay');
    type('textarea[aria-label="Starting place description"]', 'Rope and gulls.');
    post.mockResolvedValue({ worlds: [] });
    await act(async () => button('Save place').click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({
        name: 'Harbor Town',
        create: true,
        startingPlace: { name: 'The Quay', description: 'Rope and gulls.' },
      }),
    );
  });

  it('editing a world picks among its places, preselected from the relay', async () => {
    await mount([{ ...TOWN, defaultPlaceId: 'tea-1' }, TEA, HALL]);
    const edit = container.querySelector(
      '.wsg-world-card button[title="Edit"]',
    ) as HTMLButtonElement;
    await act(async () => edit.click());
    const pick = container.querySelector(
      'select[aria-label="Where chats start"]',
    ) as HTMLSelectElement;
    expect(pick.value).toBe('tea-1');
    expect(Array.from(pick.options).map((o) => o.textContent)).toEqual([
      'Pick a place',
      'Tea Rooms',
      'Town Hall',
      'A new place…',
    ]);

    type('select[aria-label="Where chats start"]', 'hall-1');
    post.mockResolvedValue({ worlds: [] });
    await act(async () => button('Save place').click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({ startingPlace: { placeId: 'hall-1' } }),
    );
  });
});
