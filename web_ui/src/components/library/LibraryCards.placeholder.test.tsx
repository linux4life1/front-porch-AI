// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character made without a portrait carries a flat coloured card picture.
// The library card draws its usual initial for it instead of that flat box.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { LibChar } from '../../hooks/useLibrary';

vi.mock('../../api/client', () => ({
  api: { avatarUrl: (path: string) => path },
}));

const { CharacterCard } = await import('./LibraryCards');

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function render(char: Partial<LibChar>) {
  const full = { id: 'c1', name: 'Juniper', tags: [], hasAvatar: true, messageCount: 0, ...char } as LibChar;
  act(() => {
    root.render(
      createElement(CharacterCard, {
        char: full,
        selecting: false,
        selected: false,
        onOpen: () => {},
        onToggleSelect: () => {},
        onMenu: () => {},
        dndEnabled: false,
        onDragStart: () => {},
      }),
    );
  });
}

it('draws the initial, not the flat placeholder picture', () => {
  render({ placeholderPortrait: true });
  expect(container.querySelector('.lib-art img')).toBeNull();
  expect(container.querySelector('.lib-art-fallback')?.textContent).toBe('J');
});

it('keeps a real portrait (and an older app that sends no flag)', () => {
  render({ placeholderPortrait: false });
  expect(container.querySelector('.lib-art img')).not.toBeNull();
  render({});
  expect(container.querySelector('.lib-art img')).not.toBeNull();
});
