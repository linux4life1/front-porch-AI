// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The place picker must hand the page only the ticked entries. A helper
// test stays green if this button dumps the whole book.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { LoreEntry } from './LoreEntriesEditor';

const get = vi.fn();

vi.mock('../api/client', () => ({
  api: {
    get: (...args: unknown[]) => get(...args),
    avatarUrl: (path: string, w: number, v?: number) =>
      `${path}?w=${w}${v ? `&v=${v}` : ''}`,
  },
  ApiError: class ApiError extends Error {},
}));

const { ImportCharacterLoreButton } = await import('./ImportCharacterLoreButton');

let container: HTMLDivElement;
let root: Root;

function render(onImport: (entries: LoreEntry[]) => void) {
  act(() => {
    root.render(createElement(ImportCharacterLoreButton, { onImport }));
  });
}

function clickButton(label: string) {
  const btn = [...container.querySelectorAll('button')].find((b) =>
    (b.textContent ?? '').includes(label),
  );
  expect(btn, `button "${label}"`).toBeTruthy();
  act(() => {
    btn!.click();
  });
}

async function flush() {
  await act(async () => {
    await Promise.resolve();
    await Promise.resolve();
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  get.mockReset();
  get.mockImplementation((path: string) => {
    if (path.includes('/detail')) {
      return Promise.resolve({
        lorebook: {
          entries: [
            {
              name: 'Harbor bell',
              key: 'harbor',
              content: 'Rings at dusk.',
              stickyDepth: 4,
            },
            {
              name: 'Market day',
              key: 'market',
              content: 'Stalls at dawn.',
              stickyDepth: 2,
            },
          ],
        },
      });
    }
    return Promise.resolve([
      { id: 'pier', name: 'Pier Keeper', hasAvatar: true, avatarVersion: 3 },
      { id: 'quiet', name: 'Quiet Extra', hasAvatar: false },
    ]);
  });
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('ImportCharacterLoreButton', () => {
  it('imports only the ticked entry', async () => {
    const imported: LoreEntry[][] = [];
    render((entries) => imported.push(entries));

    clickButton('From character');
    await flush();

    const portrait = container.querySelector('img');
    expect(portrait?.getAttribute('src')).toContain('/api/characters/pier/avatar');
    expect(portrait?.getAttribute('src')).toContain('v=3');
    expect(container.textContent).toContain('Q');

    clickButton('Pier Keeper');
    await flush();

    expect(container.textContent).toContain('Harbor bell');
    expect(container.textContent).toContain('Market day');

    const boxes = [...container.querySelectorAll('input[type="checkbox"]')];
    expect(boxes).toHaveLength(2);
    act(() => {
      boxes[0].click();
    });

    clickButton('Add 1 entry');
    expect(imported).toHaveLength(1);
    expect(imported[0].map((e) => e.name)).toEqual(['Harbor bell']);
    expect(imported[0][0].stickyDepth).toBe(4);
  });
});
