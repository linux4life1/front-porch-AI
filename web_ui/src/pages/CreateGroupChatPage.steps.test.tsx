// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web new-group wizard walks the desktop's seven steps, Group Dynamics
// sits inside Realism for a small group, and Create posts the whole draft.

import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const CHARS = [
  { id: 'j', name: 'Juniper', hasAvatar: false, folderId: '' },
  { id: 'm', name: 'Marlow', hasAvatar: false, folderId: '' },
];
const posts: { path: string; body: unknown }[] = [];

vi.mock('../api/client', () => ({
  api: {
    get: async (path: string) =>
      path.startsWith('/api/folders')
        ? { folders: [] }
        : path.startsWith('/api/worlds')
          ? { worlds: [], climates: [] }
          : path.startsWith('/api/settings')
            ? { realism: { passageOfTimeDefault: true } }
            : CHARS,
    post: async (path: string, body: unknown) => {
      posts.push({ path, body });
      return { id: 'g1', name: 'x' };
    },
    avatarUrl: () => '',
  },
  ApiError: class ApiError extends Error {},
}));

const { CreateGroupChatPage } = await import('./CreateGroupChatPage');

let container: HTMLDivElement;
let root: Root;

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(createElement(MemoryRouter, null, createElement(CreateGroupChatPage)));
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

function button(label: string): HTMLButtonElement {
  const b = [...container.querySelectorAll('button')].find((el) => el.textContent?.includes(label));
  if (!b) throw new Error(`no button "${label}"`);
  return b;
}
const click = (label: string) => act(() => button(label).click());
const text = () => container.textContent ?? '';

it('walks Members, Details, Setting, Opening, Realism, Prompts & Lore, Review', async () => {
  click('Juniper');
  click('Marlow');
  const seen: string[] = [];
  for (const landmark of [
    'Group name',
    'Where does the group meet?',
    'Opening Scene',
    'Realism Engine for this group',
    'Group System Prompt',
    'Create & open',
  ]) {
    click('Next');
    expect(text()).toContain(landmark);
    seen.push(landmark);
    if (landmark === 'Realism Engine for this group') {
      expect(
        container.querySelector('[data-testid="group-dynamics"]'),
        'Group Dynamics is a section of Realism for two members',
      ).not.toBeNull();
    }
    if (landmark === 'Group System Prompt') expect(text()).toContain('Group Lorebook');
  }
  expect(seen).toHaveLength(6);
  expect(text()).not.toContain('Next →');

  await act(async () => {
    button('Create & open').click();
  });
  const create = posts.find((p) => p.path === '/api/groups');
  expect(create?.body).toMatchObject({
    name: 'Juniper & Marlow',
    memberIds: ['j', 'm'],
    realism: { enabled: true, needsEnabled: true, timeOfDay: 'morning', dayCount: 1 },
    groupLore: [],
  });
});
