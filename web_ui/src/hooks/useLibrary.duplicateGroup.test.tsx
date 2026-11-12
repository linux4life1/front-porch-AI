// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Duplicate Group on the web asks the relay for one copy per tap, however
// fast it is tapped, then reloads the library.

import { act } from 'react-dom/test-utils';
import { createRoot } from 'react-dom/client';
import { createElement } from 'react';
import { describe, expect, it, vi } from 'vitest';

const posts: string[] = [];
let release: () => void = () => {};
vi.mock('../api/client', () => ({
  ApiError: class ApiError extends Error {},
  api: {
    post: (url: string) => {
      posts.push(url);
      return new Promise((resolve) => {
        release = () => resolve({ id: 'group_2', name: 'Crew (copy)' });
      });
    },
    get: () => new Promise(() => {}),
  },
}));

const { useLibraryActions } = await import('./useLibrary.actions');

describe('duplicateGroup', () => {
  it('posts once for a double tap, then reloads', async () => {
    (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
    const reload = vi.fn();
    let actions: ReturnType<typeof useLibraryActions> | undefined;
    function Probe() {
      actions = useLibraryActions({
        folderId: null,
        setFolderId: vi.fn(),
        reload,
        setError: vi.fn(),
        setChars: vi.fn(),
        setGroups: vi.fn(),
        setImporting: vi.fn(),
        cancelSelecting: vi.fn(),
      } as never);
      return null;
    }
    const host = document.createElement('div');
    const root = createRoot(host);
    act(() => root.render(createElement(Probe)));
    await act(async () => {
      void actions!.duplicateGroup('group_1');
      void actions!.duplicateGroup('group_1');
      await Promise.resolve();
    });
    expect(posts).toEqual(['/api/groups/group_1/duplicate']);
    await act(async () => {
      release();
      await Promise.resolve();
    });
    expect(reload).toHaveBeenCalledOnce();
    act(() => root.unmount());
  });
});
