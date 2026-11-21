// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A library card shows one line under the name: the character's title when
// it has one (it says the most about the card), else its tags — the desktop
// tile's rule (test/ui/pages/character_title_ui_test.dart).

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
  const full = { id: 'c1', name: 'Misty', tags: ['weather'], hasAvatar: true, messageCount: 0, ...char } as LibChar;
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

it('shows the title under the name in place of the tags', () => {
  render({ title: 'Misty Meadows, Misguided Meteorologist' });
  expect(container.querySelector('.lib-name')?.textContent).toBe('Misty');
  expect(container.querySelector('.lib-title')?.textContent).toBe('Misty Meadows, Misguided Meteorologist');
  expect(container.querySelector('.tag-pills')).toBeNull();
});

it('keeps the tags without a title (and from an older app that sends none)', () => {
  render({ title: '' });
  expect(container.querySelector('.lib-title')).toBeNull();
  expect(container.querySelector('.tag-pill')?.textContent).toBe('weather');
  render({});
  expect(container.querySelector('.tag-pill')?.textContent).toBe('weather');
});
