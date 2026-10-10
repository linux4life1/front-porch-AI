// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The New Group picker reads /api/characters, which marks a character whose
// picture is only the flat no-portrait colour (placeholderPortrait). The
// picker draws that character's initial instead of the colour box.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

vi.mock('../api/client', () => ({
  api: { avatarUrl: (path: string) => path },
}));

const { FolderCharacterPicker } = await import('./FolderCharacterPicker');

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

it('draws the initial for the placeholder and the picture for a real portrait', () => {
  act(() => {
    root.render(
      createElement(FolderCharacterPicker, {
        chars: [
          { id: 'c1', name: 'Juniper', hasAvatar: true, placeholderPortrait: true, folderId: '' },
          { id: 'c2', name: 'Marlow', hasAvatar: true, placeholderPortrait: false, folderId: '' },
          { id: 'c3', name: 'Rowan', hasAvatar: true, folderId: '' },
        ],
        folders: [],
        selected: [],
        onToggle: () => {},
      }),
    );
  });
  const srcs = [...container.querySelectorAll('.grp-card img')].map((i) => i.getAttribute('src'));
  expect(srcs).toEqual(['/api/characters/c2/avatar', '/api/characters/c3/avatar']);
  const initials = [...container.querySelectorAll('.grp-card .grp-initial')].map((s) => s.textContent);
  expect(initials).toEqual(['J']);
});
