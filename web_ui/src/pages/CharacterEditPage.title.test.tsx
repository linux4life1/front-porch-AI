// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A character's Title (the library label beside its name, e.g. "Misty
// Meadows, Misguided Meteorologist" for Misty): the editor shows it right
// under Name with the desktop's placeholder and help line, and Save sends it
// trimmed. A group member's copy has nowhere to keep one, so member mode
// neither shows the field nor sends a title. Desktop twin:
// test/ui/pages/character_title_ui_test.dart.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
vi.mock('../components/realism/usePassageOfTime', () => ({ usePassageOfTime: () => true }));
vi.mock('../components/CharacterStatsCard', () => ({ CharacterStatsCard: () => null }));
vi.mock('../components/AvatarManager', () => ({ AvatarManager: () => null }));

import { CharacterEditPage } from './CharacterEditPage';

const HINT = 'Optional: a full name, or what the card is about';
const HELP = 'Shown under the name in your library. Chats still use the name.';

const CARD = {
  id: 'c1',
  name: 'Misty',
  title: 'Weather Girl',
  description: 'Forecasts badly.',
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
  realism: null,
  ttsVoice: null,
};
const MEMBER = {
  ...CARD,
  id: 'mem-mara',
  name: 'Mara',
  title: '',
  groupId: 'g1',
  groupName: 'Pair',
  scene: { timeOfDay: 'evening', dayCount: 3 },
  others: [],
  groupValues: { systemPrompt: '', note: '', strength: 4, feelings: {} },
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
      url === '/api/characters/c1/detail'
        ? CARD
        : url.endsWith('/members/mem-mara/detail')
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

async function mountAt(path: string) {
  const router = createMemoryRouter(
    [
      { path: '/', element: <h1>Library page</h1> },
      { path: '/edit/:id', element: <CharacterEditPage /> },
      { path: '/groups/:groupId/members/:memberId/edit', element: <CharacterEditPage /> },
    ],
    { initialEntries: ['/', path], initialIndex: 1 },
  );
  await act(async () => root.render(<RouterProvider router={router} />));
}

/** The labelled text inputs in page order, keyed by their label. */
const fields = () =>
  [...container.querySelectorAll('label')]
    .filter((l) => l.querySelector(':scope > input:not([type])'))
    .map((l) => ({
      label: l.querySelector('span')?.textContent ?? '',
      input: l.querySelector('input') as HTMLInputElement,
    }));
const titleBox = () => fields().find((f) => f.label === 'Title')?.input;

function type(input: HTMLInputElement, value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function clickSaveTwice() {
  const save = [...container.querySelectorAll('button')].find((b) => b.textContent?.trim() === 'Save')!;
  await act(async () => {
    save.click();
    save.click();
  });
}

describe('the Title field', () => {
  it('sits right under Name with the card title, and Save sends it trimmed, once', async () => {
    await mountAt('/edit/c1');
    const labels = fields().map((f) => f.label);
    expect(labels.slice(0, 2)).toEqual(['Name', 'Title']);
    expect(titleBox()?.value).toBe('Weather Girl');
    expect(titleBox()?.placeholder).toBe(HINT);
    expect(container.textContent).toContain(HELP);

    type(titleBox()!, '  Misty Meadows, Misguided Meteorologist ');
    await clickSaveTwice();
    expect(post).toHaveBeenCalledTimes(1);
    expect(post).toHaveBeenCalledWith(
      '/api/characters/c1',
      expect.objectContaining({ name: 'Misty', title: 'Misty Meadows, Misguided Meteorologist' }),
    );
  });

  it("is not on a group member's copy, and its save sends no title", async () => {
    await mountAt('/groups/g1/members/mem-mara/edit');
    expect(fields()[0]?.label).toBe('Name');
    expect(titleBox()).toBeUndefined();
    expect(container.textContent).not.toContain(HELP);

    await clickSaveTwice();
    expect(post).toHaveBeenCalledTimes(1);
    expect(post.mock.calls[0][1]).not.toHaveProperty('title');
  });
});
