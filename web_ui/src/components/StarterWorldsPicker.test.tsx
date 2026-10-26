// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Places page's starter-world picker: it lists what the index route
// sends, a fast double tap on Add posts the import once, and the page gets
// the refreshed list so the new world shows without a reload.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const get = vi.fn();
const post = vi.fn();

vi.mock('../api/client', () => ({
  api: {
    get: (...args: unknown[]) => get(...args),
    post: (...args: unknown[]) => post(...args),
  },
  ApiError: class ApiError extends Error {},
}));

const { StarterWorldsPicker } = await import('./StarterWorldsPicker');

const STARTERS = [
  {
    id: 'whitereach',
    name: 'The Whitereach',
    blurb: 'A frozen tundra with three warm valley towns.',
    climate: 'Tundra',
    customClimate: true,
    places: 3,
    ownClimates: 3,
    loreEntries: 0,
    added: false,
  },
  {
    id: 'harborside',
    name: 'Harborside',
    blurb: 'A small seaside town with a working quay.',
    climate: 'Temperate',
    customClimate: false,
    places: 3,
    ownClimates: 0,
    loreEntries: 0,
    added: false,
  },
];

let container: HTMLDivElement;
let root: Root;

async function flush() {
  await act(async () => {
    await Promise.resolve();
    await Promise.resolve();
  });
}

function render(onAdded: (worlds: unknown[], name: string) => void, onClose = () => {}) {
  act(() => {
    root.render(createElement(StarterWorldsPicker, { onAdded, onClose }));
  });
}

function addButton(id: string): HTMLButtonElement {
  const row = container.querySelector(`[data-testid="starter-row-${id}"]`);
  expect(row, `row ${id}`).toBeTruthy();
  const btn = row!.querySelector('button');
  expect(btn, `Add in ${id}`).toBeTruthy();
  return btn as HTMLButtonElement;
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  get.mockReset();
  post.mockReset();
  get.mockResolvedValue({ starters: STARTERS });
  post.mockResolvedValue({
    world: { id: 'new-root', name: 'Harborside' },
    worlds: [
      { id: 'new-root', name: 'Harborside' },
      { id: 'quay', name: 'The Quay', parentWorldId: 'new-root' },
    ],
  });
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('StarterWorldsPicker', () => {
  it('lists the starters from the index route', async () => {
    render(() => {});
    await flush();
    expect(get).toHaveBeenCalledWith('/api/worlds/starter');
    expect(container.textContent).toContain('The Whitereach');
    expect(container.textContent).toContain('A frozen tundra with three warm valley towns.');
    expect(container.textContent).toContain('Tundra (custom climate)');
    expect(container.textContent).toContain('3 with their own climate');
    expect(container.textContent).toContain('Harborside');
    expect(container.querySelector('[role="dialog"]')?.getAttribute('aria-label')).toBe(
      'Starter worlds',
    );
  });

  it('a double tap on Add imports once and hands the page the new list', async () => {
    const added: [unknown[], string][] = [];
    render((worlds, name) => added.push([worlds, name]));
    await flush();

    const btn = addButton('harborside');
    act(() => {
      btn.click();
      btn.click();
    });
    await flush();

    expect(post).toHaveBeenCalledTimes(1);
    expect(post).toHaveBeenCalledWith('/api/worlds/starter/harborside/import');
    expect(added).toHaveLength(1);
    expect(added[0][1]).toBe('Harborside');
    expect(added[0][0]).toHaveLength(2);
    expect(container.textContent).toContain('Added as "Harborside".');
    expect(addButton('harborside').textContent).toBe('Add again');
  });

  it('a failed add says so on its row and refreshes nothing', async () => {
    post.mockRejectedValueOnce(new Error('boom'));
    const added: unknown[] = [];
    render(() => added.push(1));
    await flush();
    act(() => addButton('whitereach').click());
    await flush();
    expect(added).toHaveLength(0);
    expect(container.textContent).toContain('Could not add that world.');
  });

  it('Close and a tap outside both close it', async () => {
    let closed = 0;
    render(() => {}, () => closed++);
    await flush();
    const close = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Close');
    act(() => close!.click());
    act(() => (container.querySelector('.drawer-backdrop') as HTMLElement).click());
    expect(closed).toBe(2);
  });
});
