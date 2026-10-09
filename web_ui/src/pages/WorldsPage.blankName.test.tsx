// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A new place with no name (or only spaces) must not save, and the page says
// why: a nameless world showed as "?" everywhere. The desktop dialog refuses
// it too (world_blank_name_test.dart), and so does the server (400).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
// The climate and lore editors have their own tests; here they are in the way.
vi.mock('../components/ClimateSeasonEditor', () => ({ ClimateSeasonEditor: () => null }));
vi.mock('../components/LoreEntriesEditor', () => ({ LoreEntriesEditor: () => null }));
vi.mock('../components/ImportCharacterLoreButton', () => ({
  ImportCharacterLoreButton: () => null,
}));

import { WorldsPage } from './WorldsPage';

let container: HTMLDivElement;
let root: Root;

const button = (label: string) =>
  Array.from(container.querySelectorAll('button')).find(
    (b) => b.textContent?.trim() === label,
  )!;

const hint = () => container.querySelector('[data-testid="place-name-hint"]');

function typeName(value: string) {
  const input = container.querySelector('.world-edit label input') as HTMLInputElement;
  act(() => {
    const setter = Object.getOwnPropertyDescriptor(
      window.HTMLInputElement.prototype,
      'value',
    )?.set;
    setter?.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset();
  post.mockReset();
  get.mockImplementation((url: string) =>
    Promise.resolve(url === '/api/worlds/climates' ? { climates: [] } : { worlds: [] }),
  );
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(WorldsPage)));
  });
  act(() => button('＋ New place').click());
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

describe('a new place with no name', () => {
  it('cannot be saved, and the page says to name it', () => {
    expect(button('Save place').disabled).toBe(true);
    expect(hint()?.textContent).toBe('Give your place a name.');

    typeName('   ');
    expect(button('Save place').disabled).toBe(true);
    expect(hint()).not.toBeNull();
    act(() => button('Save place').click());
    expect(post).not.toHaveBeenCalled();
  });

  it('saves once it has a name, and the hint goes away', async () => {
    typeName('Harbor Town');
    expect(hint()).toBeNull();
    expect(button('Save place').disabled).toBe(false);

    post.mockResolvedValue({ worlds: [] });
    await act(async () => button('Save place').click());
    expect(post).toHaveBeenCalledWith(
      '/api/worlds',
      expect.objectContaining({ name: 'Harbor Town' }),
    );
  });
});
