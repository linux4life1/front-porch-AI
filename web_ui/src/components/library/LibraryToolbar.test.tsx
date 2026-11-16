// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The library toolbar carries the desktop's buttons (Refresh, Multi-select,
// Organize, New Folder or New Subfolder, Import) and none of the create
// buttons, which live in the nav as on the desktop. The selection bar has
// Cancel selection, Select all and Select none. Delete Folder gives the
// desktop's counts.

import { act } from 'react-dom/test-utils';
import { createRoot, type Root } from 'react-dom/client';
import { createElement } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { LibraryToolbar, SelectionBar } from './LibraryToolbar';
import { folderDeleteMessage } from '../../pages/CharactersPage';

let container: HTMLDivElement;
let root: Root;
beforeEach(() => {
  (globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
});
afterEach(() => {
  act(() => root.unmount());
  container.remove();
});

const toolbar = (inFolder: boolean, over: Record<string, unknown> = {}) =>
  createElement(MemoryRouter, null, createElement(LibraryToolbar, {
    search: '',
    setSearch: vi.fn(),
    sort: 'name',
    setSort: vi.fn(),
    scope: 'currentFolder',
    setScope: vi.fn(),
    searching: false,
    gridMin: 160,
    setGridMin: vi.fn(),
    importing: false,
    inFolder,
    onRefresh: vi.fn(),
    onNewFolder: vi.fn(),
    onImportMenu: vi.fn(),
    onStartSelect: vi.fn(),
    onStartOrganize: vi.fn(),
    ...over,
  } as never));

describe('library toolbar', () => {
  it('has the desktop buttons and no create buttons', () => {
    act(() => root.render(toolbar(false)));
    const titles = [...container.querySelectorAll('button[title]')].map((b) => b.getAttribute('title'));
    expect(titles).toEqual([
      'Chats',
      'Porch Stories',
      'Refresh character list (pick up external changes, e.g. Character Card Forge)',
      'Multi-select characters (for organizing, moving, etc.)',
      'Organize into folders',
      'New Folder',
      'Import or discover characters',
    ]);
    expect(container.textContent).not.toMatch(/Create|New Group/);
  });

  it('is New Subfolder inside a folder; Refresh and Organize call back', () => {
    const onRefresh = vi.fn();
    const onStartOrganize = vi.fn();
    act(() => root.render(toolbar(true, { onRefresh, onStartOrganize })));
    expect(container.querySelector('[title="New Subfolder"]')).not.toBeNull();
    act(() => (container.querySelector('[title="Organize into folders"]') as HTMLElement).click());
    act(() => (container.querySelector('[title^="Refresh"]') as HTMLElement).click());
    expect(onStartOrganize).toHaveBeenCalledOnce();
    expect(onRefresh).toHaveBeenCalledOnce();
  });
});

describe('selection bar', () => {
  it('has Cancel selection, Select all and Select none', () => {
    const onSelectAll = vi.fn();
    const onSelectNone = vi.fn();
    const onCancel = vi.fn();
    act(() =>
      root.render(
        createElement(SelectionBar, {
          count: 2,
          onSelectAll,
          onSelectNone,
          onMove: vi.fn(),
          onDelete: vi.fn(),
          onCancel,
        }),
      ),
    );
    const btn = (t: string) =>
      [...container.querySelectorAll('button')].find((b) => (b.textContent ?? '').trim() === t || b.title === t)!;
    act(() => btn('Select all').click());
    act(() => btn('Select none').click());
    act(() => btn('Cancel selection').click());
    expect([onSelectAll, onSelectNone, onCancel].map((f) => f.mock.calls.length)).toEqual([1, 1, 1]);
    expect(container.textContent).toContain('2 selected');
  });
});

describe('Delete Folder text', () => {
  it('counts characters and groups like the desktop', () => {
    const f = { id: 'f', name: 'Porch', characterCount: 3, groupCount: 1 };
    const m = folderDeleteMessage(f);
    expect(m).toContain('the 3 characters and 1 group inside return to the top level.');
    expect(m).toContain('groups are kept and return to the top level');
    expect(folderDeleteMessage({ ...f, characterCount: 1, groupCount: 0 })).toContain('the 1 character inside');
  });
});
