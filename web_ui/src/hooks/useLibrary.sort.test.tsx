// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Characters sort (and the search-scope filter) survive a PWA relaunch.
// The free-text search box does not. Junk in storage falls back to Name.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { MemoryRouter } from 'react-router-dom';
import { createElement, type ReactNode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

type Pending = { path: string; resolve: (v: unknown) => void };
const pending: Pending[] = [];

vi.mock('../api/client', () => ({
  api: {
    get: (path: string) =>
      new Promise((resolve) => {
        pending.push({ path, resolve });
      }),
    post: () => Promise.resolve({}),
  },
  ApiError: class ApiError extends Error {},
}));

vi.mock('../api/ws', () => ({
  ChatSocket: class {
    connect() {}
    close() {}
  },
}));

const { useLibrary } = await import('./useLibrary');

type Lib = ReturnType<typeof useLibrary>;
let latest: Lib | null = null;

function Probe() {
  latest = useLibrary();
  return null;
}

function wrap(children: ReactNode) {
  return createElement(MemoryRouter, null, children);
}

let container: HTMLDivElement;
let root: Root;

function lastCharPath(): string {
  const paths = pending.filter((p) => p.path.startsWith('/api/characters')).map((p) => p.path);
  return paths[paths.length - 1] ?? '';
}

function mount() {
  root = createRoot(container);
  act(() => {
    root.render(wrap(createElement(Probe)));
  });
}

beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  pending.length = 0;
  latest = null;
  localStorage.clear();
  container = document.createElement('div');
  document.body.appendChild(container);
});

afterEach(() => {
  act(() => root.unmount());
  container.remove();
  localStorage.clear();
});

describe('useLibrary sort persistence', () => {
  it('restores sort and search scope after remount, and not the search box', () => {
    mount();
    expect(latest!.sort).toBe('name');
    expect(latest!.scope).toBe('currentFolder');

    act(() => {
      latest!.setSort('recent');
      latest!.setScope('folderRecursive');
      latest!.setSearch('secret-query');
    });
    expect(latest!.sort).toBe('recent');
    expect(lastCharPath()).toContain('sort=recent');

    act(() => root.unmount());
    latest = null;
    pending.length = 0;
    mount();

    expect(latest!.sort).toBe('recent');
    expect(latest!.scope).toBe('folderRecursive');
    expect(latest!.search).toBe('');
    expect(lastCharPath()).toContain('sort=recent');
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i) ?? '';
      expect(`${key}=${localStorage.getItem(key)}`).not.toContain('secret-query');
    }
  });

  it('falls back to name when the stored sort is junk', () => {
    localStorage.setItem('fpai.lib.sort', 'garbage');
    localStorage.setItem('fpai.lib.scope', 'nope');
    mount();
    expect(latest!.sort).toBe('name');
    expect(latest!.scope).toBe('currentFolder');
    expect(lastCharPath()).not.toContain('sort=');
  });
});
