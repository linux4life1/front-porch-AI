// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The group member editor: Edit Character opened on a group member (the
// desktop member editor's twin). It loads and saves the group's own copy
// through the member routes, says whose copy it is, and shows only the
// member's own settings: no Realism master, Time & Day, Chaos, starting
// bonds or Needs switch (the group's), no avatars, stats or Delete (the
// library card's), and the member's own Afterglow under their name. Group
// Settings links each member to it.

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
import { GroupSettings } from '../components/GroupSettings';

const MEMBER = {
  id: 'mem-mara',
  groupId: 'g1',
  groupName: 'Pair',
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
  realism: { realismEnabled: false, afterglowEnabled: true },
  ttsVoice: null,
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
      url === '/api/groups/g1/members/mem-mara/detail'
        ? MEMBER
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

async function mountAt(path: string, element: JSX.Element) {
  const router = createMemoryRouter(
    [
      { path: '/', element: <h1>Chat</h1> },
      { path: '/groups/:groupId/members/:memberId/edit', element: <CharacterEditPage /> },
      { path: '/here', element },
    ],
    { initialEntries: ['/', path], initialIndex: 1 },
  );
  await act(async () => root.render(<RouterProvider router={router} />));
  return router;
}

const text = () => container.textContent ?? '';

function toggle(label: string): HTMLInputElement {
  const row = [...container.querySelectorAll('label.realism-toggle')].find(
    (l) => l.querySelector('.realism-toggle-text > span')?.textContent === label,
  );
  if (!row) throw new Error(`no toggle "${label}"`);
  return row.querySelector('input') as HTMLInputElement;
}

describe('the group member editor', () => {
  it("says whose copy it is, shows only the member's own settings, and saves to the member", async () => {
    await mountAt('/groups/g1/members/mem-mara/edit', <></>);

    const banner = container.querySelector('[data-testid="group-member-editor-banner"]');
    expect(banner?.textContent).toContain('Mara in Pair.');
    expect(
      container.querySelector('[data-testid="member-own-settings-note"]')?.textContent,
    ).toContain("Mara's own settings in this group");
    expect(get).toHaveBeenCalledWith('/api/groups/g1/members/mem-mara/detail');
    for (const groupWide of [
      'Enable Realism Engine',
      'Chaos mode (Chance Time)',
      'Needs simulation',
      'Short-term bond',
      'Your chats together',
      'Avatar manager',
      'Delete character',
    ]) {
      expect(text(), groupWide).not.toContain(groupWide);
    }

    await act(async () => toggle('Afterglow for Mara').click());
    const save = [...container.querySelectorAll('button')].find(
      (b) => b.textContent === 'Save character',
    )!;
    await act(async () => save.click());

    expect(post).toHaveBeenCalledTimes(1);
    const [url, body] = post.mock.calls[0];
    expect(url).toBe('/api/groups/g1/members/mem-mara');
    expect(body.afterglowEnabled).toBe(false);
    expect(body.description).toBe('Keeps the lighthouse.');
  });

  it('Group Settings links each member to their editor', async () => {
    await mountAt(
      '/here',
      <GroupSettings
        group={{
          name: 'Pair',
          systemPrompt: '',
          scenario: '',
          firstMessage: '',
          alternateGreetings: [],
          greetingSeeds: [],
          members: [
            { id: 'mem-mara', dbId: 'mem-mara', name: 'Mara', prompt: '' },
            // A scene guest: no member row, so no editor.
            { id: 'guest-1', name: 'Guest', prompt: '' },
          ],
        } as never}
        groupId="g1"
        onToggleDirector={() => {}}
        clockOn
      />,
    );
    const link = container.querySelector('[data-testid="edit-member-mem-mara"]');
    expect(link?.getAttribute('href')).toBe('/groups/g1/members/mem-mara/edit');
    expect(container.querySelectorAll('[data-testid^="edit-member-"]')).toHaveLength(1);
    expect(link?.closest('label'), 'the link is not part of the prompt box label').toBeNull();
  });
});

// The member editor, finished to the mock: the group's own switches are
// read-only lines, and where the member starts in the group's new chats is
// the group's seed for them (`groupStart`), never their card's own bonds.
const IN_GROUP = {
  ...MEMBER,
  alternateGreetings: ['You came back.'],
  group: {
    realism: true,
    needs: false,
    chaos: true,
    afterglow: true,
    timeLabel: 'Evening, Day 3',
    settingName: 'Harborside',
    readsMemberLorebooks: true,
  },
  start: {
    shortTermBond: 35,
    longTermBond: 35,
    trustLevel: 40,
    characterEmotion: 'neutral',
    emotionIntensity: 'mild',
  },
};

function detailIs(detail: object) {
  get.mockImplementation((url: string) =>
    Promise.resolve(
      url === '/api/groups/g1/members/mem-mara/detail'
        ? detail
        : url === '/api/worlds'
          ? { worlds: [] }
          : {},
    ),
  );
}

function slider(label: string): HTMLInputElement {
  const row = [...container.querySelectorAll('.realism-slider')].find(
    (r) => r.querySelector('.realism-slider-head > span')?.textContent === label,
  );
  if (!row) throw new Error(`no slider "${label}"`);
  return row.querySelector('input') as HTMLInputElement;
}

function setRange(el: HTMLInputElement, value: string) {
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
}

const saveButton = () =>
  [...container.querySelectorAll('button')].find((b) => b.textContent === 'Save character')!;

describe("the group member editor and the member's group", () => {
  it("shows the group's switches as lines and sends a moved start as the group's seed", async () => {
    detailIs(IN_GROUP);
    await mountAt('/groups/g1/members/mem-mara/edit', <></>);

    for (const line of [
      'Realism Engine · On for this group',
      'Time & Day · shared by the group: Evening, Day 3',
      'Chaos Mode · On for this group',
      'Afterglow · On for this group',
      'Needs · Off for this group',
      'Where Mara starts in new chats of this group.',
      'Used when a greeting opens a chat of this group.',
      'This group meets in Harborside.',
      '"Inherit character lorebooks" on; it is on for this group.',
    ]) {
      expect(text(), line).toContain(line);
    }
    expect(text()).not.toContain('Enable Realism Engine');

    await act(async () => setRange(slider('Long-term bond'), '120'));
    await act(async () => saveButton().click());

    expect(post).toHaveBeenCalledTimes(1);
    const [, body] = post.mock.calls[0];
    expect(body.groupStart).toEqual({ ...IN_GROUP.start, longTermBond: 120 });
    expect(body.longTermBond, "the card's own bond stays as it was").not.toBe(120);
  });

  it('sends no start when it did not move, so another device’s change stays', async () => {
    detailIs(IN_GROUP);
    await mountAt('/groups/g1/members/mem-mara/edit', <></>);
    await act(async () => saveButton().click());
    expect(post.mock.calls[0][1].groupStart).toBeUndefined();
  });

  it("keeps a lite member's Realism, Needs and Afterglow for when they are promoted", async () => {
    detailIs({ ...IN_GROUP, lite: true });
    await mountAt('/groups/g1/members/mem-mara/edit', <></>);

    expect(
      container.querySelector('[data-testid="member-hidden-note"]')?.textContent,
    ).toBe(
      "Mara's Realism, Needs and Afterglow start when they are promoted to a full member of this group.",
    );
    for (const hidden of ['Short-term bond', 'Needs Simulation', 'Afterglow for Mara']) {
      expect(text(), hidden).not.toContain(hidden);
    }
    expect(text()).toContain('Chaos Mode · On for this group');
  });

  it('hides Realism, Needs and Afterglow while Porch Life does not allow Realism', async () => {
    detailIs({ ...IN_GROUP, realismAllowed: false });
    await mountAt('/groups/g1/members/mem-mara/edit', <></>);

    expect(
      container.querySelector('[data-testid="member-hidden-note"]')?.textContent,
    ).toBe(
      "Realism, Needs and Afterglow are hidden: the Realism Engine is off in Porch Life. Mara's settings are kept.",
    );
    for (const hidden of ['Short-term bond', 'Needs Simulation', 'Afterglow for Mara']) {
      expect(text(), hidden).not.toContain(hidden);
    }
  });

  it("Group Settings sums up where each member starts, beside their editor's link", async () => {
    get.mockImplementation((url: string) =>
      Promise.resolve(
        url === '/api/groups/g1/member-summaries'
          ? {
              members: [
                {
                  id: 'mem-mara',
                  name: 'Mara',
                  start: { ...IN_GROUP.start, longTermBond: 25, trustLevel: 30 },
                  afterglow: true,
                  lite: false,
                },
              ],
            }
          : {},
      ),
    );
    await mountAt(
      '/here',
      <GroupSettings
        group={{
          name: 'Pair',
          systemPrompt: '',
          scenario: '',
          firstMessage: '',
          members: [{ id: 'mem-mara', dbId: 'mem-mara', name: 'Mara', prompt: '' }],
        } as never}
        groupId="g1"
        onToggleDirector={() => {}}
        clockOn
      />,
    );
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0));
    });
    expect(
      container.querySelector('[data-testid="member-summary-mem-mara"]')?.textContent,
    ).toBe('Mara · Close / Trusting · Afterglow on');
  });
});
