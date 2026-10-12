// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A half-made character used to vanish without a word when the user left
// Create Character. Leaving with anything typed now asks; Create does not.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createMemoryRouter, RouterProvider } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { UNSAVED_QUESTION } from '../hooks/useUnsavedChanges';

const { get, post } = vi.hoisted(() => ({ get: vi.fn(), post: vi.fn() }));
vi.mock('../api/client', () => ({ api: { get, post }, ApiError: class extends Error {} }));
vi.mock('../components/realism/usePassageOfTime', () => ({ usePassageOfTime: () => true }));

import { CreateCharacterPage } from './CreateCharacterPage';

let container: HTMLDivElement;
let root: Root;

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  get.mockReset().mockResolvedValue({});
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
      { path: '/chat', element: <h1>Chat page</h1> },
      { path: '/create', element: <CreateCharacterPage /> },
    ],
    { initialEntries: ['/', '/create'], initialIndex: 1 },
  );
  await act(async () => root.render(<RouterProvider router={router} />));
  return router;
}

const heading = () => container.querySelector('h1, h2')?.textContent;

function typeName(value: string) {
  const input = container.querySelector('.wizard-body input') as HTMLInputElement;
  const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
  act(() => {
    setter.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

async function click(label: string) {
  const b = [...container.querySelectorAll('button')].find((el) => el.textContent?.trim() === label);
  if (!b) throw new Error(`no button "${label}"`);
  await act(async () => b.click());
}

describe('Create Character with unsaved input', () => {
  it('leaves an untouched form without asking', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    await mount();
    await click('Cancel');
    expect(heading()).toBe('Library page');
    expect(confirm).not.toHaveBeenCalled();
  });

  it('asks before Cancel drops a typed name, and stays when told to', async () => {
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    const router = await mount();
    typeName('Juniper');
    await click('Cancel');
    expect(confirm).toHaveBeenCalledWith(UNSAVED_QUESTION);
    expect(heading()).toBe('Create character');
    expect((container.querySelector('.wizard-body input') as HTMLInputElement).value).toBe('Juniper');

    confirm.mockReturnValue(true);
    await act(async () => router.navigate('/'));
    expect(heading()).toBe('Library page');
  });

  it('Create opens the new character without asking', async () => {
    const confirm = vi.spyOn(window, 'confirm');
    post.mockResolvedValue({ id: 'c1', name: 'Juniper' });
    await mount();
    typeName('Juniper');
    for (let i = 0; i < 5; i++) await click('Next →');
    await click('Create character');
    expect(post).toHaveBeenCalledWith('/api/characters/create', expect.objectContaining({ name: 'Juniper' }));
    expect(heading()).toBe('Chat page');
    expect(confirm).not.toHaveBeenCalled();
  });
});
