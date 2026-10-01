// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's CivitAI sheet: Load more carries on from the cursor the
// computer hands back, with the same words and base; and the one base
// picker, where typing only narrows the menu, the pick is what is shown and
// sent, and "Only installed" hiding it drops it for good.

import { act } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  button, calls, click, createElement, field, mount, reset, serve, settle, text, type, unmount,
} from './deskTestKit';

vi.mock('../../../api/client', async () => (await import('./deskTestKit')).clientMock);

const { CivitaiSheet } = await import('./CivitaiSheet');

const row = (n: number) => ({
  filename: `look${n}.safetensors`,
  versionId: n,
  type: 'LORA',
  adult: false,
  name: `Look ${n}`,
  downloads: 1,
  previewUrl: null,
});

afterEach(() => {
  unmount();
  reset();
});

const open = async (search: unknown, bases: string[] = []) => {
  serve({
    'GET /api/image/civitai/credential': { saved: true },
    'GET /api/image/civitai/installed': { bases, models: [], loras: [] },
    'GET /api/image/civitai/search': search,
  });
  mount(
    createElement(CivitaiSheet, {
      lora: true,
      backend: 'comfyui',
      adultAllowed: false,
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

const runSearch = async (q: string) => {
  type('input[aria-label="Search"]', q);
  click('Search');
  await settle();
};

const BASE = 'input[aria-label="Base model"]';
const baseField = () => field(BASE);
const openPicker = () => act(() => baseField().focus());
const leavePicker = () => act(() => baseField().blur());
const options = () => [...document.querySelectorAll('[role="option"]')].map((o) => o.textContent);

describe('Load more', () => {
  it('carries on from the cursor with the words and base first searched', async () => {
    await open((_: unknown, path: string) => {
      const cursor = new URLSearchParams(path.split('?')[1]).get('cursor');
      return cursor === 'c6'
        ? { items: [row(2), row(1)], nextCursor: null }
        : { items: [row(1)], nextCursor: 'c6' };
    });
    openPicker();
    click('Pony');
    await runSearch('look');
    expect(text()).toContain('Look 1');

    type('input[aria-label="Search"]', 'something else');
    click('Load more');
    await settle();

    const [first, more] = searches();
    expect(first.get('cursor')).toBeNull();
    expect(more.get('cursor')).toBe('c6');
    expect(more.get('q')).toBe('look');
    expect(more.get('base')).toBe('Pony');
    expect(text().match(/Look 1/g)).toHaveLength(1);
    expect(text()).toContain('Look 2');
    expect(button('Load more')).toBeUndefined();
  });

  it('says when nothing matched in the first 500 but more may', async () => {
    await open({
      items: [],
      nextCursor: 'c5',
      note: 'No matches in the first 500 results. Try a different word, or Load more.',
    });
    await runSearch('look');
    expect(text()).toContain('No matches in the first 500 results. Try a different word, or Load more.');
    expect(button('Load more')).toBeDefined();
  });

  it('sends Klein (all) for the computer to spread over the four Klein bases', async () => {
    await open({ items: [row(1)], nextCursor: null });
    openPicker();
    type(BASE, 'klein');
    click('Flux.2 Klein (all)');
    await runSearch('look');
    expect(searches()[0].get('base')).toBe('Flux.2 Klein (all)');
  });
});

describe('the base picker', () => {
  it('clearing the typed words brings the whole list back', async () => {
    await open({ items: [], nextCursor: null });
    openPicker();
    type(BASE, 'qwen');
    expect(options()).toContain('Qwen 2.1');
    expect(options()).not.toContain('Flux.1 Dev');

    click('Clear');
    expect(options()).toContain('Flux.1 Dev');
    expect(options()).toContain('Qwen 2.1');
  });

  it('a pick survives typing and clearing, is shown, and is what is sent', async () => {
    await open({ items: [row(1)], nextCursor: null });
    openPicker();
    type(BASE, 'qwen');
    click('Qwen 2.1');
    expect(baseField().value).toBe('Qwen 2.1');

    openPicker();
    type(BASE, 'flux');
    click('Clear');
    leavePicker();
    expect(baseField().value).toBe('Qwen 2.1');

    await runSearch('look');
    expect(searches()[0].get('base')).toBe('Qwen 2.1');
  });

  it('Only installed drops a hidden pick with a note, and off does not bring it back', async () => {
    await open({ items: [row(1)], nextCursor: null }, ['Flux.1 D']);
    openPicker();
    click('Flux.1 Dev');
    act(() => field('input[type="checkbox"]').click());
    expect(baseField().value).toBe('Flux.1 Dev');
    act(() => field('input[type="checkbox"]').click());

    openPicker();
    click('Flux.2 Klein 9B');
    act(() => field('input[type="checkbox"]').click());
    expect(text()).toContain("Flux.2 Klein 9B isn't installed — showing Any base.");
    expect(baseField().value).toBe('Any base');

    act(() => field('input[type="checkbox"]').click());
    expect(baseField().value).toBe('Any base');
    await runSearch('look');
    expect(searches()[0].get('base')).toBe('');
  });
});
