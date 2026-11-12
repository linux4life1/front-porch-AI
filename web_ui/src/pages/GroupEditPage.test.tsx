// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Edit group page (docs/design/group-editor.md B): four tabs, the
// Details sections in the spec's order, one write on Save, the removed
// controls absent, and Bring back greyed while nobody has been removed.

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
vi.mock('../components/realism/usePassageOfTime', () => ({ usePassageOfTime: () => true }));

import { GroupEditPage } from './GroupEditPage';

const GROUP = {
  id: 'g1',
  name: 'The Porch Trio',
  turnOrder: 'roundRobin',
  autoAdvance: false,
  directorMode: false,
  personality: 'Close and teasing.',
  scenario: '',
  systemPrompt: '',
  postHistoryInstructions: '',
  mesExample: '',
  firstMessage: '',
  alternateGreetings: [],
  tags: ['friends'],
  chaosModeEnabled: false,
  inheritCharacterLorebooks: false,
  realism: {
    timeOfDay: 'morning',
    dayCount: 1,
    storyStartDate: null,
    storyStartTime: null,
    verificationEnabled: false,
    verificationStrictness: 3,
    verificationMaxReprocesses: 1,
    directorAuthority: false,
  },
  lorebook: null,
  members: [
    { id: 'a', name: 'Ana', voice: '', prompt: '', note: '', strength: 4 },
    { id: 'b', name: 'Bea', voice: 'Aoede', prompt: '', note: '', strength: 4 },
  ],
  feelings: {},
  removedCount: 0,
};

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset().mockImplementation((url: string) =>
    Promise.resolve(
      url === '/api/groups/g1/detail'
        ? GROUP
        : url === '/api/groups/g1/stats'
          ? { chats: 0, theirMessages: 0, yourMessages: 0, theirWords: 0, yourWords: 0, longestChat: 0, firstChat: null, lastChat: null }
          : url === '/api/groups/g1/worlds'
          ? { settingId: null, loreIds: [] }
          : url === '/api/worlds'
            ? { worlds: [] }
            : {},
    ),
  );
  post.mockReset().mockResolvedValue({});
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

async function mount() {
  const router = createMemoryRouter(
    [
      { path: '/', element: <h1>Chat</h1> },
      { path: '/groups/:groupId/edit', element: <GroupEditPage /> },
    ],
    { initialEntries: ['/', '/groups/g1/edit'], initialIndex: 1 },
  );
  await act(async () => root.render(<RouterProvider router={router} />));
}

const text = () => container.textContent ?? '';

describe('Edit group', () => {
  it('has the four tabs and the Details sections in the spec order', async () => {
    await mount();
    expect(text()).toContain('Edit The Porch Trio');
    expect([...container.querySelectorAll('[role="tab"]')].map((t) => t.textContent)).toEqual([
      'Details',
      'Dialogue',
      'Lorebook',
      'Worlds',
    ]);
    const heads = [...container.querySelectorAll('h3.section-label, details > summary')].map(
      (e) => e.textContent,
    );
    expect(heads).toEqual([
      'Identity',
      'Turns',
      'Voice',
      'Personality & World',
      'Advanced Prompts',
      'Tags',
      'Realism Engine',
    ]);
    expect(text()).toContain("Edit Ana's card");
    expect(text()).toContain('+ Add a character');
    expect(container.querySelector('[data-testid="group-voice-line"]')?.textContent).toContain(
      'Bea · Aoede',
    );
  });

  it('has none of the removed controls', async () => {
    await mount();
    for (const gone of [
      'Reset ALL',
      'Reset',
      'Memories per turn',
      'Memory budget',
      'Memory importance',
      'Needs simulation',
    ]) {
      expect(text(), gone).not.toContain(gone);
    }
  });

  it('greys out Bring back while nobody has been removed', async () => {
    await mount();
    const grey = container.querySelector('[data-testid="greyed-out"]');
    expect(grey?.getAttribute('title')).toBe('No removed members to bring back.');
  });

  it('Save posts the group once', async () => {
    await mount();
    const save = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Save')!;
    await act(async () => {
      save.click();
      save.click();
    });
    expect(post).toHaveBeenCalledTimes(1);
    expect(post.mock.calls[0][0]).toBe('/api/groups/g1/settings');
    expect(post.mock.calls[0][1].personality).toBe('Close and teasing.');
  });

  it('draws each member\'s avatar in the cast, from the group member route', async () => {
    await mount();
    const img = container.querySelector('[data-testid="cast-avatar-a"]') as HTMLImageElement;
    expect(img.getAttribute('src')).toBe('/api/groups/g1/members/a/avatar');
  });

  it("the stats footnote speaks of this group's chats", async () => {
    get.mockImplementation((url: string) =>
      Promise.resolve(
        url === '/api/groups/g1/detail'
          ? GROUP
          : url === '/api/groups/g1/stats'
            ? { chats: 2, theirMessages: 3, yourMessages: 4, theirWords: 9, yourWords: 9, longestChat: 5, firstChat: null, lastChat: null }
            : url === '/api/groups/g1/worlds'
              ? { settingId: null, loreIds: [] }
              : { worlds: [] },
      ),
    );
    await mount();
    expect(text()).toContain("From this group's chats.");
    expect(text()).not.toContain('Group chats are not counted');
  });

  it('keeps the editor header buttons whole, and only the editor headers', async () => {
    const css = readFileSync(resolve(__dirname, '../styles/shell.css'), 'utf8');
    expect(css).toMatch(/\.page-head\.editor-head button \{[^}]*white-space: nowrap/);
    expect(css).toMatch(/\.page-head\.editor-head \.row-actions \{[^}]*flex-wrap: nowrap/);
    expect(css).toMatch(/\.page-head\.editor-head > h2 \{[^}]*min-width: 0/);
    // Other page heads (Worlds' toolbar) must still wrap on a phone.
    expect(css).not.toMatch(/(^|\n)\.page-head (button|\.row-actions) \{[^}]*nowrap/);
    await mount();
    expect(container.querySelector('.page-head.editor-head')).not.toBeNull();
  });
});
