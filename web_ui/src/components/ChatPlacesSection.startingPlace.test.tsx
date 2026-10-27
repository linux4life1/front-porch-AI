// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Attaching a world with a starred place (web twin of the desktop attach
// picker): as the Setting the scene lands on the starred place, and "Add as
// lore" still adds the world itself. The default is chosen in the Worlds
// menu, so the chat picker says nothing about it.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({
  api: { get, post },
  ApiError: class extends Error {},
}));

import { ChatPlacesSection } from './ChatPlacesSection';

let container: HTMLDivElement;
let root: Root;

const TOWN = { id: 'town-1', name: 'Bletchfield', climateEnabled: true, defaultPlaceId: 'tea-1' };
const TEA = { id: 'tea-1', name: 'Tea Rooms', climateEnabled: false, parentWorldId: 'town-1' };
const MOOR = { id: 'moor-1', name: 'The Moor', climateEnabled: true };

const placesResponse = (primary: { id: string } | null, lore: unknown[] = []) => ({
  primary,
  primaryId: primary?.id ?? null,
  lorePlaces: lore,
  climateAuthors: primary != null,
  reachable: [],
  climateId: 'temperate',
  dayCount: 1,
  climateOptions: [],
});

async function mount(primary: { id: string } | null) {
  get.mockImplementation((url: string) => {
    if (url === '/api/chat/places') return Promise.resolve(placesResponse(primary));
    if (url === '/api/worlds') return Promise.resolve({ worlds: [TOWN, TEA, MOOR] });
    return Promise.resolve({ climates: [] });
  });
  post.mockImplementation((_url: string, body: { primaryId: string | null }) =>
    Promise.resolve(placesResponse(body.primaryId ? { id: body.primaryId } : null)),
  );
  await act(async () => {
    root.render(createElement(ChatPlacesSection));
  });
}

const attachSelect = () =>
  Array.from(container.querySelectorAll('select')).find((s) =>
    Array.from(s.querySelectorAll('option')).some((o) => o.textContent === 'Choose…'),
  ) as HTMLSelectElement;

async function choose(value: string) {
  const el = attachSelect();
  await act(async () => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLSelectElement.prototype,
      'value',
    )?.set;
    setter?.call(el, value);
    el.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find(
    (b) => b.textContent?.trim() === label,
  )!;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
});

afterEach(() => {
  vi.restoreAllMocks();
  act(() => root.unmount());
  container.remove();
});

describe('attaching a world with a starred place', () => {
  it('an empty Setting lands on the starred place', async () => {
    await mount(null);
    const option = Array.from(attachSelect().querySelectorAll('option')).find(
      (o) => o.value === 'town-1',
    )!;
    expect(option.textContent).not.toContain('Tea Rooms');

    await choose('town-1');

    expect(post).toHaveBeenCalledWith('/api/chat/places', {
      primaryId: 'tea-1',
      loreIds: [],
    });
  });

  it('Use as setting replaces with the starred place and demotes the old one', async () => {
    await mount(MOOR);
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    await choose('town-1');
    await act(async () => button('Use as setting').click());

    expect(window.confirm).toHaveBeenCalledWith(
      expect.stringContaining('switch to Tea Rooms'),
    );
    expect(post).toHaveBeenLastCalledWith('/api/chat/places', {
      primaryId: 'tea-1',
      loreIds: ['moor-1'],
    });
  });

  it('Add as lore adds the world itself', async () => {
    await mount(MOOR);
    await choose('town-1');
    await act(async () => button('Add as lore').click());

    expect(post).toHaveBeenLastCalledWith('/api/chat/places', {
      primaryId: 'moor-1',
      loreIds: ['town-1'],
    });
  });
});
