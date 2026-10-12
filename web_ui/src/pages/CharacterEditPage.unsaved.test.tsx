// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edits to a character used to be thrown away by any nav tap or Back. The
// editor now compares against the card as it loaded: an untouched card
// leaves quietly, an edited one asks, and Save goes back without asking.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UNSAVED_QUESTION } from '../hooks/useUnsavedChanges';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
vi.mock('../components/realism/usePassageOfTime', () => ({ usePassageOfTime: () => true }));
// Their own fetches and tests; not what this pins.
vi.mock('../components/CharacterStatsCard', () => ({ CharacterStatsCard: () => null }));
vi.mock('../components/AvatarManager', () => ({ AvatarManager: () => null }));

import { CharacterEditPage } from './CharacterEditPage';

const DETAIL = {
  id: 'c1',
  name: 'Juniper',
  description: 'A lighthouse keeper.',
  personality: 'Wry',
  scenario: '',
  firstMessage: 'Evening.',
  mesExample: '',
  systemPrompt: '',
  postHistoryInstructions: '',
  tags: ['coast'],
  alternateGreetings: ['Storm coming.'],
  worldNames: [],
  lorebook: { entries: [{ key: 'lamp', content: 'The lamp never goes out.' }] },
  realism: null,
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
    Promise.resolve(url === '/api/characters/c1/detail' ? DETAIL : url === '/api/worlds' ? { worlds: [] } : {}),
  );
  post.mockReset();
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  vi.restoreAllMocks();
});

async function mount() {
  const router = createMemoryRouter(
    [
      { path: '/', element: <h1>Library page</h1> },
      { path: '/edit/:id', element: <CharacterEditPage /> },
    ],
    { initialEntries: ['/', '/edit/c1'], initialIndex: 1 },
  );
  await act(async () => root.render(<RouterProvider router={router} />));
  return router;
}

const heading = () => container.querySelector('h1, h2')?.textContent;
const nameBox = () => container.querySelector('label input') as HTMLInputElement;

function typeName(value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(nameBox(), value);
    nameBox().dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(label: string) {
  const b = [...container.querySelectorAll('button')].find((el) => el.textContent?.trim() === label);
  if (!b) throw new Error(`no button "${label}"`);
  await act(async () => b.click());
}

describe('Edit character with unsaved edits', () => {
  it('leaves a card that was only looked at without asking', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    const router = await mount();
    expect(nameBox().value).toBe('Juniper');
    await act(async () => router.navigate('/'));
    expect(heading()).toBe('Library page');
    expect(confirm).not.toHaveBeenCalled();
  });

  it('asks before a nav leave drops an edit, and keeps it on Cancel', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const router = await mount();
    typeName('Juniper Vale');
    await act(async () => router.navigate('/'));
    expect(confirm).toHaveBeenCalledWith(UNSAVED_QUESTION);
    expect(heading()).toBe('Edit character');
    expect(nameBox().value).toBe('Juniper Vale');

    // The page's own Cancel (browser back) asks the same way.
    confirm.mockClear().mockReturnValue(true);
    await click('Cancel');
    expect(confirm).toHaveBeenCalledTimes(1);
    expect(heading()).toBe('Library page');
  });

  it('typing the name back to what it was is not an edit', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    const router = await mount();
    typeName('Juniper Vale');
    typeName('Juniper');
    await act(async () => router.navigate('/'));
    expect(heading()).toBe('Library page');
    expect(confirm).not.toHaveBeenCalled();
  });

  it('Save goes back without asking', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    post.mockResolvedValue({});
    await mount();
    typeName('Juniper Vale');
    await click('Save character');
    expect(post).toHaveBeenCalledWith('/api/characters/c1', expect.objectContaining({ name: 'Juniper Vale' }));
    expect(heading()).toBe('Library page');
    expect(confirm).not.toHaveBeenCalled();
  });
});
