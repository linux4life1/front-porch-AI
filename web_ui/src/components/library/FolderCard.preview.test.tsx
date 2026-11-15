// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The folder tile is the desktop folder_grid_card's twin: a portrait card
// with a 2×2 montage of up to 4 member previews from `/api/folders`
// (`preview` rows, folders_preview.dart) and a "N characters · M groups"
// line — not the old landscape 📁 row (drift ledger #4). Empty folders and
// flat-placeholder portraits fall back the way the desktop walk does.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { LibFolder, LibGroupMember } from '../../hooks/useLibrary';

vi.mock('../../api/client', () => ({
  api: { avatarUrl: (path: string) => path },
}));

const { FolderCard } = await import('./LibraryCards');

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

function render(folder: LibFolder) {
  act(() => {
    root.render(
      createElement(FolderCard, {
        folder,
        onOpen: () => {},
        onMenu: () => {},
        onDropChars: () => {},
      }),
    );
  });
}

const member = (id: string, name: string, extra: Partial<LibGroupMember> = {}): LibGroupMember => ({
  id,
  name,
  hasAvatar: true,
  ...extra,
});

const pictures = () =>
  [...container.querySelectorAll('.group-art img')].map((i) => i.getAttribute('src'));

it('montages the member previews on the character avatar URLs', () => {
  render({
    id: 'f1',
    name: 'Porch',
    characterCount: 2,
    groupCount: 0,
    preview: [member('c1', 'Ann'), member('c2', 'Bo')],
  });
  expect(pictures()).toEqual([
    '/api/characters/c1/avatar',
    '/api/characters/c2/avatar',
  ]);
  expect(container.querySelector('.lib-name')?.textContent).toBe('Porch');
  expect(container.querySelector('.lib-sub')?.textContent).toBe('2 characters');
});

it('counts groups like the desktop line when there are any', () => {
  render({ id: 'f1', name: 'Porch', characterCount: 1, groupCount: 1, preview: [] });
  expect(container.querySelector('.lib-sub')?.textContent).toBe(
    '1 character · 1 group',
  );
});

it('draws the initial for a flat placeholder portrait and the glyph when empty', () => {
  render({
    id: 'f1',
    name: 'Porch',
    characterCount: 1,
    preview: [member('c1', 'Ann', { placeholderPortrait: true })],
  });
  expect(pictures()).toEqual([]);
  expect(container.querySelector('.group-art .lib-art-fallback')?.textContent).toBe('A');

  render({ id: 'f2', name: 'Attic', characterCount: 0, preview: [] });
  expect(container.querySelector('.group-art')).toBeNull();
  expect(container.querySelector('.lib-art-fallback')?.textContent).toBe('📁');
});

it('the tile line is the DIRECT count — the recursive one is the delete '
  + 'dialog\'s, not this card\'s', () => {
  render({
    id: 'f1',
    name: 'Porch',
    characterCount: 3, // recursive: subfolders swept by a delete
    groupCount: 1,
    directCharacterCount: 1,
    directGroupCount: 0,
    preview: [member('c1', 'Ann')],
  });
  // folder_grid_card.dart:91-92 reads the folder's own lists; a nested
  // library would drift the moment the tile showed the swept count.
  expect(container.querySelector('.lib-sub')?.textContent).toBe('1 character');
});

it('an older host with no preview field still renders the glyph tile', () => {
  render({ id: 'f1', name: 'Porch', characterCount: 3, groupCount: 2 });
  expect(container.querySelector('.lib-art-fallback')?.textContent).toBe('📁');
  expect(container.querySelector('.lib-sub')?.textContent).toBe(
    '3 characters · 2 groups',
  );
});
