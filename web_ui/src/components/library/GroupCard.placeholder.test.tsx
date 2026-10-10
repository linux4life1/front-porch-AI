// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A group member made from a character without a portrait carries a flat
// coloured picture. The group tile draws that member's initial instead, as
// the desktop folder and group mosaics draw the person icon. The relay sets
// placeholderPortrait on /api/groups members (group_facade.dart).

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import type { LibGroupMember } from '../../hooks/useLibrary';

vi.mock('../../api/client', () => ({
  api: { avatarUrl: (path: string) => path },
}));

const { GroupCard } = await import('./LibraryCards');

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

function render(juniper: Partial<LibGroupMember>) {
  const members: LibGroupMember[] = [
    { id: 'm1', name: 'Juniper', hasAvatar: true, ...juniper },
    { id: 'm2', name: 'Marlow', hasAvatar: true, placeholderPortrait: false },
  ];
  act(() => {
    root.render(
      createElement(GroupCard, {
        group: { id: 'g1', name: 'Porch', folderId: '', memberCount: 2, members },
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

const pictures = () =>
  [...container.querySelectorAll('.group-art img')].map((i) => i.getAttribute('src'));

it('draws the initial for a member with only the flat placeholder picture', () => {
  render({ placeholderPortrait: true });
  expect(pictures()).toEqual(['/api/groups/g1/members/m2/avatar']);
  expect(container.querySelector('.group-art .lib-art-fallback')?.textContent).toBe('J');
});

it('keeps real member pictures (and an older app that sends no flag)', () => {
  render({});
  expect(pictures()).toEqual([
    '/api/groups/g1/members/m1/avatar',
    '/api/groups/g1/members/m2/avatar',
  ]);
});
