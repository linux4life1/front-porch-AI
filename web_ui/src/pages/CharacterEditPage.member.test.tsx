// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One editor (docs/design/group-editor.md): the group member's editor is the
// character editor on the member's own copy. It adds a notice and "In the
// group", greys out Time & Day, Chaos Mode, Realism Verification and the
// Worlds tab, and saves to the member's row only. The 1:1 editor names the
// groups its character is also in.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
vi.mock('../components/realism/usePassageOfTime', () => ({ usePassageOfTime: () => true }));
vi.mock('../components/realism/useAdultThemes', () => ({
  useAdultFlags: () => ({ adult: true, afterglow: true }),
}));
vi.mock('../components/CharacterStatsCard', () => ({
  CharacterStatsCard: () => <p>Your chats together</p>,
}));
vi.mock('../components/AvatarManager', () => ({ AvatarManager: () => <p>Avatar manager</p> }));

import { CharacterEditPage } from './CharacterEditPage';

const BASE = {
  name: 'Mara',
  description: 'Keeps the lighthouse.',
  personality: '',
  scenario: '',
  firstMessage: '',
  mesExample: '',
  systemPrompt: '',
  postHistoryInstructions: '',
  tags: [],
  alternateGreetings: [],
  worldNames: [],
  lorebook: null,
  realism: { realismEnabled: true, afterglowEnabled: true },
  ttsVoice: null,
};
const MEMBER = {
  ...BASE,
  id: 'mem-mara',
  groupId: 'g1',
  groupName: 'Pair',
  scene: { timeOfDay: 'evening', dayCount: 3 },
  others: [{ id: 'mem-bo', name: 'Bo' }],
  groupValues: { systemPrompt: '', note: '', strength: 4, feelings: {} },
};

let container: HTMLDivElement;
let root: Root;
let character: Record<string, unknown>;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  character = MEMBER;
  get.mockReset().mockImplementation((url: string) =>
    Promise.resolve(
      url.endsWith('/detail') ? character : url === '/api/worlds' ? { worlds: [] } : {},
    ),
  );
  post.mockReset().mockResolvedValue({});
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

async function mountAt(path: string) {
  const router = createMemoryRouter(
    [
      { path: '/', element: <h1>Chat</h1> },
      { path: '/groups/:groupId/members/:memberId/edit', element: <CharacterEditPage /> },
      { path: '/edit/:id', element: <CharacterEditPage /> },
    ],
    { initialEntries: ['/', path], initialIndex: 1 },
  );
  await act(async () => root.render(<RouterProvider router={router} />));
}

const text = () => container.textContent ?? '';
const greyed = () =>
  [...container.querySelectorAll('[data-testid="greyed-out"]')].map((e) => e.getAttribute('title'));

describe('the group member editor', () => {
  it('adds the notice and the group section, and greys out what the group owns', async () => {
    await mountAt('/groups/g1/members/mem-mara/edit');

    expect(container.querySelector('[data-testid="group-member-notice"]')?.textContent).toContain(
      "You're editing Mara in Pair only.",
    );
    expect(text()).toContain('In Pair');
    expect(greyed()).toEqual(
      expect.arrayContaining([
        'Time & Day is set per group, not per character.',
        'Chaos Mode is set per group for now.',
        'Realism Verification is set per group, not per character.',
      ]),
    );
    const worlds = [...container.querySelectorAll('[role="tab"]')].find((t) => t.textContent === 'Worlds')!;
    expect(worlds.getAttribute('aria-disabled')).toBe('true');
    expect(worlds.getAttribute('title')).toBe('Worlds are set per group, not per character.');
    await act(async () => (worlds as HTMLElement).click());
    expect(container.querySelector('[data-testid="character-worlds-section"]')).toBeNull();
    // The old banner and the read-only group lines are gone; Save is Save.
    expect(container.querySelector('[data-testid="group-member-editor-banner"]')).toBeNull();
    expect(text()).not.toContain('Group Settings');
    expect([...container.querySelectorAll('button')].some((b) => b.textContent === 'Save')).toBe(true);
  });

  it("a greyed control takes no input", async () => {
    await mountAt('/groups/g1/members/mem-mara/edit');
    const body = container.querySelector('.greyed-out-body') as HTMLElement;
    // Really disabled (a fieldset), not inert: nothing is drawn over the controls.
    expect((body as HTMLFieldSetElement).disabled).toBe(true);
  });

  it("saves the group's values once and the member's card, never the library", async () => {
    await mountAt('/groups/g1/members/mem-mara/edit');
    const set = (testId: string, value: string) => {
      const el = container.querySelector(`[data-testid="${testId}"]`) as HTMLInputElement;
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
      setter.call(el, value);
      el.dispatchEvent(new Event('input', { bubbles: true }));
    };
    await act(async () => set('group-member-system-prompt', 'Mara notices everything.'));
    await act(async () => set('group-member-note', 'Keep it short.'));
    const save = [...container.querySelectorAll('button')].find((b) => b.textContent === 'Save')!;
    await act(async () => {
      save.click();
      save.click();
    });
    expect(post).toHaveBeenCalledTimes(1);
    const [url, body] = post.mock.calls[0];
    expect(url).toBe('/api/groups/g1/members/mem-mara');
    expect(body.groupValues.systemPrompt).toBe('Mara notices everything.');
    expect(body.groupValues.note).toBe('Keep it short.');
    expect(url).not.toContain('/api/characters/');
  });
});

describe('the 1:1 editor', () => {
  it('names the groups its character is also in', async () => {
    character = { ...BASE, id: 'c1', inGroups: ['The Porch Trio', 'Book Club'] };
    await mountAt('/edit/c1');
    expect(container.querySelector('[data-testid="character-in-groups-note"]')?.textContent).toContain(
      "Mara is also in The Porch Trio and Book Club. Groups keep their own copy; changes here don't reach them.",
    );
    expect(greyed()).toEqual([]);
  });

  it('says nothing for a character in no group', async () => {
    character = { ...BASE, id: 'c1', inGroups: [] };
    await mountAt('/edit/c1');
    expect(container.querySelector('[data-testid="character-in-groups-note"]')).toBeNull();
    expect(container.querySelector('[data-testid="group-member-notice"]')).toBeNull();
  });
});
