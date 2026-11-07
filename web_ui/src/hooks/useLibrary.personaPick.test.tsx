// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A Backyard chat import asks which persona the user was, the way Start new
// chat does: the server answers 409 persona_pick with the persona the chat
// names most, the picker shows it as Recommended, and the upload is resent
// with the pick. A batch asks once.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const upload = vi.fn();
vi.mock('../api/client', async (orig) => {
  const real = await orig<typeof import('../api/client')>();
  return { ...real, api: { ...real.api, upload: (...a: unknown[]) => upload(...a) } };
});

import { ApiError } from '../api/client';
import { useLibraryActions } from './useLibrary.actions';
import { PersonaPickerDialog } from '../components/library/LibraryDialogs';

let container: HTMLDivElement;
let root: Root;
let actions: ReturnType<typeof useLibraryActions>;

function Harness() {
  actions = useLibraryActions({
    folderId: null,
    setFolderId: () => {},
    reload: () => {},
    setError: () => {},
    setChars: () => {},
    setGroups: () => {},
    setImporting: () => {},
    cancelSelecting: () => {},
  });
  const pick = actions.personaPick;
  return pick
    ? createElement(PersonaPickerDialog, {
        subject: pick.subject,
        title: pick.title,
        recommendedId: pick.recommendedId,
        personas: [
          { id: 'p-user', label: 'User', name: 'User', active: true, default: true },
          { id: 'p-rowan', label: 'Rowan', name: 'Rowan', active: false },
        ],
        onPick: (id: string) => actions.resolvePersonaPick(id),
        onClose: () => actions.resolvePersonaPick(null),
      })
    : null;
}

function files(...names: string[]): FileList {
  const list = names.map((n) => new File(['x'], n));
  return Object.assign(list, { item: (i: number) => list[i] }) as unknown as FileList;
}

const flush = () => act(async () => { await new Promise((r) => setTimeout(r, 0)); });

describe('Backyard import persona pick', () => {
  beforeEach(() => {
    upload.mockReset();
    container = document.createElement('div');
    document.body.appendChild(container);
    root = createRoot(container);
    act(() => root.render(createElement(Harness)));
  });

  afterEach(() => {
    act(() => root.unmount());
    container.remove();
  });

  it('shows the picker with the recommendation and resends with the pick', async () => {
    upload.mockImplementation(async (url: string) => {
      if (url.includes('persona=ask')) {
        throw new ApiError(409, 'persona_pick', {
          error: 'persona_pick',
          name: 'Juniper',
          recommendedPersonaId: 'p-rowan',
        });
      }
      return { id: 'c1', name: 'Juniper' };
    });

    let done!: Promise<void>;
    act(() => { done = actions.importFiles(files('juniper.byaf')); });
    await flush();

    expect(container.textContent).toContain('Start a new chat with Juniper as…');
    const rowanRow = [...container.querySelectorAll('button.move-row')].find((b) =>
      b.textContent?.includes('Rowan'),
    ) as HTMLButtonElement;
    expect(rowanRow.textContent).toContain('Recommended');

    act(() => rowanRow.click());
    await act(async () => { await done; });

    expect(upload).toHaveBeenLastCalledWith(
      '/api/characters/import?collision=ask&persona=p-rowan',
      expect.any(File),
    );
    expect(container.querySelector('.modal')).toBeNull();
  });

  it('asks once for a batch and reuses the pick', async () => {
    upload.mockImplementation(async (url: string) => {
      if (url.includes('persona=ask')) {
        throw new ApiError(409, 'persona_pick', { error: 'persona_pick', name: 'A' });
      }
      return { id: 'c', name: 'A' };
    });

    let done!: Promise<void>;
    act(() => { done = actions.importFiles(files('a.byaf', 'b.byaf')); });
    await flush();
    expect(container.textContent).toContain('Import these 2 Backyard chats as…');
    const userRow = container.querySelector('button.move-row') as HTMLButtonElement;
    act(() => userRow.click());
    await act(async () => { await done; });

    const asks = upload.mock.calls.filter(([u]) => String(u).includes('persona=ask'));
    expect(asks).toHaveLength(1);
    expect(upload).toHaveBeenLastCalledWith(
      '/api/characters/import?collision=keepBoth&persona=p-user',
      expect.any(File),
    );
  });

  it('closing the picker imports nothing more', async () => {
    upload.mockRejectedValue(
      new ApiError(409, 'persona_pick', { error: 'persona_pick', name: 'A' }),
    );
    let done!: Promise<void>;
    act(() => { done = actions.importFiles(files('a.byaf', 'b.byaf')); });
    await flush();
    act(() => actions.resolvePersonaPick(null));
    await act(async () => { await done; });
    expect(upload).toHaveBeenCalledTimes(1);
  });
});
