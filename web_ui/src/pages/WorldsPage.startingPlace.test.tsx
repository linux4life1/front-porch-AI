// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The starting-place star on the Worlds page (web twin of the desktop
// library star): a place inside a world shows ☆, tapping it posts the
// star to the relay, the world's card then says "Chats start at <place>",
// and tapping the starred place posts a clear. The world itself carries
// no star.

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
    `button[aria-label="Start chats at ${name}"], button[aria-label="Clear ${name} as starting place"]`,
  ) as HTMLButtonElement | null;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  get.mockImplementation((url: string) => {
    if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
    return Promise.resolve({ worlds: [TOWN, TEA, HALL] });
  });
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('the starting-place star', () => {
  it('stars a place inside a world and names it on the world card', async () => {
    expect(starOf('Bletchfield')).toBeNull();
    expect(container.querySelector('[data-testid="world-starts-at"]')).toBeNull();
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
    expect(starOf('Tea Rooms')!.textContent).toBe('★');
    expect(starOf('Tea Rooms')!.getAttribute('aria-pressed')).toBe('true');
    expect(starOf('Town Hall')!.textContent).toBe('☆');
  });

  it('a tap on the starred place clears it', async () => {
    post.mockResolvedValueOnce({
      worlds: [{ ...TOWN, defaultPlaceId: 'tea-1' }, TEA, HALL],
    });
    await act(async () => starOf('Tea Rooms')!.click());
    post.mockResolvedValueOnce({ worlds: [TOWN, TEA, HALL] });
    await act(async () => starOf('Tea Rooms')!.click());

    expect(post).toHaveBeenLastCalledWith('/api/worlds/default-place', {
      worldId: 'town-1',
      placeId: null,
    });
    expect(container.querySelector('[data-testid="world-starts-at"]')).toBeNull();
  });
});
