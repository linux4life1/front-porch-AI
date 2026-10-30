// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Web Group Settings' "New chats" section: the forked-group notice names the
// chat the group came from, "Leave as is" hides it without saving, "Use the
// chat's settings" posts and reloads the worlds, and the switches post what
// they change.

import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';

const posts: { path: string; body: unknown }[] = [];
let state: Record<string, unknown>;

vi.mock('../../api/client', () => ({
  api: {
    get: async () => state,
    post: async (path: string, body: Record<string, unknown>) => {
      posts.push({ path, body });
      state = body.useForkSource
        ? { ...state, realism: true, needs: true, forkSource: null }
        : { ...state, ...body };
      return state;
    },
  },
}));

const { GroupNewChatsSection, forkGapLine } = await import('./GroupNewChatsSection');

let container: HTMLDivElement;
let root: Root;
let worldsReloaded = 0;

const FORKED = {
  realism: false,
  needs: true,
  inherit: false,
  forkSource: { hostName: 'Juniper', realismMissing: true, needsOn: true, meet: 'Hollow Creek, starting at The Mill Kitchen' },
};

beforeEach(async () => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  posts.length = 0;
  worldsReloaded = 0;
  state = structuredClone(FORKED);
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root.render(
      createElement(GroupNewChatsSection, { groupId: 'g1', onWorldsChanged: () => worldsReloaded++ }),
    );
  });
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const notice = () => container.querySelector('[data-testid="group-fork-notice"]');
function button(label: string): HTMLButtonElement {
  const b = [...container.querySelectorAll('button')].find((el) => el.textContent === label);
  if (!b) throw new Error(`no button "${label}"`);
  return b;
}

it('names the chat the group came from and what it would fill in', () => {
  expect(notice()?.textContent).toContain('This group started from your chat with Juniper.');
  expect(notice()?.textContent).toContain('Realism on · Needs on');
  expect(notice()?.textContent).toContain('Hollow Creek, starting at The Mill Kitchen');
  expect(container.textContent).toContain("Read Juniper's lorebook");
  expect(forkGapLine(FORKED.forkSource)).toContain('Realism and Needs off and no world');
});

it('"Leave as is" hides the notice and saves nothing', () => {
  act(() => button('Leave as is').click());
  expect(notice()).toBeNull();
  expect(posts).toHaveLength(0);
});

it('"Use the chat\'s settings" saves, clears the notice and reloads the worlds', async () => {
  await act(async () => {
    button("Use the chat's settings").click();
  });
  expect(posts).toEqual([{ path: '/api/groups/g1/new-chats', body: { useForkSource: true } }]);
  expect(notice()).toBeNull();
  expect(worldsReloaded).toBe(1);
  const realism = container.querySelectorAll('input[type="checkbox"]')[0] as HTMLInputElement;
  expect(realism.checked).toBe(true);
});

it('each switch posts only what it changes', async () => {
  const boxes = () => container.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
  expect(boxes()[1].disabled, 'Needs waits for Realism').toBe(true);
  await act(async () => {
    boxes()[0].click();
  });
  await act(async () => {
    boxes()[2].click();
  });
  expect(posts.map((p) => p.body)).toEqual([{ realism: true }, { inherit: true }]);
  expect(boxes()[1].disabled).toBe(false);
});
