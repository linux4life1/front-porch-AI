// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import { afterEach, expect, it, vi } from 'vitest';
import { act } from 'react';
import { baseConfig, click, container, createElement, mount, posts, reset, serve, settle, text, pickOption, unmount } from '../components/models/studio/deskTestKit';
vi.mock('../api/client', async () => {
  const {clientMock} = await import('../components/models/studio/deskTestKit');
  return {...clientMock, api: {...clientMock.api, avatarUrl: (path: string) => path}};
});
const { ImageBatchesPage, batchCharacterPath } = await import('./ImageBatchesPage');
afterEach(() => { unmount(); reset(); });

it('distinguishes duplicate character names by nested folder path', () => {
  expect(batchCharacterPath('child', [{id: 'root', name: 'Stories'}, {id: 'child', name: 'Forest', parentId: 'root'}])).toBe('Stories / Forest');
  expect(batchCharacterPath(undefined, [])).toBe('Library root');
  expect(batchCharacterPath('loop', [{id: 'loop', name: 'Loop', parentId: 'loop'}])).toBe('Loop');
});

it('uses full sets and shared inline Edit settings with portrait selection', async () => {
  serve({
    'GET /api/image/batches': {running: false, working: false, jobs: []},
    'GET /api/characters': [{id: 'c1', name: 'Same name', folderId: 'child', hasAvatar: true}, {id: 'c2', name: 'Same name'}],
    'GET /api/folders': {folders: [{id: 'root', name: 'Stories'}, {id: 'child', name: 'Forest', parentId: 'root'}]},
    'GET /api/image/config': {...baseConfig, packConfigMode: 'edit'},
    'GET /api/auth/state': {},
    'POST /api/image/batches/prepare': {running: false, working: false, jobs: []},
  });
  mount(createElement(ImageBatchesPage)); await settle();
  expect(container.querySelector('.batch-characters img')?.getAttribute('src')).toBe('/api/characters/c1/avatar');
  expect(text()).toContain('Stories / Forest');
  pickOption('select', 'expressions'); await settle();
  const sets = container.querySelectorAll<HTMLSelectElement>('select');
  act(() => { sets[1].value = 'full'; sets[1].dispatchEvent(new Event('change', {bubbles: true})); });
  expect(text()).toContain('Prompt rules');
  expect(text()).toContain('Generation settings · Edit graph and model');
  expect(text()).not.toContain('Configure in Image Studio');
  expect(container.querySelector('.fp-config-only')).not.toBeNull();
  act(() => (container.querySelector('.batch-characters input') as HTMLInputElement).click());
  click('Prepare for 1 characters'); await settle();
  expect(posts('/api/image/batches/prepare')[0].body).toMatchObject({set: 'full', kind: 'expressions', characterIds: ['c1']});
});
