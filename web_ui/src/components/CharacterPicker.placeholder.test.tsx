// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's "add to scene" picker (/join) reads /api/characters, which marks
// a character whose picture is only the flat no-portrait colour
// (placeholderPortrait). The picker draws that character's initial instead of
// the colour box. Desktop twin: the scene guest picker dialog
// (test/ui/widgets/placeholder_portrait_everywhere_test.dart).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const rows = [
  { id: 'c1', name: 'Juniper', hasAvatar: true, placeholderPortrait: true },
  { id: 'c2', name: 'Marlow', hasAvatar: true, placeholderPortrait: false },
  { id: 'c3', name: 'Rowan', hasAvatar: true },
];

vi.mock('../api/client', () => ({
  api: {
    avatarUrl: (path: string) => path,
    get: () => Promise.resolve(rows),
  },
}));

const { CharacterPicker } = await import('./CharacterPicker');

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

it('draws the initial for the placeholder and the picture for a real portrait', async () => {
  act(() => {
    root.render(createElement(CharacterPicker, { onPick: () => {}, onClose: () => {} }));
  });
  await act(async () => {
    await Promise.resolve();
  });
  const srcs = [...container.querySelectorAll('.char-avatar img')].map((i) => i.getAttribute('src'));
  expect(srcs).toEqual(['/api/characters/c2/avatar', '/api/characters/c3/avatar']);
  const initials = [...container.querySelectorAll('.char-avatar .char-initial')].map((s) => s.textContent);
  expect(initials).toEqual(['J']);
});
