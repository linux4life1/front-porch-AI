// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The place editor is inline: opening another place, New, or Cancel used to
// replace a half-edited place without a word. Each now asks while the edit
// differs from how it opened, and a clean edit switches quietly.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UNSAVED_QUESTION } from '../hooks/useUnsavedChanges';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
// The climate and lore editors have their own tests; here they are in the way.
vi.mock('../components/ClimateSeasonEditor', () => ({ ClimateSeasonEditor: () => null }));
vi.mock('../components/LoreEntriesEditor', () => ({ LoreEntriesEditor: () => null }));
vi.mock('../components/ImportCharacterLoreButton', () => ({
  ImportCharacterLoreButton: () => null,
}));

import { WorldsPage } from './WorldsPage';

const summary = (name: string) => ({ id: name, name, description: '', entryCount: 0 });
const detail = (name: string) => ({ id: name, name, description: `${name} prose`, entries: [] });

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset().mockImplementation((url: string) => {
    if (url === '/api/worlds/climates') return Promise.resolve({ climates: [] });
    if (url === '/api/worlds') return Promise.resolve({ worlds: [summary('Harbor'), summary('Mesa')] });
    const m = /^\/api\/worlds\/([^/]+)\/detail$/.exec(url);
    return Promise.resolve(m ? detail(decodeURIComponent(m[1])) : {});
  });
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
      { path: '/worlds', element: <WorldsPage /> },
    ],
    { initialEntries: ['/worlds'] },
  );
  await act(async () => root.render(<RouterProvider router={router} />));
  return router;
}

const nameBox = () => container.querySelector('.world-edit label input') as HTMLInputElement | null;

function typeName(value: string) {
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(nameBox(), value);
    nameBox()!.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function editPlace(index: number) {
  const pencils = container.querySelectorAll<HTMLButtonElement>('button[title="Edit"]');
  await act(async () => pencils[index].click());
}

async function click(label: string) {
  const b = [...container.querySelectorAll('button')].find((el) => el.textContent?.trim() === label);
  if (!b) throw new Error(`no button "${label}"`);
  await act(async () => b.click());
}

describe('switching places with an unsaved edit', () => {
  it('opens another place quietly when nothing was changed', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    await mount();
    await editPlace(0);
    expect(nameBox()?.value).toBe('Harbor');
    await editPlace(1);
    expect(nameBox()?.value).toBe('Mesa');
    expect(confirm).not.toHaveBeenCalled();
  });

  it('asks before another place replaces an edit, and keeps it when told to', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    await mount();
    await editPlace(0);
    typeName('Harbor Town');
    await editPlace(1);
    expect(confirm).toHaveBeenCalledWith(UNSAVED_QUESTION);
    expect(nameBox()?.value).toBe('Harbor Town');

    confirm.mockReturnValue(true);
    await editPlace(1);
    expect(nameBox()?.value).toBe('Mesa');
  });

  it('asks before New or Cancel drops the edit', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    await mount();
    await editPlace(0);
    typeName('Harbor Town');
    await click('＋ New place');
    await click('Cancel');
    expect(confirm).toHaveBeenCalledTimes(2);
    expect(nameBox()?.value).toBe('Harbor Town');

    confirm.mockReturnValue(true);
    await click('Cancel');
    expect(nameBox()).toBeNull();
  });

  it('asks before the nav leaves an edit, and not after it is saved', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const router = await mount();
    await editPlace(0);
    typeName('Harbor Town');
    await act(async () => router.navigate('/'));
    expect(confirm).toHaveBeenCalledTimes(1);
    expect(nameBox()?.value).toBe('Harbor Town');

    post.mockResolvedValue({ worlds: [summary('Harbor Town'), summary('Mesa')] });
    await click('Save place');
    expect(nameBox()).toBeNull();
    await act(async () => router.navigate('/'));
    expect(container.querySelector('h1')?.textContent).toBe('Library page');
    expect(confirm).toHaveBeenCalledTimes(1);
  });
});
