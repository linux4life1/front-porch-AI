// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// "Write a story here" on the Worlds page (docs/design/stories-in-worlds.md
// §3.4): a world card opens New Story at the world's starred place, a place
// row opens it at that place. Web twin of the desktop world card and place
// row menu tests.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const { get, post, navigate } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn(), navigate: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post },
  ApiError: class extends Error {},
}));
vi.mock('react-router-dom', async (importOriginal) => ({
  ...(await importOriginal<typeof import('react-router-dom')>()),
  useNavigate: () => navigate,
}));
vi.mock('../components/ClimateSeasonEditor', () => ({ ClimateSeasonEditor: () => null }));
vi.mock('../components/LoreEntriesEditor', () => ({ LoreEntriesEditor: () => null }));
vi.mock('../components/ImportCharacterLoreButton', () => ({ ImportCharacterLoreButton: () => null }));

import { WorldsPage } from './WorldsPage';

const TOWN = { id: 'town-1', name: 'Bletchfield', description: 'A town', entryCount: 1, climateEnabled: true, biomeId: 'temperate', defaultPlaceId: 'tea-1' };
const TEA = { id: 'tea-1', name: 'Tea Rooms', description: 'Steam', entryCount: 0, climateEnabled: false, parentWorldId: 'town-1' };
const HALL = { id: 'hall-1', name: 'Town Hall', description: 'Records', entryCount: 0, climateEnabled: false, parentWorldId: 'town-1' };

let container: HTMLDivElement;
let root: Root;

const click = (testid: string) => act(async () => {
  const el = container.querySelector<HTMLButtonElement>(`[data-testid="${testid}"]`);
  if (!el) throw new Error(`no ${testid}`);
  el.click();
});

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  navigate.mockReset();
  get.mockImplementation((url: string) => {
    if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
    if (url.startsWith('/api/worlds/parent-candidates')) return Promise.resolve({ candidates: [] });
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

it('a world card opens New Story at the world\'s starred place', async () => {
  await click('world-write-story-town-1');
  expect(navigate).toHaveBeenCalledWith('/stories/new', { state: { fromWorld: 'tea-1' } });
});

it('a place row opens New Story at that place', async () => {
  await act(async () => (container.querySelector('[data-testid="world-places-toggle"]') as HTMLButtonElement).click());
  await click('place-write-story-hall-1');
  expect(navigate).toHaveBeenCalledWith('/stories/new', { state: { fromWorld: 'hall-1' } });
});
