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

it('walks Members, Details, Setting, Realism, Opening, Prompts & Lore, Review', async () => {
  click('Juniper');
  click('Marlow');
  const seen: string[] = [];
  for (const landmark of [
    'Group name',
    'Where does the group meet?',
    'Realism Engine for this group',
    'Opening Scene',
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

it('each Review line names its step, and Change goes back to that step', async () => {
  const rows: [string, string][] = [
    ['Members', 'Juniper'],
    ['Name', 'Group name'],
    ['Where', 'Where does the group meet?'],
    ['Opening', 'Opening Scene'],
    ['Realism', 'Realism Engine for this group'],
    ['Lore', 'Group Lorebook'],
  ];
  click('Juniper');
  click('Marlow');
  for (const [label, landmark] of rows) {
    while (!text().includes('Create & open')) click('Next');
    const row = [...container.querySelectorAll('.gw-review-row')].find(
      (r) => r.querySelector('dt')?.textContent === label,
    );
    expect(row, `Review has a ${label} line`).toBeTruthy();
    act(() => row!.querySelector('button')!.click());
    expect(text(), `Change on ${label}`).toContain(landmark);
    expect(text()).not.toContain('Create & open');
  }
});

it("posts each member's Voice from Details, the global voice included", async () => {
  const { api } = await import('../api/client');
  const original = api.get;
  const spy = vi.spyOn(api, 'get').mockImplementation(async (path: string) =>
    path.startsWith('/api/voice/status')
      ? {
          globalVoice: 'af_sky',
          voices: [
            { id: 'af_sky', name: 'Sky', gender: 'Female' },
            { id: 'am_adam', name: 'Adam', gender: 'Male' },
          ],
        }
      : original(path),
  );
  try {
    click('Juniper');
    click('Marlow');
    await act(async () => {
      button('Next').click();
    });
    const choose = (who: string, value: string) => {
      const s = container.querySelector<HTMLSelectElement>(`select[aria-label="${who}'s voice"]`);
      expect(s, `Details has ${who}'s voice`).not.toBeNull();
      act(() => {
        s!.value = value;
        s!.dispatchEvent(new Event('change', { bubbles: true }));
      });
    };
    choose('Juniper', 'am_adam');
    choose('Marlow', '');
    while (!text().includes('Create & open')) click('Next');
    await act(async () => {
      button('Create & open').click();
    });
    const create = posts.find((p) => p.path === '/api/groups');
    expect((create?.body as { memberVoices?: unknown }).memberVoices).toEqual({ j: 'am_adam', m: '' });
  } finally {
    spy.mockRestore();
  }
});

/// The Realism step drew every member at the neutral seed and Create posted
// that seed for each, over their cards. It now reads each picked card,
// posts only what the wizard changed, and keeps a member closed until
// their card has loaded, with a retry when it fails.
const summary = (id: string) =>
  container.querySelector(`[data-testid="group-realism-member-${id}"] summary`)?.textContent ?? '';
const pending = (id: string) => container.querySelector(`[data-testid="group-realism-member-${id}-pending"]`);

it("shows each member's card on Realism, and posts only what was changed", async () => {
  const { api } = await import('../api/client');
  const original = api.get;
  const asked: string[] = [];
  const spy = vi.spyOn(api, 'get').mockImplementation(async (path: string) => {
    if (path.includes('/detail')) asked.push(path);
    return path === '/api/characters/j/detail'
      ? { realism: { shortTermBond: -60, trustLevel: -25, characterEmotion: 'guarded', needsPace: 'fast' } }
      : original(path);
  });
  try {
    click('Juniper');
    click('Marlow');
    while (!text().includes('Realism Engine for this group')) click('Next');
    await act(async () => {});
    expect(summary('j')).toContain('guarded • Bond -60 / Trust -25');
    expect(summary('m'), 'a plain card starts where a 1:1 does').toContain('neutral • Bond 0 / Trust 0');
    expect(asked.filter((p) => p.endsWith('/j/detail')), 'each card is read once').toHaveLength(1);
    const emotion = container.querySelector<HTMLInputElement>(
      '[data-testid="group-realism-member-j"] input[placeholder="e.g. curious, guarded, amused"]',
    )!;
    Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!.call(emotion, 'fond');
    act(() => {
      emotion.dispatchEvent(new Event('input', { bubbles: true }));
    });
    while (!text().includes('Create & open')) click('Next');
    await act(async () => {
      button('Create & open').click();
    });
    const create = posts.find((p) => p.path === '/api/groups');
    expect((create?.body as { realism: { members: object } }).realism.members).toEqual({ j: { emotion: 'fond' } });
  } finally {
    spy.mockRestore();
  }
});

it("keeps a member closed while their card loads, and offers a retry when it can't", async () => {
  const { api } = await import('../api/client');
  const original = api.get;
  let release: (v: unknown) => void = () => {};
  let marlowCalls = 0;
  const spy = vi.spyOn(api, 'get').mockImplementation(async (path: string) => {
    if (path === '/api/characters/j/detail') return new Promise((r) => (release = r));
    if (path === '/api/characters/m/detail') {
      marlowCalls += 1;
      if (marlowCalls === 1) throw new Error('offline');
      return { realism: { shortTermBond: 12 } };
    }
    return original(path);
  });
  try {
    click('Juniper');
    click('Marlow');
    while (!text().includes('Realism Engine for this group')) click('Next');
    await act(async () => {});
    expect(pending('j')?.textContent).toContain("Loading Juniper's card");
    expect(button('High Bond').disabled, 'no preset over a card still loading').toBe(true);
    expect(pending('m')?.textContent).toContain("Couldn't load Marlow's card.");

    await act(async () => {
      [...pending('m')!.querySelectorAll('button')].find((b) => b.textContent === 'Retry')!.click();
    });
    expect(marlowCalls).toBe(2);
    expect(summary('m')).toContain('Bond 12');

    await act(async () => {
      release({ realism: { shortTermBond: -60, characterEmotion: 'guarded' } });
    });
    expect(summary('j')).toContain('guarded • Bond -60');
    expect(button('High Bond').disabled).toBe(false);
  } finally {
    spy.mockRestore();
  }
});
