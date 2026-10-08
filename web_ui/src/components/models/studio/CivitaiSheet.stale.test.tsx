// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Results belong to what was asked. Picking another base, changing the
// words, or unticking adult clears the list and Load more until Search is
// pressed again, so Load more can never carry on an old search (after
// unticking adult, it must not ask for adult results).

import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  button, calls, click, createElement, field, mount, reset, serve, settle, text, type, unmount,
} from './deskTestKit';

vi.mock('../../../api/client', async () => (await import('./deskTestKit')).clientMock);

const { CivitaiSheet } = await import('./CivitaiSheet');

afterEach(() => {
  unmount();
  reset();
});

const open = async () => {
  serve({
    'GET /api/image/civitai/credential': { saved: true },
    'GET /api/image/civitai/installed': { bases: [], models: [], loras: [] },
    'GET /api/image/civitai/search': {
      items: [{ filename: 'look1.safetensors', versionId: 1, type: 'LORA', adult: false, name: 'Look 1' }],
      nextCursor: 'c2',
    },
  });
  mount(
    createElement(CivitaiSheet, {
      lora: true,
      backend: 'comfyui',
      adultAllowed: true,
      totpEnabled: false,
      onInstalled: vi.fn().mockResolvedValue(''),
      onClose: vi.fn(),
    }),
  );
  await settle();
};

const searches = () =>
  calls
    .filter((c) => c.path.startsWith('/api/image/civitai/search'))
    .map((c) => new URLSearchParams(c.path.split('?')[1]));

const searched = async () => {
  type('input[aria-label="Search"]', 'look');
  click('Search');
  await settle();
  expect(text()).toContain('Look 1');
  expect(button('Load more')).toBeDefined();
};

const cleared = () => {
  expect(text()).not.toContain('Look 1');
  expect(button('Load more')).toBeUndefined();
};

describe('old results go', () => {
  it('when another base is picked', async () => {
    await open();
    await searched();
    act(() => field('input[aria-label="Base model"]').focus());
    click('Pony');
    cleared();
    expect(searches()).toHaveLength(1);
  });

  it('when the words change', async () => {
    await open();
    await searched();
    type('input[aria-label="Search"]', 'looks');
    cleared();
    expect(searches()).toHaveLength(1);
  });

  it('when adult is unticked, and adult results are not asked for again', async () => {
    await open();
    act(() => field('input[type="checkbox"]').click());
    await searched();
    expect(searches()[0].get('adult')).toBe('true');

    act(() => field('input[type="checkbox"]').click());
    cleared();
    expect(searches()).toHaveLength(1);

    click('Search');
    await settle();
    expect(searches()).toHaveLength(2);
    expect(searches()[1].get('adult')).toBe('false');
    expect(searches()[1].get('cursor')).toBeNull();
  });
});
